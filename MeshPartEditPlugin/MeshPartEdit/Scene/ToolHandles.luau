local ToolHandles = {}

local folder = nil

function ToolHandles.Begin(parent)
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name       = "ToolHandles"
	folder.Parent     = parent
end

function ToolHandles.GetFolder()
	return folder
end

function ToolHandles.Clear()
	if not folder then return end
	for _, child in ipairs(folder:GetChildren()) do child:Destroy() end
end

function ToolHandles.Destroy()
	if folder then folder:Destroy(); folder = nil end
end

function ToolHandles.CreateHandle(name, cframe, size, color, material)
	if not folder then return nil end
	local h = Instance.new("Part")
	h.Name        = name
	h.Shape       = Enum.PartType.Block
	h.Size        = size
	h.Material    = material
	h.Color       = color
	h.Anchored    = true
	h.CanCollide  = false
	h.CanTouch    = false
	h.CFrame      = cframe
	h:SetAttribute("IsToolHandle", true)
	h.Archivable = false
	h.Parent = folder
	return h
end

function ToolHandles.CloneProxyHandle(proxy, handleName)
	if not folder or not proxy then return nil end
	local h = Instance.new("Part")
	h.Name        = handleName or (proxy.Name .. "Handle")
	h.Size        = proxy.Size
	h.CFrame      = proxy.CFrame
	h.Color       = proxy.Color
	h.Material    = proxy.Material
	h.Anchored    = true
	h.CanCollide  = false
	h.CanTouch    = false
	h.Archivable  = false
	h:SetAttribute("IsToolHandle", true)
	h.Parent = folder
	return h
end

return ToolHandles
