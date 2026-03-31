-- DataStructure.luau
-- Half-edge mesh data structure, modelled after Blender's BMesh.
-- Elements: Vert, Edge, Face, Loop.
--
-- Connectivity:
--   Vert  → edges via disk cycle   (vert.edge + edge.v1_disk / edge.v2_disk)
--   Edge  → faces via radial cycle (edge.loop + loop.radial_next / radial_prev)
--   Face  → loops via face cycle   (face.loop + loop.next / loop.prev)
--
-- All adjacency queries are O(valence) pointer follows, no linear scans.

local DataStructure = {}

-- ─── Construction ─────────────────────────────────────────────────────────────

function DataStructure.new()
	return {
		verts = {},
		edges = {},
		faces = {},
		_nextVertId = 1,
		_nextEdgeId = 1,
		_nextFaceId = 1,
	}
end

-- ─── Element creation ─────────────────────────────────────────────────────────

function DataStructure.addVert(bm, position)
	local id = bm._nextVertId
	bm._nextVertId += 1
	local vert = { id = id, position = position, edge = nil }
	bm.verts[id] = vert
	return vert
end

-- ─── Disk cycle (vert ↔ edge) ─────────────────────────────────────────────────

-- Returns the disk link table for `edge` at vertex `vert`.
local function diskLink(edge, vert)
	return if vert == edge.v1 then edge.v1_disk else edge.v2_disk
end

-- Insert `edge` into `vert`'s disk cycle.
local function diskAppend(edge, vert)
	local link = diskLink(edge, vert)
	if not vert.edge then
		vert.edge  = edge
		link.next  = edge
		link.prev  = edge
	else
		local first     = vert.edge
		local firstLink = diskLink(first, vert)
		local last      = firstLink.prev
		local lastLink  = diskLink(last, vert)
		lastLink.next  = edge
		link.prev      = last
		link.next      = first
		firstLink.prev = edge
	end
end

-- Remove `edge` from `vert`'s disk cycle.
local function diskRemove(edge, vert)
	local link = diskLink(edge, vert)
	if link.next == edge then
		vert.edge = nil
	else
		local n = link.next
		local p = link.prev
		diskLink(n, vert).prev = p
		diskLink(p, vert).next = n
		if vert.edge == edge then
			vert.edge = n
		end
	end
	link.next = nil
	link.prev = nil
end

-- ─── Radial cycle (edge ↔ face via loops) ────────────────────────────────────

local function radialAppend(edge, loop)
	if not edge.loop then
		edge.loop       = loop
		loop.radial_next = loop
		loop.radial_prev = loop
	else
		local existing     = edge.loop
		local existingNext = existing.radial_next
		existing.radial_next  = loop
		loop.radial_prev      = existing
		loop.radial_next      = existingNext
		existingNext.radial_prev = loop
	end
end

local function radialRemove(edge, loop)
	if loop.radial_next == loop then
		edge.loop = nil
	else
		loop.radial_prev.radial_next = loop.radial_next
		loop.radial_next.radial_prev = loop.radial_prev
		if edge.loop == loop then
			edge.loop = loop.radial_next
		end
	end
	loop.radial_next = nil
	loop.radial_prev = nil
end

-- ─── Face creation ────────────────────────────────────────────────────────────

