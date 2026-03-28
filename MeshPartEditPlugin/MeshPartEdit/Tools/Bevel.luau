local BMesh      = require(script.Parent.Parent.Core.BMesh)
local Operations = require(script.Parent.Parent.Core.Operations)

local Bevel = {}

local savedBM       = nil
local startCF       = nil
local primaryAxis   = nil
local bevelKind     = nil
local bevelTargetId = nil

function Bevel.Activate(session, handle)
	savedBM       = nil
	startCF       = nil
	primaryAxis   = nil
	bevelKind     = nil
	bevelTargetId = nil

	if not session.bm then return end

	local pt = handle:GetAttribute("ProxyType")
	if pt == "Edge" then
		bevelKind     = "Edge"
		bevelTargetId = handle:GetAttribute("EdgeId")
	elseif pt == "Vertex" then
		bevelKind     = "Vertex"
		bevelTargetId = handle:GetAttribute("VertId")
	else
		return
	end

	local src = session.sourceMeshPart
	if bevelKind == "Edge" then
		local edge = session.bm.edges[bevelTargetId]
		if edge then
			primaryAxis = src.CFrame:VectorToWorldSpace(BMesh.edgeNormal(edge)).Unit
		end
	else
		local vert = session.bm.verts[bevelTargetId]
		if vert then
			primaryAxis = src.CFrame:VectorToWorldSpace(BMesh.vertNormal(vert)).Unit
		end
	end

	startCF = handle.CFrame
	savedBM = Operations.cloneBMesh(session.bm)
end

function Bevel.Commit(_session)
	savedBM       = nil
	startCF       = nil
	primaryAxis   = nil
	bevelKind     = nil
	bevelTargetId = nil
end

function Bevel.Cancel(session)
	if savedBM then
		session:SetBMesh(savedBM)  -- restores bm and rebuilds EM
	end
	savedBM       = nil
	startCF       = nil
	primaryAxis   = nil
	bevelKind     = nil
	bevelTargetId = nil
end

function Bevel.Apply(session, _handle, _oCF, _oSz, newCF, _nSz)
	if not savedBM or not bevelTargetId or not startCF or not primaryAxis then
		return false
	end

	local depth   = math.max(0, (newCF.Position - startCF.Position):Dot(primaryAxis))
	local freshBM = Operations.cloneBMesh(savedBM)

	if depth > 0 then
		if bevelKind == "Edge" then
			local edge = freshBM.edges[bevelTargetId]
			if edge then
				Operations.bevelEdge(freshBM, edge, depth)
			end
		elseif bevelKind == "Vertex" then
			local vert = freshBM.verts[bevelTargetId]
			if vert then
				Operations.bevelVertex(freshBM, vert, depth)
			end
		end
	end

	session:SetBMesh(freshBM)  -- replaces bm and rebuilds EM
	return true
end

return Bevel
