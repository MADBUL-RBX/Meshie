-- Meshie.plugin.luau
-- Thin bootstrap. Passes the plugin global to HUD, handles unloading.

local HUD         = require(script.Parent.HUD)
local Version     = require(script.Parent.Version)
local NoticePanel = require(script.Parent.HUD.NoticePanel)

HUD.Init(plugin)

plugin.Unloading:Connect(function()
	HUD.Shutdown()
end)

local noticedVersion = plugin:GetSetting("MeshieNoticedVersion")
if noticedVersion ~= Version then
	NoticePanel.Show(plugin, Version, function()
		plugin:SetSetting("MeshieNoticedVersion", Version)
	end)
end
