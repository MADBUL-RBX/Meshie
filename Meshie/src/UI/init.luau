local CoreGui = game:GetService("CoreGui")

local UIConfig = require(script.UIConfig)
local Factory  = require(script.Factory)

local Hud = {}

local gui                 = nil
local infoPanel           = nil
local uploadPanel         = nil
local topPanel            = nil
local settingsTogglePanel = nil
local settingsPanel       = nil
local toolRail            = nil
local operatorPanel       = nil  -- generic operator panel, rebuilt per toolstate
local geometryPanel       = nil  -- vertex/edge/face mode buttons

local geometryButtons     = {}   -- keyed by mode name

local mainButton           = nil
local uploadButton         = nil
local settingsButton       = nil

local titleLabel    = nil
local modeLabel     = nil
local verticesLabel = nil
local facesLabel    = nil
local toolLabel     = nil
local noteLabel     = nil

local toolButtons = {}

local onMainAction           = nil
local onToolState            = nil
local onUploadAction         = nil
local onOperatorCommit       = nil
local onOperatorCancel       = nil
local onGeometryMode         = nil

-- Per-toolstate operator panel callbacks
local onDissolveVertsToggle = nil

local dissolveVertsEnabled = false

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

local function setToggleButtonActive(button, isActive, activeText, inactiveText)
	if not button then return end
	button:SetAttribute("IsActive", isActive)
	button.Text = isActive and activeText or inactiveText
	if isActive then
		button.BackgroundColor3 = UIConfig.ButtonActiveColor
		button.TextColor3       = UIConfig.ButtonActiveTextColor
	else
		button.BackgroundColor3 = UIConfig.ButtonColor
		button.TextColor3       = UIConfig.TextColor
	end
end

local function clearToolButtons()
	for _, entry in pairs(toolButtons) do entry.Button:Destroy() end
	toolButtons = {}
end

local function toggleSettingsPanel()
	if settingsPanel then settingsPanel.Visible = not settingsPanel.Visible end
end

local function destroyOperatorPanel()
	if operatorPanel then
		operatorPanel:Destroy()
		operatorPanel = nil
	end
	onDissolveVertsToggle = nil
	dissolveVertsEnabled  = false
end

local function makeOperatorPanelBase(title)
	destroyOperatorPanel()
	operatorPanel = Factory.MakePanel("OperatorPanel",
		UDim2.new(0, UIConfig.InfoPanelWidth, 0, 0),
		Vector2.new(0, 0),
		UDim2.new(0, UIConfig.Margin, 0, UIConfig.Margin + UIConfig.InfoPanelHeight / 2 + 10),
		gui)
	operatorPanel.AutomaticSize = Enum.AutomaticSize.Y

	Factory.MakeLabel("OperatorTitle", title,
		UDim2.new(1, -UIConfig.Padding * 2, 0, 16),
		UDim2.new(0, UIConfig.Padding, 0, 10),
		operatorPanel, UIConfig.TextColor, UIConfig.TextSizeBody, Enum.TextXAlignment.Left)

	return operatorPanel
end

local function addCommitCancelButtons(panel, yOffset)
	local commitButton = Factory.MakeButton("OperatorCommit", "Commit",
		UDim2.new(0.5, -UIConfig.Padding - 2, 0, 26),
		UDim2.new(0, UIConfig.Padding, 0, yOffset),
		panel)
	commitButton.Activated:Connect(function()
		if onOperatorCommit then onOperatorCommit() end
	end)

	local cancelButton = Factory.MakeButton("OperatorCancel", "Cancel",
		UDim2.new(0.5, -UIConfig.Padding - 2, 0, 26),
		UDim2.new(0.5, 2, 0, yOffset),
		panel)
	cancelButton.Activated:Connect(function()
		if onOperatorCancel then onOperatorCancel() end
	end)
end

