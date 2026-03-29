-- EditScene.luau
-- Manages in-world proxy Parts representing the BMesh visually.
-- Proxies are purely visual — only the active handle has listeners.
--
-- Never calls MeshSession directly. Receives what it needs as parameters:
--   RebuildProxies(bm, localToWorld, sourceMaterial)
--   ApplyGeometryMode(mode)
--   ApplyFaceProxyColorsToSession(bm)

local AssetService = game:GetService("AssetService")

local UserConfig = require(script.Parent.Parent.UserConfig)
local BMesh = require(script.Parent.Parent.Core.BMesh)
local ToolHandles = require(script.Parent.ToolHandles)

local EditScene = {}

local root = nil
local vertexFolder = nil
local edgeFolder = nil
local faceFolder = nil
local faceEditableMeshes = {}

-- ─── Private ──────────────────────────────────────────────────────────────────

local function safeUnit(v)
	if v.Magnitude > 1e-5 then
		return v.Unit
	end
	return Vector3.new(0, 1, 0)
end

local function average(pts)
	local sum = Vector3.zero
	for _, p in ipairs(pts) do
		sum += p
	end
	return sum / #pts
end

local function buildFaceProxy(worldPoints)
	local n = #worldPoints
	local center = average(worldPoints)
	local xAxis = safeUnit(worldPoints[2] - worldPoints[1])
	local normal = safeUnit((worldPoints[2] - worldPoints[1]):Cross(worldPoints[3] - worldPoints[1]))
	local yAxis = safeUnit(normal:Cross(xAxis))
	local zAxis = safeUnit(xAxis:Cross(yAxis))

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
		warn("[EditScene] buildFaceProxy failed:", err)
		em = nil
		return nil, nil, nil
	end

	facePart.Anchored = true
	facePart.CanCollide = false
	facePart.CanTouch = false
	facePart.Archivable = false
	facePart.CFrame = CFrame.fromMatrix(center, xAxis, yAxis, zAxis)
	return facePart, em, normal  -- normal is world-space
end

-- Build a CFrame with UpVector = up, back axis as close to tangent as possible.
-- Used for edge and vertex proxies so the Studio gizmo shows the operation axis.
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
	proxy.Material = sourceMaterial or UserConfig.FaceMaterial
	proxy.Color = face.color
	proxy.Transparency = face.transparency
end

local function faceKey(face)
	return "Face_" .. tostring(face.id)
end

local function destroyFaceProxy(key)
	local existing = faceFolder and faceFolder:FindFirstChild(key)
	if existing then
		existing.Parent = nil
	end
	faceEditableMeshes[key] = nil -- nil only — face EMs are caller-owned, let GC collect
end

-- ─── Private proxy builders ───────────────────────────────────────────────────

local function rebuildVertexProxy(vert, localToWorld, localDirToWorld)
	if not vertexFolder then
		return
	end
	local name = "Vertex_" .. vert.id
	local existing = vertexFolder:FindFirstChild(name)
	if existing then
		existing.Parent = nil
	end

	local worldPos    = localToWorld(vert.position)
	local worldNormal = localDirToWorld(vert.normal or Vector3.new(0, 1, 0))

	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Material = UserConfig.VertexMaterial
	p.Color = UserConfig.VertexColor
	p.Size = Vector3.one * UserConfig.VertexSize
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Archivable = false
	p.Name = name
	p.CFrame = orientedCFrame(worldPos, worldNormal, Vector3.new(1, 0, 0))
	p:SetAttribute("ProxyType", "Vertex")
	p:SetAttribute("VertId", vert.id)
	p:SetAttribute("NormalX", worldNormal.X)
	p:SetAttribute("NormalY", worldNormal.Y)
	p:SetAttribute("NormalZ", worldNormal.Z)
	p.Parent = vertexFolder
end

local function rebuildEdgeProxy(edge, localToWorld, localDirToWorld)
	if not edgeFolder then
		return
	end
	local name = "Edge_" .. edge.id
	local existing = edgeFolder:FindFirstChild(name)
	if existing then
		existing.Parent = nil
	end

	local wA = localToWorld(edge.v1.position)
	local wB = localToWorld(edge.v2.position)
	local dir = wB - wA
	local len = dir.Magnitude
	if len <= 0 then
		return
	end

	local worldNormal  = localDirToWorld(edge.normal  or Vector3.new(0, 1, 0))
	local worldTangent = localDirToWorld(edge.tangent or dir.Unit)

	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Block
	p.Material = UserConfig.EdgeMaterial
	p.Color = UserConfig.EdgeColor
	p.Size = Vector3.new(UserConfig.EdgeThickness, UserConfig.EdgeThickness, len)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Archivable = false
	p.Name = name
	-- Use actual world edge direction (not localDirToWorld tangent) so the proxy
	-- spans correctly regardless of scale. Fall back to a safe up if parallel.
	local lookDir = dir.Unit
	local upVec   = worldNormal
	if math.abs(lookDir:Dot(upVec)) > 0.99 then
		upVec = math.abs(lookDir:Dot(Vector3.new(0, 1, 0))) < 0.9 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
	end
	p.CFrame = CFrame.lookAlong((wA + wB) * 0.5, lookDir, upVec)
	p:SetAttribute("ProxyType", "Edge")
	p:SetAttribute("EdgeId", edge.id)
	p:SetAttribute("VertId1", edge.v1.id)
	p:SetAttribute("VertId2", edge.v2.id)
	p:SetAttribute("NormalX", worldNormal.X)
	p:SetAttribute("NormalY", worldNormal.Y)
	p:SetAttribute("NormalZ", worldNormal.Z)
	p:SetAttribute("TangentX", worldTangent.X)
	p:SetAttribute("TangentY", worldTangent.Y)
	p:SetAttribute("TangentZ", worldTangent.Z)
	p.Parent = edgeFolder
