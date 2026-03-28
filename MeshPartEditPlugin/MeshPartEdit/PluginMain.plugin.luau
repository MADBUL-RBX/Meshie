local MPE          = require(script.Parent.MPE)
local Version      = require(script.Parent.Version)
local NoticePanel  = require(script.Parent.UI.NoticePanel)

local toolbar      = plugin:CreateToolbar("Meshie")
local toggleButton = toolbar:CreateButton("Meshie", "Toggle Meshie", "")

local enabled = false

toggleButton.Click:Connect(function()
	MPE.Toggle(plugin, toggleButton)
	enabled = not enabled
end)

plugin.Unloading:Connect(function()
	if enabled then
		MPE.Toggle(plugin, toggleButton)
	end
end)

-- Show the welcome notice on first load of each new version.
local noticedVersion = plugin:GetSetting("MeshieNoticedVersion")
if noticedVersion ~= Version then
	NoticePanel.Show(plugin, Version, function()
		plugin:SetSetting("MeshieNoticedVersion", Version)
	end)
end
