-- MPE.luau
-- Single coordinator for the plugin.
--
-- Owns: tool state, plugin lifecycle.
-- Core is the data hub — session state lives there, not here.
--
-- Tools are pure computation — they never call Core directly for rebuilds.
-- All proxy rebuilds happen via syncScene() and only here.

local Hotkeys          = require(script.Parent.Hotkeys)
local UserConfig       = require(script.Parent.UserConfig)
local UI               = require(script.Parent.UI)
local UIConfig         = require(script.Parent.UI.UIConfig)
local Core             = require(script.Parent.Core)
local Scene            = require(script.Parent.Scene)
local SelectionManager = require(script.Parent.Scene.SelectionManager)
local HandleManager    = require(script.Parent.Scene.HandleManager)
local GeometryMode     = require(script.Parent.Scene.GeometryMode)
local Transform        = require(script.Parent.Tools.Transform)
local Extrude          = require(script.Parent.Tools.Extrude)
local Bevel            = require(script.Parent.Tools.Bevel)
local Dissolve         = require(script.Parent.Tools.Dissolve)
local History          = require(script.Parent.History)

local MPE = {}

-- ─── State ────────────────────────────────────────────────────────────────────

local SELECT_MODE    = "Select"
local enabled        = false
local activeToolState = SELECT_MODE
local toolbarButton  = nil

local toolstates = {
	Transform = Transform,
	Extrude   = Extrude,
	Bevel     = Bevel,
	Dissolve  = Dissolve,
}

local toolStateItems = {
	{ Name = "Transform", Icon = UIConfig.ToolIcons.Transform, Hotkey = UserConfig.ToolHotkeys.Transform },
	{ Name = "Extrude",   Icon = UIConfig.ToolIcons.Extrude,   Hotkey = UserConfig.ToolHotkeys.Extrude   },
	{ Name = "Bevel",     Icon = UIConfig.ToolIcons.Bevel,     Hotkey = UserConfig.ToolHotkeys.Bevel     },
	{ Name = "Dissolve",  Icon = UIConfig.ToolIcons.Dissolve,  Hotkey = UserConfig.ToolHotkeys.Dissolve  },
}

local acceptedTypes = {
	Transform = { Vertex = true, Edge = true, Face = true },
	Extrude   = { Face = true },
	Bevel     = { Edge = true, Vertex = true },
	Dissolve  = { Edge = true },
}

-- ─── Scene sync ───────────────────────────────────────────────────────────────

local function syncScene()
	if not Core.sourceMeshPart then return end
	Scene.RebuildProxies()
	Scene.ApplyGeometryMode(GeometryMode.Get())
end

-- ─── HUD ──────────────────────────────────────────────────────────────────────

local function refreshHud()
	UI.SetActiveToolState(activeToolState)
	if Core.sourceMeshPart then
		local status = "Edit"
			.. "\nVertices: " .. tostring(Core.GetVertexCount())
			.. "\nFaces: "    .. tostring(Core.GetFaceCount())
			.. "\nTool: "     .. (if activeToolState == SELECT_MODE then "Select" else activeToolState)
		UI.SetMainButtonText("Finalize")
		UI.SetStatus(status)
	else
		UI.SetMainButtonText("Edit")
		UI.SetStatus("Selection")
	end
end

-- ─── Operation lifecycle ──────────────────────────────────────────────────────

local function commitOperation()
	if activeToolState == SELECT_MODE then return end
	SelectionManager.UnfocusHandle()

	if activeToolState == "Dissolve" then
		if Dissolve.Execute() then
			syncScene()
		end
	end

	toolstates[activeToolState].Commit()
	History.Commit()

	HandleManager.StopListening()
	HandleManager.Clear()
	SelectionManager.Clear()
	activeToolState = SELECT_MODE
	UI.SetOperatorPanel(nil)
	if Core.sourceMeshPart then
		Scene.ApplyGeometryMode(GeometryMode.Get())
	end
	refreshHud()
end

local function cancelOperation()
	if activeToolState == SELECT_MODE then return end
	SelectionManager.UnfocusHandle()

	toolstates[activeToolState].Cancel()
	History.Cancel()

	HandleManager.StopListening()
	HandleManager.Clear()
	SelectionManager.Clear()
	activeToolState = SELECT_MODE
	UI.SetOperatorPanel(nil)
	if Core.sourceMeshPart then
		syncScene()
	end
	refreshHud()
end

