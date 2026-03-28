# MPE Clean-Slate Architecture

This document is the authoritative design spec for the CV25 refactor.
Implement against this. Do not deviate without updating this document first.

---

## Core Principles

1. **EM is the CHS-tracked authority.** Every mutation to EM (`SetPosition`,
   `RemoveFace`, `AddTriangle`, etc.) is visible to Roblox's ChangeHistoryService.
   BMesh and proxies are not in the DataModel — CHS cannot see them.

2. **BMesh is a read/filter layer over EM.** It interprets EM's flat triangle
   soup into N-gon faces and logical edges. It is always derivable from EM via
   `MeshIO.fromEditableMesh`. It is never authoritative — EM is.

3. **The data arrow is strictly one direction:**
   ```
   EM → BMesh → Proxies
   ```
   Operations compute in BMesh space (N-gon logic lives there), then write the
   result back to EM. The arrow never reverses. EM is always the ground truth.

4. **MPE is the only coordinator.** It owns the session, the CHS recording
   lifecycle, and every call to `EditScene.RebuildProxies`. No tool, no scene
   module, nothing else triggers a proxy rebuild.

5. **Tools are pure computation.** They receive the session and selection as
   parameters. They mutate `session.bm` and write to `session.em` via session
   methods. They never call `EditScene` directly. Ever.

6. **One session object at a time.** MPE creates it on `beginSession`, destroys
   it on `endSession`. It is passed explicitly where needed — no module-level
   singletons for session state.

---

## Module Map

```
Core/
  BMesh.luau          -- Half-edge N-gon structure. Pure computation. No EM, no session.
  MeshIO.luau         -- fromEditableMesh(em) → bm. Reads EM, interprets as N-gons.
                         Runs dissolvePlanar to merge coplanar triangles. One direction only.
  Operations.luau     -- Pure BMesh mutations: extrude, bevel, dissolve, clone. No EM.
  MeshSession.luau    -- Session object factory. new(meshPart) → session.
                         Owns em, bm, sourceMeshPart. All EM writes go here.

Scene/
  EditScene.luau      -- Proxy Part management. Receives bm + coordinate data.
                         Never pulls from MeshSession globals.
  HandleManager.luau  -- Owns single active handle + Listen connection.
                         Fires onChange callback to MPE. No other logic.
  SelectionManager.luau -- Tracks selected proxies by attribute. Session-scoped singleton.
  GeometryMode.luau   -- Vertex / Edge / Face mode. Session-scoped singleton.
  ToolHandles.luau    -- Creates/clones handle Parts. Archivable=false on handles.

Tools/
  Transform.luau      -- Moves verts. Pure computation. No EditScene calls.
  Extrude.luau        -- Extrudes faces. Pure computation. No EditScene calls.
  Bevel.luau          -- Bevels edges/verts. Snapshot/restore in BMesh scratchpad.
  Dissolve.luau       -- Dissolves edges. Has Execute() separate from Apply().

UI/
  Hud.luau / Factory.luau / UIConfig.luau  -- Unchanged from CV24.

MPE.luau              -- Single coordinator. Owns session, CHS lifecycle, proxy rebuild.
PluginMain.plugin.luau / Hotkeys.luau / Listen.luau / UserConfig.luau  -- Unchanged.
```

---

## MeshSession Interface

`MeshSession` is a factory module. It returns session objects, not a singleton.

