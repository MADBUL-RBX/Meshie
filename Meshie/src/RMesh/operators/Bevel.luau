local RMesh    = require(script.Parent.Parent)
local EulerOps = require(script.Parent.Parent.Core.EulerOps)

local Bevel = {}

local savedBM      = nil
local startPos     = nil
local savedEntries = nil  -- { { type, id } } snapshot from Activate

-- entries: { { type, id, part } } — snapshot of selected elements at activate time.
function Bevel.Activate(handle, entries)
	savedBM      = nil
	startPos     = nil
	savedEntries = nil

	if not RMesh.bm then return end

	local pt = handle:GetAttribute("ElementType")
	if pt ~= "Edge" and pt ~= "Vertex" then return end

	startPos     = handle.CFrame.Position
	savedBM      = EulerOps.cloneBMesh(RMesh.bm)
	savedEntries = entries
end

function Bevel.Commit()
	savedBM      = nil
	startPos     = nil
	savedEntries = nil
end

function Bevel.Cancel()
	if savedBM then
		RMesh.SetBMesh(savedBM)
	end
	savedBM      = nil
	startPos     = nil
	savedEntries = nil
end

function Bevel.Apply(handle)
	if not savedBM or not startPos or not savedEntries then return false end

	local depth   = (handle.CFrame.Position - startPos).Magnitude
	local freshBM = EulerOps.cloneBMesh(savedBM)

	if depth > 0 then
		for _, entry in ipairs(savedEntries) do
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

	RMesh.SetBMesh(freshBM)
	return true
end

return Bevel
