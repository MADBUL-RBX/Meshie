local EulerOps = require(script.Parent.Parent.Core.EulerOps)

local Inset = {}
Inset.__index = Inset

function Inset.new()
	return setmetatable({}, Inset)
end

function Inset:Activate(rmesh, handle, _entries)
	self.extrudeResult = nil
	self.savedBM       = EulerOps.cloneBMesh(rmesh.bm)
	self.startCF       = handle.CFrame
	self.startSz       = handle.Size
	self.savedCapVerts  = nil
end

function Inset:Commit()
end

function Inset:Cancel(rmesh)
	if self.savedBM then
		rmesh:SetBMesh(self.savedBM)
	end
end

function Inset:Apply(rmesh, handle)
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

		handle:SetAttribute("ElementId", self.extrudeResult.capFace.id)
	end

	if not self.savedCapVerts or not self.startCF then return false end

	-- Scale only: pass same CFrame for old and new so translation cancels out.
	-- Size change from the Scale ribbon tool drives the inset depth.
	rmesh:ApplyTransformToVerts(self.savedCapVerts, self.startCF, self.startSz, self.startCF, handle.Size)
	return true
end

return Inset
