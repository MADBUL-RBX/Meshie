local EulerOps = require(script.Parent.Parent.Core.EulerOps)

local Extrude = {}
Extrude.__index = Extrude

function Extrude.new()
	return setmetatable({}, Extrude)
end

function Extrude:Activate(rmesh, handle, _entries)
	self.extrudeResult = nil
	self.savedBM       = EulerOps.cloneBMesh(rmesh.bm)
	self.startCF       = handle.CFrame
	self.savedCapVerts = nil
end

function Extrude:Commit()
end

function Extrude:Cancel(rmesh)
	if self.savedBM then
		rmesh:SetBMesh(self.savedBM)
	end
end

function Extrude:Apply(rmesh, handle)
	if not rmesh.bm then return false end

	if not self.extrudeResult then
		local fid  = handle:GetAttribute("ElementId")
		local face = fid and rmesh.bm.faces[fid]
		if not face then return false end

		self.extrudeResult = rmesh:ExtrudeFace(face)
		if not self.extrudeResult then return false end

		self.savedCapVerts = {}
		for _, v in ipairs(self.extrudeResult.capVerts) do
			self.savedCapVerts[#self.savedCapVerts + 1] = { vert = v, initialPos = v.position }
		end

		-- Update handle to point at the new cap face
		handle:SetAttribute("ElementId", self.extrudeResult.capFace.id)
	end

	if not self.savedCapVerts or not self.startCF then return false end

	-- Extrude is translation-only: pass same Size for both to cancel scale
	local sz = handle.Size
	rmesh:ApplyTransformToVerts(self.savedCapVerts, self.startCF, sz, handle.CFrame, sz)
	return true
end

return Extrude
