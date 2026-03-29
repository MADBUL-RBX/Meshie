local Core             = require(script.Parent.Parent.Core)
local Operations       = require(script.Parent.Parent.Core.Operations)
local SelectionManager = require(script.Parent.Parent.Scene.SelectionManager)

local Bevel = {}

local savedBM  = nil
local startPos = nil

function Bevel.Activate(handle)
	savedBM  = nil
	startPos = nil

	if not Core.bm then return end

	local pt = handle:GetAttribute("ProxyType")
	if pt ~= "Edge" and pt ~= "Vertex" then return end

	startPos = handle.CFrame.Position
	savedBM  = Operations.cloneBMesh(Core.bm)
end

function Bevel.Commit()
	savedBM  = nil
	startPos = nil
end

function Bevel.Cancel()
	if savedBM then
		Core.SetBMesh(savedBM)
	end
	savedBM  = nil
	startPos = nil
end

function Bevel.Apply(handle)
	if not savedBM or not startPos then return false end

	local depth   = (handle.CFrame.Position - startPos).Magnitude
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

	Core.SetBMesh(freshBM)
	return true
end

return Bevel
