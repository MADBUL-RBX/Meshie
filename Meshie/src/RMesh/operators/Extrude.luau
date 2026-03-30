local RMesh         = require(script.Parent.Parent)
local DataStructure = require(script.Parent.Parent.Core.DataStructure)

local Extrude = {}

local extrudeResult = nil
local savedBM       = nil
local startPos      = nil
local savedCapVerts = nil  -- { { vert = v, initialPos = v.position } }

local EulerOps = require(script.Parent.Parent.Core.EulerOps)

function Extrude.Activate(handle)
	extrudeResult = nil
	savedBM       = EulerOps.cloneBMesh(RMesh.bm)
	startPos      = handle.CFrame.Position
	savedCapVerts = nil
end

function Extrude.Commit()
	extrudeResult = nil
	savedBM       = nil
	startPos      = nil
	savedCapVerts = nil
end

function Extrude.Cancel()
	if savedBM then
		RMesh.SetBMesh(savedBM)
	end
	extrudeResult = nil
	savedBM       = nil
	startPos      = nil
	savedCapVerts = nil
end

function Extrude.Apply(handle)
	if not RMesh.bm then return false end

	if not extrudeResult then
		local fid  = handle:GetAttribute("ElementId")
		local face = fid and RMesh.bm.faces[fid]
		if not face then return false end

		extrudeResult = RMesh.ExtrudeFace(face)
		if not extrudeResult then return false end

		savedCapVerts = {}
		for _, v in ipairs(extrudeResult.capVerts) do
			savedCapVerts[#savedCapVerts + 1] = { vert = v, initialPos = v.position }
		end

		-- Update handle to point at the new cap face
		handle:SetAttribute("ElementId", extrudeResult.capFace.id)
	end

	if not savedCapVerts or not startPos then return false end

	local worldDelta = handle.CFrame.Position - startPos
	RMesh.ApplyTransformToVerts(savedCapVerts, worldDelta)
	return true
end

return Extrude
