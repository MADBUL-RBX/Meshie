-- MeshIO.luau
-- Converts between EditableMesh and BMesh.
--
-- fromEditableMesh: loads an EditableMesh into a BMesh.
--   Runs dissolvePlanar after loading to merge coplanar triangle pairs into N-gons.

local HttpService = game:GetService("HttpService")

local BMesh      = require(script.Parent.BMesh)
local Operations = require(script.Parent.Operations)

local MeshIO = {}

local TOPO_SNAP = 1e4  -- round positions to 4 decimal places for compact storage
local TOPO_TOL  = 0.001 -- match tolerance on reload (MergeVertices threshold)

local function snapV(v)
	return {
		math.round(v.X * TOPO_SNAP) / TOPO_SNAP,
		math.round(v.Y * TOPO_SNAP) / TOPO_SNAP,
		math.round(v.Z * TOPO_SNAP) / TOPO_SNAP,
	}
end

-- Serialize BMesh face topology to a JSON string.
-- Positions are in mesh-local space. Colors and transparency are included.
function MeshIO.serializeTopology(bm)
	local faces = {}
	for _, face in pairs(bm.faces) do
		local verts = BMesh.faceVerts(face)
		local positions = {}
		for _, v in ipairs(verts) do
			positions[#positions + 1] = snapV(v.position)
		end
		faces[#faces + 1] = {
			v = positions,
			c = { face.color.R, face.color.G, face.color.B },
			t = face.transparency,
		}
	end
	return HttpService:JSONEncode(faces)
end

-- Reconstruct BMesh from serialized topology + a freshly loaded EM.
-- Matches serialized positions to EM vertices within TOPO_TOL.
-- Returns nil if any face vertex cannot be matched — caller should fall back
-- to fromEditableMesh.
function MeshIO.fromTopology(em, jsonStr, defaultTransparency)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(jsonStr)
	end)
	if not ok or type(data) ~= "table" then
		return nil
	end

	-- Build flat list of EM vertex positions for matching.
	local emVerts = {}
	for _, vid in ipairs(em:GetVertices()) do
		local p = em:GetPosition(vid)
		emVerts[#emVerts + 1] = { id = vid, pos = p }
	end

	local function findEmId(x, y, z)
		for _, v in ipairs(emVerts) do
			if math.abs(v.pos.X - x) < TOPO_TOL
				and math.abs(v.pos.Y - y) < TOPO_TOL
				and math.abs(v.pos.Z - z) < TOPO_TOL
			then
				return v.id
			end
		end
		return nil
	end

	local bm        = BMesh.new()
	local vertByEmId = {}

	for _, faceData in ipairs(data) do
		local bmVerts = {}
		local valid   = true

		for _, pos in ipairs(faceData.v) do
			local emId = findEmId(pos[1], pos[2], pos[3])
			if not emId then
				return nil  -- unmatched vertex — fall back
			end
			if not vertByEmId[emId] then
				local v   = BMesh.addVert(bm, em:GetPosition(emId))
				v.emId    = emId
				vertByEmId[emId] = v
			end
			bmVerts[#bmVerts + 1] = vertByEmId[emId]
		end

		if not valid or #bmVerts < 3 then
			return nil
		end

		local c = faceData.c
		BMesh.addFace(bm, bmVerts, {
			Color        = Color3.new(c[1], c[2], c[3]),
			Transparency = faceData.t or defaultTransparency,
		})
	end

	return bm
end

-- Build a BMesh from an EditableMesh.
-- The EM must already be MergeVertices'd.
function MeshIO.fromEditableMesh(em, defaultColor, defaultTransparency)
	local bm       = BMesh.new()
	local vertById = {}  -- em vertex id → BMVert

	for _, vid in ipairs(em:GetVertices()) do
		local v       = BMesh.addVert(bm, em:GetPosition(vid))
		v.emId        = vid
		vertById[vid] = v
	end

	local function getColor(fid)
		local colorIds = em:GetFaceColors(fid)
		if colorIds and #colorIds > 0 then
			local c = em:GetColor(colorIds[1])
			if c then return c end
		end
		return defaultColor
	end

	for _, fid in ipairs(em:GetFaces()) do
		local vids = em:GetFaceVertices(fid)
		local v1   = vertById[vids[1]]
		local v2   = vertById[vids[2]]
		local v3   = vertById[vids[3]]
		if v1 and v2 and v3 then
			BMesh.addFace(bm, { v1, v2, v3 }, {
				Color        = getColor(fid),
				Transparency = defaultTransparency,
			})
		end
	end

	-- Merge coplanar triangle pairs into quads/N-gons.
	-- Threshold ~= 1.0 means only perfectly flat pairs merge.
	Operations.dissolvePlanar(bm, 0.999)

	return bm
end

return MeshIO
