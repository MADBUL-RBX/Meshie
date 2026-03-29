-- Core/init.luau
-- MeshSession singleton. The single source of truth for all mesh data.
-- Any module that needs mesh state requires this directly.
--
-- Core.em  (EditableMesh) — NEVER call :Destroy(). Nil and let GC collect.
-- Core.bm  (BMesh)        — N-gon filter over EM. Always derivable from EM.
-- Core.sourceMeshPart     — Hidden in ServerStorage during session.

local AssetService = game:GetService("AssetService")

local BMesh      = require(script.BMesh)
local MeshIO     = require(script.MeshIO)
local Operations = require(script.Operations)

local Core = {}

-- ─── State ────────────────────────────────────────────────────────────────────

Core.em             = nil
Core.bm             = nil
Core.sourceMeshPart = nil
local _sourceMeshPartParent = nil

-- ─── Private helpers ──────────────────────────────────────────────────────────

local function hideSource()
	_sourceMeshPartParent          = Core.sourceMeshPart.Parent
	Core.sourceMeshPart.Parent     = game:GetService("ServerStorage")
end

local function restoreSource()
	if Core.sourceMeshPart and _sourceMeshPartParent then
		Core.sourceMeshPart.Parent = _sourceMeshPartParent
		_sourceMeshPartParent      = nil
	end
end

local function rebuildEM()
	if not Core.bm or not Core.em then return end

	for _, fid in ipairs(Core.em:GetFaces()) do
		Core.em:RemoveFace(fid)
	end
	Core.em:RemoveUnused()

	local emIdByVert  = {}
	local colorIdByKey = {}

	for _, vert in pairs(Core.bm.verts) do
		local vid       = Core.em:AddVertex(vert.position)
		emIdByVert[vert] = vid
		vert.emId        = vid
	end

	local function getColorId(face)
		local ck = tostring(face.color.R) .. "|" .. tostring(face.color.G)
			.. "|" .. tostring(face.color.B) .. "|" .. tostring(face.transparency)
		if not colorIdByKey[ck] then
			colorIdByKey[ck] = Core.em:AddColor(face.color, face.transparency)
		end
		return colorIdByKey[ck]
	end

	for _, face in pairs(Core.bm.faces) do
		local verts = BMesh.faceVerts(face)
		local n = #verts
		if n < 3 then continue end
		local colorId = getColorId(face)
		for i = 2, n - 1 do
			local fid = Core.em:AddTriangle(emIdByVert[verts[1]], emIdByVert[verts[i]], emIdByVert[verts[i + 1]])
			Core.em:SetFaceColors(fid, { colorId, colorId, colorId })
			local nid = Core.em:AddNormal()
			Core.em:SetFaceNormals(fid, { nid, nid, nid })
		end
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function Core.ApplyMeshUpdate(tempPart)
	if not Core.sourceMeshPart or not tempPart then return end
	local oldScale = Core.sourceMeshPart.Size / Core.sourceMeshPart.MeshSize
	Core.sourceMeshPart:ApplyMesh(tempPart)
	Core.sourceMeshPart.Size = tempPart.MeshSize * oldScale
end

function Core.Finalize()
	if not Core.em or not Core.sourceMeshPart then return end
	rebuildEM()
	local topoJson = MeshIO.serializeTopology(Core.bm)
	local existing = Core.sourceMeshPart:FindFirstChild("MPETopology")
	if existing then
		existing.Value = topoJson
	else
		local sv = Instance.new("StringValue")
		sv.Name   = "MPETopology"
		sv.Value  = topoJson
		sv.Parent = Core.sourceMeshPart
	end
	restoreSource()
end

function Core.End()
	restoreSource()
	Core.em             = nil
	Core.bm             = nil
	Core.sourceMeshPart = nil
	_sourceMeshPartParent = nil
end

-- ─── EM ↔ BMesh sync ──────────────────────────────────────────────────────────

function Core.SyncFromEM()
	if not Core.em or not Core.sourceMeshPart then return end
	Core.bm = MeshIO.fromEditableMesh(Core.em, Core.sourceMeshPart.Color, Core.sourceMeshPart.Transparency)
end

function Core.RebuildFromContent()
	if not Core.sourceMeshPart then return false end
	local ok, err = pcall(function()
		Core.em = AssetService:CreateEditableMeshAsync(Core.sourceMeshPart.MeshContent, { FixedSize = false })
	end)
	if not ok then
		warn("[Core] RebuildFromContent failed:", err)
		return false
	end
	Core.em:MergeVertices(0.001)
	Core.em:RemoveUnused()
	Core.SyncFromEM()
	return true
