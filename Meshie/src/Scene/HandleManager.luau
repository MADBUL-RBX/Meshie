-- HandleManager.luau
-- Owns the single active handle and its Listen connection.
-- Creates one handle from a proxy, forces Studio selection on it,
-- and attaches/detaches Listen for the active operation.

local Listen = require(script.Parent.Parent.Listen)
local ToolHandles = require(script.Parent.ToolHandles)
local SelectionService = game:GetService("Selection")

local HandleManager = {}

local activeHandle = nil
local connection = nil
local onChanged = nil

local function copyProxyAttributes(proxy, handle)
	handle:SetAttribute("IsToolHandle", true)
	-- Copy all proxy attributes wholesale so normals, tangents, IDs all transfer.
	for attr, value in pairs(proxy:GetAttributes()) do
		handle:SetAttribute(attr, value)
	end
end

function HandleManager.Init(callback)
	onChanged = callback
end

-- Create a handle for the given proxy, force-select it in Studio.
function HandleManager.Arm(proxy)
	HandleManager.Clear()

	local handle = ToolHandles.CreateHandle(proxy, proxy.Name .. "Handle")
	if not handle then
		return nil
	end

	copyProxyAttributes(proxy, handle)
	activeHandle = handle

	-- Force Studio to select the handle so the native Move tool works on it
	SelectionService:Set({ handle })

	return handle
end

-- Attach Listen to the active handle. Call when an operation begins.
function HandleManager.BeginListening()
	if not activeHandle then
		return
	end
	if connection then
		for _, c in ipairs(connection) do
			c:Disconnect()
		end
	end
	connection = Listen.Attach(activeHandle, function(h, oCF, oSz, nCF, nSz)
		if onChanged then
			onChanged(h, oCF, oSz, nCF, nSz)
		end
	end)
end

-- Detach Listen. Call when an operation ends.
function HandleManager.StopListening()
	if connection then
		for _, c in ipairs(connection) do
			c:Disconnect()
		end
		connection = nil
	end
end

-- Destroy the active handle and stop listening.
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
