local CoreGui          = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")

local UIConfig  = require(script.UIConfig)
local UserConfig = require(script.UserConfig)
local Hotkeys   = require(script.Hotkeys)
local Factory   = require(script.Factory)

local Hud = {}

-- ─── Signals ──────────────────────────────────────────────────────────────────

local function Signal()
	local cbs = {}
	return {
		Connect = function(_, cb) cbs[#cbs + 1] = cb end,
		Fire    = function(_, ...) for _, cb in ipairs(cbs) do cb(...) end end,
		Clear   = function(_) cbs = {} end,
	}
end

Hud.MainActivated         = Signal() -- Edit / Finalize button
Hud.ToolActivated         = Signal() -- fires(toolName)
Hud.CommitActivated       = Signal()
Hud.CancelActivated       = Signal()
Hud.GeometryModeActivated = Signal() -- fires(modeName)
Hud.DissolveVertsToggled  = Signal() -- fires(enabled: bool)

-- ─── Forward declarations (referenced by helpers defined before construction) ─

local gui
local operatorPanel
local settingsPanel
local toolButtons        = {}
local dissolveVertsEnabled = false

-- ─── Internal helpers ─────────────────────────────────────────────────────────

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
	for _, entry in pairs(toolButtons) do
		entry.Button:Destroy()
	end
	toolButtons = {}
end

local function toggleSettingsPanel()
	settingsPanel.Visible = not settingsPanel.Visible
end

local function destroyOperatorPanel()
	if operatorPanel then
		operatorPanel:Destroy()
		operatorPanel = nil
	end
	dissolveVertsEnabled = false
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
		Hud.CommitActivated:Fire()
	end)

	local cancelButton = Factory.MakeButton("OperatorCancel", "Cancel",
		UDim2.new(0.5, -UIConfig.Padding - 2, 0, 26),
		UDim2.new(0.5, 2, 0, yOffset),
		panel)
	cancelButton.Activated:Connect(function()
		Hud.CancelActivated:Fire()
	end)
end

-- ─── Build GUI ────────────────────────────────────────────────────────────────

local existing = CoreGui:FindFirstChild("MeshPartEditHud")
if existing then existing:Destroy() end

gui = Instance.new("ScreenGui")
gui.Name           = "MeshPartEditHud"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled        = false
gui.Parent         = CoreGui

local infoPanel = Factory.MakePanel(
	"InfoPanel",
	UDim2.new(0, UIConfig.InfoPanelWidth, 0, UIConfig.InfoPanelHeight),
	Vector2.new(0, 0.5),
	UDim2.new(0, UIConfig.Margin, 0.5, 0),
	gui
)

Factory.MakeLabel("TitleLabel", "MeshPartEdit",
	UDim2.new(1, -UIConfig.Padding * 2, 0, 18),
	UDim2.new(0, UIConfig.Padding, 0, 10),
	infoPanel, UIConfig.TextColor, UIConfig.TextSizeTitle, Enum.TextXAlignment.Left)

Factory.MakeDivider("TopDivider",
	UDim2.new(1, -UIConfig.Padding * 2, 0, 1),
	UDim2.new(0, UIConfig.Padding, 0, 36), infoPanel)

local modeLabel = Factory.MakeLabel("ModeLabel", "Selection",
	UDim2.new(1, -UIConfig.Padding * 2, 0, 16),
	UDim2.new(0, UIConfig.Padding, 0, 46),
	infoPanel, UIConfig.TextColor, UIConfig.TextSizeBody, Enum.TextXAlignment.Left)

local verticesLabel = Factory.MakeLabel("VerticesLabel", "",
	UDim2.new(1, -UIConfig.Padding * 2, 0, 14),
	UDim2.new(0, UIConfig.Padding, 0, 72),
	infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall, Enum.TextXAlignment.Left)

local facesLabel = Factory.MakeLabel("FacesLabel", "",
	UDim2.new(1, -UIConfig.Padding * 2, 0, 14),
	UDim2.new(0, UIConfig.Padding, 0, 90),
	infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall, Enum.TextXAlignment.Left)

local toolLabel = Factory.MakeLabel("ToolLabel", "",
	UDim2.new(1, -UIConfig.Padding * 2, 0, 108),
	UDim2.new(0, UIConfig.Padding, 0, 108),
	infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall, Enum.TextXAlignment.Left)

Factory.MakeDivider("MiddleDivider",
	UDim2.new(1, -UIConfig.Padding * 2, 0, 1),
	UDim2.new(0, UIConfig.Padding, 0, 132), infoPanel)

local noteLabel = Factory.MakeLabel("NoteLabel", "",
	UDim2.new(1, -UIConfig.Padding * 2, 0, 38),
	UDim2.new(0, UIConfig.Padding, 0, 142),
	infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall,
	Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)

local mainButton = Factory.MakeButton("MainButton", "Edit",
	UDim2.new(1, -UIConfig.Padding * 2, 0, UIConfig.MainButtonHeight),
	UDim2.new(0, UIConfig.Padding, 1, -(UIConfig.Padding + UIConfig.MainButtonHeight)),
	infoPanel)
mainButton.Activated:Connect(function()
	Hud.MainActivated:Fire()
end)

-- ─── Upload panel ─────────────────────────────────────────────────────────────

local uploadPanel = Factory.MakePanel("UploadPanel",
	UDim2.new(0, UIConfig.UploadPanelWidth, 0, UIConfig.UploadPanelHeight),
	Vector2.new(0, 1),
	UDim2.new(0, UIConfig.Margin, 1, -UIConfig.Margin),
	gui)