```lua
-- Factory
MeshSession.new(meshPart) → session | nil

-- Session fields (read-only from outside)
session.bm             -- current BMesh (set internally, readable externally)
session.em             -- EditableMesh (readable, but only session writes to it)
session.sourceMeshPart -- the original MeshPart

-- Lifecycle
session:IsActive() → bool
session:Finalize()           -- CreateMeshPartAsync + ApplyMesh + restoreSource
session:Destroy()            -- nil em (GC), restoreSource

-- EM ↔ BMesh sync
session:SyncFromEM()         -- rebuild bm from em. Called after CHS undo/redo.
session:RebuildEM()          -- write bm → em. Called internally after topology ops.
                             -- Full rebuild: RemoveFace all → RemoveUnused → AddVertex → AddTriangle

-- Coordinate transforms
session:LocalToWorld(localPos) → worldPos
session:WorldToLocal(worldPos) → localPos

-- EM mutation helpers (all EM writes go through these)
session:ApplyTransformToVerts(verts, oldCF, oldSz, newCF, newSz)
    -- Updates bm vert positions AND calls em:SetPosition live. No rebuildEM.

session:ExtrudeFace(face) → result | nil
    -- Operations.extrudeFace(bm, face) then RebuildEM().

session:DissolveEdge(edge, dissolveVerts) → result | nil
    -- Operations.dissolveEdge(bm, edge, dissolveVerts) then RebuildEM().

session:SetFaceStyle(face, color, transparency)
    -- Mutates bm face data only. rebuildEM writes colors to EM on next rebuild.

-- For Bevel scratchpad pattern (see Bevel lifecycle below)
session:SetBMesh(newBM)
    -- Replace bm and call RebuildEM(). Used by Bevel Apply and Cancel.
```

**Construction notes:**
- `new()` calls `CreateEditableMeshAsync` (FixedSize=false), MergeVertices,
  RemoveUnused, links EM into sourceMeshPart via CreateMeshPartAsync+ApplyMesh,
  builds bm via MeshIO.fromEditableMesh, then hides sourceMeshPart.
- Returns `nil` (not the session) if any step fails.
- `Destroy()` nils `em` — **never calls `em:Destroy()`**. The reason is not
  just GC cleanliness: the EM literally IS the MeshContent of the MeshPart.
  When a mesh is first imported it has a cloud AssetID in MeshContent. After
  `CreateEditableMeshAsync` + `ApplyMesh()`, the EM replaces that AssetID as
  the live MeshContent value. Destroying the EM destroys the mesh asset itself.
  If the user edits the same MeshPart a second time, `CreateEditableMeshAsync`
  reads from the EM already in MeshContent — not the original cloud asset.

**Studio session boundary:** The EM does not survive a Studio restart.
MeshContent reverts to the original cloud asset on reload. Persistence across
sessions (e.g. DataStore serialization) is a known future need, low priority.

**Upload path (future):** `CreateAssetAsync()` will allow uploading the final
EM as a permanent Roblox asset, replacing the original cloud AssetID. It is
not yet supported for Creator Store plugins (only local plugins as of now).
Support is expected this year. The Upload panel is already stubbed in the UI
and will be wired once that support lands.

---

## EditScene Interface

EditScene never calls MeshSession directly. It receives what it needs.

```lua
EditScene.Begin(root)
    -- Create VertexProxies, EdgeProxies, FaceProxies folders under root.
    -- Does NOT call RebuildProxies — MPE calls that after Begin.

EditScene.RebuildProxies(bm, localToWorld, sourceStyle)
    -- Destroy all existing proxies, rebuild from bm.
    -- localToWorld: (Vector3) → Vector3
    -- sourceStyle: { material, color, transparency } from sourceMeshPart for face proxies.
    -- Previously called SyncAll().

EditScene.ApplyGeometryMode(mode)
    -- Set Locked/Transparency on all proxies based on "Vertex" | "Edge" | "Face".

EditScene.ApplyFaceProxyColorsToSession(bm)
    -- Read face proxy Part colors back into bm face data before Finalize.

EditScene.FindProxy(name) → Part | nil

EditScene.Destroy()
    -- Nil face EM refs (no :Destroy on any EM), destroy root folder.
```

---

## Tool Interface

All tools conform to this interface. No exceptions.

```lua
tool.Activate(session, handle)
    -- Initialize tool state. Snapshot bm if needed (Bevel, Extrude, Dissolve).
    -- Store startCF, armedId, etc. from handle attributes.
    -- Do NOT call RebuildProxies.

tool.Apply(session, handle, oldCF, oldSz, newCF, newSz) → bool
    -- Fired on every handle CFrame/Size change (native Studio snap increment).
    -- Mutate session.bm and session.em via session methods.
    -- Return true if anything changed. Return false if no-op.
    -- Do NOT call EditScene. Do NOT call RebuildProxies.

tool.Commit(session)
    -- Clear tool state. The EM is already correct.
    -- Do NOT call RebuildProxies.

tool.Cancel(session)
    -- Restore bm/em to pre-operation state if needed.
    -- For tools with savedBM: session:SetBMesh(savedBM).
    -- For Transform: no-op (CHS revert handles it).
    -- Do NOT call RebuildProxies.

-- Dissolve only — not part of the general interface:
dissolve.Execute(session) → bool
    -- Performs the actual dissolve (DissolveEdge + RebuildEM).
    -- Called by MPE from the operator panel "Execute" action, before Commit.
    -- Returns true if the dissolve succeeded.
```

