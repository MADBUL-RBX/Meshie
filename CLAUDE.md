# MeshPartEditPlugin (MPE) — Project Context

## What this is
A Roblox Studio plugin for in-editor MeshPart mesh editing. The user selects a MeshPart, enters Edit mode, manipulates geometry via proxy Parts in the viewport, then Finalizes to write back to the source MeshPart.

---

## Package structure

```
Meshie/src/
  Meshie.plugin.luau       — thin bootstrap: passes plugin to Core, handles unloading
  SelectionManager.luau    — wraps Selection service
  Input.luau               — modifier key helpers (Shift/Ctrl/Alt)
  Version.luau             — version string
  Core/                    — THE application: owns toolbar, input, display, session, tools
    init.luau              — orchestrator: all input → operators, results → display
    HUD.luau               — builds/destroys all 2D UI on demand (Create/Destroy pattern)
    ProxyManager.luau      — owns proxy Parts in the viewport
    HandleManager.luau     — owns the drag handle Part
    GeometryMode.luau      — geometry selection mode singleton (Vertex/Edge/Face)
    History.luau           — CHS undo/redo integration
    Selection.luau         — EM raycast picking + hover highlight (UIS-based input)
    RibbonToolManager.luau — constrains Studio ribbon tool during operations
    UIConfig.luau          — visual constants (colors, sizes, fonts)
    UserConfig.luau        — user preferences (hotkeys, proxy appearance)
    Hotkeys.luau           — maps action names to KeyCodes from UserConfig
    NoticePanel.luau       — first-launch welcome notice
  RMesh/                   — mesh kernel (no Roblox instance knowledge except AssetService/EM)
    init.luau              — RMesh class: owns em + bm, exposes mutation API
    Core/
      Data.luau            — half-edge BMesh data structure (OOP class)
      EulerOps.luau        — topology ops (extrude, dissolve, bevel, etc.)
    Operators/             — OOP tool classes: Activate/Apply/Commit/Cancel lifecycle
      Transform.luau
      Extrude.luau
      Inset.luau
      Bevel.luau
      Dissolve.luau
```

---

## Architecture: Plugin → Core → RMesh

**Meshie.plugin.luau** is a thin bootstrap (~20 lines). It passes the `plugin` global to `Core.Init(plugin)`, handles `plugin.Unloading`, and shows the version notice. It does not require or touch any module besides Core.

**Core** is the application. It owns everything: toolbar buttons, keyboard input, 2D display, session lifecycle, tool activation, proxy/handle/selection management, and history. Core requires RMesh and its operators directly. There is no separate "Editor" or "Controller" module — Core is both the interface and the coordinator. The `HUD.luau` submodule builds/destroys the ScreenGui on demand (Create/Destroy pattern — fresh GUI on Enable, destroyed on Disable).

**RMesh** is a headless mesh kernel library. It knows about `EditableMesh` (AssetService) but has no knowledge of Studio plugins, proxies, handles, or CHS. `RMesh.new(meshPart)` returns an instance that owns the live `em` and `bm`.

Dependency direction is strictly one-way: `Plugin → Core → RMesh`. Nothing flows backward.

---

## Data flow

```
EM (EditableMesh, CHS asset)
  ↓ CreateEditableMeshAsync + MergeVertices + fromEditableMesh/fromTopology
bm (Data / BMesh — n-gon topology)
  ↓ ProxyManager reads bm to place proxy Parts
Proxies (Parts in viewport, manipulated by user)
  ↓ Handle drag → operator Apply → RMesh:SetPosition / ExtrudeFace / etc.
bm + em updated live
  ↓ Finalize
baked MeshPart
```

Direction is always **EM → bm → Proxies**, never reversed. The bm is the n-gon filter over the triangulated EM.

---

## Operator lifecycle

Each tool (Transform, Extrude, Inset, Bevel, Dissolve) is an OOP class with four methods:

- `Activate(rmesh, handle, entries)` — snapshot state, arm the tool
- `Apply(rmesh, handle)` — called on every handle drag tick, returns `bool` (dirty)
- `Commit()` — accept the result, tool is done
- `Cancel(rmesh)` — restore saved state (savedBM or savedVerts), tool is done

