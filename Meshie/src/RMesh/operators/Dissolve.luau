local EulerOps = require(script.Parent.Parent.Core.EulerOps)

local Dissolve = {}
Dissolve.__index = Dissolve

function Dissolve.new()
	return setmetatable({}, Dissolve)
end

function Dissolve:Activate(rmesh, handle, _entries)
	self.savedBM       = EulerOps.cloneBMesh(rmesh.bm)
	self.dissolveVerts = false
	self.armedEdgeId   = handle:GetAttribute("ElementId")
end

function Dissolve:Commit()
end

function Dissolve:Cancel(rmesh)
	if self.savedBM then
		rmesh:SetBMesh(self.savedBM)
	end
end

-- Apply is a no-op for Dissolve — operation is performed by Execute().
function Dissolve:Apply(_rmesh, _handle)
	return false
end

function Dissolve:SetDissolveVerts(value)
	self.dissolveVerts = value
end

-- Perform the dissolve. Called by Editor before Commit.
function Dissolve:Execute(rmesh)
	if not self.armedEdgeId then return false end
	local edge = rmesh.bm and rmesh.bm.edges[self.armedEdgeId]
	if not edge then return false end
	local result = rmesh:DissolveEdge(edge, self.dissolveVerts)
	return result ~= nil
end

return Dissolve
