-- RibbonToolManager.luau
-- Constrains the Studio ribbon tool to the valid set for the active operation.
-- Polls via RenderStepped — there is no native RibbonTool.Changed event.
-- On Stop(), restores the ribbon tool the user had before the operation began.
--
-- Idle() keeps Enum.RibbonTool.None active while in SELECT_MODE so the native
-- Select tool doesn't interfere with Meshie's custom EM raycast picking.
--
-- Init(plugin) must be called from Loader.plugin.luau, the only script where
-- the plugin global is available without explicit passing.

local RunService = game:GetService("RunService")

local RibbonToolManager = {}

local plugin     = nil
local validTools = nil
local lastValid  = nil
local previous   = nil
local pollConn   = nil
local idleConn   = nil

function RibbonToolManager.Init(p)
	plugin = p
end

-- Keep Enum.RibbonTool.None active while in SELECT_MODE.
-- Polls to snap back if Studio switches away (e.g. user clicks a toolbar button).
function RibbonToolManager.Idle()
	RibbonToolManager.StopIdle()
	if not plugin then return end

	plugin:SelectRibbonTool(Enum.RibbonTool.None, UDim2.new())

	idleConn = RunService.RenderStepped:Connect(function()
		if plugin:GetSelectedRibbonTool() ~= Enum.RibbonTool.None then
			plugin:SelectRibbonTool(Enum.RibbonTool.None, UDim2.new())
		end
	end)
end

function RibbonToolManager.StopIdle()
	if idleConn then
		idleConn:Disconnect()
		idleConn = nil
	end
end

-- Begin constraining to a set of valid ribbon tools.
-- Immediately switches to the first valid tool and starts polling.
-- Pass an empty table for operations with no ribbon interaction (e.g. Dissolve).
function RibbonToolManager.Begin(tools)
	RibbonToolManager.Stop()
	if not plugin or not tools or #tools == 0 then
		return
	end

	validTools = tools
	previous   = plugin:GetSelectedRibbonTool()
	lastValid  = tools[1]

	plugin:SelectRibbonTool(lastValid, UDim2.new())

	-- Defer poll start by one frame so Studio processes the initial tool switch
	-- before we begin checking — avoids a stutter from the first poll firing early.
	task.defer(function()
		if not validTools then return end
		pollConn = RunService.RenderStepped:Connect(function()
			local current = plugin:GetSelectedRibbonTool()
			for _, t in ipairs(validTools) do
				if current == t then
					lastValid = current
					return
				end
			end
			plugin:SelectRibbonTool(lastValid, UDim2.new())
		end)
	end)
end

-- Stop constraining and restore the ribbon tool from before the operation.
function RibbonToolManager.Stop()
	if pollConn then
		pollConn:Disconnect()
		pollConn = nil
	end
	if plugin and previous then
		plugin:SelectRibbonTool(previous, UDim2.new())
	end
	validTools = nil
	lastValid  = nil
	previous   = nil
end

return RibbonToolManager
