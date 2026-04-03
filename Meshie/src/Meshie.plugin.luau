-- Meshie.plugin.luau
-- Thin bootstrap. Passes the plugin global to HUD, handles unloading.

local Core        = require(script.Parent.Core)
local Version     = require(script.Parent.Version)
local NoticePanel = require(script.Parent.Core.NoticePanel)

Core.Init(plugin)

plugin.Unloading:Connect(function()
	Core.Shutdown()
end)

local noticedVersion = plugin:GetSetting("MeshieNoticedVersion")
if noticedVersion ~= Version then
	NoticePanel.Show(plugin, Version, function()
		plugin:SetSetting("MeshieNoticedVersion", Version)
	end)
end