end

local function rebuildFaceProxy(face, localToWorld, sourceMaterial)
	if not faceFolder then
		return
	end
	local key = faceKey(face)
	destroyFaceProxy(key)

	local faceVerts = BMesh.faceVerts(face)
	local worldPts = {}
	for _, v in ipairs(faceVerts) do
		worldPts[#worldPts + 1] = localToWorld(v.position)
	end
	if #worldPts < 3 then
		return
	end

	local proxy, em, worldNormal = buildFaceProxy(worldPts)
	if not proxy then
		return
	end

	applyFaceStyle(proxy, face, sourceMaterial)
	proxy.Name = key
	proxy:SetAttribute("ProxyType", "Face")
	proxy:SetAttribute("FaceId", face.id)
	local n = #faceVerts
	proxy:SetAttribute("VertCount", n)
	for i, v in ipairs(faceVerts) do
		proxy:SetAttribute("VertId" .. i, v.id)
	end
	if worldNormal then
		proxy:SetAttribute("NormalX", worldNormal.X)
		proxy:SetAttribute("NormalY", worldNormal.Y)
		proxy:SetAttribute("NormalZ", worldNormal.Z)
	end
	proxy.Parent = faceFolder
	faceEditableMeshes[key] = em
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function EditScene.GetRoot()
	return root
end

function EditScene.GetToolHandlesFolder()
	return ToolHandles.GetFolder()
end

function EditScene.FindProxy(name)
	for _, folder in ipairs({ vertexFolder, edgeFolder, faceFolder }) do
		if folder then
			local p = folder:FindFirstChild(name)
			if p then
				return p
			end
		end
	end
	return nil
end

-- Destroy and recreate all proxy Parts from bm.
-- localToWorld:    (Vector3) → Vector3, maps mesh-local positions to world space.
-- localDirToWorld: (Vector3) → Vector3, maps mesh-local directions (normals) to world space (rotation only, no scale).
-- sourceMaterial:  Enum.Material for face proxies.
function EditScene.RebuildProxies(bm, localToWorld, localDirToWorld, sourceMaterial)
	if not root or not bm then
		return
	end

	BMesh.computeNormals(bm)

	for _, p in ipairs(vertexFolder:GetChildren()) do
		p.Parent = nil
	end
	for _, p in ipairs(edgeFolder:GetChildren()) do
		p.Parent = nil
	end
	for _, p in ipairs(faceFolder:GetChildren()) do
		p.Parent = nil
	end
	faceEditableMeshes = {}

	for _, vert in pairs(bm.verts) do
		rebuildVertexProxy(vert, localToWorld, localDirToWorld)
	end
	for _, edge in pairs(bm.edges) do
		rebuildEdgeProxy(edge, localToWorld, localDirToWorld)
	end
	for _, face in pairs(bm.faces) do
		rebuildFaceProxy(face, localToWorld, sourceMaterial)
	end
end

-- Set proxy visibility and selectability based on the current geometry mode.
-- mode: "Vertex" | "Edge" | "Face"
function EditScene.ApplyGeometryMode(mode)
	if not vertexFolder or not edgeFolder then
		return
	end

	for _, p in ipairs(vertexFolder:GetChildren()) do
		p.Locked = (mode ~= "Vertex")
		p.Transparency = if mode == "Vertex" then 0 else 0.95
	end
	for _, p in ipairs(edgeFolder:GetChildren()) do
		p.Locked = (mode ~= "Edge")
		p.Transparency = if mode == "Edge" then 0 else 0.95
	end
	if faceFolder then
		for _, p in ipairs(faceFolder:GetChildren()) do
			p.Locked = (mode ~= "Face")
		end
	end
end

-- Read face proxy Part colors back into bm face data before Finalize.
-- Lets users tint faces by painting proxy Parts directly in Studio.
function EditScene.ApplyFaceProxyColorsToSession(bm)
	if not faceFolder or not bm then
		return
	end
	for _, proxy in ipairs(faceFolder:GetChildren()) do
		if proxy:GetAttribute("ProxyType") == "Face" then
			local fid = proxy:GetAttribute("FaceId")
			local face = fid and bm.faces[fid]
			if face then
				face.color = proxy.Color
				face.transparency = proxy.Transparency
			end
		end
	end
end

function EditScene.Begin()
	root = Instance.new("Folder")
	root.Name = "EditObjects"
	root.Archivable = false
	root.Parent = workspace

	vertexFolder = Instance.new("Folder")
	vertexFolder.Name = "VertexProxies"
	vertexFolder.Archivable = false
	vertexFolder.Parent = root

	edgeFolder = Instance.new("Folder")
	edgeFolder.Name = "EdgeProxies"
	edgeFolder.Archivable = false
	edgeFolder.Parent = root

	faceFolder = Instance.new("Folder")
	faceFolder.Name = "FaceProxies"
	faceFolder.Archivable = false
	faceFolder.Parent = root

	ToolHandles.Begin(root)
end

function EditScene.Destroy()
	-- Nil face EM refs — they are caller-owned, let GC collect. Never :Destroy().
	faceEditableMeshes = {}

	ToolHandles.Destroy()
	if root then
		root:Destroy()
	end
	root = nil
	vertexFolder = nil
	edgeFolder = nil
	faceFolder = nil
end

return EditScene
