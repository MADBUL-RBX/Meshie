-- Editor/ProxyManager.luau
-- The Roblox translator for RMesh.
-- Manages in-world proxy Parts that visualize the mesh.
-- Meshie-specific — not part of the RMesh library.
--
-- ProxyManager.new(rmesh) → a proxy manager instance bound to that rmesh.

local AssetService = game:GetService("AssetService")

local UserConfig = require(script.Parent.Parent.HUD.UserConfig)

local ProxyManager = {}
ProxyManager.__index = ProxyManager

-- ─── Private helpers ──────────────────────────────────────────────────────────

local function safeUnit(v)
	if v.Magnitude > 1e-5 then return v.Unit end
	return Vector3.new(0, 1, 0)
end

local function average(pts)
	local sum = Vector3.zero
	for _, p in ipairs(pts) do sum += p end
	return sum / #pts
end

local function buildFaceProxy(worldPoints)
	local n      = #worldPoints
	local center = average(worldPoints)
	local xAxis  = safeUnit(worldPoints[2] - worldPoints[1])
	local normal = safeUnit((worldPoints[2] - worldPoints[1]):Cross(worldPoints[3] - worldPoints[1]))
	local yAxis  = safeUnit(normal:Cross(xAxis))
	local zAxis  = safeUnit(xAxis:Cross(yAxis))

	local em = AssetService:CreateEditableMesh()
	local localIds = {}
	for _, wp in ipairs(worldPoints) do
		local off = wp - center
		localIds[#localIds + 1] = em:AddVertex(Vector3.new(off:Dot(xAxis), off:Dot(yAxis), off:Dot(zAxis)))
	end
	for i = 2, n - 1 do
		em:AddTriangle(localIds[1], localIds[i], localIds[i + 1])
	end

	local facePart = nil
	local ok, err = pcall(function()
		facePart = AssetService:CreateMeshPartAsync(Content.fromObject(em), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
		})
	end)
	if not ok then
		warn("[ProxyManager] buildFaceProxy failed:", err)
		em = nil
		return nil, nil
	end

	facePart.Anchored   = true
	facePart.CanCollide = false
	facePart.CanTouch   = false
	facePart.Archivable = false
	facePart.CFrame     = CFrame.fromMatrix(center, xAxis, yAxis, zAxis)
	return facePart, em
end

local function orientedCFrame(pos, up, tangent)
	local right = up:Cross(tangent)
	if right.Magnitude < 1e-5 then
		local alt = math.abs(up:Dot(Vector3.new(1, 0, 0))) < 0.9 and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)
		right = up:Cross(alt)
	end
	right = right.Unit
	local back = right:Cross(up)
	return CFrame.fromMatrix(pos, right, up, back)
end

local function faceKey(face)
	return "Face_" .. tostring(face.id)
end

-- ─── Private proxy builders ───────────────────────────────────────────────────

local function rebuildVertexProxy(self, vert)
	local name     = "Vertex_" .. vert.id
	local existing = self.vertexFolder:FindFirstChild(name)
	if existing then existing.Parent = nil end

	local worldPos    = self.rmesh:LocalToWorld(vert.position)
	local worldNormal = self.rmesh.meshPart.CFrame:VectorToWorldSpace(vert.normal or Vector3.new(0, 1, 0))

	local p = Instance.new("Part")
	p.Shape      = Enum.PartType.Ball
	p.Material   = UserConfig.VertexMaterial
	p.Color      = UserConfig.VertexColor
	p.Size       = Vector3.one * UserConfig.VertexSize
	p.Anchored   = true
	p.CanCollide = false
	p.CanTouch   = false
	p.Archivable = false
	p.Name       = name
	p.CFrame     = orientedCFrame(worldPos, worldNormal, Vector3.new(1, 0, 0))
	p:SetAttribute("ElementId", vert.id)
	p.Parent = self.vertexFolder
end

local function rebuildEdgeProxy(self, edge)
	local name     = "Edge_" .. edge.id
	local existing = self.edgeFolder:FindFirstChild(name)
	if existing then
		existing.Parent = nil
	end

	local wA  = self.rmesh:LocalToWorld(edge.v1.position)
	local wB  = self.rmesh:LocalToWorld(edge.v2.position)
	local dir = wB - wA
	local len = dir.Magnitude
	if len <= 0 then return end

	local worldNormal = self.rmesh.meshPart.CFrame:VectorToWorldSpace(edge.normal or Vector3.new(0, 1, 0))

	local p = Instance.new("Part")
	p.Shape      = Enum.PartType.Block
	p.Material   = UserConfig.EdgeMaterial
	p.Color      = UserConfig.EdgeColor
	p.Size       = Vector3.new(UserConfig.EdgeThickness, UserConfig.EdgeThickness, len)
	p.Anchored   = true
	p.CanCollide = false
	p.CanTouch   = false
	p.Archivable = false
	p.Name       = name
	local lookDir = dir.Unit
	local upVec   = worldNormal
	if math.abs(lookDir:Dot(upVec)) > 0.99 then
		upVec = math.abs(lookDir:Dot(Vector3.new(0, 1, 0))) < 0.9 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
	end
	p.CFrame = CFrame.lookAlong((wA + wB) * 0.5, lookDir, upVec)
	p:SetAttribute("ElementId", edge.id)
	p.Parent = self.edgeFolder
