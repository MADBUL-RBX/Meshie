-- HandleManager.luau
-- Owns the single active handle and its property signal connections.
-- Creates one handle from a proxy, and attaches/detaches change listeners
-- for the active operation.

local ToolHandles = require(script.Parent.ToolHandles)

local HandleManager = {}

local activeHandle = nil
local connection   = nil
local onChanged    = nil

local function copyProxyAttributes(proxy, handle)
	handle:SetAttribute("IsToolHandle", true)
	for attr, value in pairs(proxy:GetAttributes()) do
		handle:SetAttribute(attr, value)
	end
end

function HandleManager.Init(callback)
	onChanged = callback
end

function HandleManager.Arm(proxy)
	HandleManager.Clear()

	local handle = ToolHandles.CreateHandle(proxy, proxy.Name .. "Handle")
	if not handle then
		return nil
	end

	copyProxyAttributes(proxy, handle)
	activeHandle = handle
	return handle
end

function HandleManager.BeginListening()
	if not activeHandle then return end
	HandleManager.StopListening()

	local function fire()
		if onChanged then
			onChanged(activeHandle)
		end
	end

	connection = {
		activeHandle:GetPropertyChangedSignal("CFrame"):Connect(fire),
		activeHandle:GetPropertyChangedSignal("Size"):Connect(fire),
	}
end

function HandleManager.StopListening()
	if connection then
		for _, c in ipairs(connection) do
			c:Disconnect()
		end
		connection = nil
	end
end

function HandleManager.Clear()
	HandleManager.StopListening()
	if activeHandle then
		activeHandle:Destroy()
		activeHandle = nil
	end
end

function HandleManager.GetHandle()
	return activeHandle
end

function HandleManager.HasHandle()
	return activeHandle ~= nil
end

return HandleManager
