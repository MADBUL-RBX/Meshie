-- Factory.luau
-- Builds and owns all plugin GUI at require time.
-- Returns a refs table for HUD to wire and controller to use.

local CoreGui    = game:GetService("CoreGui")
local UIConfig   = require(script.Parent.UIConfig)
local UserConfig = require(script.Parent.UserConfig)

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function create(className, props, children)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do inst[k] = v end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	return inst
end

local function connectHover(btn)
	btn:SetAttribute("IsActive", false)
	btn.MouseEnter:Connect(function()
		if not btn:GetAttribute("IsActive") then
			btn.BackgroundColor3 = UIConfig.ButtonHoverColor
		end
	end)
	btn.MouseLeave:Connect(function()
		if not btn:GetAttribute("IsActive") then
			btn.BackgroundColor3 = UIConfig.ButtonColor
		end
	end)
end

local function makePanel(name, size, anchor, pos, parent)
	return create("Frame", {
		Name = name, Size = size, AnchorPoint = anchor, Position = pos,
		BackgroundColor3 = UIConfig.PanelColor,
		BackgroundTransparency = UIConfig.PanelTransparency,
		BorderSizePixel = 0, Parent = parent,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, UIConfig.CornerRadius) }),
		create("UIStroke", { Color = UIConfig.PanelStrokeColor, Thickness = UIConfig.StrokeThickness, Transparency = 0.2 }),
	})
end

local function makeLabel(name, text, size, pos, parent, textColor, textSize, xAlign, yAlign)
	return create("TextLabel", {
		Name = name, Size = size, Position = pos,
		BackgroundTransparency = 1, Text = text,
		TextColor3 = textColor or UIConfig.TextColor,
		Font = UIConfig.Font,
		TextSize = textSize or UIConfig.TextSizeBody,
		TextWrapped = true,
		TextXAlignment = xAlign or Enum.TextXAlignment.Left,
		TextYAlignment = yAlign or Enum.TextYAlignment.Center,
		Parent = parent,
	})
end

local function makeDivider(name, size, pos, parent)
	return create("Frame", {
		Name = name, Size = size, Position = pos,
		BackgroundColor3 = UIConfig.PanelStrokeColor,
		BackgroundTransparency = 0.35, BorderSizePixel = 0,
		Parent = parent,
	})
end

local function makeButton(name, text, size, pos, parent)
	local btn = create("TextButton", {
		Name = name, Size = size, Position = pos,
		BackgroundColor3 = UIConfig.ButtonColor,
		BorderSizePixel = 0, AutoButtonColor = false,
		Text = text, TextColor3 = UIConfig.TextColor,
		Font = UIConfig.Font, TextSize = UIConfig.TextSizeButton,
		Parent = parent,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, UIConfig.CornerRadius) }),
		create("UIStroke", { Color = UIConfig.PanelStrokeColor, Thickness = 1, Transparency = 0.35 }),
	})
	connectHover(btn)
	return btn
end

local function makeToolButton(name, icon, hotkey, parent)
	local btn = create("TextButton", {
		Name = name,
		Size = UDim2.new(1, 0, 0, UIConfig.ToolRailButtonHeight),
		BackgroundColor3 = UIConfig.ButtonColor,
		BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", Parent = parent,
	}, {
		create("UICorner", { CornerRadius = UDim.new(0, UIConfig.CornerRadius) }),
		create("UIStroke", { Color = UIConfig.PanelStrokeColor, Thickness = 1, Transparency = 0.35 }),
	})
	connectHover(btn)

	local iconObj
	if icon and icon ~= "" then
		iconObj = create("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, -14, 1, -14),
			BackgroundTransparency = 1,
			Image = icon, ImageColor3 = UIConfig.TextColor,
			ScaleType = Enum.ScaleType.Fit, Parent = btn,
		})
	else
		iconObj = create("TextLabel", {
			Name = "IconFallback",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, -12, 1, -12),
			BackgroundTransparency = 1, Text = "?",
			TextColor3 = UIConfig.TextColor, Font = UIConfig.Font,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			Parent = btn,
		})
	end

	local hotkeyLbl = create("TextLabel", {
		Name = "HotkeyLabel",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -5, 1, -4),
		Size = UDim2.new(0, 20, 0, 12),
		BackgroundTransparency = 1,
		Text = hotkey or "", TextColor3 = UIConfig.SubTextColor,
		Font = UIConfig.Font, TextSize = UIConfig.TextSizeSmall,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Visible = hotkey ~= nil and hotkey ~= "",
		Parent = btn,
	})

	return btn, hotkeyLbl, iconObj
