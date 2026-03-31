local EulerOps = require(script.Parent.Parent.Core.EulerOps)

local Bevel = {}
Bevel.__index = Bevel

function Bevel.new()
	return setmetatable({}, Bevel)
end

-- entries: { { type, id, part } } — snapshot of selected elements at activate time.
function Bevel:Activate(rmesh, handle, entries)
	if not rmesh.bm then return end

	local pt = handle:GetAttribute("ElementType")
	if pt ~= "Edge" and pt ~= "Vertex" then return end

	self.startPos     = handle.CFrame.Position
	self.savedBM      = EulerOps.cloneBMesh(rmesh.bm)
	self.savedEntries = entries
end

function Bevel:Commit()
end

function Bevel:Cancel(rmesh)
	if self.savedBM then
		rmesh:SetBMesh(self.savedBM)
	end
end

function Bevel:Apply(rmesh, handle)
	if not self.savedBM or not self.startPos or not self.savedEntries then return false end

	local depth   = (handle.CFrame.Position - self.startPos).Magnitude
	local freshBM = EulerOps.cloneBMesh(self.savedBM)

	if depth > 0 then
		for _, entry in ipairs(self.savedEntries) do
			if entry.type == "Edge" then
				local edge = freshBM.edges[entry.id]
				if edge then
					EulerOps.bevelEdge(freshBM, edge, depth)
				end
			elseif entry.type == "Vertex" then
				local vert = freshBM.verts[entry.id]
				if vert then
					EulerOps.bevelVertex(freshBM, vert, depth)
				end
			end
		end
	end

	rmesh:SetBMesh(freshBM)
	return true
end

return Bevel
