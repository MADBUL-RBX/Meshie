local EulerOps = require(script.Parent.Parent.Core.EulerOps)

local Extrude = {}

local extrudeResult = nil
local savedBM       = nil
local startPos      = nil
local savedCapVerts = nil  -- { { vert = v, initialPos = v.position } }

function Extrude.Activate(rmesh, handle, _entries)
	extrudeResult = nil
	savedBM       = EulerOps.cloneBMesh(rmesh.bm)
	startPos      = handle.CFrame.Position
	savedCapVerts = nil
end

function Extrude.Commit()
	extrudeResult = nil
	savedBM       = nil
	startPos      = nil
	savedCapVerts = nil
end

function Extrude.Cancel(rmesh)
	if savedBM then
		rmesh:SetBMesh(savedBM)
	end
	extrudeResult = nil
	savedBM       = nil
	startPos      = nil
	savedCapVerts = nil
end

function Extrude.Apply(rmesh, handle)
	if not rmesh.bm then return false end

	if not extrudeResult then
		local fid  = handle:GetAttribute("ElementId")
		local face = fid and rmesh.bm.faces[fid]
		if not face then return false end

		extrudeResult = rmesh:ExtrudeFace(face)
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
	rmesh:ApplyTransformToVerts(savedCapVerts, worldDelta)
	return true
end

return Extrude