**Per-tool notes:**

- **Transform**: no savedBM. Cancel is a no-op — CHS reverts EM, MPE calls
  SyncFromEM + RebuildProxies. Apply collects verts from selection, calls
  `session:ApplyTransformToVerts`.

- **Extrude**: savedBM for cancel. First Apply call extrudes the face
  (ExtrudeFace → RebuildEM), updates handle attributes to cap face. Subsequent
  Apply calls move cap verts via ApplyTransformToVerts. Cancel restores savedBM.

- **Bevel**: savedBM as computation base. Every Apply clones savedBM, applies
  bevel at new depth, calls `session:SetBMesh(freshBM)` (which calls RebuildEM).
  Cancel calls `session:SetBMesh(savedBM)`. This is correct — BMesh is a
  scratchpad here, bm changes many times per operation, EM follows each time.
  The entire sequence is within one CHS recording so undo is one step.

- **Dissolve**: Apply is always a no-op (returns false). The operation is
  performed by `Execute()`, called explicitly by MPE. savedBM for cancel.

---

## MPE as Coordinator

MPE owns: the session object, the CHS recording identifier, the active tool state.

### Session lifecycle

```lua
beginSession():
    session = MeshSession.new(selectedMeshPart)
    if not session then return end   -- new() returns nil on failure

    root = Instance.new("Folder") ...
    EditScene.Begin(root)
    HandleManager.Init(onHandleChanged)
    SelectionManager.Clear()
    EditScene.RebuildProxies(session.bm, session.LocalToWorld, getSourceStyle(session))
    EditScene.ApplyGeometryMode(GeometryMode.Get())

endSession():
    cancelOperation()  -- if active
    EditScene.ApplyFaceProxyColorsToSession(session.bm)
    EditScene.Destroy()
    session:Finalize()
    session:Destroy()
    session = nil
```

### Tool activation

```lua
activateToolState(name):
    -- validate session, selection, acceptedTypes as today
    if activeToolState ~= SELECT_MODE then cancelOperation() end

    local proxy  = EditScene.FindProxy(entry.name)
    local handle = HandleManager.Arm(proxy)
    if not handle then return end

    recordingId = plugin:GetChangeHistoryService():TryBeginRecording(name)

    activeToolState = name
    toolstates[name].Activate(session, handle)
    HandleManager.BeginListening()
```

### Handle change → the core loop

```lua
onHandleChanged(handle, oldCF, oldSz, newCF, newSz):
    local tool = toolstates[activeToolState]
    if tool.Apply(session, handle, oldCF, oldSz, newCF, newSz) then
        EditScene.RebuildProxies(session.bm, session.LocalToWorld, getSourceStyle(session))
        EditScene.ApplyGeometryMode(GeometryMode.Get())
        refreshHud()
    end
```

### Commit and cancel

```lua
commitOperation():
    toolstates[activeToolState].Commit(session)
    plugin:GetChangeHistoryService():FinishRecording(
        recordingId, Enum.FinishRecordingOperation.Commit)
    recordingId = nil
    HandleManager.StopListening()
    HandleManager.Clear()
    SelectionManager.Clear()
    activeToolState = SELECT_MODE
    EditScene.ApplyGeometryMode(GeometryMode.Get())
    refreshHud()

cancelOperation():
    toolstates[activeToolState].Cancel(session)
    -- Cancel() may call session:SetBMesh(savedBM) which rebuilds EM.
    -- CHS reverts EM for tools without savedBM (Transform).
    plugin:GetChangeHistoryService():FinishRecording(
        recordingId, Enum.FinishRecordingOperation.Cancel)
    recordingId = nil
    HandleManager.StopListening()
    HandleManager.Clear()
    SelectionManager.Clear()
    activeToolState = SELECT_MODE
    -- Rebuild proxies to reflect restored state
    EditScene.RebuildProxies(session.bm, session.LocalToWorld, getSourceStyle(session))
    EditScene.ApplyGeometryMode(GeometryMode.Get())
    refreshHud()
```

