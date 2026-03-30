-- History.luau
-- Owns all CHS logic for the plugin.
--
-- History.Begin()               — initial snapshot + ResetWaypoints at session start
-- History.StartRecording(name)  — snapshot mesh + open CHS recording
-- History.Commit()              — push snapshot, ApplyMesh for CHS, close as Commit
-- History.Cancel()              — discard snapshot, close as Cancel
-- History.Restore(isRedo)       — pop mesh stack, SetBMesh to restore

local AssetService = game:GetService("AssetService")
local CHS          = game:GetService("ChangeHistoryService")

local RMesh    = require(script.Parent.Parent.RMesh)
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
	if undoConn then undoConn:Disconnect(); undoConn = nil end
	if redoConn then redoConn:Disconnect(); redoConn = nil end
end

-- ─── Session start ────────────────────────────────────────────────────────────

function History.Begin()
	local ok, result, content = pcall(function()
		return AssetService:CreateDataModelContentAsync(Content.fromObject(RMesh.em))
	end)
	if not ok then
		warn("[History] Begin snapshot failed:", result)
	end
	print("[History] Begin — snapshot ok:", ok)
	if ok and content ~= nil then
		local tempPart = AssetService:CreateMeshPartAsync(content)
		RMesh.ApplyMeshUpdate(tempPart)
	end
	CHS:ResetWaypoints()
	undoStack = {}
	redoStack = {}
end

-- ─── Operation lifecycle ──────────────────────────────────────────────────────

function History.StartRecording(name)
	pendingBM = EulerOps.cloneBMesh(RMesh.bm)
	activeId  = CHS:TryBeginRecording(name)
	print("[History] StartRecording:", name, "→", activeId)
end

function History.Commit()
	if pendingBM then
		table.insert(undoStack, pendingBM)
		pendingBM = nil
		redoStack = {}
		print("[History] Commit — undo depth:", #undoStack)
	end

	if not RMesh.em or not RMesh.sourceMeshPart then
		History.Cancel()
		return
	end

	local ok, result, content = pcall(function()
		return AssetService:CreateDataModelContentAsync(Content.fromObject(RMesh.em))
	end)
	if not ok then
		warn("[History] CreateDataModelContentAsync failed:", result)
	end
	if ok and content ~= nil then
		local tempPart = AssetService:CreateMeshPartAsync(content)
		RMesh.ApplyMeshUpdate(tempPart)
	end

	if activeId then
		local op = (ok and content ~= nil)
			and Enum.FinishRecordingOperation.Commit
			or  Enum.FinishRecordingOperation.Cancel
		print("[History] FinishRecording:", op)
		CHS:FinishRecording(activeId, op)
		activeId = nil
	end
end

function History.Cancel()
	pendingBM = nil
	if activeId then
		print("[History] Cancel recording")
		CHS:FinishRecording(activeId, Enum.FinishRecordingOperation.Cancel)
		activeId = nil
	end
end

-- ─── Undo / Redo ──────────────────────────────────────────────────────────────

function History.Restore(isRedo)
	local fromStack = isRedo and redoStack or undoStack
	local toStack   = isRedo and undoStack or redoStack
	local label     = isRedo and "Redo"    or "Undo"

	if #fromStack == 0 then
		print("[History]", label, "— stack empty")
		return
	end

	table.insert(toStack, EulerOps.cloneBMesh(RMesh.bm))
	local bm = table.remove(fromStack)
	print("[History]", label, "— restoring, remaining depth:", #fromStack)
	RMesh.SetBMesh(bm)
end

return History
