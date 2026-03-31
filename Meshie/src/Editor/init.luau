-- Editor/init.luau
-- Thin coordinator for the plugin.
-- Owns: tool state, plugin lifecycle, session management.
-- RMesh is the data brain — all mesh state lives there, not here.

local HUD = require(script.Parent.HUD)
local UIConfig = require(script.Parent.HUD.UIConfig)
local UserConfig = require(script.Parent.HUD.UserConfig)
local Hotkeys = require(script.Parent.HUD.Hotkeys)
local RMesh = require(script.Parent.RMesh)
local ProxyManager = require(script.ProxyManager)
local HandleManager = require(script.HandleManager)
local SelectionManager = require(script.Parent.SelectionManager)
local GeometryMode = require(script.GeometryMode)
local History = require(script.History)
local Transform = require(script.Parent.RMesh.Operators.Transform)
local Extrude = require(script.Parent.RMesh.Operators.Extrude)
local Bevel = require(script.Parent.RMesh.Operators.Bevel)
local Dissolve = require(script.Parent.RMesh.Operators.Dissolve)

local Editor = {}

-- ─── State ────────────────────────────────────────────────────────────────────

local SELECT_MODE = "Select"
local enabled = false
local activeToolState = SELECT_MODE
local toolbarButton = nil

local rmesh = nil -- active RMesh instance, or nil when no session
local pm = nil -- active ProxyManager instance, or nil when no session
local originalParent = nil -- meshPart's parent before session (restored on end)
local activeTool = nil -- active operator instance, or nil when in SELECT_MODE

-- selectedEntries: { { type, id, part } } — proxies the user has selected.
local selectedEntries = {}
local selectionConn = nil
local handleDeselectedCallback = nil

local toolstates = {
	Transform = Transform,
	Extrude = Extrude,
	Bevel = Bevel,
	Dissolve = Dissolve,
}

local toolStateItems = {
	{ Name = "Transform", Icon = UIConfig.ToolIcons.Transform, Hotkey = UserConfig.ToolHotkeys.Transform },
	{ Name = "Extrude", Icon = UIConfig.ToolIcons.Extrude, Hotkey = UserConfig.ToolHotkeys.Extrude },
	{ Name = "Bevel", Icon = UIConfig.ToolIcons.Bevel, Hotkey = UserConfig.ToolHotkeys.Bevel },
	{ Name = "Dissolve", Icon = UIConfig.ToolIcons.Dissolve, Hotkey = UserConfig.ToolHotkeys.Dissolve },
}

local acceptedTypes = {
	Transform = { Vertex = true, Edge = true, Face = true },
	Extrude = { Face = true },
	Bevel = { Edge = true, Vertex = true },
	Dissolve = { Edge = true },
}

-- ─── Selection helpers ────────────────────────────────────────────────────────

-- Derive element type from proxy folder name.
local function getProxyInfo(part)
	if not part:IsA("BasePart") then
		return nil
	end
	local id = part:GetAttribute("ElementId")
	if not id then
		return nil
	end
	local parentName = part.Parent and part.Parent.Name
	local t
	if parentName == "VertexProxies" then
		t = "Vertex"
	elseif parentName == "EdgeProxies" then
		t = "Edge"
	elseif parentName == "FaceProxies" then
		t = "Face"
	else
		return nil
	end
	return { type = t, id = id, part = part }
end

-- ─── Scene sync ───────────────────────────────────────────────────────────────

local function syncScene()
	if not pm then
		return
	end
	pm:rebuild()
	pm:applyGeometryMode(GeometryMode.Get())
	if activeToolState ~= SELECT_MODE then
		pm:lockAll()
	end
end

-- ─── HUD ──────────────────────────────────────────────────────────────────────

local function refreshHud()
	HUD.SetActiveToolState(activeToolState)
	if rmesh then
		local status = "Edit"
			.. "\nVertices: "
			.. tostring(rmesh:GetVertexCount())
			.. "\nFaces: "
			.. tostring(rmesh:GetFaceCount())
			.. "\nTool: "
			.. (if activeToolState == SELECT_MODE then "Select" else activeToolState)
		HUD.SetMainButtonText("Finalize")
		HUD.SetStatus(status)
	else
		HUD.SetMainButtonText("Edit")
		HUD.SetStatus("Selection")
	end
