-- Editor/init.luau
-- Thin coordinator for the plugin.
-- Owns: tool state, plugin lifecycle, session management.
-- RMesh is the data brain — all mesh state lives there, not here.

local HUD              = require(script.Parent.HUD)
local RMesh            = require(script.Parent.RMesh)
local ProxyManager     = require(script.ProxyManager)
local HandleManager    = require(script.HandleManager)
local SelectionManager = require(script.Parent.SelectionManager)
local GeometryMode     = require(script.GeometryMode)
local History          = require(script.History)
local RibbonToolManager = require(script.RibbonToolManager)
local Selection        = require(script.Selection)
local Transform        = require(script.Parent.RMesh.Operators.Transform)
local Extrude          = require(script.Parent.RMesh.Operators.Extrude)
local Bevel            = require(script.Parent.RMesh.Operators.Bevel)
local Dissolve         = require(script.Parent.RMesh.Operators.Dissolve)

local Editor = {}

-- ─── State ────────────────────────────────────────────────────────────────────

local SELECT_MODE    = "Select"
local enabled        = false
local activeToolState = SELECT_MODE
local toolbarButton  = nil

local rmesh          = nil -- active RMesh instance, or nil when no session
local pm             = nil -- active ProxyManager instance, or nil when no session
local originalParent = nil -- meshPart's parent before session (restored on end)
local activeTool     = nil -- active operator instance, or nil when in SELECT_MODE

local selectedEntries        = {}
local selectionConn          = nil
local handleDeselectedCallback = nil

local toolstates = {
	Transform = Transform,
	Extrude   = Extrude,
	Bevel     = Bevel,
	Dissolve  = Dissolve,
}

local validRibbonTools = {
	Transform = { Enum.RibbonTool.Move, Enum.RibbonTool.Scale, Enum.RibbonTool.Rotate },
	Extrude   = { Enum.RibbonTool.Move },
	Bevel     = { Enum.RibbonTool.Move },
	Dissolve  = {},
}

-- Which element types each tool accepts.
local acceptedTypes = {
	Transform = { Vertex = true, Edge = true, Face = true },
	Extrude   = { Face = true },
	Bevel     = { Edge = true, Vertex = true },
	Dissolve  = { Edge = true },
}

-- ─── Selection helpers ────────────────────────────────────────────────────────

