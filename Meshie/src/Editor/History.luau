-- History.luau
-- Owns all CHS logic for the plugin.
--
-- History.Begin(rmesh)               — initial snapshot + ResetWaypoints at session start
-- History.StartRecording(rmesh, name) — snapshot mesh + open CHS recording
-- History.Commit(rmesh)              — push snapshot, ApplyMesh for CHS, close as Commit
-- History.Cancel()                   — discard snapshot, close as Cancel
-- History.Restore(rmesh, isRedo)     — pop mesh stack, SetBMesh to restore

local CHS = game:GetService("ChangeHistoryService")

local EulerOps = require(script.Parent.Parent.RMesh.Core.EulerOps)

local History = {}

local activeId  = nil
local pendingBM = nil
local undoStack = {}
local redoStack = {}
local undoConn  = nil
local redoConn  = nil

-- ─── CHS event wiring ────────────────────────────────────────────────────────

function History.Listen(onUndo, onRedo)
	History.Unlisten()
	undoConn = CHS.OnUndo:Connect(onUndo)
	redoConn = CHS.OnRedo:Connect(onRedo)
end

function History.Unlisten()
	if undoConn then
		undoConn:Disconnect()
		undoConn = nil
	end
	if redoConn then
		redoConn:Disconnect()
		redoConn = nil
	end
end

-- ─── Session start ────────────────────────────────────────────────────────────

function History.Begin(rmesh)
	rmesh:ApplyMeshUpdate()
	CHS:ResetWaypoints()
	undoStack = {}
	redoStack = {}
end

-- ─── Operation lifecycle ──────────────────────────────────────────────────────

function History.StartRecording(rmesh, name)
	pendingBM = EulerOps.cloneBMesh(rmesh.bm)
	activeId  = CHS:TryBeginRecording(name)
end

function History.Commit(rmesh)
	if pendingBM then
		table.insert(undoStack, pendingBM)
		pendingBM = nil
		redoStack = {}
	end

	if not rmesh then
		History.Cancel()
		return
	end

	local ok = pcall(function() rmesh:ApplyMeshUpdate() end)

	if activeId then
		local op = ok
			and Enum.FinishRecordingOperation.Commit
			or  Enum.FinishRecordingOperation.Cancel
		CHS:FinishRecording(activeId, op)
		activeId = nil
	end
end

function History.Cancel()
	pendingBM = nil
	if activeId then
		CHS:FinishRecording(activeId, Enum.FinishRecordingOperation.Cancel)
		activeId = nil
	end
end

-- ─── Undo / Redo ──────────────────────────────────────────────────────────────

function History.Restore(rmesh, isRedo)
	local fromStack = isRedo and redoStack or undoStack
	local toStack   = isRedo and undoStack or redoStack

	if #fromStack == 0 then return end

	table.insert(toStack, EulerOps.cloneBMesh(rmesh.bm))
	local bm = table.remove(fromStack)
	rmesh:SetBMesh(bm)
end

return History
