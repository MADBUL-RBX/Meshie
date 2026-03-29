local BMesh      = require(script.Parent.Parent.Core.BMesh)
local Operations = require(script.Parent.Parent.Core.Operations)

local Extrude = {}

local extrudeResult  = nil
local savedBM        = nil
local startPos       = nil
local savedCapVerts  = nil  -- { { vert = v, initialPos = v.position } }

function Extrude.Activate(session, handle)
	extrudeResult = nil
	savedBM       = Operations.cloneBMesh(session.bm)
	startPos      = handle.CFrame.Position
	savedCapVerts = nil
end

function Extrude.Commit(_session)
	extrudeResult = nil
	savedBM       = nil
	startPos      = nil
	savedCapVerts = nil
end

function Extrude.Cancel(session)
	if savedBM then
		session:SetBMesh(savedBM)
	end
	extrudeResult = nil
	savedBM       = nil
	startPos      = nil
	savedCapVerts = nil
end

function Extrude.Apply(session, handle)
	if not session.bm then return false end

	if not extrudeResult then
		local fid  = handle:GetAttribute("FaceId")
		local face = fid and session.bm.faces[fid]
		if not face then return false end

		extrudeResult = session:ExtrudeFace(face)
		if not extrudeResult then return false end

		-- Snapshot cap vert initial positions (at the original face location)
		savedCapVerts = {}
		for _, v in ipairs(extrudeResult.capVerts) do
			savedCapVerts[#savedCapVerts + 1] = { vert = v, initialPos = v.position }
		end

		-- Update handle attributes to point at the new cap face
		local capVerts = BMesh.faceVerts(extrudeResult.capFace)
		handle:SetAttribute("FaceId",    extrudeResult.capFace.id)
		handle:SetAttribute("VertCount", #capVerts)
		for i, v in ipairs(capVerts) do
			handle:SetAttribute("VertId" .. i, v.id)
		end
	end

	if not savedCapVerts or not startPos then return false end

	local worldDelta = handle.CFrame.Position - startPos
	session:ApplyTransformToVerts(savedCapVerts, worldDelta)
	return true
end

return Extrude
