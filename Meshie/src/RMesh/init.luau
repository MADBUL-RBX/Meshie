-- RMesh/init.luau
-- The mesh editing kernel singleton.
-- Single source of truth for all mesh data.
--
-- RMesh.em  (EditableMesh) — NEVER :Destroy(). Nil and let GC.
-- RMesh.bm  (mesh data)    — N-gon half-edge structure over EM.
-- RMesh.sourceMeshPart     — Hidden in ServerStorage during session.

local AssetService = game:GetService("AssetService")
local HttpService  = game:GetService("HttpService")

local DataStructure = require(script.Core.DataStructure)
local EulerOps      = require(script.Core.EulerOps)

local RMesh = {}

-- ─── State ────────────────────────────────────────────────────────────────────

RMesh.em             = nil
RMesh.bm             = nil
RMesh.sourceMeshPart = nil
local _sourceMeshPartParent = nil

-- ─── Private ──────────────────────────────────────────────────────────────────

local function hideSource()
	_sourceMeshPartParent       = RMesh.sourceMeshPart.Parent
	RMesh.sourceMeshPart.Parent = game:GetService("ServerStorage")
end

local function restoreSource()
	if RMesh.sourceMeshPart and _sourceMeshPartParent then
		RMesh.sourceMeshPart.Parent = _sourceMeshPartParent
		_sourceMeshPartParent       = nil
	end
end

local function rebuildEM()
	if not RMesh.bm or not RMesh.em then return end

	for _, fid in ipairs(RMesh.em:GetFaces()) do
		RMesh.em:RemoveFace(fid)
	end
	RMesh.em:RemoveUnused()

	local emIdByVert   = {}
	local colorIdByKey = {}

	for _, vert in pairs(RMesh.bm.verts) do
		local vid        = RMesh.em:AddVertex(vert.position)
		emIdByVert[vert] = vid
		vert.emId        = vid
	end

	local function getColorId(face)
		local ck = tostring(face.color.R) .. "|" .. tostring(face.color.G)
			.. "|" .. tostring(face.color.B) .. "|" .. tostring(face.transparency)
		if not colorIdByKey[ck] then
			colorIdByKey[ck] = RMesh.em:AddColor(face.color, face.transparency)
		end
		return colorIdByKey[ck]
	end

	for _, face in pairs(RMesh.bm.faces) do
		local verts = DataStructure.faceVerts(face)
		local n = #verts
		if n < 3 then continue end
		local colorId = getColorId(face)
		for i = 2, n - 1 do
			local fid = RMesh.em:AddTriangle(emIdByVert[verts[1]], emIdByVert[verts[i]], emIdByVert[verts[i + 1]])
			RMesh.em:SetFaceColors(fid, { colorId, colorId, colorId })
			local nid = RMesh.em:AddNormal()
			RMesh.em:SetFaceNormals(fid, { nid, nid, nid })
		end
	end
end

-- ─── MeshIO (absorbed) ────────────────────────────────────────────────────────

local TOPO_SNAP = 1e4
local TOPO_TOL  = 0.001

local function snapV(v)
	return {
		math.round(v.X * TOPO_SNAP) / TOPO_SNAP,
		math.round(v.Y * TOPO_SNAP) / TOPO_SNAP,
		math.round(v.Z * TOPO_SNAP) / TOPO_SNAP,
	}
end

local function serializeTopology(bm)
	local faces = {}
	for _, face in pairs(bm.faces) do
		local verts = DataStructure.faceVerts(face)
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

