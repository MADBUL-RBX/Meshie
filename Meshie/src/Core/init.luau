-- Core/init.luau
-- THE application. Owns toolbar, input, display, session, and tool coordination.
-- Plugin script is a thin bootstrap that calls Init/Enable/Disable/Shutdown.

local UserInputService = game:GetService("UserInputService")

-- Subsystems
local HUD               = require(script.HUD)
local UIConfig          = require(script.UIConfig)
local Hotkeys           = require(script.Hotkeys)
local ProxyManager      = require(script.ProxyManager)
local HandleManager     = require(script.HandleManager)
local GeometryMode      = require(script.GeometryMode)
local History           = require(script.History)
local RibbonToolManager = require(script.RibbonToolManager)
local Selection         = require(script.Selection)

-- External
local RMesh            = require(script.Parent.RMesh)
local SelectionManager = require(script.Parent.SelectionManager)
local Transform        = require(script.Parent.RMesh.Operators.Transform)
local Extrude          = require(script.Parent.RMesh.Operators.Extrude)
local Bevel            = require(script.Parent.RMesh.Operators.Bevel)
local Dissolve         = require(script.Parent.RMesh.Operators.Dissolve)
local Inset            = require(script.Parent.RMesh.Operators.Inset)

local Core = {}

-- ─── State ───────────────────────────────────────────────────────────────────

local SELECT_MODE = "Select"

local enabled           = false
local activeToolState   = SELECT_MODE
local historyBusy       = false
local dissolveVertsEnabled = false

local rmesh          = nil
local pm             = nil
local originalParent = nil
local activeTool     = nil
local sessionFolder  = nil

local selectedEntries          = {}
local selectionConn            = nil
local handleDeselectedCallback = nil

local toggleButton = nil
local geoButtons   = {}
local uisConn      = nil
local UI            = nil -- set by Enable, nilled by Disable

local toolstates = {
	Transform = Transform,
	Extrude   = Extrude,
	Bevel     = Bevel,
	Dissolve  = Dissolve,
	Inset     = Inset,
}

local validRibbonTools = {
	Transform = { Enum.RibbonTool.Move, Enum.RibbonTool.Scale, Enum.RibbonTool.Rotate },
	Extrude   = { Enum.RibbonTool.Move },
	Bevel     = { Enum.RibbonTool.Move },
	Dissolve  = {},
	Inset     = { Enum.RibbonTool.Scale },
}

local acceptedTypes = {
	Transform = { Vertex = true, Edge = true, Face = true },
	Extrude   = { Face = true },
	Bevel     = { Edge = true, Vertex = true },
	Dissolve  = { Edge = true },
	Inset     = { Face = true },
}

-- ─── Display helpers ─────────────────────────────────────────────────────────

local function setToolButtonActive(entry, isActive)
	entry.Button:SetAttribute("IsActive", isActive)
	if isActive then
		entry.Button.BackgroundColor3 = UIConfig.ButtonActiveColor
		if entry.Label then entry.Label.TextColor3 = UIConfig.ButtonActiveTextColor end
		if entry.Icon then
			if entry.Icon:IsA("ImageLabel") then
				entry.Icon.ImageColor3 = UIConfig.ButtonActiveTextColor
			elseif entry.Icon:IsA("TextLabel") then
				entry.Icon.TextColor3 = UIConfig.ButtonActiveTextColor
			end
		end
	else
		entry.Button.BackgroundColor3 = UIConfig.ButtonColor
		if entry.Label then entry.Label.TextColor3 = UIConfig.SubTextColor end
		if entry.Icon then
			if entry.Icon:IsA("ImageLabel") then
				entry.Icon.ImageColor3 = UIConfig.TextColor
			elseif entry.Icon:IsA("TextLabel") then
				entry.Icon.TextColor3 = UIConfig.TextColor
			end
		end
	end
end

