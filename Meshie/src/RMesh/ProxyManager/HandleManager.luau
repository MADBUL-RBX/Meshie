-- HandleManager.luau
-- Owns the single active handle and its CFrame/Size signal connections.
-- Absorbs ToolHandles — all handle Instance management lives here.

local HandleManager = {}

local folder      = nil
local activeHandle = nil
local connection  = nil
local onChanged   = nil

-- ─── Handle folder ────────────────────────────────────────────────────────────

function HandleManager.Begin(parent)
	if folder then folder:Destroy() end
	folder        = Instance.new("Folder")
	folder.Name   = "ToolHandles"
	folder.Parent = parent
end

function HandleManager.DestroyFolder()
	if folder then folder:Destroy(); folder = nil end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function HandleManager.Init(callback)
	onChanged = callback
end

-- Create a handle from a proxy Part.
-- elementType ("Vertex"/"Edge"/"Face") is stamped on the handle for operators.
function HandleManager.Arm(proxy, elementType)
	HandleManager.Clear()
	if not folder or not proxy then return nil end

	proxy.Archivable = true
	local handle = proxy:Clone()
	proxy.Archivable = false
	if not handle then return nil end

	handle.Name         = proxy.Name .. "Handle"
	handle.Transparency = 1
	handle.Anchored     = true
	handle.CanCollide   = false
	handle.CanTouch     = false
	handle.Archivable   = false
	handle:SetAttribute("IsToolHandle", true)
	handle:SetAttribute("ElementId",    proxy:GetAttribute("ElementId"))
	handle:SetAttribute("ElementType",  elementType)
	handle.Parent = folder

	activeHandle = handle
	return handle
end

function HandleManager.BeginListening()
	if not activeHandle then return end
	HandleManager.StopListening()

	local function fire()
		if onChanged then onChanged(activeHandle) end
	end

	connection = {
		activeHandle:GetPropertyChangedSignal("CFrame"):Connect(fire),
		activeHandle:GetPropertyChangedSignal("Size"):Connect(fire),
	}
end

function HandleManager.StopListening()
	if connection then
		for _, c in ipairs(connection) do c:Disconnect() end
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
