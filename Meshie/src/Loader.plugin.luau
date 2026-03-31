local Editor              = require(script.Parent.Editor)
local RibbonToolManager   = require(script.Parent.Editor.RibbonToolManager)
local Version             = require(script.Parent.Version)
local NoticePanel         = require(script.Parent.HUD.NoticePanel)

RibbonToolManager.Init(plugin)

local toolbar      = plugin:CreateToolbar("Meshie")
local toggleButton = toolbar:CreateButton("Meshie", "Toggle Meshie", "")

local enabled = false

toggleButton.Click:Connect(function()
	Editor.Toggle(plugin, toggleButton)
	enabled = not enabled
end)

plugin.Unloading:Connect(function()
	if enabled then
		Editor.Toggle(plugin, toggleButton)
	end
end)

-- Show the welcome notice on first load of each new version.
local noticedVersion = plugin:GetSetting("MeshieNoticedVersion")
if noticedVersion ~= Version then
	NoticePanel.Show(plugin, Version, function()
		plugin:SetSetting("MeshieNoticedVersion", Version)
	end)
end