function Hud.Start()
	local existing = CoreGui:FindFirstChild("MeshPartEditHud")
	if existing then existing:Destroy() end

	gui = Instance.new("ScreenGui")
	gui.Name            = "MeshPartEditHud"
	gui.ResetOnSpawn    = false
	gui.IgnoreGuiInset  = true
	gui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
	gui.Enabled         = false
	gui.Parent          = CoreGui

	infoPanel = Factory.MakePanel(
		"InfoPanel",
		UDim2.new(0, UIConfig.InfoPanelWidth, 0, UIConfig.InfoPanelHeight),
		Vector2.new(0, 0.5),
		UDim2.new(0, UIConfig.Margin, 0.5, 0),
		gui
	)

	titleLabel = Factory.MakeLabel("TitleLabel", "MeshPartEdit",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 18),
		UDim2.new(0, UIConfig.Padding, 0, 10),
		infoPanel, UIConfig.TextColor, UIConfig.TextSizeTitle, Enum.TextXAlignment.Left)

	Factory.MakeDivider("TopDivider",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 1),
		UDim2.new(0, UIConfig.Padding, 0, 36), infoPanel)

	modeLabel = Factory.MakeLabel("ModeLabel", "Selection",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 16),
		UDim2.new(0, UIConfig.Padding, 0, 46),
		infoPanel, UIConfig.TextColor, UIConfig.TextSizeBody, Enum.TextXAlignment.Left)

	verticesLabel = Factory.MakeLabel("VerticesLabel", "",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 14),
		UDim2.new(0, UIConfig.Padding, 0, 72),
		infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall, Enum.TextXAlignment.Left)

	facesLabel = Factory.MakeLabel("FacesLabel", "",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 14),
		UDim2.new(0, UIConfig.Padding, 0, 90),
		infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall, Enum.TextXAlignment.Left)

	toolLabel = Factory.MakeLabel("ToolLabel", "Select",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 108),
		UDim2.new(0, UIConfig.Padding, 0, 108),
		infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall, Enum.TextXAlignment.Left)

	Factory.MakeDivider("MiddleDivider",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 1),
		UDim2.new(0, UIConfig.Padding, 0, 132), infoPanel)

	noteLabel = Factory.MakeLabel("NoteLabel", "",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 38),
		UDim2.new(0, UIConfig.Padding, 0, 142),
		infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall,
		Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)

	mainButton = Factory.MakeButton("MainButton", "Edit",
		UDim2.new(1, -UIConfig.Padding * 2, 0, UIConfig.MainButtonHeight),
		UDim2.new(0, UIConfig.Padding, 1, -(UIConfig.Padding + UIConfig.MainButtonHeight)),
		infoPanel)
	mainButton.Activated:Connect(function()
		if onMainAction then onMainAction() end
	end)

	-- ─── Upload panel ─────────────────────────────────────────────────────────
	uploadPanel = Factory.MakePanel("UploadPanel",
		UDim2.new(0, UIConfig.UploadPanelWidth, 0, UIConfig.UploadPanelHeight),
		Vector2.new(0, 1),
		UDim2.new(0, UIConfig.Margin, 1, -UIConfig.Margin),
		gui)

	uploadButton = Factory.MakeButton("UploadButton", "Upload",
		UDim2.new(1, -UIConfig.Padding * 2, 0, UIConfig.UploadButtonHeight),
		UDim2.new(0, UIConfig.Padding, 0, UIConfig.Padding),
		uploadPanel)
	uploadButton.Activated:Connect(function()
		if onUploadAction then onUploadAction() end
	end)

	Factory.MakeLabel("UploadInfoLabel", "Non-operational until CreateAssetAsync() support is added.",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 30),
		UDim2.new(0, UIConfig.Padding, 0, UIConfig.Padding + UIConfig.UploadButtonHeight + 8),
		uploadPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall,
		Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)

	-- ─── Top panel ────────────────────────────────────────────────────────────
	topPanel = Factory.MakePanel("TopPanel",
		UDim2.new(0, UIConfig.FaceModePanelWidth, 0, 58),
		Vector2.new(0.5, 0),
		UDim2.new(0.5, 0, 0, UIConfig.Margin),
		gui)

	Factory.MakeLabel("TopPanelLabel", "View",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 12),
		UDim2.new(0, UIConfig.Padding, 0, 8),
		topPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall, Enum.TextXAlignment.Left)

	-- ─── Geometry mode panel ──────────────────────────────────────────────────
	geometryPanel = Factory.MakePanel("GeometryPanel",
		UDim2.new(0, UIConfig.FaceModePanelWidth, 0, 58),
		Vector2.new(0.5, 0),
		UDim2.new(0.5, 0, 0, UIConfig.Margin + 68),
		gui)

	Factory.MakeLabel("GeometryModeLabel", "Mode",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 12),
		UDim2.new(0, UIConfig.Padding, 0, 8),
		geometryPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall, Enum.TextXAlignment.Left)

	local modeNames = { "Vertex", "Edge", "Face" }
	local modeHotkeyLabel = { Vertex = "[", Edge = "]", Face = "\\" }
	local btnWidth  = (UIConfig.FaceModePanelWidth - UIConfig.Padding * 2 - 4) / 3
	geometryButtons = {}

	for i, modeName in ipairs(modeNames) do
		local xOff = UIConfig.Padding + (i - 1) * (btnWidth + 2)
		local btn = Factory.MakeButton("GeoMode" .. modeName, modeName,
			UDim2.new(0, btnWidth, 0, 26),
			UDim2.new(0, xOff, 0, 24),
			geometryPanel)
		btn.Activated:Connect(function()
			if onGeometryMode then onGeometryMode(modeName) end
		end)
		Factory.Create("TextLabel", {
			Name = "HotkeyLabel",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -3),
			Size = UDim2.new(0, 16, 0, 12),
			BackgroundTransparency = 1,
			Text = modeHotkeyLabel[modeName] or "",
			TextColor3 = UIConfig.SubTextColor,
			Font = UIConfig.Font,
			TextSize = UIConfig.TextSizeSmall,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Parent = btn,
		})
		geometryButtons[modeName] = btn
	end

	Hud.SetGeometryMode("Vertex")

	-- ─── Settings ─────────────────────────────────────────────────────────────
	settingsTogglePanel = Factory.MakePanel("SettingsTogglePanel",
		UDim2.new(0, UIConfig.SettingsToggleWidth, 0, UIConfig.SettingsToggleHeight),
		Vector2.new(1, 1),
		UDim2.new(1, -UIConfig.Margin, 1, -UIConfig.Margin),
		gui)

	settingsButton = Factory.MakeButton("SettingsButton", "Settings",
		UDim2.new(1, -UIConfig.Padding * 2, 0, UIConfig.SettingsButtonHeight),
		UDim2.new(0, UIConfig.Padding, 0, UIConfig.Padding),
		settingsTogglePanel)
	settingsButton.Activated:Connect(toggleSettingsPanel)

	settingsPanel = Factory.MakePanel("SettingsPanel",
		UDim2.new(0, UIConfig.SettingsPanelWidth, 0, UIConfig.SettingsPanelHeight),
		Vector2.new(1, 1),
		UDim2.new(1, -UIConfig.Margin, 1, -(UIConfig.Margin + UIConfig.SettingsToggleHeight + 10)),
		gui)
	settingsPanel.Visible = false

	Factory.MakeLabel("SettingsTitle", "User Settings",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 18),
		UDim2.new(0, UIConfig.Padding, 0, 10),
		settingsPanel, UIConfig.TextColor, UIConfig.TextSizeTitle, Enum.TextXAlignment.Left)

	Factory.MakeDivider("SettingsDivider",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 1),
		UDim2.new(0, UIConfig.Padding, 0, 36), settingsPanel)

	Factory.MakeLabel("SettingsPlaceholder", "Hotkeys and user preferences will live here later.",
		UDim2.new(1, -UIConfig.Padding * 2, 0, 50),
		UDim2.new(0, UIConfig.Padding, 0, 48),
		settingsPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall,
		Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)

	-- ─── Tool rail ────────────────────────────────────────────────────────────
	toolRail = Factory.MakePanel("ToolRail",
		UDim2.new(0, UIConfig.ToolRailWidth, 0, 0),
		Vector2.new(1, 0.5),
		UDim2.new(1, -UIConfig.Margin, 0.5, 0),
		gui)

	Factory.Create("UIPadding", {
		PaddingTop    = UDim.new(0, UIConfig.Padding),
		PaddingBottom = UDim.new(0, UIConfig.Padding),
		PaddingLeft   = UDim.new(0, UIConfig.Padding - 2),
		PaddingRight  = UDim.new(0, UIConfig.Padding - 2),
		Parent        = toolRail,
	})

	Factory.Create("UIListLayout", {
		FillDirection       = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment   = Enum.VerticalAlignment.Top,
		Padding             = UDim.new(0, UIConfig.Spacing),
		Parent              = toolRail,
	})
	toolRail.AutomaticSize = Enum.AutomaticSize.Y
