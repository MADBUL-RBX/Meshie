local Core       = require(script.Parent.Parent.Core)
local Operations = require(script.Parent.Parent.Core.Operations)

local Dissolve = {}

local armedEdgeId   = nil
local dissolveVerts = false
local savedBM       = nil

function Dissolve.Activate(handle)
	savedBM       = Operations.cloneBMesh(Core.bm)
	dissolveVerts = false
	armedEdgeId   = handle:GetAttribute("EdgeId")
end

function Dissolve.Commit()
	armedEdgeId   = nil
	dissolveVerts = false
	savedBM       = nil
end

function Dissolve.Cancel()
	if savedBM then
		Core.SetBMesh(savedBM)
	end
	armedEdgeId   = nil
	dissolveVerts = false
	savedBM       = nil
end

-- Apply is always a no-op for Dissolve — operation is performed by Execute().
function Dissolve.Apply(_handle)
	return false
end

function Dissolve.SetDissolveVerts(value)
	dissolveVerts = value
end

-- Perform the dissolve. Called by MPE from the operator panel action,
-- before Commit. Returns true if the dissolve succeeded.
function Dissolve.Execute()
	if not armedEdgeId then return false end
	local edge = Core.bm and Core.bm.edges[armedEdgeId]
	if not edge then return false end
	local result = Core.DissolveEdge(edge, dissolveVerts)
	return result ~= nil
end

return Dissolve