end

-- ─── Build GUI ────────────────────────────────────────────────────────────────

local existing = CoreGui:FindFirstChild("MeshPartEditHud")
if existing then existing:Destroy() end

local gui = create("ScreenGui", {
	Name = "MeshPartEditHud", ResetOnSpawn = false,
	IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false, Parent = CoreGui,
})

-- ─── Info panel ───────────────────────────────────────────────────────────────

local infoPanel = makePanel("InfoPanel",
	UDim2.new(0, UIConfig.InfoPanelWidth, 0, UIConfig.InfoPanelHeight),
	Vector2.new(0, 0.5), UDim2.new(0, UIConfig.Margin, 0.5, 0), gui)

makeLabel("TitleLabel", "MeshPartEdit",
	UDim2.new(1, -UIConfig.Padding*2, 0, 18), UDim2.new(0, UIConfig.Padding, 0, 10),
	infoPanel, UIConfig.TextColor, UIConfig.TextSizeTitle)

makeDivider("TopDivider",
	UDim2.new(1, -UIConfig.Padding*2, 0, 1), UDim2.new(0, UIConfig.Padding, 0, 36), infoPanel)

local modeLabel = makeLabel("ModeLabel", "Selection",
	UDim2.new(1, -UIConfig.Padding*2, 0, 16), UDim2.new(0, UIConfig.Padding, 0, 46),
	infoPanel, UIConfig.TextColor, UIConfig.TextSizeBody)

local verticesLabel = makeLabel("VerticesLabel", "",
	UDim2.new(1, -UIConfig.Padding*2, 0, 14), UDim2.new(0, UIConfig.Padding, 0, 72),
	infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall)

local facesLabel = makeLabel("FacesLabel", "",
	UDim2.new(1, -UIConfig.Padding*2, 0, 14), UDim2.new(0, UIConfig.Padding, 0, 90),
	infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall)

local toolLabel = makeLabel("ToolLabel", "",
	UDim2.new(1, -UIConfig.Padding*2, 0, 14), UDim2.new(0, UIConfig.Padding, 0, 108),
	infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall)

makeDivider("MiddleDivider",
	UDim2.new(1, -UIConfig.Padding*2, 0, 1), UDim2.new(0, UIConfig.Padding, 0, 132), infoPanel)

local noteLabel = makeLabel("NoteLabel", "",
	UDim2.new(1, -UIConfig.Padding*2, 0, 38), UDim2.new(0, UIConfig.Padding, 0, 142),
	infoPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall,
	Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)

local mainButton = makeButton("MainButton", "Edit",
	UDim2.new(1, -UIConfig.Padding*2, 0, UIConfig.MainButtonHeight),
	UDim2.new(0, UIConfig.Padding, 1, -(UIConfig.Padding + UIConfig.MainButtonHeight)), infoPanel)

-- ─── Upload panel ─────────────────────────────────────────────────────────────

local uploadPanel = makePanel("UploadPanel",
	UDim2.new(0, UIConfig.UploadPanelWidth, 0, UIConfig.UploadPanelHeight),
	Vector2.new(0, 1), UDim2.new(0, UIConfig.Margin, 1, -UIConfig.Margin), gui)

local uploadButton = makeButton("UploadButton", "Upload",
	UDim2.new(1, -UIConfig.Padding*2, 0, UIConfig.UploadButtonHeight),
	UDim2.new(0, UIConfig.Padding, 0, UIConfig.Padding), uploadPanel)

makeLabel("UploadInfoLabel", "Non-operational until CreateAssetAsync() support is added.",
	UDim2.new(1, -UIConfig.Padding*2, 0, 30),
	UDim2.new(0, UIConfig.Padding, 0, UIConfig.Padding + UIConfig.UploadButtonHeight + 8),
	uploadPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall,
	Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)

-- ─── Top panel ────────────────────────────────────────────────────────────────

local topPanel = makePanel("TopPanel",
	UDim2.new(0, UIConfig.FaceModePanelWidth, 0, 58),
	Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, UIConfig.Margin), gui)

