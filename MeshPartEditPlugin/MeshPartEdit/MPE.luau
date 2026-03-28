-- MPE.luau
-- Single coordinator for the plugin.
--
-- Owns: the session object, the tool state.
-- Responsible for: session lifecycle, calling EditScene.RebuildProxies after every change.
--
-- Tools are pure computation — they never call EditScene directly.
-- All proxy rebuilds happen here and only here.

local Selection = game:GetService("Selection")

local Hotkeys = require(script.Parent.Hotkeys)
local UserConfig = require(script.Parent.UserConfig)
local Hud = require(script.Parent.UI.Hud)
local UIConfig = require(script.Parent.UI.UIConfig)
local MeshSession = require(script.Parent.Core.MeshSession)
local EditScene = require(script.Parent.Scene.EditScene)
local SelectionManager = require(script.Parent.Scene.SelectionManager)
local HandleManager = require(script.Parent.Scene.HandleManager)
local GeometryMode = require(script.Parent.Scene.GeometryMode)
local Transform = require(script.Parent.Tools.Transform)
local Extrude = require(script.Parent.Tools.Extrude)
local Bevel = require(script.Parent.Tools.Bevel)
local Dissolve = require(script.Parent.Tools.Dissolve)
local History = require(script.Parent.History)

local MPE = {}

-- ─── State ────────────────────────────────────────────────────────────────────

local SELECT_MODE = "Select"
local session = nil -- active MeshSession object; non-nil iff in session
local enabled = false
local activeToolState = SELECT_MODE
local selectionConn = nil
local undoConn = nil
local redoConn = nil
local toolbarButton = nil

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

-- ─── Scene sync ───────────────────────────────────────────────────────────────

-- Rebuild all proxies from current session state, then apply geometry mode.
-- This is the only place RebuildProxies is called. Tools never call it.
local function syncScene()
	if not session then
		return
	end
	EditScene.RebuildProxies(session.bm, function(p)
		return session:LocalToWorld(p)
	end, session.sourceMeshPart.Material)
	EditScene.ApplyGeometryMode(GeometryMode.Get())
end

-- ─── HUD ──────────────────────────────────────────────────────────────────────

local function refreshHud()
	Hud.SetActiveToolState(activeToolState)
	if session then
		local status = "Edit"
			.. "\nVertices: "
			.. tostring(session:GetVertexCount())
			.. "\nFaces: "
			.. tostring(session:GetFaceCount())
			.. "\nTool: "
			.. (if activeToolState == SELECT_MODE then "Select" else activeToolState)
		Hud.SetMainButtonText("Finalize")
		Hud.SetStatus(status)
	else
		Hud.SetMainButtonText("Edit")
		Hud.SetStatus("Selection")
	end
end

-- ─── Operation lifecycle ──────────────────────────────────────────────────────

local function commitOperation()
	if activeToolState == SELECT_MODE then
		return
	end

	-- Dissolve performs its operation on commit (Apply is always a no-op for Dissolve)
	if activeToolState == "Dissolve" then
		if Dissolve.Execute(session) then
			syncScene()
		end
	end

	toolstates[activeToolState].Commit(session)
	History.Commit(session)

	HandleManager.StopListening()
	HandleManager.Clear()
	SelectionManager.Clear()
	activeToolState = SELECT_MODE
	Hud.SetOperatorPanel(nil)
	if session then
		EditScene.ApplyGeometryMode(GeometryMode.Get())
	end
	refreshHud()
end

local function cancelOperation()
	if activeToolState == SELECT_MODE then
		return
	end

	-- Tool Cancel calls session:SetBMesh(savedBM) to restore topology.
	toolstates[activeToolState].Cancel(session)
	History.Cancel()

	HandleManager.StopListening()
	HandleManager.Clear()
	SelectionManager.Clear()
	activeToolState = SELECT_MODE
	Hud.SetOperatorPanel(nil)
	if session then
		syncScene()
	end
	refreshHud()
end

-- ─── Toolstate activation ─────────────────────────────────────────────────────

local function activateToolState(name)
	if not session then
		return
	end
	if not toolstates[name] then
		return
	end
	if not SelectionManager.HasSelection() then
		return
	end

	local entry = SelectionManager.GetLast()
	if not entry then
		return
	end

	local pt = entry.proxyType
	if not acceptedTypes[name] or not acceptedTypes[name][pt] then
		return
	end

	if activeToolState ~= SELECT_MODE then
		cancelOperation()
	end

	activeToolState = name

	local proxy = EditScene.FindProxy(entry.name)
	if not proxy then
		activeToolState = SELECT_MODE
		return
	end

	local handle = HandleManager.Arm(proxy)
	if not handle then
		activeToolState = SELECT_MODE
		return
	end

	History.StartRecording(name, session)
	toolstates[name].Activate(session, handle)
	HandleManager.BeginListening()
	Hud.SetOperatorPanel(name)
	refreshHud()
end

-- ─── Geometry mode ────────────────────────────────────────────────────────────