end

function Core.SetBMesh(newBM)
	Core.bm = newBM
	rebuildEM()
end

-- ─── Coordinate transforms ────────────────────────────────────────────────────

function Core.GetScaleFactor()
	if not Core.sourceMeshPart then return Vector3.one end
	return Core.sourceMeshPart.Size / Core.sourceMeshPart.MeshSize
end

function Core.LocalToWorld(localPos)
	return Core.sourceMeshPart.CFrame:PointToWorldSpace(localPos * Core.GetScaleFactor())
end

function Core.WorldToLocal(worldPos)
	return Core.sourceMeshPart.CFrame:PointToObjectSpace(worldPos) / Core.GetScaleFactor()
end

-- ─── EM mutation helpers ──────────────────────────────────────────────────────

-- savedVerts: { { vert = v, initialPos = v.position } } — snapshot taken at tool Activate.
-- worldDelta: Vector3 offset from the handle's initial position to its current position.
function Core.ApplyTransformToVerts(savedVerts, worldDelta)
	if not Core.bm or not Core.em then return end
	local localDelta = Core.sourceMeshPart.CFrame:VectorToObjectSpace(worldDelta) / Core.GetScaleFactor()
	for _, entry in ipairs(savedVerts) do
		local newPos = entry.initialPos + localDelta
		entry.vert.position = newPos
		if entry.vert.emId then
			Core.em:SetPosition(entry.vert.emId, newPos)
		end
	end
end

function Core.ExtrudeFace(face)
	if not Core.bm or not Core.em then return nil end
	local result = Operations.extrudeFace(Core.bm, face)
	if result then rebuildEM() end
	return result
end

function Core.DissolveEdge(edge, dissolveVerts)
	if not Core.bm or not Core.em then return nil end
	local result = Operations.dissolveEdge(Core.bm, edge, dissolveVerts)
	if result then rebuildEM() end
	return result
end

function Core.SetFaceStyle(face, color, transparency)
	if color       ~= nil then face.color        = color        end
	if transparency ~= nil then face.transparency = transparency end
end

-- ─── HUD helpers ─────────────────────────────────────────────────────────────

function Core.GetVertexCount()
	if not Core.bm then return 0 end
	local n = 0
	for _ in pairs(Core.bm.verts) do n += 1 end
	return n
end

function Core.GetFaceCount()
	if not Core.bm then return 0 end
	local n = 0
	for _ in pairs(Core.bm.faces) do n += 1 end
	return n
end

-- ─── Session start ────────────────────────────────────────────────────────────

-- Initialize a session for meshPart. Returns true on success, false on failure.
function Core.Begin(meshPart)
	Core.sourceMeshPart   = meshPart
	_sourceMeshPartParent = meshPart.Parent

	local ok, err = pcall(function()
		Core.em = AssetService:CreateEditableMeshAsync(meshPart.MeshContent, { FixedSize = false })
	end)
	if not ok then
		warn("[Core] Could not load mesh:", err)
		Core.sourceMeshPart   = nil
		_sourceMeshPartParent = nil
		return false
	end

	Core.em:MergeVertices(0.001)
	Core.em:RemoveUnused()

	local ok2, err2 = pcall(function()
		local tempPart = AssetService:CreateMeshPartAsync(Content.fromObject(Core.em))
		meshPart:ApplyMesh(tempPart)
	end)
	if not ok2 then
		warn("[Core] Could not link mesh:", err2)
		Core.em               = nil
		Core.sourceMeshPart   = nil
		_sourceMeshPartParent = nil
		return false
	end

	local topoValue = meshPart:FindFirstChild("MPETopology")
	if topoValue and topoValue:IsA("StringValue") then
		local bm = MeshIO.fromTopology(Core.em, topoValue.Value, meshPart.Transparency)
		if bm then
			Core.bm = bm
		else
			warn("[Core] fromTopology failed, falling back to dissolvePlanar")
			Core.bm = MeshIO.fromEditableMesh(Core.em, meshPart.Color, meshPart.Transparency)
		end
	else
		Core.bm = MeshIO.fromEditableMesh(Core.em, meshPart.Color, meshPart.Transparency)
	end

	hideSource()
	return true
end

return Core
