local RMesh         = require(script.Parent.Parent)
local DataStructure = require(script.Parent.Parent.Core.DataStructure)

local Transform = {}

local startPos   = nil
local savedVerts = nil  -- { { vert = v, initialPos = v.position } }

-- entries: { { type, id, part } } — snapshot of selected elements at activate time.
function Transform.Activate(handle, entries)
	startPos   = handle.CFrame.Position
	savedVerts = {}
	local seen = {}

	local function addVert(v)
		if v and not seen[v.id] then
			seen[v.id]                  = true
			savedVerts[#savedVerts + 1] = { vert = v, initialPos = v.position }
		end
	end

	for _, entry in ipairs(entries) do
		if entry.type == "Vertex" then
			addVert(RMesh.bm.verts[entry.id])
		elseif entry.type == "Edge" then
			local e = RMesh.bm.edges[entry.id]
			if e then addVert(e.v1); addVert(e.v2) end
		elseif entry.type == "Face" then
			local f = RMesh.bm.faces[entry.id]
			if f then
				for _, v in ipairs(DataStructure.faceVerts(f)) do addVert(v) end
			end
		end
	end
end

function Transform.Commit()
	startPos   = nil
	savedVerts = nil
end

function Transform.Cancel()
	if savedVerts and RMesh.bm and RMesh.em then
		for _, entry in ipairs(savedVerts) do
			entry.vert.position = entry.initialPos
			if entry.vert.emId then
				RMesh.em:SetPosition(entry.vert.emId, entry.initialPos)
			end
		end
	end
	startPos   = nil
	savedVerts = nil
end

function Transform.Apply(handle)
	if not startPos or not savedVerts or #savedVerts == 0 then return false end
	local worldDelta = handle.CFrame.Position - startPos
	RMesh.ApplyTransformToVerts(savedVerts, worldDelta)
	return true
end

return Transform