local uploadButton = Factory.MakeButton("UploadButton", "Upload",
	UDim2.new(1, -UIConfig.Padding * 2, 0, UIConfig.UploadButtonHeight),
	UDim2.new(0, UIConfig.Padding, 0, UIConfig.Padding),
	uploadPanel)
uploadButton.Activated:Connect(function()
	Hud.MainActivated:Fire()
end)

Factory.MakeLabel("UploadInfoLabel", "Non-operational until CreateAssetAsync() support is added.",
	UDim2.new(1, -UIConfig.Padding * 2, 0, 30),
	UDim2.new(0, UIConfig.Padding, 0, UIConfig.Padding + UIConfig.UploadButtonHeight + 8),
	uploadPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall,
	Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)

-- ─── Top panel ────────────────────────────────────────────────────────────────

local topPanel = Factory.MakePanel("TopPanel",
	UDim2.new(0, UIConfig.FaceModePanelWidth, 0, 58),
	Vector2.new(0.5, 0),
	UDim2.new(0.5, 0, 0, UIConfig.Margin),
	gui)

Factory.MakeLabel("TopPanelLabel", "View",
	UDim2.new(1, -UIConfig.Padding * 2, 0, 12),
	UDim2.new(0, UIConfig.Padding, 0, 8),
	topPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall, Enum.TextXAlignment.Left)

-- ─── Geometry mode panel ──────────────────────────────────────────────────────

local geometryPanel = Factory.MakePanel("GeometryPanel",
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
local btnWidth = (UIConfig.FaceModePanelWidth - UIConfig.Padding * 2 - 4) / 3
local geometryButtons = {}

for i, modeName in ipairs(modeNames) do
	local xOff = UIConfig.Padding + (i - 1) * (btnWidth + 2)
	local btn = Factory.MakeButton("GeoMode" .. modeName, modeName,
		UDim2.new(0, btnWidth, 0, 26),
		UDim2.new(0, xOff, 0, 24),
		geometryPanel)
	btn.Activated:Connect(function()
		Hud.GeometryModeActivated:Fire(modeName)
	end)
	Factory.Create("TextLabel", {
		Name                  = "HotkeyLabel",
		AnchorPoint           = Vector2.new(1, 1),
		Position              = UDim2.new(1, -4, 1, -3),
		Size                  = UDim2.new(0, 16, 0, 12),
		BackgroundTransparency = 1,
		Text                  = modeHotkeyLabel[modeName] or "",
		TextColor3            = UIConfig.SubTextColor,
		Font                  = UIConfig.Font,
		TextSize              = UIConfig.TextSizeSmall,
		TextXAlignment        = Enum.TextXAlignment.Right,
		TextYAlignment        = Enum.TextYAlignment.Bottom,
		Parent                = btn,
	})
	geometryButtons[modeName] = btn
end

-- ─── Settings ─────────────────────────────────────────────────────────────────

local settingsTogglePanel = Factory.MakePanel("SettingsTogglePanel",
	UDim2.new(0, UIConfig.SettingsToggleWidth, 0, UIConfig.SettingsToggleHeight),
	Vector2.new(1, 1),
	UDim2.new(1, -UIConfig.Margin, 1, -UIConfig.Margin),
	gui)

local settingsButton = Factory.MakeButton("SettingsButton", "Settings",
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

-- ─── Tool rail ────────────────────────────────────────────────────────────────

local toolRail = Factory.MakePanel("ToolRail",
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

-- ─── Keyboard input ───────────────────────────────────────────────────────────
-- HUD owns all user input. Keyboard hotkeys fire the same signals as buttons.

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gui.Enabled then return end
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if UserInputService:GetFocusedTextBox() then return end

	local key = input.KeyCode
	if key == Hotkeys.GetKeyCode("Cancel") then
		Hud.CancelActivated:Fire()
		return
	end
	for name in pairs(toolButtons) do
		if key == Hotkeys.GetKeyCode(name) then
			Hud.ToolActivated:Fire(name)
			return
		end
	end
	for _, mode in ipairs({ "Vertex", "Edge", "Face" }) do
		if key == Hotkeys.GetKeyCode(mode) then
			Hud.GeometryModeActivated:Fire(mode)
			return
		end
	end
end)

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
			Hud.DissolveVertsToggled:Fire(dissolveVertsEnabled)
		end)
		addCommitCancelButtons(panel, 70)
	end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

function Hud.SetVisible(isVisible)
	gui.Enabled = isVisible
end

function Hud.SetMainButtonText(text)
	mainButton.Text = text
end

function Hud.SetMode(text)
	modeLabel.Text = text
end

function Hud.SetCounts(vertices, faces)
	verticesLabel.Text = vertices ~= nil and "Vertices: " .. vertices or ""
	facesLabel.Text    = faces ~= nil and "Faces: " .. faces or ""
end

function Hud.SetTool(name)
	toolLabel.Text = name and "Tool: " .. name or ""
end

function Hud.SetNote(text)
	noteLabel.Text = text or ""
end

function Hud.SetGeometryMode(mode, validTools)
	for name, btn in pairs(geometryButtons) do
		setToggleButtonActive(btn, name == mode, name, name)
	end
	local valid = validTools or {}
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

function Hud.SetToolStates(toolNames, activeName)
	clearToolButtons()
	for _, name in ipairs(toolNames) do
		local button, hotkeyLabel, iconObject = Factory.MakeToolButton(
			name .. "Button",
			UIConfig.ToolIcons[name] or "",
			UserConfig.ToolHotkeys[name] or "",
			toolRail)
		button.Activated:Connect(function()
			Hud.ToolActivated:Fire(name)
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

-- Called by Loader on plugin.Unloading.
function Hud.Destroy()
	destroyOperatorPanel()
	gui:Destroy()
end

Hud.SetGeometryMode("Vertex")

return Hud
