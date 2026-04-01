-- Hotkeys.luau
-- Pure data module. Maps action/tool names to KeyCodes from UserConfig.
-- No lifecycle, no callbacks. Consumers call GetKeyCode(name) directly.

local UserConfig = require(script.Parent.UserConfig)

local Hotkeys = {}

function Hotkeys.GetKeyCode(name)
	local hotkey = UserConfig.ToolHotkeys[name]
		or UserConfig.ActionHotkeys[name]
		or UserConfig.GeometryModeHotkeys[name]
	if not hotkey or hotkey == "" then return nil end
	return Enum.KeyCode[hotkey]
end

return Hotkeys
