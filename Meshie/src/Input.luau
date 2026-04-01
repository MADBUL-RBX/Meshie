local UIS = game:GetService("UserInputService")

local Input = {}

Input.IsShiftDown = function()
	return UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
end

Input.IsCtrlDown = function()
	return UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
end

Input.IsAltDown = function()
	return UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt)
end

return Input
