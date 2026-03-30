-- GeometryMode.luau
-- Tracks the current geometry selection mode: Vertex, Edge, or Face.
-- ProxyManager reads this to set proxy Locked/Transparency states.

local GeometryMode = {}

local MODES = { Vertex = true, Edge = true, Face = true }
local current = "Vertex"

function GeometryMode.Set(mode)
	if not MODES[mode] then return end
	current = mode
end

function GeometryMode.Get()
	return current
end

function GeometryMode.IsVertex() return current == "Vertex" end
function GeometryMode.IsEdge()   return current == "Edge"   end
function GeometryMode.IsFace()   return current == "Face"   end

return GeometryMode