### Dissolve execute action

```lua
-- Called from operator panel "Execute" button (replaces old Preview())
onDissolveExecute():
    if activeToolState ~= "Dissolve" then return end
    if Dissolve.Execute(session) then
        EditScene.RebuildProxies(session.bm, session.LocalToWorld, getSourceStyle(session))
        EditScene.ApplyGeometryMode(GeometryMode.Get())
        refreshHud()
    end
    commitOperation()
```

### Undo / Redo

```lua
-- Wired up in enable(), torn down in disable()
undoConn = plugin:GetChangeHistoryService().OnUndo:Connect(function()
    if not session then return end
    session:SyncFromEM()
    EditScene.RebuildProxies(session.bm, session.LocalToWorld, getSourceStyle(session))
    EditScene.ApplyGeometryMode(GeometryMode.Get())
    refreshHud()
end)

redoConn = plugin:GetChangeHistoryService().OnRedo:Connect(function()
    if not session then return end
    session:SyncFromEM()
    EditScene.RebuildProxies(session.bm, session.LocalToWorld, getSourceStyle(session))
    EditScene.ApplyGeometryMode(GeometryMode.Get())
    refreshHud()
end)
```

---

## CHS Integration Summary

| Event | CHS action |
|---|---|
| Handle armed | `TryBeginRecording(toolName)` |
| Commit | `FinishRecording(id, Commit)` |
| Cancel | `FinishRecording(id, Cancel)` |
| OnUndo fires | CHS reverts EM → `SyncFromEM` + `RebuildProxies` |
| OnRedo fires | CHS replays EM → `SyncFromEM` + `RebuildProxies` |

**Why this works:** EM is in the DataModel. Every `SetPosition`, `RemoveFace`,
`AddVertex`, `AddTriangle` is CHS-visible. Wrapping all mutations in a single
recording collapses them into one undo step regardless of how many snaps or
rebuildEM calls occurred. BMesh and proxies are not CHS-tracked, so they are
reconstructed from EM after CHS reverts.

**Bevel note:** Bevel calls `session:SetBMesh(freshBM)` (→ `RebuildEM`) on
every snap increment. All of these rebuildEM calls are within one open
recording. Undo reverts all of them atomically to the pre-bevel EM state.
`SyncFromEM` then reconstructs the correct pre-bevel BMesh.

---

## What Doesn't Change

- `BMesh.luau` — kept as-is
- `Operations.luau` — kept as-is
- `MeshIO.luau` — kept as-is (fromEditableMesh is already the right direction)
- `PluginMain.plugin.luau` — kept as-is
- `Hotkeys.luau`, `Listen.luau`, `UserConfig.luau` — kept as-is
- `UI/` — kept as-is
- `HandleManager.luau`, `SelectionManager.luau`, `GeometryMode.luau` — minor
  cleanup only (ensure proper init/destroy per session, no logic changes)

---

## Implementation Order

Implement bottom-up. Each step should be testable in isolation before moving on.

1. **`MeshSession.luau`** — rewrite as object factory. Non-singleton.
   Validate: begin a session, check session.bm and session.em are populated.

2. **`EditScene.luau`** — rewrite to accept parameters, remove global pulls.
   Validate: RebuildProxies produces correct proxies from a session's bm.

3. **`Tools/*.luau`** — update signatures, remove EditScene calls, remove
   MeshSession global requires.
   Validate: each tool's Apply mutates session state correctly.

4. **`MPE.luau`** — rewrite coordinator: own session object, CHS lifecycle,
   call RebuildProxies after every Apply, wire OnUndo/OnRedo.
   Validate: full operation cycle works end-to-end. Then test undo.

5. **`PluginMain.plugin.luau`** — pass plugin reference through to MPE for CHS.
   (Plugin global not available in ModuleScripts — must be threaded through.)
