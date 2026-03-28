-- History.luau
-- Owns all CHS logic for MPE.
--
-- History.Begin(session)               -- initial snapshot + ResetWaypoints at session start
-- History.StartRecording(name, session) -- snapshot BMesh + open recording
-- History.Commit(session)              -- push BMesh snapshot, ApplyMesh for CHS, close as Commit
-- History.Cancel()                     -- discard snapshot, close as Cancel
-- History.Restore(session, isRedo)     -- pop BMesh stack, SetBMesh to restore

local AssetService = game:GetService("AssetService")
local CHS = game:GetService("ChangeHistoryService")
local Operations = require(script.Parent.Core.Operations)

local History = {}

local activeId = nil
local pendingBM = nil
local undoStack = {}
local redoStack = {}

-- ─── Session start ────────────────────────────────────────────────────────────

-- Bake a static snapshot of the initial EM into sourceMeshPart.MeshContent so
-- CHS has a baseline to revert to, then wipe undo history and clear stacks.
function History.Begin(session)
	local ok, result, content = pcall(function()
		return AssetService:CreateDataModelContentAsync(Content.fromObject(session.em))
	end)
	if not ok then
		warn("[History] Begin snapshot failed:", result)
	end
	print("[History] Begin — snapshot ok:", ok)
	if ok and content ~= nil then
		local tempPart = AssetService:CreateMeshPartAsync(content)
		session.sourceMeshPart:ApplyMesh(tempPart)
	end
	CHS:ResetWaypoints()
	undoStack = {}
	redoStack = {}
end

-- ─── Operation lifecycle ──────────────────────────────────────────────────────

-- Snapshot BMesh before the operation touches anything, then open a recording.
function History.StartRecording(name, session)
	pendingBM = Operations.cloneBMesh(session.bm)
	activeId = CHS:TryBeginRecording(name)
	print("[History] StartRecording:", name, "→", activeId)
end

-- Push the pre-op BMesh snapshot onto the undo stack, clear redo, bake a static
-- snapshot into MeshContent for CHS to track, then close the recording.
function History.Commit(session)
	if pendingBM then
		table.insert(undoStack, pendingBM)
		pendingBM = nil
		redoStack = {}
		print("[History] Commit — undo depth:", #undoStack)
	end

	if not session.em or not session.sourceMeshPart then
		History.Cancel()
		return
	end

	local ok, result, content = pcall(function()
		return AssetService:CreateDataModelContentAsync(Content.fromObject(session.em))
	end)
	if not ok then
		warn("[History] CreateDataModelContentAsync failed:", result)
	end
	if ok and content ~= nil then
		local tempPart = AssetService:CreateMeshPartAsync(content)
		session.sourceMeshPart:ApplyMesh(tempPart)
	end

	if activeId then
		local op = (ok and content ~= nil)
			and Enum.FinishRecordingOperation.Commit
			or Enum.FinishRecordingOperation.Cancel
		print("[History] FinishRecording:", op)
		CHS:FinishRecording(activeId, op)
		activeId = nil
	end
end

-- Discard the pending snapshot and close the recording as Cancel.
function History.Cancel()
	pendingBM = nil
	if activeId then
		print("[History] Cancel recording")
		CHS:FinishRecording(activeId, Enum.FinishRecordingOperation.Cancel)
		activeId = nil
	end
end

-- ─── Undo / Redo ──────────────────────────────────────────────────────────────

-- Pop from the undo or redo stack, save current BMesh to the other stack,
-- and restore via SetBMesh. CHS is just the trigger — all state lives in BMesh.
function History.Restore(session, isRedo)
	local fromStack = isRedo and redoStack or undoStack
	local toStack = isRedo and undoStack or redoStack
	local label = isRedo and "Redo" or "Undo"

	if #fromStack == 0 then
		print("[History]", label, "— stack empty")
		return
	end

	table.insert(toStack, Operations.cloneBMesh(session.bm))
	local bm = table.remove(fromStack)
	print("[History]", label, "— restoring, remaining depth:", #fromStack)
	session:SetBMesh(bm)
end

return History
