local Transform = {}

local startPos   = nil
local savedVerts = nil  -- { { vert = v, initialPos = v.position } }

-- entries: { { type, id, part } } — snapshot of selected elements at activate time.
function Transform.Activate(rmesh, handle, entries)
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
			addVert(rmesh.bm.verts[entry.id])
		elseif entry.type == "Edge" then
			local e = rmesh.bm.edges[entry.id]
			if e then
				addVert(e.v1)
				addVert(e.v2)
			end
		elseif entry.type == "Face" then
			local f = rmesh.bm.faces[entry.id]
			if f then
				for _, v in ipairs(rmesh.bm:faceVerts(f)) do
					addVert(v)
				end
			end
		end
	end
end

function Transform.Commit()
	startPos   = nil
	savedVerts = nil
end

function Transform.Cancel(rmesh)
	if savedVerts and rmesh.bm and rmesh.em then
		for _, entry in ipairs(savedVerts) do
			entry.vert.position = entry.initialPos
			if entry.vert.emId then
				rmesh.em:SetPosition(entry.vert.emId, entry.initialPos)
			end
		end
	end
	startPos   = nil
	savedVerts = nil
end

function Transform.Apply(rmesh, handle)
	if not startPos or not savedVerts or #savedVerts == 0 then return false end
	local worldDelta = handle.CFrame.Position - startPos
	rmesh:ApplyTransformToVerts(savedVerts, worldDelta)
	return true
end

return Transform