local function setGeometryMode(mode)
	if GeometryMode.Get() == mode then
		return
	end
	GeometryMode.Set(mode)
	SelectionManager.Clear()
	HandleManager.Clear()
	if session then
		EditScene.ApplyGeometryMode(mode)
	end
	Hud.SetGeometryMode(mode)
	refreshHud()
end

-- ─── Handle movement — the core loop ─────────────────────────────────────────

local function onHandleChanged(handle, oldCF, oldSz, newCF, newSz)
	if not session or activeToolState == SELECT_MODE then
		return
	end
	local tool = toolstates[activeToolState]
	if tool.Apply(session, handle, oldCF, oldSz, newCF, newSz) then
		syncScene()
		refreshHud()
	end
end

-- ─── Selection ────────────────────────────────────────────────────────────────

local function onSelectionChanged()
	if not session then
		return
	end
	if activeToolState ~= SELECT_MODE then
		return
	end

	local sel = Selection:Get()
	if #sel == 0 then
		return
	end

	for _, inst in ipairs(sel) do
		if inst:GetAttribute("IsToolHandle") then
			continue
		end
		local pt = inst:GetAttribute("ProxyType")
		if not pt then
			continue
		end
		if pt ~= GeometryMode.Get() then
			continue
		end
		SelectionManager.Add(inst)
	end

	refreshHud()
end

-- ─── Session lifecycle ────────────────────────────────────────────────────────

local function beginSession()
	local sel = Selection:Get()
	if #sel ~= 1 or not sel[1]:IsA("MeshPart") then
		Hud.SetStatus("Select one MeshPart.")
		return
	end

	session = MeshSession.new(sel[1])
	if not session then
		refreshHud()
		return
	end
	History.Begin(session)

	EditScene.Begin()
	Selection:Set({})
	HandleManager.Init(onHandleChanged)
	SelectionManager.Clear()
	syncScene()
	refreshHud()
end

local function endSession()
	if activeToolState ~= SELECT_MODE then
		cancelOperation()
	end
	HandleManager.Clear()
	SelectionManager.Clear()

	local meshPart = session.sourceMeshPart
	EditScene.ApplyFaceProxyColorsToSession(session.bm)
	EditScene.Destroy()
	session:Finalize()
	session:Destroy()
	session = nil

	if meshPart then
		Selection:Set({ meshPart })
	end
	refreshHud()
end

-- ─── Plugin lifecycle ─────────────────────────────────────────────────────────

local function enable(_p, button)
	toolbarButton = button
	toolbarButton:SetActive(true)

	local historyBusy = false
	local function onHistoryChanged(label, isRedo)
		print("[MPE]", label, "fired — session:", session ~= nil, "busy:", historyBusy)
		if historyBusy or not session then
			return
		end
		historyBusy = true
		History.Restore(session, isRedo)
		syncScene()
		refreshHud()
		task.defer(function()
			historyBusy = false
		end)
	end
	undoConn = game:GetService("ChangeHistoryService").OnUndo:Connect(function()
		onHistoryChanged("OnUndo", false)
	end)
	redoConn = game:GetService("ChangeHistoryService").OnRedo:Connect(function()
		onHistoryChanged("OnRedo", true)
	end)

	Hud.Start()
	Hud.SetToolStates(toolStateItems, SELECT_MODE)
	Hud.SetMainActionCallback(function()
		if session then
			endSession()
		else
			beginSession()
		end
	end)
	Hud.SetToolStateCallback(activateToolState)
	Hud.SetGeometryModeCallback(setGeometryMode)
	Hud.SetOperatorCommitCallback(commitOperation)
	Hud.SetOperatorCancelCallback(cancelOperation)
	Hud.SetUploadActionCallback(function()
		Hud.SetStatus("Upload unavailable\nuntil CreateAssetAsync() supports\nCreator Store plugins.")
	end)
	Hud.SetDebugHighlightActionCallback(function()
		UserConfig.DebugHighlight = not UserConfig.DebugHighlight
		Hud.SetDebugHighlight(UserConfig.DebugHighlight)
		if session then
			syncScene()
		end
		refreshHud()
	end)
	Hud.SetDebugHighlight(UserConfig.DebugHighlight)
	Hud.SetVisible(true)

	selectionConn = Selection.SelectionChanged:Connect(onSelectionChanged)
	Hotkeys.Start(function()
		return enabled
	end, activateToolState)
	refreshHud()
end

local function disable()
	if session then
		endSession()
	end

	if undoConn then
		undoConn:Disconnect()
		undoConn = nil
	end
	if redoConn then
		redoConn:Disconnect()
		redoConn = nil
	end
	if selectionConn then
		selectionConn:Disconnect()
		selectionConn = nil
	end

	Hotkeys.Destroy()
	HandleManager.Clear()
	SelectionManager.Clear()
	Hud.SetVisible(false)
	Hud.Destroy()

	if toolbarButton then
		toolbarButton:SetActive(false)
		toolbarButton = nil
	end
end

function MPE.Toggle(p, button)
	if enabled then
		enabled = false
		disable()
	else
		enabled = true
		enable(p, button)
	end
end

return MPE
