local BMesh      = require(script.Parent.Parent.Core.BMesh)
local Operations = require(script.Parent.Parent.Core.Operations)

local Extrude = {}

local extrudeResult = nil
local savedBM       = nil

function Extrude.Activate(session, _handle)
	extrudeResult = nil
	savedBM       = Operations.cloneBMesh(session.bm)
end

function Extrude.Commit(_session)
	extrudeResult = nil
	savedBM       = nil
end

function Extrude.Cancel(session)
	if savedBM then
		session:SetBMesh(savedBM)  -- restores bm and rebuilds EM
	end
	extrudeResult = nil
	savedBM       = nil
end

function Extrude.Apply(session, handle, oldCF, oldSz, newCF, newSz)
	if not session.bm then return false end

	if not extrudeResult then
		local fid  = handle:GetAttribute("FaceId")
		local face = fid and session.bm.faces[fid]
		if not face then return false end

		-- ExtrudeFace mutates bm and rebuilds EM, refreshing all emIds
		extrudeResult = session:ExtrudeFace(face)
		if not extrudeResult then return false end

		-- Update handle attributes to point at the new cap face
		local capVerts = BMesh.faceVerts(extrudeResult.capFace)
		handle:SetAttribute("FaceId",    extrudeResult.capFace.id)
		handle:SetAttribute("VertCount", #capVerts)
		for i, v in ipairs(capVerts) do
			handle:SetAttribute("VertId" .. i, v.id)
		end
	end

	-- Move cap verts live via SetPosition
	session:ApplyTransformToVerts(extrudeResult.capVerts, oldCF, oldSz, newCF, newSz)
	return true
end

return Extrude