end

local function rebuildFaceProxy(self, face)
	local key = faceKey(face)
	local existing = self.faceFolder:FindFirstChild(key)
	if existing then
		existing.Parent = nil
	end
	self.faceEMs[key] = nil

	local faceVerts = self.rmesh.bm:faceVerts(face)
	local worldPts  = {}
	for _, v in ipairs(faceVerts) do
		worldPts[#worldPts + 1] = self.rmesh:LocalToWorld(v.position)
	end
	if #worldPts < 3 then return end

	local proxy, em = buildFaceProxy(worldPts)
	if not proxy then return end

	proxy.Material     = self.rmesh.meshPart.Material or UserConfig.FaceMaterial
	proxy.Color        = face.color
	proxy.Transparency = face.transparency
	proxy.Name         = key
	proxy:SetAttribute("ElementId", face.id)
	proxy.Parent       = self.faceFolder
	self.faceEMs[key]  = em
end

-- ─── Constructor ──────────────────────────────────────────────────────────────

function ProxyManager.new(rmesh)
	local self        = setmetatable({}, ProxyManager)
	self.rmesh        = rmesh
	self.faceEMs      = {}

	self.root              = Instance.new("Folder")
	self.root.Name         = "EditObjects"
	self.root.Archivable   = false
	self.root.Parent       = workspace

	self.vertexFolder            = Instance.new("Folder")
	self.vertexFolder.Name       = "VertexProxies"
	self.vertexFolder.Archivable = false
	self.vertexFolder.Parent     = self.root

	self.edgeFolder            = Instance.new("Folder")
	self.edgeFolder.Name       = "EdgeProxies"
	self.edgeFolder.Archivable = false
	self.edgeFolder.Parent     = self.root

	self.faceFolder            = Instance.new("Folder")
	self.faceFolder.Name       = "FaceProxies"
	self.faceFolder.Archivable = false
	self.faceFolder.Parent     = self.root

	return self
end

-- ─── Methods ──────────────────────────────────────────────────────────────────

function ProxyManager:rebuild()
	if not self.rmesh.bm then return end

	self.rmesh.bm:computeNormals()

	for _, p in ipairs(self.vertexFolder:GetChildren()) do
		p.Parent = nil
	end
	for _, p in ipairs(self.edgeFolder:GetChildren()) do
		p.Parent = nil
	end
	for _, p in ipairs(self.faceFolder:GetChildren()) do
		p.Parent = nil
	end
	self.faceEMs = {}

	for _, vert in pairs(self.rmesh.bm.verts) do
		rebuildVertexProxy(self, vert)
	end
	for _, edge in pairs(self.rmesh.bm.edges) do
		rebuildEdgeProxy(self, edge)
	end
	for _, face in pairs(self.rmesh.bm.faces) do
		rebuildFaceProxy(self, face)
	end
end

function ProxyManager:applyGeometryMode(mode)
	for _, p in ipairs(self.vertexFolder:GetChildren()) do
		p.Locked       = (mode ~= "Vertex")
		p.Transparency = if mode == "Vertex" then 0 else 0.95
	end
	for _, p in ipairs(self.edgeFolder:GetChildren()) do
		p.Locked       = (mode ~= "Edge")
		p.Transparency = if mode == "Edge" then 0 else 0.95
	end
	for _, p in ipairs(self.faceFolder:GetChildren()) do
		p.Locked = (mode ~= "Face")
	end
end

function ProxyManager:applyFaceProxyColors()
	if not self.rmesh.bm then return end
	for _, proxy in ipairs(self.faceFolder:GetChildren()) do
		local fid  = proxy:GetAttribute("ElementId")
		local face = fid and self.rmesh.bm.faces[fid]
		if face then
			face.color        = proxy.Color
			face.transparency = proxy.Transparency
		end
	end
end

function ProxyManager:lockAll()
	for _, p in ipairs(self.vertexFolder:GetChildren()) do
		p.Locked = true
	end
	for _, p in ipairs(self.edgeFolder:GetChildren()) do
		p.Locked = true
	end
	for _, p in ipairs(self.faceFolder:GetChildren()) do
		p.Locked = true
	end
end

function ProxyManager:findProxy(elementType, elementId)
	local folder
	if elementType == "Vertex" then
		folder = self.vertexFolder
	elseif elementType == "Edge" then
		folder = self.edgeFolder
	elseif elementType == "Face" then
		folder = self.faceFolder
	end
	if not folder then return nil end
	return folder:FindFirstChild(elementType .. "_" .. tostring(elementId))
end

function ProxyManager:destroy()
	self.faceEMs = {}
	if self.root then
		self.root:Destroy()
		self.root         = nil
		self.vertexFolder = nil
		self.edgeFolder   = nil
		self.faceFolder   = nil
	end
	self.rmesh = nil
end

return ProxyManager