Core holds `activeTool = toolstates[name].new()`. On commit/cancel it nils `activeTool`. Display updates happen inline — no signals needed since Core initiated the action. Tool chaining: pressing a tool hotkey mid-operation commits the active tool and immediately starts the new one, preserving the current selection.

---

## Core public API

The plugin script only calls these four functions:

- `Core.Init(plugin)` — stores plugin ref, creates toolbar, wires buttons, inits subsystems
- `Core.Enable()` — creates fresh GUI (HUD.Create), starts history listening, sets initial state
- `Core.Disable()` — ends session if active, destroys GUI (HUD.Destroy), cleans up
- `Core.Shutdown()` — calls Disable if enabled

Core creates the toolbar buttons internally during Init. No signals flow from Core back to the plugin script.

---

## RMesh session lifecycle

1. `Core.beginSession` — saves `originalParent`, moves meshPart to ServerStorage, creates `"Meshie"` folder in workspace, calls `RMesh.new(meshPart)`
2. `RMesh.new` — `CreateEditableMeshAsync` (FixedSize=false) → `MergeVertices` → `RemoveUnused` → build `bm` (from topology or EM). **No ApplyMesh here.**
3. Live editing — operators call `rmesh:SetPosition`, `rmesh:ExtrudeFace`, etc. EM is updated live via `SetPosition` or `rebuildEM`. `ApplyMeshUpdate` rebakes for CHS/collision sync.
4. `RMesh:Finalize` — center geometry, serialize topology, bake, ApplyMesh, restore CFrame
5. `Core.endSession` — destroys session folder, restores `meshPart.Parent = originalParent`, nils rmesh

---

## Critical EditableMesh rules

- `CreateEditableMeshAsync` returns the actual MeshContent object — **NEVER `:Destroy()` it**. Nil the reference and let GC handle it. The EM IS the mesh — destroying it destroys the user's work.
- `CreateEditableMesh` (non-async, caller-owned) — nil ref, let GC.
- `FixedSize = false` is required on `CreateEditableMeshAsync` or you can't add/remove verts/faces.
- `ApplyMesh()` is for physics/collision baking — **NOT for syncing during edits and NOT in the constructor**. Visual changes to EM are instant via CHS.
- `RemoveVertex` does NOT exist. Use `RemoveUnused()` after `RemoveFace` calls.
- **Do NOT call `ApplyMesh` in `RMesh.new`.** `CreateEditableMeshAsync` already establishes the live CHS link. An extra `ApplyMesh` in the constructor rebakes the EM into a new static mesh, overwrites `meshPart.MeshSize`, and corrupts `GetScaleFactor()` — causing the mesh to appear visually larger on every re-edit.

---

## Finalize pivot centering

After editing, the bm bounding box center drifts from the mesh origin. `Finalize` corrects this:

1. Compute `localCenter` = bm bounding box center (mesh local space)
2. Compute `worldOffset = meshPart.CFrame:VectorToWorldSpace(localCenter * GetScaleFactor())`
3. Shift all bm verts: `vert.position -= localCenter` + `em:SetPosition(vert.emId, vert.position)`
4. **Serialize topology** (positions are now centered — must happen after step 3)
5. Bake from `self.em` → `CreateMeshPartAsync` → `ApplyMesh` → preserve `Size`
6. `meshPart.CFrame += worldOffset`

No `rebuildEM`, no new EM instance needed — it's just a `SetPosition` loop, same as any live edit.

---

## Topology serialization (MPETopology)

N-gon face topology is saved as a `StringValue` child of the MeshPart (`MPETopology`). On re-edit, `fromTopology` matches saved positions (4 decimal places) against the loaded EM to reconstruct the bm with original n-gon groupings, avoiding `dissolvePlanar` fallback. Positions in the JSON **must match the baked EM positions** — serialize only after centering.

---

## Save / upload limitation

Until `CreateAssetAsync()` is supported for Creator Store plugins, the EM IS the mesh content. Users must manually save and upload their mesh — the edited mesh will be lost on Studio restart otherwise.