local function showOperatorPanel(name)
	if not UI then return end
	if name ~= "Dissolve" then
		dissolveVertsEnabled = false
		local d = UI.operatorPanels.Dissolve.dissolveVertsButton
		d.Text             = "Dissolve Vertices: Off"
		d.BackgroundColor3 = UIConfig.ButtonColor
		d.TextColor3       = UIConfig.TextColor
		d:SetAttribute("IsActive", false)
	end
	for n, op in pairs(UI.operatorPanels) do
		op.panel.Visible = n == name
	end
end

local function updateGeoVisuals(mode)
	if not UI then return end
	for name, btn in pairs(UI.geometryButtons) do
		local isActive = name == mode
		btn:SetAttribute("IsActive", isActive)
		btn.BackgroundColor3 = isActive and UIConfig.ButtonActiveColor or UIConfig.ButtonColor
		btn.TextColor3       = isActive and UIConfig.ButtonActiveTextColor or UIConfig.TextColor
	end
	for name, btn in pairs(geoButtons) do
		btn:SetActive(name == mode)
	end
	for name, entry in pairs(UI.toolButtons) do
		local types = acceptedTypes[name]
		local isValid = types and types[mode] == true
		entry.Button.AutoButtonColor = isValid
		entry.Button.Active          = isValid
		entry.Button.BackgroundTransparency = isValid and 0 or 0.6
		if entry.Label then entry.Label.TextTransparency = isValid and 0 or 0.6 end
	end
end

-- ─── Selection helpers ───────────────────────────────────────────────────────

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

-- ─── Scene sync ──────────────────────────────────────────────────────────────

local function syncScene()
	if not pm then return end
	pm:rebuild()
	Selection.Refresh()
	pm:applyGeometryMode(GeometryMode.Get())
	if activeToolState ~= SELECT_MODE then
		pm:lockAll()
	end
end

-- ─── Handle focus ────────────────────────────────────────────────────────────

local function focusHandle(handle, onDeselected)
	SelectionManager.Set({ handle })
	task.defer(function()
		handleDeselectedCallback = onDeselected
	end)
end

local function unfocusHandle()
	handleDeselectedCallback = nil
end

-- ─── Selection listener ──────────────────────────────────────────────────────

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

-- ─── Operation lifecycle ─────────────────────────────────────────────────────

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

	if UI then
		local v = rmesh and rmesh:GetVertexCount() or 0
		local f = rmesh and rmesh:GetFaceCount() or 0
		UI.toolLabel.Text     = "Tool: Select"
		UI.verticesLabel.Text = "Vertices: " .. v
		UI.facesLabel.Text    = "Faces: " .. f
		showOperatorPanel(nil)
		for _, entry in pairs(UI.toolButtons) do
			setToolButtonActive(entry, false)
		end
	end
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

	if UI then
		local v = rmesh and rmesh:GetVertexCount() or 0
		local f = rmesh and rmesh:GetFaceCount() or 0
		UI.toolLabel.Text     = "Tool: Select"
		UI.verticesLabel.Text = "Vertices: " .. v
		UI.facesLabel.Text    = "Faces: " .. f
		showOperatorPanel(nil)
		for _, entry in pairs(UI.toolButtons) do
			setToolButtonActive(entry, false)
		end
	end
end

-- ─── Tool activation ─────────────────────────────────────────────────────────

local function activateTool(name)
	if not rmesh then return end
	if not toolstates[name] then return end
	if activeToolState ~= SELECT_MODE then
		-- Preserve selection across commit for tool chaining.
		-- Operators may update the handle's ElementId (e.g. Inset → capFace),
		-- so read the current id from the handle before it gets destroyed.
		local handle = HandleManager.GetHandle()
		local chainType = handle and handle:GetAttribute("ElementType")
		local chainId   = handle and handle:GetAttribute("ElementId")
		commitOperation()
		if chainType and chainId then
			local proxy = pm and pm:findProxy(chainType, chainId)
			if proxy then
				selectedEntries = {{ type = chainType, id = chainId, part = proxy }}
			end
		end
	end
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

	if UI then
		UI.toolLabel.Text = "Tool: " .. name
		showOperatorPanel(name)
		for n, entry in pairs(UI.toolButtons) do
			setToolButtonActive(entry, n == name)
		end
	end