local function fromTopology(em, jsonStr, defaultTransparency)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(jsonStr)
	end)
	if not ok or type(data) ~= "table" then return nil end

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

	local bm         = DataStructure.new()
	local vertByEmId = {}

	for _, faceData in ipairs(data) do
		local bmVerts = {}
		local valid   = true

		for _, pos in ipairs(faceData.v) do
			local emId = findEmId(pos[1], pos[2], pos[3])
			if not emId then return nil end
			if not vertByEmId[emId] then
				local v   = DataStructure.addVert(bm, em:GetPosition(emId))
				v.emId    = emId
				vertByEmId[emId] = v
			end
			bmVerts[#bmVerts + 1] = vertByEmId[emId]
		end

		if not valid or #bmVerts < 3 then return nil end

		local c = faceData.c
		DataStructure.addFace(bm, bmVerts, {
			Color        = Color3.new(c[1], c[2], c[3]),
			Transparency = faceData.t or defaultTransparency,
		})
	end

	return bm
end

local function fromEditableMesh(em, defaultColor, defaultTransparency)
	local bm       = DataStructure.new()
	local vertById = {}

	for _, vid in ipairs(em:GetVertices()) do
		local v       = DataStructure.addVert(bm, em:GetPosition(vid))
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
			DataStructure.addFace(bm, { v1, v2, v3 }, {
				Color        = getColor(fid),
				Transparency = defaultTransparency,
			})
		end
	end

	EulerOps.dissolvePlanar(bm, 0.999)
	return bm
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function RMesh.ApplyMeshUpdate(tempPart)
	if not RMesh.sourceMeshPart or not tempPart then return end
	local oldScale = RMesh.sourceMeshPart.Size / RMesh.sourceMeshPart.MeshSize
	RMesh.sourceMeshPart:ApplyMesh(tempPart)
	RMesh.sourceMeshPart.Size = tempPart.MeshSize * oldScale
end

function RMesh.Finalize()
	if not RMesh.em or not RMesh.sourceMeshPart then return end
	rebuildEM()
	local topoJson = serializeTopology(RMesh.bm)
	local existing = RMesh.sourceMeshPart:FindFirstChild("MPETopology")
	if existing then
		existing.Value = topoJson
	else
		local sv = Instance.new("StringValue")
		sv.Name   = "MPETopology"
		sv.Value  = topoJson
		sv.Parent = RMesh.sourceMeshPart
	end
	restoreSource()
end

function RMesh.End()
	restoreSource()
	RMesh.em             = nil
	RMesh.bm             = nil
	RMesh.sourceMeshPart = nil
	_sourceMeshPartParent = nil
end

-- ─── EM ↔ mesh sync ──────────────────────────────────────────────────────────

function RMesh.SyncFromEM()
	if not RMesh.em or not RMesh.sourceMeshPart then return end
	RMesh.bm = fromEditableMesh(RMesh.em, RMesh.sourceMeshPart.Color, RMesh.sourceMeshPart.Transparency)
end

function RMesh.SetBMesh(newBM)
	RMesh.bm = newBM
	rebuildEM()
end

-- ─── Coordinate transforms ────────────────────────────────────────────────────

function RMesh.GetScaleFactor()
	if not RMesh.sourceMeshPart then return Vector3.one end
	return RMesh.sourceMeshPart.Size / RMesh.sourceMeshPart.MeshSize
end

function RMesh.LocalToWorld(localPos)
	return RMesh.sourceMeshPart.CFrame:PointToWorldSpace(localPos * RMesh.GetScaleFactor())
end

function RMesh.WorldToLocal(worldPos)
	return RMesh.sourceMeshPart.CFrame:PointToObjectSpace(worldPos) / RMesh.GetScaleFactor()
end

-- ─── Mesh operations ──────────────────────────────────────────────────────────

-- savedVerts: { { vert = v, initialPos = v.position } } — snapshot at Activate.
-- worldDelta: Vector3 from handle's initial to current world position.
function RMesh.ApplyTransformToVerts(savedVerts, worldDelta)
	if not RMesh.bm or not RMesh.em then return end
	local localDelta = RMesh.sourceMeshPart.CFrame:VectorToObjectSpace(worldDelta) / RMesh.GetScaleFactor()
	for _, entry in ipairs(savedVerts) do
		local newPos = entry.initialPos + localDelta
		entry.vert.position = newPos
		if entry.vert.emId then
			RMesh.em:SetPosition(entry.vert.emId, newPos)
		end
	end
end

function RMesh.ExtrudeFace(face)
	if not RMesh.bm or not RMesh.em then return nil end
	local result = EulerOps.extrudeFace(RMesh.bm, face)
	if result then
		rebuildEM()
	end
	return result
end

function RMesh.DissolveEdge(edge, dissolveVerts)
	if not RMesh.bm or not RMesh.em then return nil end
	local result = EulerOps.dissolveEdge(RMesh.bm, edge, dissolveVerts)
	if result then
		rebuildEM()
	end
	return result
end

function RMesh.SetFaceStyle(face, color, transparency)
	if color ~= nil then
		face.color = color
	end
	if transparency ~= nil then
		face.transparency = transparency
	end
end

-- ─── HUD helpers ──────────────────────────────────────────────────────────────

function RMesh.GetVertexCount()
	if not RMesh.bm then return 0 end
	local n = 0
	for _ in pairs(RMesh.bm.verts) do
		n += 1
	end
	return n
end

function RMesh.GetFaceCount()
	if not RMesh.bm then return 0 end
	local n = 0
	for _ in pairs(RMesh.bm.faces) do
		n += 1
	end
	return n
end

-- ─── Session start ────────────────────────────────────────────────────────────

function RMesh.Begin(meshPart)
	RMesh.sourceMeshPart  = meshPart
	_sourceMeshPartParent = meshPart.Parent

	local ok, err = pcall(function()
		RMesh.em = AssetService:CreateEditableMeshAsync(meshPart.MeshContent, { FixedSize = false })
	end)
	if not ok then
		warn("[RMesh] Could not load mesh:", err)
		RMesh.sourceMeshPart  = nil
		_sourceMeshPartParent = nil
		return false
	end

	RMesh.em:MergeVertices(0.001)
	RMesh.em:RemoveUnused()

	local ok2, err2 = pcall(function()
		local tempPart = AssetService:CreateMeshPartAsync(Content.fromObject(RMesh.em))
		meshPart:ApplyMesh(tempPart)
	end)
	if not ok2 then
		warn("[RMesh] Could not link mesh:", err2)
		RMesh.em              = nil
		RMesh.sourceMeshPart  = nil
		_sourceMeshPartParent = nil
		return false
	end

	local topoValue = meshPart:FindFirstChild("MPETopology")
	if topoValue and topoValue:IsA("StringValue") then
		local bm = fromTopology(RMesh.em, topoValue.Value, meshPart.Transparency)
		if bm then
			RMesh.bm = bm
		else
			warn("[RMesh] fromTopology failed, falling back to dissolvePlanar")
			RMesh.bm = fromEditableMesh(RMesh.em, meshPart.Color, meshPart.Transparency)
		end
	else
		RMesh.bm = fromEditableMesh(RMesh.em, meshPart.Color, meshPart.Transparency)
	end

	hideSource()
	return true
end

return RMesh
