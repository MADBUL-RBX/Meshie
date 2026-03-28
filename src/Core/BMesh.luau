-- BMesh.luau
-- Half-edge mesh data structure.
-- Elements: Vert, Edge, Face, Loop.
-- Loops are the connective tissue — one per (vert, face) participation.
-- All adjacency queries are O(1) pointer follows.

local BMesh = {}

-- ─── Construction ─────────────────────────────────────────────────────────────

function BMesh.new()
	return {
		verts       = {},
		edges       = {},
		faces       = {},
		_nextVertId = 1,
		_nextEdgeId = 1,
		_nextFaceId = 1,
	}
end

-- ─── Element creation ─────────────────────────────────────────────────────────

function BMesh.addVert(bm, position)
	local id   = bm._nextVertId
	bm._nextVertId += 1
	local vert = { id = id, position = position, loop = nil }
	bm.verts[id] = vert
	return vert
end

local function findEdge(bm, v1, v2)
	for _, e in pairs(bm.edges) do
		if (e.v1 == v1 and e.v2 == v2) or (e.v1 == v2 and e.v2 == v1) then
			return e
		end
	end
	return nil
end

local function getOrCreateEdge(bm, v1, v2)
	local existing = findEdge(bm, v1, v2)
	if existing then return existing end
	local id   = bm._nextEdgeId
	bm._nextEdgeId += 1
	local edge = { id = id, v1 = v1, v2 = v2, loop = nil }
	bm.edges[id] = edge
	return edge
end

local function radialAppend(edge, loop)
	if not edge.loop then
		edge.loop        = loop
		loop.radial_next = loop
		loop.radial_prev = loop
	else
		local existing           = edge.loop
		local existingNext       = existing.radial_next
		existing.radial_next     = loop
		loop.radial_prev         = existing
		loop.radial_next         = existingNext
		existingNext.radial_prev = loop
	end
end

local function radialRemove(edge, loop)
	if loop.radial_next == loop then
		edge.loop = nil
	else
		loop.radial_prev.radial_next = loop.radial_next
		loop.radial_next.radial_prev = loop.radial_prev
		if edge.loop == loop then edge.loop = loop.radial_next end
	end
	loop.radial_next = nil
	loop.radial_prev = nil
end

-- verts: ordered array of BMVert (3+)
-- style: { Color, Transparency } optional
function BMesh.addFace(bm, verts, style)
	assert(#verts >= 3, "BMesh.addFace: need at least 3 verts")
	local id   = bm._nextFaceId
	bm._nextFaceId += 1
	local face = {
		id           = id,
		loop         = nil,
		color        = (style and style.Color) or Color3.new(1, 1, 1),
		transparency = (style and style.Transparency) or 0,
	}
	bm.faces[id] = face

	local n     = #verts
	local loops = table.create(n)
	for i = 1, n do
		loops[i] = {
			vert        = verts[i],
			edge        = nil,
			face        = face,
			next        = nil,
			prev        = nil,
			radial_next = nil,
			radial_prev = nil,
		}
	end

	for i = 1, n do
		loops[i].next = loops[(i % n) + 1]
		loops[i].prev = loops[((i - 2) % n) + 1]
	end

	for i = 1, n do
		local loop = loops[i]
		local vA   = verts[i]
		local vB   = verts[(i % n) + 1]
		local edge = getOrCreateEdge(bm, vA, vB)
		loop.edge  = edge
		radialAppend(edge, loop)
		if not vA.loop then vA.loop = loop end
	end

	face.loop = loops[1]
	return face
end

-- ─── removeFace ───────────────────────────────────────────────────────────────

function BMesh.removeFace(bm, face)
	local loops = BMesh.faceLoops(face)

	local needUpdate = {}
	for _, l in ipairs(loops) do
		if l.vert.loop == l then
			l.vert.loop = nil
			needUpdate[#needUpdate + 1] = l.vert
		end
	end

	for _, l in ipairs(loops) do
		if l.radial_next == l then
			l.edge.loop = nil
			bm.edges[l.edge.id] = nil
		else
			radialRemove(l.edge, l)
		end
	end

	bm.faces[face.id] = nil

	for _, vert in ipairs(needUpdate) do
		for _, e in pairs(bm.edges) do
			if not e.loop then continue end
			local el = e.loop
			repeat
				if el.vert == vert then
					vert.loop = el
					break
				end
				el = el.radial_next
			until el == e.loop or vert.loop
			if vert.loop then break end
		end
	end
end

function BMesh.removeVert(bm, vert)
	bm.verts[vert.id] = nil
end

-- ─── Traversal ────────────────────────────────────────────────────────────────

function BMesh.faceLoops(face)
	local result = {}
	local start  = face.loop
	local l      = start
	repeat
		result[#result + 1] = l
		l = l.next
	until l == start
	return result
end

function BMesh.faceVerts(face)
	local result = {}
	local start  = face.loop
	local l      = start
	repeat
		result[#result + 1] = l.vert
		l = l.next
	until l == start
	return result
end

function BMesh.edgeFaces(edge)
	local result = {}
	if not edge.loop then return result end
	local start = edge.loop
	local l     = start
	repeat
		result[#result + 1] = l.face
		l = l.radial_next
	until l == start
	return result
end

function BMesh.vertFaces(vert)
	local result = {}
	if not vert.loop then return result end
	local start = vert.loop
	local l     = start
	repeat
		result[#result + 1] = l.face
		l = l.radial_next.next
	until l == start
	return result
end

function BMesh.vertEdges(vert)
	local result = {}
	if not vert.loop then return result end
	local start = vert.loop
	local l     = start
	repeat
		result[#result + 1] = l.edge
		l = l.radial_next.next
	until l == start
	return result
end

function BMesh.isBoundaryEdge(edge)
	return edge.loop ~= nil and edge.loop.radial_next == edge.loop
end

-- ─── Geometry ─────────────────────────────────────────────────────────────────

-- Face normal using Newell's method (correct for N-gons)
function BMesh.faceNormal(face)
	local n     = Vector3.zero
	local start = face.loop
	local l     = start
	repeat
		local curr = l.vert.position
		local next = l.next.vert.position
		n += curr:Cross(next)
		l = l.next
	until l == start
	if n.Magnitude > 1e-5 then return n.Unit end
	return Vector3.new(0, 1, 0)
end

function BMesh.faceCentroid(face)
	local sum   = Vector3.zero
	local count = 0
	local start = face.loop
	local l     = start
	repeat
		sum   += l.vert.position
		count += 1
		l = l.next
	until l == start
	return sum / count
end

function BMesh.vertNormal(vert)
	local sum = Vector3.zero
	for _, f in ipairs(BMesh.vertFaces(vert)) do
		sum += BMesh.faceNormal(f)
	end
	if sum.Magnitude > 1e-5 then return sum.Unit end
	return Vector3.new(0, 1, 0)
end

function BMesh.edgeMidpoint(edge)
	return (edge.v1.position + edge.v2.position) * 0.5
end

function BMesh.edgeNormal(edge)
	local sum = Vector3.zero
	for _, f in ipairs(BMesh.edgeFaces(edge)) do
		sum += BMesh.faceNormal(f)
	end
	if sum.Magnitude > 1e-5 then return sum.Unit end
	return Vector3.new(0, 1, 0)
end

function BMesh.removeOrphanedVerts(bm)
	for id, vert in pairs(bm.verts) do
		if #BMesh.vertFaces(vert) == 0 then
			bm.verts[id] = nil
		end
	end
end

return BMesh
