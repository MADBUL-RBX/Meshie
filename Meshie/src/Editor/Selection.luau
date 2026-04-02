-- Selection.luau
-- Custom mouse picking and hover highlight for Meshie.
-- Raycasts EditableMesh:RaycastLocal() to bypass CollisionFidelity issues
-- with proxy parts. Resolves hits to bm elements and force-selects the
-- corresponding proxy via SelectionManager.
--
-- Init(plugin) must be called from Loader.plugin.luau (same pattern as
-- RibbonToolManager) since plugin is only a global there.

local UserInputService = game:GetService("UserInputService")
local SelectionManager = require(script.Parent.Parent.SelectionManager)
local Input = require(script.Parent.Parent.Input)

local Selection = {}

local plugin = nil
local rmesh = nil
local pm = nil
local getMode = nil -- () → "Vertex" | "Edge" | "Face"
local paused = false
local hoverHL = nil -- single Highlight instance, Adornee swapped per hover
local emToVert = {} -- emId → bm vert reverse map
local mouse = nil -- PluginMouse, obtained after Activate
local moveConn = nil
local clickConn = nil

-- ─── Init ────────────────────────────────────────────────────────────────────

function Selection.Init(p)
	plugin = p
end

-- ─── Reverse map ─────────────────────────────────────────────────────────────

local function buildReverseMap()
	emToVert = {}
	if not rmesh or not rmesh.bm then
		return
	end
	local count = 0
	for _, vert in pairs(rmesh.bm.verts) do
		if vert.emId then
			emToVert[vert.emId] = vert
			count += 1
		end
	end
	print("[Selection] buildReverseMap: mapped", count, "verts")
end

-- ─── Element resolution ───────────────────────────────────────────────────────

local function findEdgeBetween(bm, v1, v2)
	for _, edge in ipairs(bm:vertEdges(v1)) do
		if edge.v1 == v2 or edge.v2 == v2 then
			return edge
		end
	end
	return nil
end

local function findFaceContaining(bm, v1, v2, v3)
	for _, edge in ipairs(bm:vertEdges(v1)) do
		for _, face in ipairs(bm:edgeFaces(edge)) do
			local hasV2, hasV3 = false, false
			for _, v in ipairs(bm:faceVerts(face)) do
				if v == v2 then
					hasV2 = true
				end
				if v == v3 then
					hasV3 = true
				end
			end
			if hasV2 and hasV3 then
				return face
			end
		end
	end
	return nil
end

-- ─── EM raycast ───────────────────────────────────────────────────────────────

