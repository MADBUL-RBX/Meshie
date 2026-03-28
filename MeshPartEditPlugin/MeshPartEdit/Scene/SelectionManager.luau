-- SelectionManager.luau
-- Tracks the ordered list of selected proxies by their identifying attributes,
-- not by Part reference (which becomes stale after SyncAll rebuilds proxies).

local SelectionManager = {}

-- Each entry: { proxyType, id, name }
-- proxyType: "Vertex" | "Edge" | "Face"
-- id: the VertId, EdgeId, or FaceId
-- name: the proxy Part name (e.g. "Vertex_3") for lookup
local orderedEntries = {}
local entrySet       = {}  -- keyed by proxy name for O(1) duplicate check

local function entryFromProxy(proxy)
	local pt   = proxy:GetAttribute("ProxyType")
	local name = proxy.Name
	local id   = nil
	if pt == "Vertex" then
		id = proxy:GetAttribute("VertId")
	elseif pt == "Edge" then
		id = proxy:GetAttribute("EdgeId")
	elseif pt == "Face" then
		id = proxy:GetAttribute("FaceId")
	end
	if not pt or not id then return nil end
	return { proxyType = pt, id = id, name = name }
end

function SelectionManager.Add(proxy)
	if entrySet[proxy.Name] then return end
	local entry = entryFromProxy(proxy)
	if not entry then return end
	orderedEntries[#orderedEntries + 1] = entry
	entrySet[proxy.Name] = entry
end

function SelectionManager.GetLast()
	return orderedEntries[#orderedEntries]
end

function SelectionManager.GetAll()
	return orderedEntries
end

function SelectionManager.HasSelection()
	return #orderedEntries > 0
end

function SelectionManager.Count()
	return #orderedEntries
end

function SelectionManager.Clear()
	orderedEntries = {}
	entrySet       = {}
end

return SelectionManager
