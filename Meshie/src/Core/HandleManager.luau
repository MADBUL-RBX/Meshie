-- HandleManager.luau
-- Owns the single active handle and its CFrame/Size signal connections.
-- Studio-specific: creates handle Parts, listens to axis-drag changes.

local HandleManager = {}

local folder       = nil
local activeHandle = nil
local connection   = nil
local onChanged    = nil

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

-- Create the handle folder. Call at session start.
function HandleManager.Begin(parentFolder)
	if folder then folder:Destroy() end
	folder            = Instance.new("Folder")
	folder.Name       = "ToolHandles"
	folder.Archivable = false
	folder.Parent     = parentFolder or workspace
end

-- Set the callback fired on every handle CFrame/Size change.
function HandleManager.Init(callback)
	onChanged = callback
end

-- Destroy folder and active handle. Call at session end.
function HandleManager.Destroy()
	HandleManager.Clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

-- ─── Handle creation ──────────────────────────────────────────────────────────

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

-- ─── Listening ────────────────────────────────────────────────────────────────

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

-- ─── Clear ────────────────────────────────────────────────────────────────────

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

return HandleManager
