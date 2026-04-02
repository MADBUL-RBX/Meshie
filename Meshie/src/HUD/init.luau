-- HUD/init.luau
-- Owns: signals, keyboard input, display setters.
-- Factory owns construction. HUD owns wiring.

local UserInputService = game:GetService("UserInputService")

local UI        = require(script.Factory)
local UIConfig  = require(script.UIConfig)
local Hotkeys   = require(script.Hotkeys)

local Hud = {}

-- ─── Signals ──────────────────────────────────────────────────────────────────

local function Signal()
	local cbs = {}
	return {
		Connect = function(_, cb) cbs[#cbs + 1] = cb end,
		Fire    = function(_, ...) for _, cb in ipairs(cbs) do cb(...) end end,
	}
end

Hud.MainActivated         = Signal() -- Edit / Finalize button
Hud.ToolActivated         = Signal() -- fires(toolName)
Hud.CommitActivated       = Signal()
Hud.CancelActivated       = Signal()
Hud.GeometryModeActivated = Signal() -- fires(modeName)
Hud.DissolveVertsToggled  = Signal() -- fires(enabled: bool)

-- ─── Wire built UI to signals ─────────────────────────────────────────────────

UI.mainButton.Activated:Connect(function() Hud.MainActivated:Fire() end)
UI.uploadButton.Activated:Connect(function() Hud.MainActivated:Fire() end)

for modeName, btn in pairs(UI.geometryButtons) do
	btn.Activated:Connect(function() Hud.GeometryModeActivated:Fire(modeName) end)
end

for _, op in pairs(UI.operatorPanels) do
	op.commitButton.Activated:Connect(function() Hud.CommitActivated:Fire() end)
	op.cancelButton.Activated:Connect(function() Hud.CancelActivated:Fire() end)
end

for name, entry in pairs(UI.toolButtons) do
	entry.Button.Activated:Connect(function() Hud.ToolActivated:Fire(name) end)
end

local dissolveVertsEnabled = false
UI.operatorPanels.Dissolve.dissolveVertsButton.Activated:Connect(function()
	dissolveVertsEnabled = not dissolveVertsEnabled
	local btn = UI.operatorPanels.Dissolve.dissolveVertsButton
	btn.Text             = dissolveVertsEnabled and "Dissolve Vertices: On" or "Dissolve Vertices: Off"
	btn.BackgroundColor3 = dissolveVertsEnabled and UIConfig.ButtonActiveColor or UIConfig.ButtonColor
	btn.TextColor3       = dissolveVertsEnabled and UIConfig.ButtonActiveTextColor or UIConfig.TextColor
	btn:SetAttribute("IsActive", dissolveVertsEnabled)
	Hud.DissolveVertsToggled:Fire(dissolveVertsEnabled)
end)

-- ─── Keyboard input ───────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not UI.gui.Enabled then return end
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if UserInputService:GetFocusedTextBox() then return end
	local key = input.KeyCode
	if key == Hotkeys.GetKeyCode("Cancel") then
		Hud.CancelActivated:Fire()
		return
	end
	for name in pairs(UI.toolButtons) do
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

-- ─── Tool button visual state ─────────────────────────────────────────────────

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

-- ─── Public API ───────────────────────────────────────────────────────────────

function Hud.SetVisible(isVisible)
	UI.gui.Enabled = isVisible
end

function Hud.SetMainButtonText(text)
	UI.mainButton.Text = text
end

function Hud.SetMode(text)
	UI.modeLabel.Text = text
end

function Hud.SetCounts(vertices, faces)
	UI.verticesLabel.Text = vertices ~= nil and "Vertices: " .. vertices or ""
	UI.facesLabel.Text    = faces ~= nil and "Faces: " .. faces or ""
end

function Hud.SetTool(name)
	UI.toolLabel.Text = name and "Tool: " .. name or ""
end

function Hud.SetNote(text)
	UI.noteLabel.Text = text or ""
end

function Hud.SetGeometryMode(mode, validTools)
	local valid = validTools or {}
	for name, btn in pairs(UI.geometryButtons) do
		local isActive = name == mode
		btn:SetAttribute("IsActive", isActive)
		btn.BackgroundColor3 = isActive and UIConfig.ButtonActiveColor or UIConfig.ButtonColor
		btn.TextColor3       = isActive and UIConfig.ButtonActiveTextColor or UIConfig.TextColor
	end
	for name, entry in pairs(UI.toolButtons) do
		local isValid = valid[name] == true
		entry.Button.AutoButtonColor = isValid
		entry.Button.Active          = isValid
		entry.Button.BackgroundTransparency = isValid and 0 or 0.6
		if entry.Label then entry.Label.TextTransparency = isValid and 0 or 0.6 end
	end
end

function Hud.SetOperatorPanel(toolstateName)
	if toolstateName ~= "Dissolve" then
		dissolveVertsEnabled = false
		local d = UI.operatorPanels.Dissolve.dissolveVertsButton
		d.Text             = "Dissolve Vertices: Off"
		d.BackgroundColor3 = UIConfig.ButtonColor
		d.TextColor3       = UIConfig.TextColor
		d:SetAttribute("IsActive", false)
	end
	for name, op in pairs(UI.operatorPanels) do
		op.panel.Visible = name == toolstateName
	end
end

function Hud.SetActiveToolState(activeName)
	for name, entry in pairs(UI.toolButtons) do
		setToolButtonActive(entry, name == activeName)
	end
end

function Hud.Destroy()
	UI.gui:Destroy()
end

return Hud