end

-- ─── Operator Panel ───────────────────────────────────────────────────────────

function Hud.SetOperatorPanel(toolstateName)
	destroyOperatorPanel()
	if not toolstateName then return end

	if toolstateName == "Transform" then
		local panel = makeOperatorPanelBase("Transform")
		addCommitCancelButtons(panel, 34)

	elseif toolstateName == "Bevel" then
		local panel = makeOperatorPanelBase("Bevel")
		Factory.MakeLabel("BevelNote", "Move handle to adjust depth.",
			UDim2.new(1, -UIConfig.Padding * 2, 0, 28),
			UDim2.new(0, UIConfig.Padding, 0, 34),
			panel, UIConfig.SubTextColor, UIConfig.TextSizeSmall,
			Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
		addCommitCancelButtons(panel, 70)

	elseif toolstateName == "Extrude" then
		local panel = makeOperatorPanelBase("Extrude")
		Factory.MakeLabel("ExtrudeNote", "Move handle to adjust depth.",
			UDim2.new(1, -UIConfig.Padding * 2, 0, 28),
			UDim2.new(0, UIConfig.Padding, 0, 34),
			panel, UIConfig.SubTextColor, UIConfig.TextSizeSmall,
			Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
		addCommitCancelButtons(panel, 70)

	elseif toolstateName == "Dissolve" then
		local panel = makeOperatorPanelBase("Dissolve Edge")
		local dissolveVertsButton = Factory.MakeButton("DissolveVertsToggle", "Dissolve Vertices: Off",
			UDim2.new(1, -UIConfig.Padding * 2, 0, 26),
			UDim2.new(0, UIConfig.Padding, 0, 34),
			panel)
		dissolveVertsEnabled = false
		dissolveVertsButton.Activated:Connect(function()
			dissolveVertsEnabled = not dissolveVertsEnabled
			setToggleButtonActive(dissolveVertsButton, dissolveVertsEnabled,
				"Dissolve Vertices: On", "Dissolve Vertices: Off")
			if onDissolveVertsToggle then onDissolveVertsToggle(dissolveVertsEnabled) end
		end)
		addCommitCancelButtons(panel, 70)
	end
end

function Hud.SetDissolveVertsCallback(callback)
	onDissolveVertsToggle = callback
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function Hud.SetVisible(isVisible)
	if gui then gui.Enabled = isVisible end
end

function Hud.SetMainButtonText(text)
	if mainButton then mainButton.Text = text end
end

function Hud.SetStatus(text)
	local modeText, verticesText, facesText, toolText = nil, "", "", nil
	local extras = {}
	for line in string.gmatch(text or "", "[^\n]+") do
		if line == "Edit" or line == "Selection" or line == "Disabled" then
			modeText = line
		elseif string.match(line, "^Vertices:") then
			verticesText = line
		elseif string.match(line, "^Faces:") then
			facesText = line
		elseif string.match(line, "^Tool:") then
			toolText = line
		else
			table.insert(extras, line)
		end
	end
	if modeLabel and modeText then modeLabel.Text = modeText end
	if verticesLabel then verticesLabel.Text = verticesText end
	if facesLabel then facesLabel.Text = facesText end
	if toolLabel and toolText then toolLabel.Text = toolText end
	if noteLabel then noteLabel.Text = table.concat(extras, "\n") end
end

local validToolsForMode = {
	Vertex = { Transform = true, Bevel = true },
	Edge   = { Transform = true, Bevel = true, Dissolve = true },
	Face   = { Transform = true, Extrude = true },
}

function Hud.SetGeometryMode(mode)
	for name, btn in pairs(geometryButtons) do
		setToggleButtonActive(btn, name == mode, name, name)
	end
	local valid = validToolsForMode[mode] or {}
	for name, entry in pairs(toolButtons) do
		local isValid = valid[name] == true
		entry.Button.AutoButtonColor = isValid
		entry.Button.Active          = isValid
		if isValid then
			entry.Button.BackgroundTransparency = 0
			if entry.Label then entry.Label.TextTransparency = 0 end
		else
			entry.Button.BackgroundTransparency = 0.6
			if entry.Label then entry.Label.TextTransparency = 0.6 end
		end
	end
end

function Hud.SetGeometryModeCallback(callback)  onGeometryMode   = callback end
function Hud.SetMainActionCallback(callback)     onMainAction     = callback end
function Hud.SetToolStateCallback(callback)      onToolState      = callback end
function Hud.SetUploadActionCallback(callback)   onUploadAction   = callback end
function Hud.SetOperatorCommitCallback(callback) onOperatorCommit = callback end
function Hud.SetOperatorCancelCallback(callback) onOperatorCancel = callback end

function Hud.SetToolStates(items, activeName)
	clearToolButtons()
	for _, item in ipairs(items) do
		local name, icon, hotkey
		if typeof(item) == "table" then
			name = item.Name; icon = item.Icon; hotkey = item.Hotkey
		else
			name = item; icon = UIConfig.ToolIcons[name]; hotkey = ""
		end
		local button, hotkeyLabel, iconObject = Factory.MakeToolButton(
			name .. "Button", icon or "", hotkey or "", toolRail)
		button.Activated:Connect(function()
			if onToolState then onToolState(name) end
		end)
		toolButtons[name] = { Button = button, Label = hotkeyLabel, Icon = iconObject }
	end
	Hud.SetActiveToolState(activeName)
end

function Hud.SetActiveToolState(activeName)
	for name, entry in pairs(toolButtons) do
		setToolButtonActive(entry, name == activeName)
	end
end

function Hud.Destroy()
	destroyOperatorPanel()
	if gui then gui:Destroy(); gui = nil end
	infoPanel = nil; uploadPanel = nil; topPanel = nil
	settingsTogglePanel = nil; settingsPanel = nil; toolRail = nil
	geometryPanel = nil; geometryButtons = {}
	mainButton = nil; uploadButton = nil; settingsButton = nil
	titleLabel = nil
	modeLabel = nil
	verticesLabel = nil; facesLabel = nil; toolLabel = nil; noteLabel = nil
	toolButtons = {}
end

return Hud