end

-- ─── Handle movement ─────────────────────────────────────────────────────────

local function onHandleChanged(handle)
	if not rmesh or activeToolState == SELECT_MODE or not activeTool then return end
	if activeTool:Apply(rmesh, handle) then
		syncScene()
		if UI then
			UI.verticesLabel.Text = "Vertices: " .. rmesh:GetVertexCount()
			UI.facesLabel.Text    = "Faces: " .. rmesh:GetFaceCount()
		end
	end
end

-- ─── Geometry mode ───────────────────────────────────────────────────────────

local function setGeometryMode(mode)
	if GeometryMode.Get() == mode then return end
	GeometryMode.Set(mode)
	selectedEntries = {}
	HandleManager.Clear()
	if pm then pm:applyGeometryMode(mode) end
	updateGeoVisuals(mode)
end

-- ─── Session lifecycle ───────────────────────────────────────────────────────

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

	sessionFolder              = Instance.new("Folder")
	sessionFolder.Name         = "Meshie"
	sessionFolder.Archivable   = false
	sessionFolder.Parent       = workspace

	pm = ProxyManager.new(rmesh, sessionFolder)
	Selection.Start(rmesh, pm, GeometryMode.Get, sessionFolder)
	History.Begin(rmesh)
	HandleManager.Begin(sessionFolder)
	HandleManager.Init(onHandleChanged)
	selectionConn = SelectionManager.Changed:Connect(onSelectionChanged)
	selectedEntries = {}
	syncScene()

	if UI then
		local v = rmesh:GetVertexCount()
		local f = rmesh:GetFaceCount()
		UI.modeLabel.Text     = "Edit"
		UI.mainButton.Text    = "Finalize"
		UI.verticesLabel.Text = "Vertices: " .. v
		UI.facesLabel.Text    = "Faces: " .. f
		UI.toolLabel.Text     = "Tool: Select"
		UI.noteLabel.Text     = ""
		showOperatorPanel(nil)
		for _, entry in pairs(UI.toolButtons) do
			setToolButtonActive(entry, false)
		end
	end
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

	if sessionFolder then
		sessionFolder:Destroy()
		sessionFolder = nil
	end

	meshPart.Parent = originalParent
	originalParent = nil
	SelectionManager.Set({ meshPart })

	if UI then
		UI.modeLabel.Text     = "Select a MeshPart"
		UI.mainButton.Text    = "Edit"
		UI.verticesLabel.Text = ""
		UI.facesLabel.Text    = ""
		UI.toolLabel.Text     = ""
		UI.noteLabel.Text     = ""
		showOperatorPanel(nil)
		for _, entry in pairs(UI.toolButtons) do
			setToolButtonActive(entry, false)
		end
	end
end

-- ─── Wire UI buttons (called in Enable) ─────────────────────────────────────

