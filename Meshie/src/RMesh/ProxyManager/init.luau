-- ProxyManager/init.luau
-- Manages in-world proxy Parts representing the mesh visually.
-- Reads mesh data from RMesh (singleton).
--
-- Each proxy carries exactly ONE attribute: ElementId.
-- Proxy type is encoded by folder: VertexProxies / EdgeProxies / FaceProxies.

local AssetService = game:GetService("AssetService")

local RMesh         = require(script.Parent)
local DataStructure = require(script.Parent.Core.DataStructure)
local UserConfig    = require(script.Parent.Parent.HUD.UserConfig)
local HandleManager = require(script.HandleManager)

local ProxyManager = {}

local root         = nil
local vertexFolder = nil
local edgeFolder   = nil
local faceFolder   = nil
local faceEditableMeshes = {}

-- ─── Private ──────────────────────────────────────────────────────────────────

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
		return nil, nil, nil
	end

	facePart.Anchored   = true
	facePart.CanCollide = false
	facePart.CanTouch   = false
	facePart.Archivable = false
	facePart.CFrame     = CFrame.fromMatrix(center, xAxis, yAxis, zAxis)
	return facePart, em, normal
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

local function applyFaceStyle(proxy, face, sourceMaterial)
	proxy.Material    = sourceMaterial or UserConfig.FaceMaterial
	proxy.Color       = face.color
	proxy.Transparency = face.transparency
end

local function faceKey(face)
	return "Face_" .. tostring(face.id)
end

local function destroyFaceProxy(key)
	local existing = faceFolder and faceFolder:FindFirstChild(key)
	if existing then existing.Parent = nil end
	faceEditableMeshes[key] = nil
end

-- ─── Private proxy builders ───────────────────────────────────────────────────

local function rebuildVertexProxy(vert, localToWorld, localDirToWorld)
	if not vertexFolder then return end
	local name     = "Vertex_" .. vert.id
	local existing = vertexFolder:FindFirstChild(name)
	if existing then existing.Parent = nil end

	local worldPos    = localToWorld(vert.position)
	local worldNormal = localDirToWorld(vert.normal or Vector3.new(0, 1, 0))

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
	p.Parent = vertexFolder
end

local function rebuildEdgeProxy(edge, localToWorld, localDirToWorld)
	if not edgeFolder then return end
	local name     = "Edge_" .. edge.id
	local existing = edgeFolder:FindFirstChild(name)
	if existing then existing.Parent = nil end

	local wA  = localToWorld(edge.v1.position)
	local wB  = localToWorld(edge.v2.position)
	local dir = wB - wA
	local len = dir.Magnitude
	if len <= 0 then return end

	local worldNormal = localDirToWorld(edge.normal or Vector3.new(0, 1, 0))

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
	p.Parent = edgeFolder
end

local function rebuildFaceProxy(face, localToWorld, sourceMaterial)
	if not faceFolder then return end
	local key = faceKey(face)
	destroyFaceProxy(key)

	local faceVerts = DataStructure.faceVerts(face)
	local worldPts  = {}
	for _, v in ipairs(faceVerts) do
		worldPts[#worldPts + 1] = localToWorld(v.position)
	end
	if #worldPts < 3 then return end

	local proxy, em, _ = buildFaceProxy(worldPts)
	if not proxy then return end

	applyFaceStyle(proxy, face, sourceMaterial)
	proxy.Name = key
	proxy:SetAttribute("ElementId", face.id)
	proxy.Parent = faceFolder
	faceEditableMeshes[key] = em
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function ProxyManager.GetRoot()
	return root
end

-- Find a proxy by element type and ID.
function ProxyManager.FindProxy(elementType, elementId)
	local folder
	if elementType == "Vertex" then
		folder = vertexFolder
	elseif elementType == "Edge" then
		folder = edgeFolder
	elseif elementType == "Face" then
		folder = faceFolder
	end
	if not folder then return nil end
	local name
	if elementType == "Vertex" then
		name = "Vertex_" .. tostring(elementId)
	elseif elementType == "Edge" then
		name = "Edge_" .. tostring(elementId)
	elseif elementType == "Face" then
		name = "Face_" .. tostring(elementId)
	end
	return name and folder:FindFirstChild(name)
end

-- Rebuild all proxy Parts from RMesh.bm.
function ProxyManager.RebuildProxies()
	if not root or not RMesh.bm then return end

	DataStructure.computeNormals(RMesh.bm)

	for _, p in ipairs(vertexFolder:GetChildren()) do p.Parent = nil end
	for _, p in ipairs(edgeFolder:GetChildren())   do p.Parent = nil end
	for _, p in ipairs(faceFolder:GetChildren())   do p.Parent = nil end
	faceEditableMeshes = {}

	local localToWorld    = function(p) return RMesh.LocalToWorld(p) end
	local localDirToWorld = function(d) return RMesh.sourceMeshPart.CFrame:VectorToWorldSpace(d) end
	local sourceMaterial  = RMesh.sourceMeshPart.Material

	for _, vert in pairs(RMesh.bm.verts) do
		rebuildVertexProxy(vert, localToWorld, localDirToWorld)
	end
	for _, edge in pairs(RMesh.bm.edges) do
		rebuildEdgeProxy(edge, localToWorld, localDirToWorld)
	end
	for _, face in pairs(RMesh.bm.faces) do
		rebuildFaceProxy(face, localToWorld, sourceMaterial)
	end
end

-- Set proxy visibility and selectability based on the current geometry mode.
function ProxyManager.ApplyGeometryMode(mode)
	if not vertexFolder or not edgeFolder then return end

	for _, p in ipairs(vertexFolder:GetChildren()) do
		p.Locked       = (mode ~= "Vertex")
		p.Transparency = if mode == "Vertex" then 0 else 0.95
	end
	for _, p in ipairs(edgeFolder:GetChildren()) do
		p.Locked       = (mode ~= "Edge")
		p.Transparency = if mode == "Edge" then 0 else 0.95
	end
	if faceFolder then
		for _, p in ipairs(faceFolder:GetChildren()) do
			p.Locked = (mode ~= "Face")
		end
	end
end

-- Read face proxy colors back into RMesh.bm before Finalize.
function ProxyManager.ApplyFaceProxyColors()
	if not faceFolder or not RMesh.bm then return end
	for _, proxy in ipairs(faceFolder:GetChildren()) do
		local fid  = proxy:GetAttribute("ElementId")
		local face = fid and RMesh.bm.faces[fid]
		if face then
			face.color        = proxy.Color
			face.transparency = proxy.Transparency
		end
	end
end

function ProxyManager.Begin()
	root           = Instance.new("Folder")
	root.Name      = "EditObjects"
	root.Archivable = false
	root.Parent    = workspace

	vertexFolder           = Instance.new("Folder")
	vertexFolder.Name      = "VertexProxies"
	vertexFolder.Archivable = false
	vertexFolder.Parent    = root

	edgeFolder           = Instance.new("Folder")
	edgeFolder.Name      = "EdgeProxies"
	edgeFolder.Archivable = false
	edgeFolder.Parent    = root

	faceFolder           = Instance.new("Folder")
	faceFolder.Name      = "FaceProxies"
	faceFolder.Archivable = false
	faceFolder.Parent    = root

	HandleManager.Begin(root)
end

function ProxyManager.Destroy()
	faceEditableMeshes = {}
	HandleManager.DestroyFolder()
	if root then root:Destroy() end
	root         = nil
	vertexFolder = nil
	edgeFolder   = nil
	faceFolder   = nil
end

return ProxyManager