-- verts: ordered array of Vert (3+)
-- style: { Color, Transparency } optional
function DataStructure.addFace(bm, verts, style)
	assert(#verts >= 3, "DataStructure.addFace: need at least 3 verts")
	local id = bm._nextFaceId
	bm._nextFaceId += 1
	local face = {
		id           = id,
		loop         = nil,
		color        = (style and style.Color)        or Color3.new(1, 1, 1),
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
		local edge = DataStructure._getOrCreateEdge(bm, vA, vB)
		loop.edge  = edge
		radialAppend(edge, loop)
	end

	face.loop = loops[1]
	return face
end

function DataStructure._getOrCreateEdge(bm, v1, v2)
	-- Check existing edges via disk — O(valence), no full scan.
	if v1.edge then
		local start = v1.edge
		local e     = start
		repeat
			if (e.v1 == v1 and e.v2 == v2) or (e.v1 == v2 and e.v2 == v1) then
				return e
			end
			e = diskLink(e, v1).next
		until e == start
	end
	local id = bm._nextEdgeId
	bm._nextEdgeId += 1
	local edge = {
		id      = id,
		v1      = v1,
		v2      = v2,
		loop    = nil,
		v1_disk = {},
		v2_disk = {},
	}
	bm.edges[id] = edge
	diskAppend(edge, v1)
	diskAppend(edge, v2)
	return edge
end

-- ─── Face removal ─────────────────────────────────────────────────────────────

function DataStructure.removeFace(bm, face)
	local loops = DataStructure.faceLoops(face)

	for _, l in ipairs(loops) do
		if l.radial_next == l then
			-- Last face using this edge — remove it entirely.
			diskRemove(l.edge, l.edge.v1)
			diskRemove(l.edge, l.edge.v2)
			l.edge.loop    = nil
			bm.edges[l.edge.id] = nil
		else
			radialRemove(l.edge, l)
		end
	end

	bm.faces[face.id] = nil
end

function DataStructure.removeVert(bm, vert)
	bm.verts[vert.id] = nil
end

-- ─── Traversal ────────────────────────────────────────────────────────────────

function DataStructure.faceLoops(face)
	local result = {}
	local start  = face.loop
	local l      = start
	repeat
		result[#result + 1] = l
		l = l.next
	until l == start
	return result
end

function DataStructure.faceVerts(face)
	local result = {}
	local start  = face.loop
	local l      = start
	repeat
		result[#result + 1] = l.vert
		l = l.next
	until l == start
	return result
end

function DataStructure.edgeFaces(edge)
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

-- Walk the disk cycle to collect all edges connected to vert.
function DataStructure.vertEdges(vert)
	local result = {}
	if not vert.edge then return result end
	local start = vert.edge
	local e     = start
	repeat
		result[#result + 1] = e
		e = diskLink(e, vert).next
	until e == start
	return result
end

-- Walk disk then radial to collect all faces containing vert.
-- Correct for both manifold and boundary geometry.
function DataStructure.vertFaces(vert)
	local result = {}
	if not vert.edge then return result end
	local seen  = {}
	local start = vert.edge
	local e     = start
	repeat
		if e.loop then
			local sl = e.loop
			local l  = sl
			repeat
				if not seen[l.face.id] then
					seen[l.face.id]     = true
					result[#result + 1] = l.face
				end
				l = l.radial_next
			until l == sl
		end
		e = diskLink(e, vert).next
	until e == start
	return result
end

function DataStructure.isBoundaryEdge(edge)
	return edge.loop ~= nil and edge.loop.radial_next == edge.loop
end

-- ─── Geometry ─────────────────────────────────────────────────────────────────

-- Face normal using Newell's method (correct for N-gons).
function DataStructure.faceNormal(face)
	local n     = Vector3.zero
	local start = face.loop
	local l     = start
	repeat
		local curr = l.vert.position
		local next = l.next.vert.position
		n += curr:Cross(next)
		l = l.next
	until l == start
	if n.Magnitude > 1e-5 then
		return n.Unit
	end
	return Vector3.new(0, 1, 0)
end

function DataStructure.faceCentroid(face)
	local sum   = Vector3.zero
	local count = 0
	local start = face.loop
	local l     = start
	repeat
		sum   += l.vert.position
		count += 1
		l      = l.next
	until l == start
	return sum / count
end

function DataStructure.vertNormal(vert)
	local sum = Vector3.zero
	for _, f in ipairs(DataStructure.vertFaces(vert)) do
		sum += DataStructure.faceNormal(f)
	end
	if sum.Magnitude > 1e-5 then
		return sum.Unit
	end
	return Vector3.new(0, 1, 0)
end

function DataStructure.edgeMidpoint(edge)
	return (edge.v1.position + edge.v2.position) * 0.5
end

function DataStructure.edgeNormal(edge)
	local sum = Vector3.zero
	for _, f in ipairs(DataStructure.edgeFaces(edge)) do
		sum += DataStructure.faceNormal(f)
	end
	if sum.Magnitude > 1e-5 then
		return sum.Unit
	end
	return Vector3.new(0, 1, 0)
end

function DataStructure.removeOrphanedVerts(bm)
	for id, vert in pairs(bm.verts) do
		if not vert.edge then
			bm.verts[id] = nil
		end
	end
end

-- ─── Normal cache ─────────────────────────────────────────────────────────────

-- Compute and store normals/tangents on all mesh elements (local space).
-- Sets face.normal, vert.normal, edge.normal, edge.tangent.
function DataStructure.computeNormals(bm)
	for _, face in pairs(bm.faces) do
		face.normal = DataStructure.faceNormal(face)
	end
	for _, vert in pairs(bm.verts) do
		local sum = Vector3.zero
		for _, f in ipairs(DataStructure.vertFaces(vert)) do
			sum += f.normal
		end
		vert.normal = if sum.Magnitude > 1e-5 then sum.Unit else Vector3.new(0, 1, 0)
	end
	for _, edge in pairs(bm.edges) do
		local sum = Vector3.zero
		for _, f in ipairs(DataStructure.edgeFaces(edge)) do
			sum += f.normal
		end
		edge.normal = if sum.Magnitude > 1e-5 then sum.Unit else Vector3.new(0, 1, 0)
		local dir = edge.v2.position - edge.v1.position
		edge.tangent = if dir.Magnitude > 1e-5 then dir.Unit else Vector3.new(1, 0, 0)
	end
end

return DataStructure
