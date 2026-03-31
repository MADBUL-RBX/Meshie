local EulerOps = require(script.Parent.Parent.Core.EulerOps)

local Dissolve = {}

local armedEdgeId   = nil
local dissolveVerts = false
local savedBM       = nil

function Dissolve.Activate(rmesh, handle, _entries)
	savedBM       = EulerOps.cloneBMesh(rmesh.bm)
	dissolveVerts = false
	armedEdgeId   = handle:GetAttribute("ElementId")
end

function Dissolve.Commit()
	armedEdgeId   = nil
	dissolveVerts = false
	savedBM       = nil
end

function Dissolve.Cancel(rmesh)
	if savedBM then
		rmesh:SetBMesh(savedBM)
	end
	armedEdgeId   = nil
	dissolveVerts = false
	savedBM       = nil
end

-- Apply is a no-op for Dissolve — operation is performed by Execute().
function Dissolve.Apply(_rmesh, _handle)
	return false
end

function Dissolve.SetDissolveVerts(value)
	dissolveVerts = value
end

-- Perform the dissolve. Called by Editor before Commit.
function Dissolve.Execute(rmesh)
	if not armedEdgeId then return false end
	local edge = rmesh.bm and rmesh.bm.edges[armedEdgeId]
	if not edge then return false end
	local result = rmesh:DissolveEdge(edge, dissolveVerts)
	return result ~= nil
end

return Dissolve