-- ─── Toolstate activation ─────────────────────────────────────────────────────

local function activateToolState(name)
	if not Core.sourceMeshPart then return end
	if not toolstates[name] then return end
	if not SelectionManager.HasSelection() then return end

	local entry = SelectionManager.GetLast()
	if not entry then return end

	local pt = entry.proxyType
	if not acceptedTypes[name] or not acceptedTypes[name][pt] then return end

	if activeToolState ~= SELECT_MODE then
		cancelOperation()
		local freshProxy = Scene.FindProxy(entry.name)
		if not freshProxy then return end
		SelectionManager.Add(freshProxy)
		entry = SelectionManager.GetLast()
		if not entry then return end
	end

	activeToolState = name

	local proxy = entry.proxy or Scene.FindProxy(entry.name)
	if not proxy then
		activeToolState = SELECT_MODE
		return
	end

	local handle = HandleManager.Arm(proxy)
	if not handle then
		activeToolState = SELECT_MODE
		return
	end

	SelectionManager.FocusHandle(handle, commitOperation)
	History.StartRecording(name)
	toolstates[name].Activate(handle)
	HandleManager.BeginListening()
	UI.SetOperatorPanel(name)
	refreshHud()
end

-- ─── Geometry mode ────────────────────────────────────────────────────────────

local function setGeometryMode(mode)
	if GeometryMode.Get() == mode then return end
	GeometryMode.Set(mode)
	SelectionManager.Clear()
	HandleManager.Clear()
	if Core.sourceMeshPart then
		Scene.ApplyGeometryMode(mode)
	end
	UI.SetGeometryMode(mode)
	refreshHud()
end

-- ─── Handle movement — the core loop ─────────────────────────────────────────

local function onHandleChanged(handle)
	if not Core.sourceMeshPart or activeToolState == SELECT_MODE then return end
	local tool = toolstates[activeToolState]
	if tool.Apply(handle) then
		syncScene()
		refreshHud()
	end
end

-- ─── Session lifecycle ────────────────────────────────────────────────────────

local function beginSession()
	local sel = SelectionManager.GetStudioSelection()
	if #sel ~= 1 or not sel[1]:IsA("MeshPart") then
		UI.SetStatus("Select one MeshPart.")
		return
	end

	if not Core.Begin(sel[1]) then
		refreshHud()
		return
	end
	History.Begin()

	Scene.Begin()
	SelectionManager.Begin()
	HandleManager.Init(onHandleChanged)
	syncScene()
	refreshHud()
end

local function endSession()
	if activeToolState ~= SELECT_MODE then
		cancelOperation()
	end
	HandleManager.Clear()

	local meshPart = Core.sourceMeshPart
	Scene.ApplyFaceProxyColors()
	Scene.Destroy()
	Core.Finalize()
	Core.End()

	SelectionManager.End(meshPart)
	refreshHud()
end

-- ─── Plugin lifecycle ─────────────────────────────────────────────────────────

local function enable(_p, button)
	toolbarButton = button
	toolbarButton:SetActive(true)

	local historyBusy = false
	local function onHistoryChanged(isRedo)
		if historyBusy or not Core.sourceMeshPart then return end
		historyBusy = true
		History.Restore(isRedo)
		syncScene()
		refreshHud()
		task.defer(function()
			historyBusy = false
		end)
	end
	History.Listen(
		function() onHistoryChanged(false) end,
		function() onHistoryChanged(true)  end
	)

	UI.Start()
	UI.SetToolStates(toolStateItems, SELECT_MODE)
	UI.SetMainActionCallback(function()
		if Core.sourceMeshPart then
			endSession()
		else
			beginSession()
		end
	end)
	UI.SetToolStateCallback(activateToolState)
	UI.SetGeometryModeCallback(setGeometryMode)
	UI.SetOperatorCommitCallback(commitOperation)
	UI.SetOperatorCancelCallback(cancelOperation)
	UI.SetUploadActionCallback(function()
		UI.SetStatus("Upload unavailable\nuntil CreateAssetAsync() supports\nCreator Store plugins.")
	end)
	UI.SetVisible(true)

	Hotkeys.Start(function()
		return enabled
	end, activateToolState, setGeometryMode)
	refreshHud()
end

local function disable()
	if Core.sourceMeshPart then
		endSession()
	end

	History.Unlisten()
	Hotkeys.Destroy()
	HandleManager.Clear()
	UI.SetVisible(false)
	UI.Destroy()

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
