local RMesh    = require(script.Parent.Parent)
local EulerOps = require(script.Parent.Parent.Core.EulerOps)

local Dissolve = {}

local armedEdgeId   = nil
local dissolveVerts = false
local savedBM       = nil

function Dissolve.Activate(handle)
	savedBM       = EulerOps.cloneBMesh(RMesh.bm)
	dissolveVerts = false
	armedEdgeId   = handle:GetAttribute("ElementId")
end

function Dissolve.Commit()
	armedEdgeId   = nil
	dissolveVerts = false
	savedBM       = nil
end

function Dissolve.Cancel()
	if savedBM then
		RMesh.SetBMesh(savedBM)
	end
	armedEdgeId   = nil
	dissolveVerts = false
	savedBM       = nil
end

-- Apply is a no-op for Dissolve — operation is performed by Execute().
function Dissolve.Apply(_handle)
	return false
end

function Dissolve.SetDissolveVerts(value)
	dissolveVerts = value
end

-- Perform the dissolve. Called by Editor before Commit.
function Dissolve.Execute()
	if not armedEdgeId then return false end
	local edge = RMesh.bm and RMesh.bm.edges[armedEdgeId]
	if not edge then return false end
	local result = RMesh.DissolveEdge(edge, dissolveVerts)
	return result ~= nil
end

return Dissolve
