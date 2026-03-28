-- Operations.luau
-- Pure BMesh mutation operations.
-- No knowledge of EditableMesh, proxies, or scene state.

local BMesh = require(script.Parent.BMesh)

local Operations = {}

local function safeUnit(v)
	if v.Magnitude > 1e-5 then
		return v.Unit
	end
	return Vector3.zero
end

-- ─── Clone ────────────────────────────────────────────────────────────────────
-- Deep clone a BMesh preserving all element IDs.
-- Critical for bevel snapshot/restore — IDs must match so lookups work.
function Operations.cloneBMesh(bm)
	local c = BMesh.new()
	c._nextVertId = bm._nextVertId
	c._nextEdgeId = bm._nextEdgeId
	c._nextFaceId = bm._nextFaceId

	-- Clone verts with original IDs
	for id, v in pairs(bm.verts) do
		c.verts[id] = { id = id, position = v.position, loop = nil }
	end

	-- Clone faces by walking original face loops, rebuilding with cloned verts
	-- This rewires all loop/edge/radial structure correctly while preserving IDs
	for _, face in pairs(bm.faces) do
		local origVerts = BMesh.faceVerts(face)
		local cloneVerts = {}
		for _, v in ipairs(origVerts) do
			cloneVerts[#cloneVerts + 1] = c.verts[v.id]
		end
		-- Use addFace but then fix the face ID to match the original
		local newFace = BMesh.addFace(c, cloneVerts, {
			Color = face.color,
			Transparency = face.transparency,
		})
		-- Fix ID: remove from wrong slot, re-insert with original ID
		c.faces[newFace.id] = nil
		newFace.id = face.id
		c.faces[face.id] = newFace
	end
	-- Fix _nextFaceId since we manually reassigned IDs
	c._nextFaceId = bm._nextFaceId

	-- Fix edge IDs similarly
	local edgeIdMap = {} -- new edge id → original edge id
	for _, origEdge in pairs(bm.edges) do
		local key1 = origEdge.v1.id .. "_" .. origEdge.v2.id
		local key2 = origEdge.v2.id .. "_" .. origEdge.v1.id
		for newId, newEdge in pairs(c.edges) do
			local nk1 = newEdge.v1.id .. "_" .. newEdge.v2.id
			local nk2 = newEdge.v2.id .. "_" .. newEdge.v1.id
			if (nk1 == key1 or nk1 == key2 or nk2 == key1 or nk2 == key2) and not edgeIdMap[newId] then
				edgeIdMap[newId] = origEdge.id
				break
			end
		end
	end
	local fixedEdges = {}
	for newId, origId in pairs(edgeIdMap) do
		local e = c.edges[newId]
		if e then
			c.edges[newId] = nil
			e.id = origId
			fixedEdges[origId] = e
		end
	end
	for origId, e in pairs(fixedEdges) do
		c.edges[origId] = e
	end
	c._nextEdgeId = bm._nextEdgeId

	return c
end

-- ─── Dissolve ─────────────────────────────────────────────────────────────────

-- Merge the two faces sharing an edge into one N-gon.
-- dissolveVerts: if true, also remove the edge's endpoint vertices if they
-- become redundant (connected to only 2 coplanar edges after dissolve).
function Operations.dissolveEdge(bm, edge, dissolveVerts)
	local faces = BMesh.edgeFaces(edge)
	if #faces ~= 2 then
		return nil
	end

	local faceA = faces[1]
	local faceB = faces[2]
	local VA = edge.v1
	local VB = edge.v2

	local loopA = (edge.loop.face == faceA) and edge.loop or edge.loop.radial_next
	local loopB = loopA.radial_next

	local style = { Color = faceA.color, Transparency = faceA.transparency }

	local mergedVerts = {}
	local l = loopA.next
	while l ~= loopA do
		mergedVerts[#mergedVerts + 1] = l.vert
		l = l.next
	end
	l = loopB.next
	while l ~= loopB do
		mergedVerts[#mergedVerts + 1] = l.vert
		l = l.next
	end

	if #mergedVerts < 3 then
		return nil
	end

	BMesh.removeFace(bm, faceA)
	BMesh.removeFace(bm, faceB)
	local merged = BMesh.addFace(bm, mergedVerts, style)

	-- Optionally dissolve endpoint verts if they're now degree-2 and coplanar
	if dissolveVerts then
		for _, vert in ipairs({ VA, VB }) do
			local vertEdges = BMesh.vertEdges(vert)
			if #vertEdges == 2 then
				-- Check if the two remaining edges are coplanar enough to dissolve
				local vertFaces = BMesh.vertFaces(vert)
				local coplanar = true
				if #vertFaces >= 2 then
					local n1 = BMesh.faceNormal(vertFaces[1])
					for i = 2, #vertFaces do
						if n1:Dot(BMesh.faceNormal(vertFaces[i])) < 0.999 then
							coplanar = false
							break
						end
					end
				end
				if coplanar then
					-- Dissolve this vert: merge its two adjacent edges into one
					-- by rebuilding the face without this vert
					local adjFaces = BMesh.vertFaces(vert)
					for _, f in ipairs(adjFaces) do
						local oldVerts = BMesh.faceVerts(f)
						local newVerts = {}
						for _, v in ipairs(oldVerts) do
							if v ~= vert then
								newVerts[#newVerts + 1] = v
							end
						end
						local fStyle = { Color = f.color, Transparency = f.transparency }
						BMesh.removeFace(bm, f)
						if #newVerts >= 3 then
							BMesh.addFace(bm, newVerts, fStyle)
						end
					end
					BMesh.removeVert(bm, vert)
				end
			end
		end
	end

	return merged
end

-- ─── Extrude ──────────────────────────────────────────────────────────────────

-- Extrude a face outward.
-- Original face verts stay as the BASE ring (still connected to surrounding mesh).
-- New cap verts are created at the same positions and dragged outward by the tool.
-- Side quads connect the base ring to the cap ring.
-- No bottom face is added — the existing mesh topology is the base.
-- Returns { capFace, capVerts, baseVerts, sideFaces } or nil.
function Operations.extrudeFace(bm, face)
	local baseVerts = BMesh.faceVerts(face) -- original verts stay connected to mesh
	local n = #baseVerts
	local style = { Color = face.color, Transparency = face.transparency }

	-- Create new cap verts at the same positions — these get dragged outward
	local capVerts = {}
	for _, v in ipairs(baseVerts) do
		capVerts[#capVerts + 1] = BMesh.addVert(bm, v.position)
	end

	-- Remove the original face (baseVerts remain connected to surrounding mesh edges)
	BMesh.removeFace(bm, face)

	-- Side quads: base[i] → base[i+1] → cap[i+1] → cap[i]
	local sideFaces = {}
	for i = 1, n do
		local b1 = baseVerts[i]
		local b2 = baseVerts[(i % n) + 1]
		local c1 = capVerts[i]
		local c2 = capVerts[(i % n) + 1]
		sideFaces[#sideFaces + 1] = BMesh.addFace(bm, { b1, b2, c2, c1 }, style)
	end

	-- Cap face — new verts, same winding as original face
	local capFace = BMesh.addFace(bm, capVerts, style)

	return {
		capFace = capFace,
		capVerts = capVerts,
		baseVerts = baseVerts,
		sideFaces = sideFaces,
	}
end

-- ─── Bevel edge ───────────────────────────────────────────────────────────────

function Operations.bevelEdge(bm, edge, depth)
	if depth <= 0 then
		return nil
	end
	local adjFaces = BMesh.edgeFaces(edge)
	if #adjFaces ~= 2 then
		return nil
	end

	local VA = edge.v1
	local VB = edge.v2
	local posA = VA.position
	local posB = VB.position

	local facesForVA = BMesh.vertFaces(VA)
	local facesForVB = BMesh.vertFaces(VB)

	local loopInF1 = (edge.loop.face == adjFaces[1]) and edge.loop or edge.loop.radial_next
	local edgeStartIsVA = (loopInF1.vert == VA)

	-- adjFace set for quick lookup
	local isAdjFace = { [adjFaces[1].id] = true, [adjFaces[2].id] = true }

	local newVA = {} -- faceId → new vert retracting VA toward that face
	local newVB = {} -- faceId → new vert retracting VB toward that face

	local function makeRetracted(origVert, origPos, otherVert, face)
		local fv = BMesh.faceVerts(face)
		local fn = #fv
		local neighbor = nil
		for i, v in ipairs(fv) do
			if v == origVert then
				local prev = fv[((i - 2) % fn) + 1]
				local next = fv[(i % fn) + 1]
				neighbor = if prev ~= otherVert then prev else next
				break
			end
		end
		if not neighbor then
			return nil
		end
		local dir = neighbor.position - origPos
		local d = math.min(depth, dir.Magnitude)
		return BMesh.addVert(bm, origPos + safeUnit(dir) * d)
	end

	for _, f in ipairs(facesForVA) do
		local nv = makeRetracted(VA, posA, VB, f)
		if nv then
			newVA[f.id] = nv
		end
	end
	for _, f in ipairs(facesForVB) do
		local nv = makeRetracted(VB, posB, VA, f)
		if nv then
			newVB[f.id] = nv
		end
	end

	-- Collect all faces to rebuild
	local rebuilt = {}
	local seen = {}
	for _, f in ipairs(facesForVA) do
		if not seen[f.id] then
			seen[f.id] = true
			rebuilt[#rebuilt + 1] = f
		end
	end
	for _, f in ipairs(facesForVB) do
		if not seen[f.id] then
			seen[f.id] = true
			rebuilt[#rebuilt + 1] = f
		end
	end

	-- Snapshot all face verts BEFORE any removals so removeFace can't interfere
	local snapshots = {}
	for _, f in ipairs(rebuilt) do
		snapshots[f.id] = BMesh.faceVerts(f)
	end

	for _, f in ipairs(rebuilt) do
		local oldVerts = snapshots[f.id]
		local style = { Color = f.color, Transparency = f.transparency }
		local newVerts = {}
		local hasVA = newVA[f.id] ~= nil
		local hasVB = newVB[f.id] ~= nil

		for _, v in ipairs(oldVerts) do
			if v == VA and hasVA then
				if isAdjFace[f.id] then
					-- AdjFace: just replace VA with its retracted vert
					newVerts[#newVerts + 1] = newVA[f.id]
				else
					-- Non-adjFace: insert BOTH VA retractions in reverse strip order
					local nv1 = newVA[adjFaces[1].id]
					local nv2 = newVA[adjFaces[2].id]
					-- Strip goes nVA1→nVA2, so face must traverse nVA2→nVA1
					if edgeStartIsVA then
						if nv2 then
							newVerts[#newVerts + 1] = nv2
						end
						if nv1 and nv1 ~= nv2 then
							newVerts[#newVerts + 1] = nv1
						end
					else
						if nv1 then
							newVerts[#newVerts + 1] = nv1
						end
						if nv2 and nv2 ~= nv1 then
							newVerts[#newVerts + 1] = nv2
						end
					end
				end
			elseif v == VB and hasVB then
				if isAdjFace[f.id] then
					-- AdjFace: just replace VB with its retracted vert
					newVerts[#newVerts + 1] = newVB[f.id]
				else
					-- Non-adjFace: insert BOTH VB retractions in reverse strip order
					local nv1 = newVB[adjFaces[1].id]
					local nv2 = newVB[adjFaces[2].id]
					-- Strip goes nVB2→nVB1, so face must traverse nVB1→nVB2
					if edgeStartIsVA then
						if nv1 then
							newVerts[#newVerts + 1] = nv1
						end
						if nv2 and nv2 ~= nv1 then
							newVerts[#newVerts + 1] = nv2
						end
					else
						if nv2 then
							newVerts[#newVerts + 1] = nv2
						end
						if nv1 and nv1 ~= nv2 then
							newVerts[#newVerts + 1] = nv1
						end
					end
				end
			else
				newVerts[#newVerts + 1] = v
			end
		end

		BMesh.removeFace(bm, f)
		BMesh.addFace(bm, newVerts, style)
	end

	-- Bevel strip face
	local nVA1 = newVA[adjFaces[1].id]
	local nVA2 = newVA[adjFaces[2].id]
	local nVB1 = newVB[adjFaces[1].id]
	local nVB2 = newVB[adjFaces[2].id]

	local stripStyle = { Color = adjFaces[1].color, Transparency = adjFaces[1].transparency }

	if nVA1 and nVA2 and nVB1 and nVB2 then
		local stripVerts = if edgeStartIsVA then { nVA1, nVA2, nVB2, nVB1 } else { nVB1, nVB2, nVA2, nVA1 }
		BMesh.addFace(bm, stripVerts, stripStyle)
	end

	if not VA.loop then
		BMesh.removeVert(bm, VA)
	end
	if not VB.loop then
		BMesh.removeVert(bm, VB)
	end

	BMesh.removeOrphanedVerts(bm)

	return true
end

-- ─── Bevel vertex ─────────────────────────────────────────────────────────────

function Operations.bevelVertex(bm, vert, depth)
	if depth <= 0 then
		return nil
	end
	if not vert.loop then
		return nil
	end

	local pos = vert.position
	local normal = BMesh.vertNormal(vert)
	local edges = BMesh.vertEdges(vert)
	local adjFaces = BMesh.vertFaces(vert)

	if #edges < 2 then
		return nil
	end

	local newByEdge = {}
	for _, e in ipairs(edges) do
		local nb = if e.v1 == vert then e.v2 else e.v1
		local dir = nb.position - pos
		local d = math.min(depth, if dir.Magnitude > 0 then dir.Magnitude * 0.49 else depth)
		newByEdge[e.id] = BMesh.addVert(bm, pos + safeUnit(dir) * d)
	end

	for _, f in ipairs(adjFaces) do
		local oldVerts = BMesh.faceVerts(f)
		local style = { Color = f.color, Transparency = f.transparency }
		local newVerts = {}
		local fn = #oldVerts
		for i, v in ipairs(oldVerts) do
			if v == vert then
				local nextV = oldVerts[(i % fn) + 1]
				local found = nil
				for _, e in ipairs(edges) do
					local nb = if e.v1 == vert then e.v2 else e.v1
					if nb == nextV then
						found = newByEdge[e.id]
						break
					end
				end
				newVerts[#newVerts + 1] = found or v
			else
				newVerts[#newVerts + 1] = v
			end
		end
		BMesh.removeFace(bm, f)
		BMesh.addFace(bm, newVerts, style)
	end

	local capVerts = {}
	for _, nv in pairs(newByEdge) do
		capVerts[#capVerts + 1] = nv
	end

	local ref = nil
	for _, v in ipairs(capVerts) do
		local off = v.position - pos
		if off.Magnitude > 1e-5 then
			ref = off.Unit
			break
		end
	end
	if ref then
		local yAx = safeUnit(normal:Cross(ref))
		if yAx.Magnitude > 1e-5 then
			table.sort(capVerts, function(a, b)
				local oa = a.position - pos
				local ob = b.position - pos
				return math.atan2(oa:Dot(yAx), oa:Dot(ref)) < math.atan2(ob:Dot(yAx), ob:Dot(ref))
			end)
		end
	end

	BMesh.removeVert(bm, vert)

	if #capVerts >= 3 then
		local style = adjFaces[1] and { Color = adjFaces[1].color, Transparency = adjFaces[1].transparency }
		BMesh.addFace(bm, capVerts, style)
	end

	return true
end

-- ─── Planar dissolve (load-time) ──────────────────────────────────────────────

function Operations.dissolvePlanar(bm, threshold)
	threshold = threshold or 0.999
	local candidates = {}
	for _, edge in pairs(bm.edges) do
		local faces = BMesh.edgeFaces(edge)
		if #faces == 2 then
			local dot = BMesh.faceNormal(faces[1]):Dot(BMesh.faceNormal(faces[2]))
			if dot >= threshold then
				candidates[#candidates + 1] = { edge = edge, score = dot }
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.score > b.score
	end)
	for _, c in ipairs(candidates) do
		if bm.edges[c.edge.id] then
			Operations.dissolveEdge(bm, c.edge, false)
		end
	end
end

return Operations