local function getProxyInfo(part)
	if not part:IsA("BasePart") then return nil end
	local id = part:GetAttribute("ElementId")
	if not id then return nil end
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
	if not pm then return end
	pm:rebuild()
	Selection.Refresh()
	pm:applyGeometryMode(GeometryMode.Get())
	if activeToolState ~= SELECT_MODE then
		pm:lockAll()
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

	if handleDeselectedCallback then
		for _, inst in ipairs(sel) do
			if inst:GetAttribute("IsToolHandle") then return end
		end
		local cb = handleDeselectedCallback
		handleDeselectedCallback = nil
		cb()
		return
	end

	if activeToolState ~= SELECT_MODE then return end

	selectedEntries = {}
	for _, inst in ipairs(sel) do
		if inst:GetAttribute("IsToolHandle") then continue end
		local info = getProxyInfo(inst)
		if info and info.type == GeometryMode.Get() then
			selectedEntries[#selectedEntries + 1] = info
		end
	end
end

-- ─── Operation lifecycle ──────────────────────────────────────────────────────

local function commitOperation()
	if activeToolState == SELECT_MODE then return end
	RibbonToolManager.Stop()
	Selection.Resume()
	unfocusHandle()

	if activeToolState == "Dissolve" then
		if activeTool:Execute(rmesh) then syncScene() end
	end

	activeTool:Commit()
	activeTool = nil
	History.Commit(rmesh)

	HandleManager.StopListening()
	HandleManager.Clear()
	selectedEntries = {}
	activeToolState = SELECT_MODE
	HUD.SetOperatorPanel(nil)
	if pm then pm:applyGeometryMode(GeometryMode.Get()) end
	HUD.SetActiveToolState(SELECT_MODE)
	HUD.SetTool("Select")
	if rmesh then HUD.SetCounts(rmesh:GetVertexCount(), rmesh:GetFaceCount()) end
end

local function cancelOperation()
	if activeToolState == SELECT_MODE then return end
	RibbonToolManager.Stop()
	Selection.Resume()
	unfocusHandle()

	activeTool:Cancel(rmesh)
	activeTool = nil
	History.Cancel()

	HandleManager.StopListening()
	HandleManager.Clear()
	selectedEntries = {}
	activeToolState = SELECT_MODE
	HUD.SetOperatorPanel(nil)
	if rmesh then syncScene() end
	HUD.SetActiveToolState(SELECT_MODE)
	HUD.SetTool("Select")
	if rmesh then HUD.SetCounts(rmesh:GetVertexCount(), rmesh:GetFaceCount()) end
end

-- ─── Tool activation ─────────────────────────────────────────────────────────

local function activateToolState(name)
	if not rmesh then return end
	if not toolstates[name] then return end
	if activeToolState ~= SELECT_MODE then return end
	if #selectedEntries == 0 then return end

	local lastEntry = selectedEntries[#selectedEntries]
	if not acceptedTypes[name] or not acceptedTypes[name][lastEntry.type] then return end

	activeToolState = name

	local proxy = lastEntry.part
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

	if pm then pm:lockAll() end
	Selection.Pause()
	RibbonToolManager.Begin(validRibbonTools[name] or {})
	focusHandle(handle, commitOperation)
	activeTool = toolstates[name].new()
	History.StartRecording(rmesh, name)
	activeTool:Activate(rmesh, handle, selectedEntries)
	HandleManager.BeginListening()
	HUD.SetOperatorPanel(name)
	HUD.SetActiveToolState(name)
	HUD.SetTool(name)
end

-- ─── Geometry mode ────────────────────────────────────────────────────────────

local function setGeometryMode(mode)
	if GeometryMode.Get() == mode then return end
	GeometryMode.Set(mode)
	selectedEntries = {}
	HandleManager.Clear()
	if pm then pm:applyGeometryMode(mode) end

	local validTools = {}
	for name, types in pairs(acceptedTypes) do
		validTools[name] = types[mode] == true
	end
	HUD.SetGeometryMode(mode, validTools)
end

-- ─── Handle movement — the core loop ─────────────────────────────────────────

local function onHandleChanged(handle)
	if not rmesh or activeToolState == SELECT_MODE or not activeTool then return end
	if activeTool:Apply(rmesh, handle) then
		syncScene()
		HUD.SetCounts(rmesh:GetVertexCount(), rmesh:GetFaceCount())
	end
end

-- ─── Session lifecycle ────────────────────────────────────────────────────────

local function beginSession()
	local sel = SelectionManager.Get()
	if #sel ~= 1 or not sel[1]:IsA("MeshPart") then
		HUD.SetNote("Select one MeshPart.")
		return
	end

	HUD.SetNote("")
	originalParent = sel[1].Parent
	sel[1].Parent = game:GetService("ServerStorage")

	rmesh = RMesh.new(sel[1])
	if not rmesh then
		sel[1].Parent = originalParent
		originalParent = nil
		return
	end

	pm = ProxyManager.new(rmesh)
	Selection.Start(rmesh, pm, GeometryMode.Get)
	History.Begin(rmesh)
	HandleManager.Begin()
	HandleManager.Init(onHandleChanged)
	selectionConn = SelectionManager.Changed:Connect(onSelectionChanged)
	selectedEntries = {}
	syncScene()

	HUD.SetMode("Edit")
	HUD.SetMainButtonText("Finalize")
	HUD.SetCounts(rmesh:GetVertexCount(), rmesh:GetFaceCount())
	HUD.SetTool("Select")
	HUD.SetActiveToolState(SELECT_MODE)
end

local function endSession()
	if activeToolState ~= SELECT_MODE then cancelOperation() end
	HandleManager.Destroy()

	if selectionConn then
		selectionConn:Disconnect()
		selectionConn = nil
	end
	selectedEntries = {}

	Selection.Stop()
	local meshPart = rmesh.meshPart
	pm:applyFaceProxyColors()
	pm:destroy()
	pm = nil
	rmesh:Finalize()
	rmesh = nil

	meshPart.Parent = originalParent
	originalParent = nil

	SelectionManager.Set({ meshPart })
	HUD.SetMode("Selection")
	HUD.SetMainButtonText("Edit")
	HUD.SetCounts(nil, nil)
	HUD.SetTool(nil)
	HUD.SetActiveToolState(SELECT_MODE)
end

-- ─── Plugin lifecycle ─────────────────────────────────────────────────────────

local function enable(_p, button)
	toolbarButton = button
	toolbarButton:SetActive(true)

	local historyBusy = false
	local function onHistoryChanged(isRedo)
		if historyBusy or not rmesh then return end
		historyBusy = true
		History.Restore(rmesh, isRedo)
		syncScene()
		HUD.SetCounts(rmesh:GetVertexCount(), rmesh:GetFaceCount())
		task.defer(function() historyBusy = false end)
	end
	History.Listen(function()
		onHistoryChanged(false)
	end, function()
		onHistoryChanged(true)
	end)

	HUD.SetVisible(true)
	HUD.SetMode("Selection")
	HUD.SetMainButtonText("Edit")
end

local function disable()
	if rmesh then endSession() end
	History.Unlisten()
	HandleManager.Destroy()
	HUD.SetVisible(false)
	if toolbarButton then
		toolbarButton:SetActive(false)
		toolbarButton = nil
	end
end

-- ─── Wire HUD signals (once, at module load) ──────────────────────────────────

HUD.SetToolStates({ "Transform", "Extrude", "Bevel", "Dissolve" }, SELECT_MODE)
HUD.MainActivated:Connect(function()
	if rmesh then endSession() else beginSession() end
end)
HUD.ToolActivated:Connect(activateToolState)
HUD.GeometryModeActivated:Connect(setGeometryMode)
HUD.CommitActivated:Connect(commitOperation)
HUD.CancelActivated:Connect(cancelOperation)
HUD.DissolveVertsToggled:Connect(function(isEnabled)
	if activeTool and activeTool.SetDissolveVerts then
		activeTool:SetDissolveVerts(isEnabled)
	end
end)

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
