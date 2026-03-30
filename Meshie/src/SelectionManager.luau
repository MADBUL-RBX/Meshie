-- SelectionManager.luau
-- Owns game:GetService("Selection"). No other module should import it directly.
-- Dead simple wrapper — all proxy-selection logic lives in Editor.

local Selection = game:GetService("Selection")

local SelectionManager = {}

SelectionManager.Changed = Selection.SelectionChanged

function SelectionManager.Get()
	return Selection:Get()
end

function SelectionManager.Set(parts)
	Selection:Set(parts)
end

return SelectionManager
