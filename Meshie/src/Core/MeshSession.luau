-- MeshSession.luau
-- Session object factory. One session lives per editing session.
-- MeshSession.new(meshPart) → session | nil
--
-- The session owns:
--   em  (EditableMesh) — CHS-tracked source of truth. The EM IS the MeshContent
--                        asset. NEVER call em:Destroy(). Nil on Destroy() and
--                        let GC collect it.
--   bm  (BMesh)        — N-gon filter over EM. Always derivable from EM via
--                        SyncFromEM(). Written back to EM via rebuildEM().
--   sourceMeshPart     — The MeshPart being edited. Hidden in ServerStorage
--                        during the session, restored on Finalize/Destroy.
--
-- Data direction: EM → BMesh → Proxies. Never reversed.
-- rebuildEM()              — only path that writes BMesh → EM (topology ops).
-- ApplyTransformToVerts()  — writes positions live via SetPosition (no rebuild).

local AssetService = game:GetService("AssetService")

local BMesh = require(script.Parent.BMesh)
local MeshIO = require(script.Parent.MeshIO)
local Operations = require(script.Parent.Operations)

local MeshSession = {}

-- ─── Private helpers ──────────────────────────────────────────────────────────

local function hideSource(self)
	self._sourceMeshPartParent = self.sourceMeshPart.Parent
	self.sourceMeshPart.Parent = game:GetService("ServerStorage")
end

local function restoreSource(self)
	if self.sourceMeshPart and self._sourceMeshPartParent then
		self.sourceMeshPart.Parent = self._sourceMeshPartParent
		self._sourceMeshPartParent = nil
	end
end

-- Full EM rebuild from current BMesh state.
-- Called after any topology change (extrude, bevel, dissolve, SetBMesh).
-- Refreshes emId on all BMesh verts so SetPosition works correctly afterwards.
local function rebuildEM(self)
	if not self.bm or not self.em then
		return
	end

	for _, fid in ipairs(self.em:GetFaces()) do
		self.em:RemoveFace(fid)
	end
	self.em:RemoveUnused()

	local emIdByVert = {}
	local colorIdByKey = {}

	for _, vert in pairs(self.bm.verts) do
		local vid = self.em:AddVertex(vert.position)
		emIdByVert[vert] = vid
		vert.emId = vid
	end

	local function getColorId(face)
		local ck = tostring(face.color.R)
			.. "|"
			.. tostring(face.color.G)
			.. "|"
			.. tostring(face.color.B)
			.. "|"
			.. tostring(face.transparency)
		if not colorIdByKey[ck] then
			colorIdByKey[ck] = self.em:AddColor(face.color, face.transparency)
		end
		return colorIdByKey[ck]
	end

	for _, face in pairs(self.bm.faces) do
		local verts = BMesh.faceVerts(face)
		local n = #verts
		if n < 3 then
			continue
		end
		local colorId = getColorId(face)
		for i = 2, n - 1 do
			local fid = self.em:AddTriangle(emIdByVert[verts[1]], emIdByVert[verts[i]], emIdByVert[verts[i + 1]])
			self.em:SetFaceColors(fid, { colorId, colorId, colorId })
			local nid = self.em:AddNormal()
			self.em:SetFaceNormals(fid, { nid, nid, nid })
		end
	end
end

-- ─── Session object ───────────────────────────────────────────────────────────

local Session = {}
Session.__index = Session

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

-- Apply a baked MeshPart to sourceMeshPart, preserving the current Size/MeshSize ratio.
function Session:ApplyMeshUpdate(tempPart)
	if not self.sourceMeshPart or not tempPart then return end
	local oldScale = self.sourceMeshPart.Size / self.sourceMeshPart.MeshSize
	self.sourceMeshPart:ApplyMesh(tempPart)
	self.sourceMeshPart.Size = tempPart.MeshSize * oldScale
end

-- Finalize: sync face colors, serialize topology, restore source.
-- No ApplyMesh needed — History.Commit already keeps MeshContent current.
function Session:Finalize()
	if not self.em or not self.sourceMeshPart then
		return
	end

	-- Sync BMesh → EM so face colors painted on proxies are baked in.
	rebuildEM(self)

	-- Persist N-gon face topology so re-editing reconstructs BMesh correctly.
	local topoJson = MeshIO.serializeTopology(self.bm)
	local existing = self.sourceMeshPart:FindFirstChild("MPETopology")
	if existing then
		existing.Value = topoJson
	else
		local sv = Instance.new("StringValue")
		sv.Name = "MPETopology"
		sv.Value = topoJson
		sv.Parent = self.sourceMeshPart
	end

	restoreSource(self)
end

-- End the session. Restores sourceMeshPart and nils all state.
-- NEVER calls em:Destroy() — the EM IS the MeshContent asset.
function Session:Destroy()
	restoreSource(self)
	self.em = nil
	self.bm = nil
	self.sourceMeshPart = nil
	self._sourceMeshPartParent = nil
end

-- ─── EM ↔ BMesh sync ──────────────────────────────────────────────────────────

-- Rebuild BMesh from EM. Called after CHS undo/redo reverts EM state.
function Session:SyncFromEM()
	if not self.em or not self.sourceMeshPart then
		return
	end
	self.bm = MeshIO.fromEditableMesh(self.em, self.sourceMeshPart.Color, self.sourceMeshPart.Transparency)
end

