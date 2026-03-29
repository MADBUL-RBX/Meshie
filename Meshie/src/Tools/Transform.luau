local Core             = require(script.Parent.Parent.Core)
local BMesh            = require(script.Parent.Parent.Core.BMesh)
local SelectionManager = require(script.Parent.Parent.Scene.SelectionManager)

local Transform = {}

local startPos   = nil
local savedVerts = nil  -- { { vert = v, initialPos = v.position } }

function Transform.Activate(handle)
	startPos   = handle.CFrame.Position
	savedVerts = {}
	local seen = {}

	local function addVert(v)
		if v and not seen[v.id] then
			seen[v.id]                  = true
			savedVerts[#savedVerts + 1] = { vert = v, initialPos = v.position }
		end
	end

	for _, entry in ipairs(SelectionManager.GetAll()) do
		if entry.proxyType == "Vertex" then
			addVert(Core.bm.verts[entry.id])
		elseif entry.proxyType == "Edge" then
			local e = Core.bm.edges[entry.id]
			if e then
				addVert(e.v1)
				addVert(e.v2)
			end
		elseif entry.proxyType == "Face" then
			local f = Core.bm.faces[entry.id]
			if f then
				for _, v in ipairs(BMesh.faceVerts(f)) do
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

function Transform.Cancel()
	if savedVerts and Core.bm and Core.em then
		for _, entry in ipairs(savedVerts) do
			entry.vert.position = entry.initialPos
			if entry.vert.emId then
				Core.em:SetPosition(entry.vert.emId, entry.initialPos)
			end
		end
	end
	startPos   = nil
	savedVerts = nil
end

function Transform.Apply(handle)
	if not startPos or not savedVerts or #savedVerts == 0 then return false end
	local worldDelta = handle.CFrame.Position - startPos
	Core.ApplyTransformToVerts(savedVerts, worldDelta)
	return true
end

return Transform
