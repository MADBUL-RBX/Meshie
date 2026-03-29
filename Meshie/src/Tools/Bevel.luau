local Operations       = require(script.Parent.Parent.Core.Operations)
local SelectionManager = require(script.Parent.Parent.Scene.SelectionManager)

local Bevel = {}

local savedBM   = nil
local startCF   = nil
local bevelAxis = nil  -- world-space axis along which the primary handle was dragged

local function normalFromHandle(handle)
	local x = handle:GetAttribute("NormalX")
	local y = handle:GetAttribute("NormalY")
	local z = handle:GetAttribute("NormalZ")
	if x and y and z then
		local v = Vector3.new(x, y, z)
		if v.Magnitude > 1e-5 then return v.Unit end
	end
	return handle.CFrame.UpVector
end

function Bevel.Activate(session, handle)
	savedBM   = nil
	startCF   = nil
	bevelAxis = nil

	if not session.bm then return end

	local pt = handle:GetAttribute("ProxyType")
	if pt ~= "Edge" and pt ~= "Vertex" then return end

	bevelAxis = normalFromHandle(handle)
	startCF   = handle.CFrame
	savedBM   = Operations.cloneBMesh(session.bm)
end

function Bevel.Commit(_session)
	savedBM   = nil
	startCF   = nil
	bevelAxis = nil
end

function Bevel.Cancel(session)
	if savedBM then
		session:SetBMesh(savedBM)
	end
	savedBM   = nil
	startCF   = nil
	bevelAxis = nil
end

function Bevel.Apply(session, _handle, _oCF, _oSz, newCF, _nSz)
	if not savedBM or not startCF or not bevelAxis then
		return false
	end

	local depth   = math.max(0, (newCF.Position - startCF.Position):Dot(bevelAxis))
	local freshBM = Operations.cloneBMesh(savedBM)

	if depth > 0 then
		for _, entry in ipairs(SelectionManager.GetAll()) do
			if entry.proxyType == "Edge" then
				local edge = freshBM.edges[entry.id]
				if edge then
					Operations.bevelEdge(freshBM, edge, depth)
				end
			elseif entry.proxyType == "Vertex" then
				local vert = freshBM.verts[entry.id]
				if vert then
					Operations.bevelVertex(freshBM, vert, depth)
				end
			end
		end
	end

	session:SetBMesh(freshBM)
	return true
end

return Bevel
