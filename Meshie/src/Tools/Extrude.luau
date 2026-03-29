local Core       = require(script.Parent.Parent.Core)
local BMesh      = require(script.Parent.Parent.Core.BMesh)
local Operations = require(script.Parent.Parent.Core.Operations)

local Extrude = {}

local extrudeResult = nil
local savedBM       = nil
local startPos      = nil
local savedCapVerts = nil  -- { { vert = v, initialPos = v.position } }

function Extrude.Activate(handle)
	extrudeResult = nil
	savedBM       = Operations.cloneBMesh(Core.bm)
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
		Core.SetBMesh(savedBM)
	end
	extrudeResult = nil
	savedBM       = nil
	startPos      = nil
	savedCapVerts = nil
end

function Extrude.Apply(handle)
	if not Core.bm then return false end

	if not extrudeResult then
		local fid  = handle:GetAttribute("FaceId")
		local face = fid and Core.bm.faces[fid]
		if not face then return false end

		extrudeResult = Core.ExtrudeFace(face)
		if not extrudeResult then return false end

		savedCapVerts = {}
		for _, v in ipairs(extrudeResult.capVerts) do
			savedCapVerts[#savedCapVerts + 1] = { vert = v, initialPos = v.position }
		end

		local capVerts = BMesh.faceVerts(extrudeResult.capFace)
		handle:SetAttribute("FaceId",    extrudeResult.capFace.id)
		handle:SetAttribute("VertCount", #capVerts)
		for i, v in ipairs(capVerts) do
			handle:SetAttribute("VertId" .. i, v.id)
		end
	end

	if not savedCapVerts or not startPos then return false end

	local worldDelta = handle.CFrame.Position - startPos
	Core.ApplyTransformToVerts(savedCapVerts, worldDelta)
	return true
end

return Extrude