makeLabel("TopPanelLabel", "View",
	UDim2.new(1, -UIConfig.Padding*2, 0, 12), UDim2.new(0, UIConfig.Padding, 0, 8),
	topPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall)

-- ─── Geometry panel ───────────────────────────────────────────────────────────

local geometryPanel = makePanel("GeometryPanel",
	UDim2.new(0, UIConfig.FaceModePanelWidth, 0, 58),
	Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, UIConfig.Margin + 68), gui)

makeLabel("GeometryModeLabel", "Mode",
	UDim2.new(1, -UIConfig.Padding*2, 0, 12), UDim2.new(0, UIConfig.Padding, 0, 8),
	geometryPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall)

local btnW = (UIConfig.FaceModePanelWidth - UIConfig.Padding*2 - 4) / 3
local geoHotkeys = { Vertex = "[", Edge = "]", Face = "\\" }
local geometryButtons = {}

for i, modeName in ipairs({ "Vertex", "Edge", "Face" }) do
	local xOff = UIConfig.Padding + (i-1) * (btnW + 2)
	local btn = makeButton("GeoMode"..modeName, modeName,
		UDim2.new(0, btnW, 0, 26), UDim2.new(0, xOff, 0, 24), geometryPanel)
	create("TextLabel", {
		Name = "HotkeyLabel", AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -3), Size = UDim2.new(0, 16, 0, 12),
		BackgroundTransparency = 1, Text = geoHotkeys[modeName] or "",
		TextColor3 = UIConfig.SubTextColor, Font = UIConfig.Font,
		TextSize = UIConfig.TextSizeSmall,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom, Parent = btn,
	})
	geometryButtons[modeName] = btn
end

-- ─── Settings ─────────────────────────────────────────────────────────────────

local settingsTogglePanel = makePanel("SettingsTogglePanel",
	UDim2.new(0, UIConfig.SettingsToggleWidth, 0, UIConfig.SettingsToggleHeight),
	Vector2.new(1, 1), UDim2.new(1, -UIConfig.Margin, 1, -UIConfig.Margin), gui)

local settingsButton = makeButton("SettingsButton", "Settings",
	UDim2.new(1, -UIConfig.Padding*2, 0, UIConfig.SettingsButtonHeight),
	UDim2.new(0, UIConfig.Padding, 0, UIConfig.Padding), settingsTogglePanel)

local settingsPanel = makePanel("SettingsPanel",
	UDim2.new(0, UIConfig.SettingsPanelWidth, 0, UIConfig.SettingsPanelHeight),
	Vector2.new(1, 1),
	UDim2.new(1, -UIConfig.Margin, 1, -(UIConfig.Margin + UIConfig.SettingsToggleHeight + 10)), gui)
settingsPanel.Visible = false

makeLabel("SettingsTitle", "User Settings",
	UDim2.new(1, -UIConfig.Padding*2, 0, 18), UDim2.new(0, UIConfig.Padding, 0, 10),
	settingsPanel, UIConfig.TextColor, UIConfig.TextSizeTitle)

makeDivider("SettingsDivider",
	UDim2.new(1, -UIConfig.Padding*2, 0, 1), UDim2.new(0, UIConfig.Padding, 0, 36), settingsPanel)

makeLabel("SettingsPlaceholder", "Hotkeys and user preferences will live here later.",
	UDim2.new(1, -UIConfig.Padding*2, 0, 50), UDim2.new(0, UIConfig.Padding, 0, 48),
	settingsPanel, UIConfig.SubTextColor, UIConfig.TextSizeSmall,
	Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)

-- Purely visual toggle — no signal needed
settingsButton.Activated:Connect(function()
	settingsPanel.Visible = not settingsPanel.Visible
end)

-- ─── Tool rail ────────────────────────────────────────────────────────────────

local toolRail = makePanel("ToolRail",
	UDim2.new(0, UIConfig.ToolRailWidth, 0, 0),
	Vector2.new(1, 0.5), UDim2.new(1, -UIConfig.Margin, 0.5, 0), gui)

create("UIPadding", {
	PaddingTop = UDim.new(0, UIConfig.Padding), PaddingBottom = UDim.new(0, UIConfig.Padding),
	PaddingLeft = UDim.new(0, UIConfig.Padding - 2), PaddingRight = UDim.new(0, UIConfig.Padding - 2),
	Parent = toolRail,
})
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	Padding = UDim.new(0, UIConfig.Spacing), Parent = toolRail,
})
toolRail.AutomaticSize = Enum.AutomaticSize.Y