local function pick()
	if not rmesh or not rmesh.em or not rmesh.meshPart then
		return nil
	end

	local mousePos = UserInputService:GetMouseLocation()
	local camera = workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local cf = rmesh.meshPart.CFrame
	local sf = rmesh:GetScaleFactor()
	local localOrigin = cf:PointToObjectSpace(ray.Origin) / sf
	local localDir = cf:VectorToObjectSpace(ray.Direction) / sf

	local faceId, hitPoint, bary = rmesh.em:RaycastLocal(localOrigin, localDir * 5000)
	if not faceId then
		return nil
	end

	local emVerts = rmesh.em:GetFaceVertices(faceId)
	if not emVerts or #emVerts < 3 then
		print("[Selection] pick: faceId", faceId, "has fewer than 3 em verts")
		return nil
	end

	local bv1 = emToVert[emVerts[1]]
	local bv2 = emToVert[emVerts[2]]
	local bv3 = emToVert[emVerts[3]]
	if not bv1 or not bv2 or not bv3 then
		print(
			"[Selection] pick: emId→bm lookup failed for face",
			faceId,
			"emVerts:",
			emVerts[1],
			emVerts[2],
			emVerts[3],
			"→ bv:",
			bv1 ~= nil,
			bv2 ~= nil,
			bv3 ~= nil
		)
		return nil
	end

	local mode = getMode()

	if mode == "Face" then
		local face = findFaceContaining(rmesh.bm, bv1, bv2, bv3)
		if face then
			print("[Selection] pick: Face hit →", face.id)
			return pm:findProxy("Face", face.id)
		end
		print("[Selection] pick: Face mode — no bm face found for hit triangle")
	elseif mode == "Edge" then
		local candidates = {
			findEdgeBetween(rmesh.bm, bv1, bv2),
			findEdgeBetween(rmesh.bm, bv2, bv3),
			findEdgeBetween(rmesh.bm, bv1, bv3),
		}
		local worldHit = rmesh:LocalToWorld(hitPoint)
		local bestEdge, bestDist = nil, math.huge
		for _, edge in ipairs(candidates) do
			if edge then
				local mid = rmesh:LocalToWorld((edge.v1.position + edge.v2.position) * 0.5)
				local dist = (mid - worldHit).Magnitude
				if dist < bestDist then
					bestEdge = edge
					bestDist = dist
				end
			end
		end
		if bestEdge then
			print("[Selection] pick: Edge hit →", bestEdge.id, "(dist", bestDist, ")")
			return pm:findProxy("Edge", bestEdge.id)
		end
		print("[Selection] pick: Edge mode — no candidate edge found")
	elseif mode == "Vertex" then
		local bestVert
		if bary.X >= bary.Y and bary.X >= bary.Z then
			bestVert = bv1
		elseif bary.Y >= bary.X and bary.Y >= bary.Z then
			bestVert = bv2
		else
			bestVert = bv3
		end
		if bestVert then
			print("[Selection] pick: Vertex hit →", bestVert.id, "(bary", bary, ")")
			return pm:findProxy("Vertex", bestVert.id)
		end
	end

	return nil
end

-- ─── Hover + click handlers ───────────────────────────────────────────────────

local function updateHover()
	if paused then
		hoverHL.Enabled = false
		return
	end
	local proxy = pick()
	if proxy then
		hoverHL.Adornee = proxy
		hoverHL.Enabled = true
	else
		hoverHL.Enabled = false
	end
end

local function onClick()
	if paused then
		print("[Selection] onClick: paused, ignoring")
		return
	end
	local proxy = pick()
	if proxy then
		print("[Selection] onClick: selecting proxy", proxy:GetAttribute("ElementId"))
		SelectionManager.Set({ proxy })
	else
		print("[Selection] onClick: no proxy hit")
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function Selection.Start(r, p, modeGetter)
	rmesh = r
	pm = p
	getMode = modeGetter
	paused = false

	buildReverseMap()

	hoverHL = Instance.new("Highlight")
	hoverHL.FillTransparency = 1
	hoverHL.OutlineColor = Color3.fromRGB(255, 255, 255)
	hoverHL.Adornee = nil
	hoverHL.Parent = workspace

	if plugin then
		plugin:Activate(true)
		mouse = plugin:GetMouse()
		moveConn = mouse.Move:Connect(updateHover)
		clickConn = mouse.Button1Down:Connect(onClick)
	end

	print("[Selection] Started")
end

function Selection.Refresh()
	buildReverseMap()
end

function Selection.Pause()
	paused = true
	if hoverHL then
		hoverHL.Enabled = false
	end
	if plugin then
		plugin:Deactivate()
	end
	print("[Selection] Paused")
end

function Selection.Resume()
	paused = false
	if plugin then
		plugin:Activate(true)
	end
	print("[Selection] Resumed")
end

function Selection.Stop()
	if moveConn then
		moveConn:Disconnect()
		moveConn = nil
	end
	if clickConn then
		clickConn:Disconnect()
		clickConn = nil
	end
	if hoverHL then
		hoverHL:Destroy()
		hoverHL = nil
	end
	if plugin then
		plugin:Deactivate()
	end
	mouse = nil
	rmesh = nil
	pm = nil
	getMode = nil
	emToVert = {}
	print("[Selection] Stopped")
end

return Selection
