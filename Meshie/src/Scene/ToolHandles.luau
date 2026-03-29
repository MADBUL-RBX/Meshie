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

function ToolHandles.CreateHandle(proxy, handleName)
	if not folder or not proxy then return nil end
	proxy.Archivable = true
	local h = proxy:Clone()
	proxy.Archivable = false
	if not h then return nil end
	h.Name         = handleName or (proxy.Name .. "Handle")
	h.Transparency = 1
	h.Anchored     = true
	h.CanCollide   = false
	h.CanTouch     = false
	h.Archivable   = false
	h:SetAttribute("IsToolHandle", true)
	h.Parent       = folder
	return h
end

return ToolHandles
