local BMesh            = require(script.Parent.Parent.Core.BMesh)
local SelectionManager = require(script.Parent.Parent.Scene.SelectionManager)

local Transform = {}

function Transform.Activate(_session, _handle) end
function Transform.Commit(_session)             end
function Transform.Cancel(_session)             end  -- CHS reverts EM; no state to restore

function Transform.Apply(session, _handle, oldCF, oldSz, newCF, newSz)
	if not session.bm then return false end

	local verts = {}
	local seen  = {}

	local function addVert(v)
		if v and not seen[v.id] then
			seen[v.id]        = true
			verts[#verts + 1] = v
		end
	end

	for _, entry in ipairs(SelectionManager.GetAll()) do
		if entry.proxyType == "Vertex" then
			addVert(session.bm.verts[entry.id])
		elseif entry.proxyType == "Edge" then
			local e = session.bm.edges[entry.id]
			if e then
				addVert(e.v1)
				addVert(e.v2)
			end
		elseif entry.proxyType == "Face" then
			local f = session.bm.faces[entry.id]
			if f then
				for _, v in ipairs(BMesh.faceVerts(f)) do
					addVert(v)
				end
			end
		end
	end

	if #verts == 0 then return false end

	session:ApplyTransformToVerts(verts, oldCF, oldSz, newCF, newSz)
	return true
end

return Transform
