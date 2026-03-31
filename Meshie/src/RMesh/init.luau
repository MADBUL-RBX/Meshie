-- RMesh/init.luau
-- The mesh editing kernel. A library.
-- RMesh.new(meshPart) → an rmesh instance.
-- No knowledge of Meshie's session lifecycle, CHS, Studio plugins, or proxies.

local AssetService = game:GetService("AssetService")
local HttpService  = game:GetService("HttpService")

local DataStructure = require(script.Core.DataStructure)
local EulerOps      = require(script.Core.EulerOps)

local RMesh = {}
RMesh.__index = RMesh

-- ─── Internal: EM ↔ BM conversion ────────────────────────────────────────────

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
	local ok, data = pcall(function() return HttpService:JSONDecode(jsonStr) end)
	if not ok or type(data) ~= "table" then return nil end

	local emVerts = {}
	for _, vid in ipairs(em:GetVertices()) do
		emVerts[#emVerts + 1] = { id = vid, pos = em:GetPosition(vid) }
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
				local v      = DataStructure.addVert(bm, em:GetPosition(emId))
				v.emId       = emId
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
		local v1, v2, v3 = vertById[vids[1]], vertById[vids[2]], vertById[vids[3]]
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

local function rebuildEM(em, bm)
	for _, fid in ipairs(em:GetFaces()) do em:RemoveFace(fid) end
	em:RemoveUnused()

	local emIdByVert   = {}
	local colorIdByKey = {}

	for _, vert in pairs(bm.verts) do
		local vid        = em:AddVertex(vert.position)
		emIdByVert[vert] = vid
		vert.emId        = vid
	end

	local function getColorId(face)
		local ck = tostring(face.color.R) .. "|" .. tostring(face.color.G)
			.. "|" .. tostring(face.color.B) .. "|" .. tostring(face.transparency)
		if not colorIdByKey[ck] then
			colorIdByKey[ck] = em:AddColor(face.color, face.transparency)
		end
		return colorIdByKey[ck]
	end

	for _, face in pairs(bm.faces) do
		local verts = DataStructure.faceVerts(face)
		local n = #verts
		if n < 3 then continue end
		local colorId = getColorId(face)
		for i = 2, n - 1 do
			local fid = em:AddTriangle(emIdByVert[verts[1]], emIdByVert[verts[i]], emIdByVert[verts[i + 1]])
			em:SetFaceColors(fid, { colorId, colorId, colorId })
			local nid = em:AddNormal()
			em:SetFaceNormals(fid, { nid, nid, nid })
		end
	end
end

-- ─── Constructor ──────────────────────────────────────────────────────────────

-- Returns a new RMesh instance, or nil if the mesh could not be loaded.
function RMesh.new(meshPart)
	local em
	local ok, err = pcall(function()
		em = AssetService:CreateEditableMeshAsync(meshPart.MeshContent, { FixedSize = false })
	end)
	if not ok then
		warn("[RMesh] Could not load mesh:", err)
		return nil
	end

	em:MergeVertices(0.001)
	em:RemoveUnused()

	local ok2, err2 = pcall(function()
		local tempPart = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		meshPart:ApplyMesh(tempPart)
	end)
	if not ok2 then
		warn("[RMesh] Could not link mesh:", err2)
		em = nil
		return nil
	end

	local self        = setmetatable({}, RMesh)
	self.em           = em
	self.meshPart     = meshPart

	local topoValue = meshPart:FindFirstChild("MPETopology")
	if topoValue and topoValue:IsA("StringValue") then
		local bm = fromTopology(em, topoValue.Value, meshPart.Transparency)
		if bm then
			self.bm = bm
		else
			warn("[RMesh] fromTopology failed, falling back to dissolvePlanar")
			self.bm = fromEditableMesh(em, meshPart.Color, meshPart.Transparency)
		end
	else
		self.bm = fromEditableMesh(em, meshPart.Color, meshPart.Transparency)
	end

	return self
end

-- ─── Coordinate transforms ────────────────────────────────────────────────────

function RMesh:GetScaleFactor()
	return self.meshPart.Size / self.meshPart.MeshSize
end

function RMesh:LocalToWorld(localPos)
	return self.meshPart.CFrame:PointToWorldSpace(localPos * self:GetScaleFactor())
end

function RMesh:WorldToLocal(worldPos)
	return self.meshPart.CFrame:PointToObjectSpace(worldPos) / self:GetScaleFactor()
end

-- ─── EM sync ──────────────────────────────────────────────────────────────────

function RMesh:SyncFromEM()
	self.bm = fromEditableMesh(self.em, self.meshPart.Color, self.meshPart.Transparency)
end

function RMesh:SetBMesh(newBM)
	self.bm = newBM
	rebuildEM(self.em, self.bm)
end

-- ─── Mesh mutation ────────────────────────────────────────────────────────────

function RMesh:SetPosition(vert, pos)
	vert.position = pos
	if vert.emId then
		self.em:SetPosition(vert.emId, pos)
	end
end

-- savedVerts: { { vert, initialPos } } — snapshot taken at tool Activate.
-- worldDelta: Vector3 from handle's initial to current world position.
function RMesh:ApplyTransformToVerts(savedVerts, worldDelta)
	local localDelta = self.meshPart.CFrame:VectorToObjectSpace(worldDelta) / self:GetScaleFactor()
	for _, entry in ipairs(savedVerts) do
		self:SetPosition(entry.vert, entry.initialPos + localDelta)
	end
end

function RMesh:ExtrudeFace(face)
	local result = EulerOps.extrudeFace(self.bm, face)
	if result then rebuildEM(self.em, self.bm) end
	return result
end

function RMesh:DissolveEdge(edge, dissolveVerts)
	local result = EulerOps.dissolveEdge(self.bm, edge, dissolveVerts)
	if result then rebuildEM(self.em, self.bm) end
	return result
end

function RMesh:SetFaceStyle(face, color, transparency)
	if color ~= nil then face.color = color end
	if transparency ~= nil then face.transparency = transparency end
end

-- ─── Queries ──────────────────────────────────────────────────────────────────

function RMesh:GetVertexCount()
	local n = 0
	for _ in pairs(self.bm.verts) do n += 1 end
	return n
end

function RMesh:GetFaceCount()
	local n = 0
	for _ in pairs(self.bm.faces) do n += 1 end
	return n
end

-- ─── Finalize & Destroy ───────────────────────────────────────────────────────

-- Write the current mesh state back to meshPart.
-- Bakes collision, applies mesh, saves topology for future sessions.
function RMesh:Finalize()
	rebuildEM(self.em, self.bm)

	local topoJson = serializeTopology(self.bm)
	local existing = self.meshPart:FindFirstChild("MPETopology")
	if existing then
		existing.Value = topoJson
	else
		local sv = Instance.new("StringValue")
		sv.Name   = "MPETopology"
		sv.Value  = topoJson
		sv.Parent = self.meshPart
	end

	local ok, err = pcall(function()
		local tempPart = AssetService:CreateMeshPartAsync(Content.fromObject(self.em))
		local oldScale = self.meshPart.Size / self.meshPart.MeshSize
		self.meshPart:ApplyMesh(tempPart)
		self.meshPart.Size = tempPart.MeshSize * oldScale
	end)
	if not ok then
		warn("[RMesh] Finalize failed:", err)
	end
end

-- Apply the current EM state to meshPart without saving topology.
-- Used by History to keep CHS in sync after each operation.
function RMesh:ApplyMeshUpdate()
	local ok, result, content = pcall(function()
		return AssetService:CreateDataModelContentAsync(Content.fromObject(self.em))
	end)
	if ok and content ~= nil then
		local tempPart = AssetService:CreateMeshPartAsync(content)
		local oldScale = self.meshPart.Size / self.meshPart.MeshSize
		self.meshPart:ApplyMesh(tempPart)
		self.meshPart.Size = tempPart.MeshSize * oldScale
	end
end

-- Nil EM and BM so they can be GC'd. Caller is responsible for any proxy cleanup.
function RMesh:Destroy()
	self.em       = nil
	self.bm       = nil
	self.meshPart = nil
end

return RMesh
