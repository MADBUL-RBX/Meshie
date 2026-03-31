-- Bridge.luau
-- The Roblox translator for RMesh.
-- Manages in-world proxy Parts that visualize the mesh.
-- Meshie-specific — not part of the RMesh library.
--
-- Bridge.init(rmesh)                    — create proxy folders, attach refs to rmesh instance
-- Bridge.rebuildProxies(rmesh)          — rebuild all proxy Parts from rmesh.bm
-- Bridge.applyGeometryMode(rmesh, mode) — set proxy visibility/selectability
-- Bridge.applyFaceProxyColors(rmesh)    — read face proxy colors back into rmesh.bm
-- Bridge.findProxy(rmesh, type, id)     — find a proxy Part by element type and ID
-- Bridge.destroy(rmesh)                 — destroy all proxy instances

local AssetService = game:GetService("AssetService")

local DataStructure = require(script.Parent.Parent.RMesh.Core.DataStructure)
local UserConfig    = require(script.Parent.HUD.UserConfig)

local Bridge = {}

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
		warn("[Bridge] buildFaceProxy failed:", err)
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

local function destroyFaceProxy(rmesh, key)
	local existing = rmesh._faceFolder and rmesh._faceFolder:FindFirstChild(key)
	if existing then existing.Parent = nil end
	rmesh._faceEMs[key] = nil
end

-- ─── Private proxy builders ───────────────────────────────────────────────────

local function rebuildVertexProxy(rmesh, vert)
	if not rmesh._vertexFolder then return end
	local name     = "Vertex_" .. vert.id
	local existing = rmesh._vertexFolder:FindFirstChild(name)
	if existing then existing.Parent = nil end

	local worldPos    = rmesh:LocalToWorld(vert.position)
	local worldNormal = rmesh.meshPart.CFrame:VectorToWorldSpace(vert.normal or Vector3.new(0, 1, 0))

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
	p.Parent = rmesh._vertexFolder
end

local function rebuildEdgeProxy(rmesh, edge)
	if not rmesh._edgeFolder then return end
	local name     = "Edge_" .. edge.id
	local existing = rmesh._edgeFolder:FindFirstChild(name)
	if existing then existing.Parent = nil end

	local wA  = rmesh:LocalToWorld(edge.v1.position)
	local wB  = rmesh:LocalToWorld(edge.v2.position)
	local dir = wB - wA
	local len = dir.Magnitude
	if len <= 0 then return end

	local worldNormal = rmesh.meshPart.CFrame:VectorToWorldSpace(edge.normal or Vector3.new(0, 1, 0))

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
	p.Parent = rmesh._edgeFolder
end

local function rebuildFaceProxy(rmesh, face)
	if not rmesh._faceFolder then return end
	local key = faceKey(face)
	destroyFaceProxy(rmesh, key)

	local faceVerts = DataStructure.faceVerts(face)
	local worldPts  = {}
	for _, v in ipairs(faceVerts) do
		worldPts[#worldPts + 1] = rmesh:LocalToWorld(v.position)
	end
	if #worldPts < 3 then return end

	local proxy, em = buildFaceProxy(worldPts)
	if not proxy then return end

	proxy.Material    = rmesh.meshPart.Material or UserConfig.FaceMaterial
	proxy.Color       = face.color
	proxy.Transparency = face.transparency
	proxy.Name        = key
	proxy:SetAttribute("ElementId", face.id)
	proxy.Parent      = rmesh._faceFolder
	rmesh._faceEMs[key] = em
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function Bridge.init(rmesh)
	rmesh._faceEMs = {}

	rmesh._root            = Instance.new("Folder")
	rmesh._root.Name       = "EditObjects"
	rmesh._root.Archivable = false
	rmesh._root.Parent     = workspace

	rmesh._vertexFolder            = Instance.new("Folder")
	rmesh._vertexFolder.Name       = "VertexProxies"
	rmesh._vertexFolder.Archivable = false
	rmesh._vertexFolder.Parent     = rmesh._root

	rmesh._edgeFolder            = Instance.new("Folder")
	rmesh._edgeFolder.Name       = "EdgeProxies"
	rmesh._edgeFolder.Archivable = false
	rmesh._edgeFolder.Parent     = rmesh._root

	rmesh._faceFolder            = Instance.new("Folder")
	rmesh._faceFolder.Name       = "FaceProxies"
	rmesh._faceFolder.Archivable = false
	rmesh._faceFolder.Parent     = rmesh._root
end

function Bridge.rebuildProxies(rmesh)
	if not rmesh._root or not rmesh.bm then return end

	DataStructure.computeNormals(rmesh.bm)

	for _, p in ipairs(rmesh._vertexFolder:GetChildren()) do p.Parent = nil end
	for _, p in ipairs(rmesh._edgeFolder:GetChildren())   do p.Parent = nil end
	for _, p in ipairs(rmesh._faceFolder:GetChildren())   do p.Parent = nil end
	rmesh._faceEMs = {}

	for _, vert in pairs(rmesh.bm.verts) do
		rebuildVertexProxy(rmesh, vert)
	end
	for _, edge in pairs(rmesh.bm.edges) do
		rebuildEdgeProxy(rmesh, edge)
	end
	for _, face in pairs(rmesh.bm.faces) do
		rebuildFaceProxy(rmesh, face)
	end
end

function Bridge.applyGeometryMode(rmesh, mode)
	if not rmesh._vertexFolder or not rmesh._edgeFolder then return end

	for _, p in ipairs(rmesh._vertexFolder:GetChildren()) do
		p.Locked       = (mode ~= "Vertex")
		p.Transparency = if mode == "Vertex" then 0 else 0.95
	end
	for _, p in ipairs(rmesh._edgeFolder:GetChildren()) do
		p.Locked       = (mode ~= "Edge")
		p.Transparency = if mode == "Edge" then 0 else 0.95
	end
	if rmesh._faceFolder then
		for _, p in ipairs(rmesh._faceFolder:GetChildren()) do
			p.Locked = (mode ~= "Face")
		end
	end
end

function Bridge.applyFaceProxyColors(rmesh)
	if not rmesh._faceFolder or not rmesh.bm then return end
	for _, proxy in ipairs(rmesh._faceFolder:GetChildren()) do
		local fid  = proxy:GetAttribute("ElementId")
		local face = fid and rmesh.bm.faces[fid]
		if face then
			face.color        = proxy.Color
			face.transparency = proxy.Transparency
		end
	end
end

function Bridge.findProxy(rmesh, elementType, elementId)
	local folder
	if elementType == "Vertex" then
		folder = rmesh._vertexFolder
	elseif elementType == "Edge" then
		folder = rmesh._edgeFolder
	elseif elementType == "Face" then
		folder = rmesh._faceFolder
	end
	if not folder then return nil end
	return folder:FindFirstChild(elementType .. "_" .. tostring(elementId))
end

function Bridge.destroy(rmesh)
	rmesh._faceEMs = {}
	if rmesh._root then
		rmesh._root:Destroy()
		rmesh._root         = nil
		rmesh._vertexFolder = nil
		rmesh._edgeFolder   = nil
		rmesh._faceFolder   = nil
	end
end

return Bridge