local function wireUI()
	UI.mainButton.Activated:Connect(function()
		if rmesh then
			endSession()
		elseif not beginSession() then
			UI.noteLabel.Text = "Select one MeshPart."
		end
	end)

	UI.uploadButton.Activated:Connect(function() end)

	for modeName, btn in pairs(UI.geometryButtons) do
		btn.Activated:Connect(function() setGeometryMode(modeName) end)
	end

	for _, op in pairs(UI.operatorPanels) do
		op.commitButton.Activated:Connect(function() commitOperation() end)
		op.cancelButton.Activated:Connect(function() cancelOperation() end)
	end

	for name, entry in pairs(UI.toolButtons) do
		entry.Button.Activated:Connect(function() activateTool(name) end)
	end

	UI.operatorPanels.Dissolve.dissolveVertsButton.Activated:Connect(function()
		dissolveVertsEnabled = not dissolveVertsEnabled
		local btn = UI.operatorPanels.Dissolve.dissolveVertsButton
		btn.Text             = dissolveVertsEnabled and "Dissolve Vertices: On" or "Dissolve Vertices: Off"
		btn.BackgroundColor3 = dissolveVertsEnabled and UIConfig.ButtonActiveColor or UIConfig.ButtonColor
		btn.TextColor3       = dissolveVertsEnabled and UIConfig.ButtonActiveTextColor or UIConfig.TextColor
		btn:SetAttribute("IsActive", dissolveVertsEnabled)
		if activeTool and activeTool.SetDissolveVerts then
			activeTool:SetDissolveVerts(dissolveVertsEnabled)
		end
	end)

	uisConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if UserInputService:GetFocusedTextBox() then return end
		local key = input.KeyCode
		if key == Hotkeys.GetKeyCode("Cancel") then
			cancelOperation()
			return
		end
		for name in pairs(UI.toolButtons) do
			if key == Hotkeys.GetKeyCode(name) then
				activateTool(name)
				return
			end
		end
		for _, mode in ipairs({ "Vertex", "Edge", "Face" }) do
			if key == Hotkeys.GetKeyCode(mode) then
				setGeometryMode(mode)
				return
			end
		end
	end)
end

-- ─── Public API (for plugin script) ──────────────────────────────────────────

function Core.Init(p)
	RibbonToolManager.Init(p)
	Selection.Init(p)

	local toolbar = p:CreateToolbar("Meshie")
	toggleButton = toolbar:CreateButton("Meshie", "Toggle Meshie editor", "")

	local vBtn = toolbar:CreateButton("Vertex", "Vertex mode", "")
	local eBtn = toolbar:CreateButton("Edge",   "Edge mode",   "")
	local fBtn = toolbar:CreateButton("Face",   "Face mode",   "")
	geoButtons = { Vertex = vBtn, Edge = eBtn, Face = fBtn }

	toggleButton.Click:Connect(function()
		if enabled then Core.Disable() else Core.Enable() end
	end)

	for mode, btn in pairs(geoButtons) do
		btn.Click:Connect(function()
			if not enabled then return end
			setGeometryMode(mode)
		end)
	end
end

function Core.Enable()
	enabled = true
	toggleButton:SetActive(true)

	UI = HUD.Create()
	wireUI()

	local function onHistory(isRedo)
		if historyBusy or not rmesh then return end
		historyBusy = true
		History.Restore(rmesh, isRedo)
		syncScene()
		UI.verticesLabel.Text = "Vertices: " .. rmesh:GetVertexCount()
		UI.facesLabel.Text    = "Faces: " .. rmesh:GetFaceCount()
		task.defer(function() historyBusy = false end)
	end
	History.Listen(function() onHistory(false) end, function() onHistory(true) end)

	UI.modeLabel.Text  = "Select a MeshPart"
	UI.mainButton.Text = "Edit"
	UI.verticesLabel.Text = ""
	UI.facesLabel.Text    = ""
	UI.toolLabel.Text     = ""
	UI.noteLabel.Text     = ""
	showOperatorPanel(nil)
	setGeometryMode("Vertex")
	updateGeoVisuals(GeometryMode.Get())
end

function Core.Disable()
	if rmesh then endSession() end
	History.Unlisten()
	HandleManager.Destroy()

	if uisConn then
		uisConn:Disconnect()
		uisConn = nil
	end

	HUD.Destroy()
	UI = nil

	toggleButton:SetActive(false)
	for _, btn in pairs(geoButtons) do btn:SetActive(false) end
	enabled = false
end

function Core.Shutdown()
	if enabled then Core.Disable() end
end

return Core
