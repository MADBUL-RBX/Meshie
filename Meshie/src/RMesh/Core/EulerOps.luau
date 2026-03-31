-- EulerOps.luau
-- Pure mesh mutation operations.
-- No knowledge of EditableMesh, proxies, or scene state.

local DataStructure = require(script.Parent.DataStructure)

local EulerOps = {}

local function safeUnit(v)
	if v.Magnitude > 1e-5 then
		return v.Unit
	end
	return Vector3.zero
end

-- ─── Clone ────────────────────────────────────────────────────────────────────
-- Deep clone a mesh preserving all element IDs.
-- Critical for bevel snapshot/restore — IDs must match so lookups work.
function EulerOps.cloneBMesh(bm)
	local c = DataStructure.new()
	c._nextVertId = bm._nextVertId
	c._nextEdgeId = bm._nextEdgeId
	c._nextFaceId = bm._nextFaceId

	for id, v in pairs(bm.verts) do
		c.verts[id] = { id = id, position = v.position, edge = nil, normal = v.normal }
	end

	for _, face in pairs(bm.faces) do
		local origVerts = DataStructure.faceVerts(face)
		local cloneVerts = {}
		for _, v in ipairs(origVerts) do
			cloneVerts[#cloneVerts + 1] = c.verts[v.id]
		end
		local newFace = DataStructure.addFace(c, cloneVerts, {
			Color = face.color,
			Transparency = face.transparency,
		})
		c.faces[newFace.id] = nil
		newFace.id     = face.id
		newFace.normal = face.normal
		c.faces[face.id] = newFace
	end
	c._nextFaceId = bm._nextFaceId

	local edgeIdMap = {}
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
		local orig = bm.edges[origId]
		if orig then
			e.normal  = orig.normal
			e.tangent = orig.tangent
		end
	end
	c._nextEdgeId = bm._nextEdgeId

	return c
end

-- ─── Dissolve ─────────────────────────────────────────────────────────────────

function EulerOps.dissolveEdge(bm, edge, dissolveVerts)
	local faces = DataStructure.edgeFaces(edge)
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

	DataStructure.removeFace(bm, faceA)
	DataStructure.removeFace(bm, faceB)
	local merged = DataStructure.addFace(bm, mergedVerts, style)

	if dissolveVerts then
		for _, vert in ipairs({ VA, VB }) do
			local vertEdges = DataStructure.vertEdges(vert)
			if #vertEdges == 2 then
				local vertFaces = DataStructure.vertFaces(vert)
				local coplanar = true
				if #vertFaces >= 2 then
					local n1 = DataStructure.faceNormal(vertFaces[1])
					for i = 2, #vertFaces do
						if n1:Dot(DataStructure.faceNormal(vertFaces[i])) < 0.999 then
							coplanar = false
							break
						end
					end
				end
				if coplanar then
					local adjFaces = DataStructure.vertFaces(vert)
					for _, f in ipairs(adjFaces) do
						local oldVerts = DataStructure.faceVerts(f)
						local newVerts = {}
						for _, v in ipairs(oldVerts) do
							if v ~= vert then
								newVerts[#newVerts + 1] = v
							end
						end
						local fStyle = { Color = f.color, Transparency = f.transparency }
						DataStructure.removeFace(bm, f)
						if #newVerts >= 3 then
							DataStructure.addFace(bm, newVerts, fStyle)
						end
					end
					DataStructure.removeVert(bm, vert)
				end
			end
		end
	end

	return merged
end

-- ─── Extrude ──────────────────────────────────────────────────────────────────

function EulerOps.extrudeFace(bm, face)
	local baseVerts = DataStructure.faceVerts(face)
	local n = #baseVerts
	local style = { Color = face.color, Transparency = face.transparency }

	local capVerts = {}
	for _, v in ipairs(baseVerts) do
		capVerts[#capVerts + 1] = DataStructure.addVert(bm, v.position)
	end

	DataStructure.removeFace(bm, face)

	local sideFaces = {}
	for i = 1, n do
		local b1 = baseVerts[i]
		local b2 = baseVerts[(i % n) + 1]
		local c1 = capVerts[i]
		local c2 = capVerts[(i % n) + 1]
		sideFaces[#sideFaces + 1] = DataStructure.addFace(bm, { b1, b2, c2, c1 }, style)
	end

	local capFace = DataStructure.addFace(bm, capVerts, style)

	return {
		capFace = capFace,
		capVerts = capVerts,
		baseVerts = baseVerts,
		sideFaces = sideFaces,
	}
end

-- ─── Bevel edge ───────────────────────────────────────────────────────────────

function EulerOps.bevelEdge(bm, edge, depth)
	if depth <= 0 then return nil end
	local adjFaces = DataStructure.edgeFaces(edge)
	if #adjFaces ~= 2 then return nil end

	local VA = edge.v1
	local VB = edge.v2
	local posA = VA.position
	local posB = VB.position

	local facesForVA = DataStructure.vertFaces(VA)
	local facesForVB = DataStructure.vertFaces(VB)

	local loopInF1 = (edge.loop.face == adjFaces[1]) and edge.loop or edge.loop.radial_next
	local edgeStartIsVA = (loopInF1.vert == VA)

	local isAdjFace = { [adjFaces[1].id] = true, [adjFaces[2].id] = true }

	local newVA = {}
	local newVB = {}

	local function makeRetracted(origVert, origPos, otherVert, face)
		local fv = DataStructure.faceVerts(face)
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
		if not neighbor then return nil end
		local dir = neighbor.position - origPos
		local d = math.min(depth, dir.Magnitude)
		return DataStructure.addVert(bm, origPos + safeUnit(dir) * d)
	end

	for _, f in ipairs(facesForVA) do
		local nv = makeRetracted(VA, posA, VB, f)
		if nv then newVA[f.id] = nv end
	end
	for _, f in ipairs(facesForVB) do
		local nv = makeRetracted(VB, posB, VA, f)
		if nv then newVB[f.id] = nv end
	end

	local rebuilt = {}
	local seen = {}
	for _, f in ipairs(facesForVA) do
		if not seen[f.id] then seen[f.id] = true; rebuilt[#rebuilt + 1] = f end
	end
	for _, f in ipairs(facesForVB) do
		if not seen[f.id] then seen[f.id] = true; rebuilt[#rebuilt + 1] = f end
	end

	local snapshots = {}
	for _, f in ipairs(rebuilt) do
		snapshots[f.id] = DataStructure.faceVerts(f)
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
					newVerts[#newVerts + 1] = newVA[f.id]
				else
					local nv1 = newVA[adjFaces[1].id]
					local nv2 = newVA[adjFaces[2].id]
					if edgeStartIsVA then
						if nv2 then newVerts[#newVerts + 1] = nv2 end
						if nv1 and nv1 ~= nv2 then newVerts[#newVerts + 1] = nv1 end
					else
						if nv1 then newVerts[#newVerts + 1] = nv1 end
						if nv2 and nv2 ~= nv1 then newVerts[#newVerts + 1] = nv2 end
					end
				end
			elseif v == VB and hasVB then
				if isAdjFace[f.id] then
					newVerts[#newVerts + 1] = newVB[f.id]
				else
					local nv1 = newVB[adjFaces[1].id]
					local nv2 = newVB[adjFaces[2].id]
					if edgeStartIsVA then
						if nv1 then newVerts[#newVerts + 1] = nv1 end
						if nv2 and nv2 ~= nv1 then newVerts[#newVerts + 1] = nv2 end
					else
						if nv2 then newVerts[#newVerts + 1] = nv2 end
						if nv1 and nv1 ~= nv2 then newVerts[#newVerts + 1] = nv1 end
					end
				end
			else
				newVerts[#newVerts + 1] = v
			end
		end

		DataStructure.removeFace(bm, f)
		DataStructure.addFace(bm, newVerts, style)
	end

	local nVA1 = newVA[adjFaces[1].id]
	local nVA2 = newVA[adjFaces[2].id]
	local nVB1 = newVB[adjFaces[1].id]
	local nVB2 = newVB[adjFaces[2].id]

	local stripStyle = { Color = adjFaces[1].color, Transparency = adjFaces[1].transparency }

	if nVA1 and nVA2 and nVB1 and nVB2 then
		local stripVerts = if edgeStartIsVA then { nVA1, nVA2, nVB2, nVB1 } else { nVB1, nVB2, nVA2, nVA1 }
		DataStructure.addFace(bm, stripVerts, stripStyle)
	end

	if not VA.edge then DataStructure.removeVert(bm, VA) end
	if not VB.edge then DataStructure.removeVert(bm, VB) end
	DataStructure.removeOrphanedVerts(bm)

	return true
end

-- ─── Bevel vertex ─────────────────────────────────────────────────────────────

function EulerOps.bevelVertex(bm, vert, depth)
	if depth <= 0 then return nil end
	if not vert.edge then return nil end

	local pos = vert.position
	local normal = DataStructure.vertNormal(vert)
	local edges = DataStructure.vertEdges(vert)
	local adjFaces = DataStructure.vertFaces(vert)

	if #edges < 2 then return nil end

	local newByEdge = {}
	for _, e in ipairs(edges) do
		local nb = if e.v1 == vert then e.v2 else e.v1
		local dir = nb.position - pos
		local d = math.min(depth, if dir.Magnitude > 0 then dir.Magnitude * 0.49 else depth)
		newByEdge[e.id] = DataStructure.addVert(bm, pos + safeUnit(dir) * d)
	end

	for _, f in ipairs(adjFaces) do
		local oldVerts = DataStructure.faceVerts(f)
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
		DataStructure.removeFace(bm, f)
		DataStructure.addFace(bm, newVerts, style)
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

	DataStructure.removeVert(bm, vert)

	if #capVerts >= 3 then
		local style = adjFaces[1] and { Color = adjFaces[1].color, Transparency = adjFaces[1].transparency }
		DataStructure.addFace(bm, capVerts, style)
	end

	return true
end

-- ─── Planar dissolve (load-time) ──────────────────────────────────────────────

function EulerOps.dissolvePlanar(bm, threshold)
	threshold = threshold or 0.999
	local candidates = {}
	for _, edge in pairs(bm.edges) do
		local faces = DataStructure.edgeFaces(edge)
		if #faces == 2 then
			local dot = DataStructure.faceNormal(faces[1]):Dot(DataStructure.faceNormal(faces[2]))
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
			EulerOps.dissolveEdge(bm, c.edge, false)
		end
	end
end

return EulerOps
