-- GeometryMode.luau
-- Tracks the current geometry selection mode: Vertex, Edge, or Face.
-- Module-level singleton — one mode for the whole plugin, no instance needed.

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

return GeometryMode