end

-- ─── Handle focus ─────────────────────────────────────────────────────────────

local function focusHandle(handle, onDeselected)
	SelectionManager.Set({ handle })
	task.defer(function()
		handleDeselectedCallback = onDeselected
	end)
end

local function unfocusHandle()
	handleDeselectedCallback = nil
end

-- ─── Selection listener ───────────────────────────────────────────────────────

local function onSelectionChanged()
	local sel = SelectionManager.Get()

	-- Handle auto-commit: fires once when the handle leaves the selection.
	if handleDeselectedCallback then
		for _, inst in ipairs(sel) do
			if inst:GetAttribute("IsToolHandle") then
				return
			end
		end
		local cb = handleDeselectedCallback
		handleDeselectedCallback = nil
		cb()
		return
	end

	-- Proxy selection is locked during an active operation.
	if activeToolState ~= SELECT_MODE then
		return
	end

	-- Proxy selection: accumulate proxies matching the current geometry mode.
	selectedEntries = {}
	for _, inst in ipairs(sel) do
		if inst:GetAttribute("IsToolHandle") then
			continue
		end
		local info = getProxyInfo(inst)
		if info and info.type == GeometryMode.Get() then
			selectedEntries[#selectedEntries + 1] = info
		end
	end
end

-- ─── Operation lifecycle ──────────────────────────────────────────────────────

local function commitOperation()
	if activeToolState == SELECT_MODE then
		return
	end
	unfocusHandle()

	if activeToolState == "Dissolve" then
		if activeTool:Execute(rmesh) then
			syncScene()
		end
	end

	activeTool:Commit()
	activeTool = nil
	History.Commit(rmesh)

	HandleManager.StopListening()
	HandleManager.Clear()
	selectedEntries = {}
	activeToolState = SELECT_MODE
	HUD.SetOperatorPanel(nil)
	if pm then
		pm:applyGeometryMode(GeometryMode.Get())
	end
	refreshHud()
end

local function cancelOperation()
	if activeToolState == SELECT_MODE then
		return
	end
	unfocusHandle()

	activeTool:Cancel(rmesh)
	activeTool = nil
	History.Cancel()

	HandleManager.StopListening()
	HandleManager.Clear()
	selectedEntries = {}
	activeToolState = SELECT_MODE
	HUD.SetOperatorPanel(nil)
	if rmesh then
		syncScene()
	end
	refreshHud()
end

-- ─── Tool activation ─────────────────────────────────────────────────────────

local function activateToolState(name)
	if not rmesh then
		return
	end
	if not toolstates[name] then
		return
	end
	if #selectedEntries == 0 then
		return
	end

	local lastEntry = selectedEntries[#selectedEntries]
	if not acceptedTypes[name] or not acceptedTypes[name][lastEntry.type] then
		return
	end

	if activeToolState ~= SELECT_MODE then
		cancelOperation()
		-- Re-find the proxy after syncScene rebuilt all proxies.
		local freshProxy = pm:findProxy(lastEntry.type, lastEntry.id)
		if not freshProxy then
			return
		end
		local freshInfo = getProxyInfo(freshProxy)
		if not freshInfo then
			return
		end
		selectedEntries = { freshInfo }
		lastEntry = freshInfo
	end

	activeToolState = name

	local proxy = lastEntry.part
	-- Re-look up the proxy in case it was rebuilt by cancelOperation above.
	if not proxy or not proxy.Parent then
		proxy = pm:findProxy(lastEntry.type, lastEntry.id)
	end
	if not proxy then
		activeToolState = SELECT_MODE
		return
	end

	local handle = HandleManager.Arm(proxy, lastEntry.type)
	if not handle then
		activeToolState = SELECT_MODE
		return
	end

	if pm then
		pm:lockAll()
	end
	focusHandle(handle, commitOperation)
	activeTool = toolstates[name].new()
	History.StartRecording(rmesh, name)
	activeTool:Activate(rmesh, handle, selectedEntries)
	HandleManager.BeginListening()
	HUD.SetOperatorPanel(name)
	refreshHud()
end

-- ─── Geometry mode ────────────────────────────────────────────────────────────

local function setGeometryMode(mode)
	if GeometryMode.Get() == mode then
		return
	end
	GeometryMode.Set(mode)
	selectedEntries = {}
	HandleManager.Clear()
	if pm then
		pm:applyGeometryMode(mode)
	end
	HUD.SetGeometryMode(mode)
	refreshHud()
end

-- ─── Handle movement — the core loop ─────────────────────────────────────────

local function onHandleChanged(handle)
	if not rmesh or activeToolState == SELECT_MODE or not activeTool then
		return
	end
	if activeTool:Apply(rmesh, handle) then
		syncScene()
		refreshHud()
	end
end

-- ─── Session lifecycle ────────────────────────────────────────────────────────

local function beginSession()
	local sel = SelectionManager.Get()
	if #sel ~= 1 or not sel[1]:IsA("MeshPart") then
		HUD.SetStatus("Select one MeshPart.")
		return
	end

	originalParent = sel[1].Parent
	sel[1].Parent = game:GetService("ServerStorage")

	rmesh = RMesh.new(sel[1])
	if not rmesh then
		sel[1].Parent = originalParent
		originalParent = nil
		refreshHud()
		return
	end

	pm = ProxyManager.new(rmesh)
	History.Begin(rmesh)
	HandleManager.Begin()
	HandleManager.Init(onHandleChanged)
	selectionConn = SelectionManager.Changed:Connect(onSelectionChanged)
	selectedEntries = {}
	syncScene()
	refreshHud()
end

local function endSession()
	if activeToolState ~= SELECT_MODE then
		cancelOperation()
	end
	HandleManager.Destroy()

	if selectionConn then
		selectionConn:Disconnect()
		selectionConn = nil
	end
	selectedEntries = {}

	local meshPart = rmesh.meshPart
	pm:applyFaceProxyColors()
	pm:destroy()
	pm = nil
	rmesh:Finalize()
	--rmesh:Destroy()
	rmesh = nil

	meshPart.Parent = originalParent
	originalParent = nil

	SelectionManager.Set({ meshPart })
	refreshHud()
end

-- ─── Plugin lifecycle ─────────────────────────────────────────────────────────

local function enable(_p, button)
	toolbarButton = button
	toolbarButton:SetActive(true)

	local historyBusy = false
	local function onHistoryChanged(isRedo)
		if historyBusy or not rmesh then
			return
		end
		historyBusy = true
		History.Restore(rmesh, isRedo)
		syncScene()
		refreshHud()
		task.defer(function()
			historyBusy = false
		end)
	end
	History.Listen(function()
		onHistoryChanged(false)
	end, function()
		onHistoryChanged(true)
	end)

	HUD.Start()
	HUD.SetToolStates(toolStateItems, SELECT_MODE)
	HUD.SetMainActionCallback(function()
		if rmesh then
			endSession()
		else
			beginSession()
		end
	end)
	HUD.SetToolStateCallback(activateToolState)
	HUD.SetGeometryModeCallback(setGeometryMode)
	HUD.SetOperatorCommitCallback(commitOperation)
	HUD.SetOperatorCancelCallback(cancelOperation)
	HUD.SetUploadActionCallback(function()
		HUD.SetStatus("Upload unavailable\nuntil CreateAssetAsync() supports\nCreator Store plugins.")
	end)
	HUD.SetVisible(true)

	Hotkeys.Start(function()
		return enabled
	end, activateToolState, setGeometryMode)
	refreshHud()
end

local function disable()
	if rmesh then
		endSession()
	end

	History.Unlisten()
	Hotkeys.Destroy()
	HandleManager.Destroy()
	HUD.SetVisible(false)
	HUD.Destroy()

	if toolbarButton then
		toolbarButton:SetActive(false)
		toolbarButton = nil
	end
end

function Editor.Toggle(p, button)
	if enabled then
		enabled = false
		disable()
	else
		enabled = true
		enable(p, button)
	end
end

return Editor
