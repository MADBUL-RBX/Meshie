local Operations = require(script.Parent.Parent.Core.Operations)

local Dissolve = {}

local armedEdgeId   = nil
local dissolveVerts = false
local savedBM       = nil

function Dissolve.Activate(session, handle)
	savedBM       = Operations.cloneBMesh(session.bm)
	dissolveVerts = false
	armedEdgeId   = handle:GetAttribute("EdgeId")
end

function Dissolve.Commit(_session)
	armedEdgeId = nil
	dissolveVerts = false
	savedBM = nil
end

function Dissolve.Cancel(session)
	if savedBM then
		session:SetBMesh(savedBM)  -- restores bm and rebuilds EM
	end
	armedEdgeId = nil
	dissolveVerts = false
	savedBM = nil
end

-- Apply is always a no-op for Dissolve — operation is performed by Execute().
function Dissolve.Apply(_session, _handle, _oCF, _oSz, _nCF, _nSz)
	return false
end

function Dissolve.SetDissolveVerts(value)
	dissolveVerts = value
end

-- Perform the dissolve. Called by MPE from the operator panel action,
-- before Commit. Returns true if the dissolve succeeded.
function Dissolve.Execute(session)
	if not armedEdgeId then return false end
	local edge = session.bm and session.bm.edges[armedEdgeId]
	if not edge then return false end
	local result = session:DissolveEdge(edge, dissolveVerts)
	return result ~= nil
end

return Dissolve
