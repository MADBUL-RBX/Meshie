local UserInputService = game:GetService("UserInputService")

local UserConfig = require(script.Parent.UserConfig)

local Hotkeys = {}

local inputConnection = nil
local keyToToolState = {}

local function rebuildBindings()
	keyToToolState = {}

	for toolStateName, hotkey in pairs(UserConfig.ToolHotkeys) do
		if typeof(hotkey) == "string" and hotkey ~= "" then
			local keyCode = Enum.KeyCode[string.upper(hotkey)]
			if keyCode then
				keyToToolState[keyCode] = toolStateName
			end
		end
	end
end

function Hotkeys.Start(isEnabledCallback, setToolStateCallback)
	rebuildBindings()

	if inputConnection then
		inputConnection:Disconnect()
	end

	inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		if UserInputService:GetFocusedTextBox() then
			return
		end

		if not isEnabledCallback() then
			return
		end

		local toolStateName = keyToToolState[input.KeyCode]
		if toolStateName then
			setToolStateCallback(toolStateName)
		end
	end)
end

function Hotkeys.Rebuild()
	rebuildBindings()
end

function Hotkeys.Destroy()
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end
end

return Hotkeys