-- Tool buttons (pre-built in order)
local toolButtons = {}
for _, name in ipairs({ "Transform", "Extrude", "Bevel", "Dissolve" }) do
	local btn, lbl, icon = makeToolButton(
		name.."Button",
		UIConfig.ToolIcons and UIConfig.ToolIcons[name] or "",
		UserConfig.ToolHotkeys and UserConfig.ToolHotkeys[name] or "",
		toolRail)
	toolButtons[name] = { Button = btn, Label = lbl, Icon = icon }
end

-- ─── Operator panels (pre-built, hidden) ──────────────────────────────────────

local opPos = UDim2.new(0, UIConfig.Margin, 0, UIConfig.Margin + UIConfig.InfoPanelHeight / 2 + 10)

local function makeOpPanel(title)
	local p = makePanel(title.."OpPanel",
		UDim2.new(0, UIConfig.InfoPanelWidth, 0, 0),
		Vector2.new(0, 0), opPos, gui)
	p.AutomaticSize = Enum.AutomaticSize.Y
	p.Visible = false
	makeLabel("OpTitle", title,
		UDim2.new(1, -UIConfig.Padding*2, 0, 16), UDim2.new(0, UIConfig.Padding, 0, 10),
		p, UIConfig.TextColor, UIConfig.TextSizeBody)
	return p
end

local function makeOpButtons(p, yOff)
	local c = makeButton("OperatorCommit", "Commit",
		UDim2.new(0.5, -UIConfig.Padding-2, 0, 26), UDim2.new(0, UIConfig.Padding, 0, yOff), p)
	local x = makeButton("OperatorCancel", "Cancel",
		UDim2.new(0.5, -UIConfig.Padding-2, 0, 26), UDim2.new(0.5, 2, 0, yOff), p)
	return c, x
end

local function makeNote(text, p)
	makeLabel("Note", text,
		UDim2.new(1, -UIConfig.Padding*2, 0, 28), UDim2.new(0, UIConfig.Padding, 0, 34),
		p, UIConfig.SubTextColor, UIConfig.TextSizeSmall,
		Enum.TextXAlignment.Left, Enum.TextYAlignment.Top)
end

local transformPanel = makeOpPanel("Transform")
local tCommit, tCancel = makeOpButtons(transformPanel, 34)

local bevelPanel = makeOpPanel("Bevel")
makeNote("Move handle to adjust depth.", bevelPanel)
local bCommit, bCancel = makeOpButtons(bevelPanel, 70)

local extrudePanel = makeOpPanel("Extrude")
makeNote("Move handle to adjust depth.", extrudePanel)
local eCommit, eCancel = makeOpButtons(extrudePanel, 70)

local dissolvePanel = makeOpPanel("Dissolve Edge")
local dissolveVertsBtn = makeButton("DissolveVertsToggle", "Dissolve Vertices: Off",
	UDim2.new(1, -UIConfig.Padding*2, 0, 26), UDim2.new(0, UIConfig.Padding, 0, 34), dissolvePanel)
local dCommit, dCancel = makeOpButtons(dissolvePanel, 70)

-- ─── Return refs ──────────────────────────────────────────────────────────────

return {
	Create        = create,
	gui           = gui,
	mainButton    = mainButton,
	uploadButton  = uploadButton,
	modeLabel     = modeLabel,
	verticesLabel = verticesLabel,
	facesLabel    = facesLabel,
	toolLabel     = toolLabel,
	noteLabel     = noteLabel,
	geometryButtons = geometryButtons,
	settingsPanel   = settingsPanel,
	toolRail        = toolRail,
	toolButtons     = toolButtons,
	operatorPanels  = {
		Transform = { panel = transformPanel, commitButton = tCommit, cancelButton = tCancel },
		Bevel     = { panel = bevelPanel,     commitButton = bCommit, cancelButton = bCancel },
		Extrude   = { panel = extrudePanel,   commitButton = eCommit, cancelButton = eCancel },
		Dissolve  = { panel = dissolvePanel,  commitButton = dCommit, cancelButton = dCancel, dissolveVertsButton = dissolveVertsBtn },
	},
}