-- Rebuild EM from sourceMeshPart.MeshContent after CHS reverts it to a static
-- snapshot, then sync BMesh. Static content has split vertex attributes so
-- MergeVertices + RemoveUnused are required before SyncFromEM.
function Session:RebuildFromContent()
	if not self.sourceMeshPart then
		return false
	end
	local ok, err = pcall(function()
		self.em = AssetService:CreateEditableMeshAsync(self.sourceMeshPart.MeshContent, { FixedSize = false })
	end)
	if not ok then
		warn("[MeshSession] RebuildFromContent failed:", err)
		return false
	end
	self.em:MergeVertices(0.001)
	self.em:RemoveUnused()
	self:SyncFromEM()
	return true
end

-- Replace BMesh and immediately rebuild EM to match.
-- Used by Bevel (fresh clone per snap) and Cancel (restore savedBM).
function Session:SetBMesh(newBM)
	self.bm = newBM
	rebuildEM(self)
end

-- ─── Coordinate transforms ────────────────────────────────────────────────────

function Session:GetScaleFactor()
	if not self.sourceMeshPart then
		return Vector3.one
	end
	return self.sourceMeshPart.Size / self.sourceMeshPart.MeshSize
end

function Session:LocalToWorld(localPos)
	return self.sourceMeshPart.CFrame:PointToWorldSpace(localPos * self:GetScaleFactor())
end

function Session:WorldToLocal(worldPos)
	return self.sourceMeshPart.CFrame:PointToObjectSpace(worldPos) / self:GetScaleFactor()
end

-- ─── EM mutation helpers ──────────────────────────────────────────────────────

-- Move verts in BMesh and write to EM via SetPosition.
-- Called live every snap increment — no rebuildEM.
function Session:ApplyTransformToVerts(verts, oldCF, oldSz, newCF, newSz)
	if not self.bm or not self.em then
		return
	end
	local function ax(o, n)
		return if o == 0 then 1 else n / o
	end
	local scale = Vector3.new(ax(oldSz.X, newSz.X), ax(oldSz.Y, newSz.Y), ax(oldSz.Z, newSz.Z))
	for _, vert in ipairs(verts) do
		local world = self:LocalToWorld(vert.position)
		local handleLocal = oldCF:PointToObjectSpace(world)
		local scaledLocal = handleLocal * scale
		local newWorld = newCF:PointToWorldSpace(scaledLocal)
		vert.position = self:WorldToLocal(newWorld)
		if vert.emId then
			self.em:SetPosition(vert.emId, vert.position)
		end
	end
end

-- Extrude a face in BMesh then rebuild EM.
-- Returns the extrude result table, or nil if it failed.
function Session:ExtrudeFace(face)
	if not self.bm or not self.em then
		return nil
	end
	local result = Operations.extrudeFace(self.bm, face)
	if result then
		rebuildEM(self)
	end
	return result
end

-- Dissolve an edge in BMesh then rebuild EM.
-- Returns the dissolve result table, or nil if it failed.
function Session:DissolveEdge(edge, dissolveVerts)
	if not self.bm or not self.em then
		return nil
	end
	local result = Operations.dissolveEdge(self.bm, edge, dissolveVerts)
	if result then
		rebuildEM(self)
	end
	return result
end

-- Mutate face style in BMesh. Written to EM on next rebuildEM.
function Session:SetFaceStyle(face, color, transparency)
	if color ~= nil then
		face.color = color
	end
	if transparency ~= nil then
		face.transparency = transparency
	end
end

-- ─── HUD helpers ─────────────────────────────────────────────────────────────

function Session:GetVertexCount()
	if not self.bm then
		return 0
	end
	local n = 0
	for _ in pairs(self.bm.verts) do
		n += 1
	end
	return n
end

function Session:GetFaceCount()
	if not self.bm then
		return 0
	end
	local n = 0
	for _ in pairs(self.bm.faces) do
		n += 1
	end
	return n
end

-- ─── Factory ──────────────────────────────────────────────────────────────────

-- Create a new session for meshPart. Returns the session object, or nil on failure.
-- On success, sourceMeshPart is hidden in ServerStorage and editing can begin.
function MeshSession.new(meshPart)
	local self = setmetatable({
		em = nil,
		bm = nil,
		sourceMeshPart = meshPart,
		_sourceMeshPartParent = meshPart.Parent,
	}, Session)

	-- Load EM from MeshContent. FixedSize=false is mandatory to add/remove geometry.
	local ok, err = pcall(function()
		self.em = AssetService:CreateEditableMeshAsync(meshPart.MeshContent, { FixedSize = false })
	end)
	if not ok then
		warn("[MeshSession] Could not load mesh:", err)
		return nil
	end

	-- Collapse split vertex attributes from the imported mesh down to unique positions.
	self.em:MergeVertices(0.001)
	self.em:RemoveUnused()

	-- Link EM into sourceMeshPart.MeshContent so the EM IS the live asset.
	local ok2, err2 = pcall(function()
		local tempPart = AssetService:CreateMeshPartAsync(Content.fromObject(self.em))
		meshPart:ApplyMesh(tempPart)
	end)
	if not ok2 then
		warn("[MeshSession] Could not link mesh:", err2)
		return nil
	end

	-- Build BMesh. Use persisted topology if available to preserve N-gon faces
	-- from a previous session; fall back to dissolvePlanar reconstruction otherwise.
	local topoValue = meshPart:FindFirstChild("MPETopology")
	if topoValue and topoValue:IsA("StringValue") then
		local bm = MeshIO.fromTopology(self.em, topoValue.Value, meshPart.Transparency)
		if bm then
			self.bm = bm
		else
			warn("[MeshSession] fromTopology failed, falling back to dissolvePlanar")
			self.bm = MeshIO.fromEditableMesh(self.em, meshPart.Color, meshPart.Transparency)
		end
	else
		self.bm = MeshIO.fromEditableMesh(self.em, meshPart.Color, meshPart.Transparency)
	end

	hideSource(self)
	return self
end

return MeshSession
