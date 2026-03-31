local Transform = {}
Transform.__index = Transform

function Transform.new()
	return setmetatable({}, Transform)
end

-- entries: { { type, id, part } } — snapshot of selected elements at activate time.
function Transform:Activate(rmesh, handle, entries)
	self.startPos   = handle.CFrame.Position
	self.savedVerts = {}
	local seen = {}

	local function addVert(v)
		if v and not seen[v.id] then
			seen[v.id]                        = true
			self.savedVerts[#self.savedVerts + 1] = { vert = v, initialPos = v.position }
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

function Transform:Commit()
end

function Transform:Cancel(rmesh)
	if self.savedVerts and rmesh.bm and rmesh.em then
		for _, entry in ipairs(self.savedVerts) do
			entry.vert.position = entry.initialPos
			if entry.vert.emId then
				rmesh.em:SetPosition(entry.vert.emId, entry.initialPos)
			end
		end
	end
end

function Transform:Apply(rmesh, handle)
	if not self.startPos or not self.savedVerts or #self.savedVerts == 0 then return false end
	local worldDelta = handle.CFrame.Position - self.startPos
	rmesh:ApplyTransformToVerts(self.savedVerts, worldDelta)
	return true
end

return Transform
