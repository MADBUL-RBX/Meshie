-- Editor/init.luau
-- Pure state machine. No UI knowledge.
-- Fires signals; controller wires them to HUD.

local RMesh             = require(script.Parent.RMesh)
local ProxyManager      = require(script.ProxyManager)
local HandleManager     = require(script.HandleManager)
local SelectionManager  = require(script.Parent.SelectionManager)
local GeometryMode      = require(script.GeometryMode)
local History           = require(script.History)
local RibbonToolManager = require(script.RibbonToolManager)
local Selection         = require(script.Selection)
local Transform         = require(script.Parent.RMesh.Operators.Transform)
local Extrude           = require(script.Parent.RMesh.Operators.Extrude)
local Bevel             = require(script.Parent.RMesh.Operators.Bevel)
local Dissolve          = require(script.Parent.RMesh.Operators.Dissolve)

local Editor = {}

-- ─── Signals ──────────────────────────────────────────────────────────────────

local function Signal()
	local cbs = {}
	return {
		Connect = function(_, cb) cbs[#cbs + 1] = cb end,
		Fire    = function(_, ...) for _, cb in ipairs(cbs) do cb(...) end end,
	}
end

Editor.SessionStarted   = Signal() -- fires(vertexCount, faceCount)
Editor.SessionEnded     = Signal()
Editor.OperationStarted = Signal() -- fires(toolName)
Editor.OperationEnded   = Signal() -- fires(vertexCount, faceCount)
Editor.CountsChanged    = Signal() -- fires(vertexCount, faceCount)
Editor.GeometryModeSet  = Signal() -- fires(mode, validTools)

-- ─── State ────────────────────────────────────────────────────────────────────

local SELECT_MODE     = "Select"
local activeToolState = SELECT_MODE
local historyBusy     = false

local rmesh          = nil
local pm             = nil
local originalParent = nil
local activeTool     = nil

local selectedEntries          = {}
local selectionConn            = nil
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
	if pm then pm:applyGeometryMode(GeometryMode.Get()) end

	local v = rmesh and rmesh:GetVertexCount() or 0
	local f = rmesh and rmesh:GetFaceCount() or 0
	Editor.OperationEnded:Fire(v, f)
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
	if rmesh then syncScene() end

	local v = rmesh and rmesh:GetVertexCount() or 0
	local f = rmesh and rmesh:GetFaceCount() or 0
	Editor.OperationEnded:Fire(v, f)
end

-- ─── Tool activation ─────────────────────────────────────────────────────────

local function activateTool(name)
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
	Editor.OperationStarted:Fire(name)
end

-- ─── Handle movement ─────────────────────────────────────────────────────────

local function onHandleChanged(handle)
	if not rmesh or activeToolState == SELECT_MODE or not activeTool then return end
	if activeTool:Apply(rmesh, handle) then
		syncScene()
		Editor.CountsChanged:Fire(rmesh:GetVertexCount(), rmesh:GetFaceCount())
	end
end

-- ─── Session lifecycle ────────────────────────────────────────────────────────

local function beginSession()
	local sel = SelectionManager.Get()
	if #sel ~= 1 or not sel[1]:IsA("MeshPart") then
		return false
	end

	originalParent = sel[1].Parent
	sel[1].Parent = game:GetService("ServerStorage")

	rmesh = RMesh.new(sel[1])
	if not rmesh then
		sel[1].Parent = originalParent
		originalParent = nil
		return false
	end

	pm = ProxyManager.new(rmesh)
	Selection.Start(rmesh, pm, GeometryMode.Get)
	History.Begin(rmesh)
	HandleManager.Begin()
	HandleManager.Init(onHandleChanged)
	selectionConn = SelectionManager.Changed:Connect(onSelectionChanged)
	selectedEntries = {}
	syncScene()

	Editor.SessionStarted:Fire(rmesh:GetVertexCount(), rmesh:GetFaceCount())
	return true
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
	Editor.SessionEnded:Fire()
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function Editor.BeginSession()
	return beginSession()
end

function Editor.EndSession()
	endSession()
end

function Editor.ActivateTool(name)
	activateTool(name)
end

function Editor.CommitOperation()
	commitOperation()
end

function Editor.CancelOperation()
	cancelOperation()
end

function Editor.IsSessionActive()
	return rmesh ~= nil
end

function Editor.SetGeometryMode(mode)
	if GeometryMode.Get() == mode then return end
	GeometryMode.Set(mode)
	selectedEntries = {}
	HandleManager.Clear()
	if pm then pm:applyGeometryMode(mode) end
	local validTools = {}
	for name, types in pairs(acceptedTypes) do
		validTools[name] = types[mode] == true
	end
	Editor.GeometryModeSet:Fire(mode, validTools)
end

function Editor.GetValidToolsForMode(mode)
	local valid = {}
	for name, types in pairs(acceptedTypes) do
		valid[name] = types[mode] == true
	end
	return valid
end

function Editor.SetDissolveVerts(isEnabled)
	if activeTool and activeTool.SetDissolveVerts then
		activeTool:SetDissolveVerts(isEnabled)
	end
end

function Editor.StartListening()
	local function onHistory(isRedo)
		if historyBusy or not rmesh then return end
		historyBusy = true
		History.Restore(rmesh, isRedo)
		syncScene()
		Editor.CountsChanged:Fire(rmesh:GetVertexCount(), rmesh:GetFaceCount())
		task.defer(function() historyBusy = false end)
	end
	History.Listen(function() onHistory(false) end, function() onHistory(true) end)
end

function Editor.StopListening()
	History.Unlisten()
	HandleManager.Destroy()
end

return Editor
