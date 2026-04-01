# RMesh Refactor Plan

## Context

The current codebase is over-engineered — Core, Scene, and MPE are tangled together with callback injection, too many proxy attributes, and three parallel representations of the same mesh data (RMesh, EditableMesh, Proxies). This refactor reorganizes the system into a clean, Roblox-idiomatic structure where:

- **RMesh** is a proper mesh editing kernel (the half-edge layer above EditableMesh, equivalent to what BMesh is to Blender)
- **Editor** is a thin singleton that orchestrates UI, hotkeys, and session lifecycle — nothing more
- **ProxyManager** owns all Instance-level mesh representation (proxies + handles)
- **SelectionManager** is a dead-simple wrapper around Roblox's Selection service
- Proxy Parts carry **one attribute only**: their element ID. All data lives in RMesh.

This is a rename + reorganize + cleanup refactor. The hard math (half-edge, extrude, bevel, dissolve) is already written and does not change.

---

## Target File Structure

```
Meshie/src/
  Loader.plugin.luau           ← was PluginMain.plugin.luau
  SelectionManager.luau        ← thin Selection wrapper: Get() + Changed signal
  Editor/
    init.luau                  ← was MPE.luau (thin: UI, hotkeys, session lifecycle)
    History.luau               ← was History.luau (child of Editor)
    GeometryMode.luau          ← was GeometryMode.luau (child of Editor)
  HUD/
    init.luau                  ← was UI/init.luau
    Hotkeys.luau               ← was Hotkeys.luau (child of HUD)
    UserConfig.luau            ← was UserConfig.luau (child of HUD)
    Factory.luau
    UIConfig.luau
    NoticePanel.luau
  RMesh/
    init.luau                  ← was Core/init.luau (singleton brain)
    ProxyManager/
      init.luau                ← was Scene/init.luau (renders proxies from RMesh)
      HandleManager.luau       ← was HandleManager.luau (absorbs ToolHandles.luau)
    Core/
      DataStructure.luau       ← was BMesh.luau
      EulerOps.luau            ← was Operations.luau
    Operators/
      Transform.luau
      Extrude.luau
      Bevel.luau
      Dissolve.luau
```

---

## What Changes Per File

### Renames / Moves (logic unchanged)
| Old path | New path |
|---|---|
| `Core/BMesh.luau` | `RMesh/Core/DataStructure.luau` |
| `Core/Operations.luau` | `RMesh/Core/EulerOps.luau` |
| `Core/MeshIO.luau` | absorbed into `RMesh/init.luau` |
| `Core/init.luau` | `RMesh/init.luau` |
| `Scene/init.luau` | `RMesh/ProxyManager/init.luau` |
| `Scene/HandleManager.luau` + `Scene/ToolHandles.luau` | `RMesh/ProxyManager/HandleManager.luau` |
| `Scene/GeometryMode.luau` | `Editor/GeometryMode.luau` |
| `UI/init.luau` | `HUD/init.luau` |
| `UI/Factory.luau` | `HUD/Factory.luau` |
| `UI/UIConfig.luau` | `HUD/UIConfig.luau` |
| `UI/NoticePanel.luau` | `HUD/NoticePanel.luau` |
| `MPE.luau` | `Editor/init.luau` |
| `History.luau` | `Editor/History.luau` |
| `Hotkeys.luau` | `HUD/Hotkeys.luau` |
| `UserConfig.luau` | `HUD/UserConfig.luau` |
| `Scene/SelectionManager.luau` | `SelectionManager.luau` |

### Logic Changes

**SelectionManager.luau** — strip down to bare minimum:
- `SelectionManager.Get()` → `Selection:Get()`
- `SelectionManager.Changed` → connect to `Selection.SelectionChanged`
- Remove all proxy tracking, entry structs, FocusHandle, UnfocusHandle, Begin, End, Add, Clear, GetLast, GetAll, HasSelection, Count, GetStudioSelection

**RMesh/ProxyManager/HandleManager.luau** — absorb ToolHandles:
- Inline `ToolHandles.Begin()`, `ToolHandles.Destroy()`, `ToolHandles.CreateHandle()`, `ToolHandles.GetFolder()` directly
- Delete `ToolHandles.luau`

**All require paths** — update throughout to reflect new locations:
- `script.Parent.Core.BMesh` → `script.Parent.Core.DataStructure` (or `script.DataStructure` from within RMesh)
- `script.Parent.Core.Operations` → `script.Parent.Core.EulerOps`
- `script.Parent.UI` → `script.Parent.HUD`
- etc.

**PluginMain.plugin.luau** → renamed to **Loader.plugin.luau** — update require paths:
- `script.Parent.MPE` → `script.Parent.Editor`
- `script.Parent.UI.NoticePanel` → `script.Parent.HUD.NoticePanel`

---

## What Does NOT Change

- RMesh/init.luau logic (was Core/init.luau — singleton, em, bm, all methods)
- ProxyManager/init.luau logic (was Scene/init.luau)
- Editor/init.luau logic (was MPE.luau)
- All Operator logic (Transform, Extrude, Bevel, Dissolve)
- HUD logic
- History logic
- BMesh algorithm / Operations algorithm

This is purely structural — no logic changes, only renames, moves, and require path updates. The proxy attribute strip-down (one ID only) and EM sync simplification are **out of scope** for this refactor.

---

## Execution Order

1. Create new directory structure (new files, copy content)
2. Update all internal require paths
3. Delete old files
4. Update PluginMain.plugin.luau
5. Verify sourcemap.json updates correctly via Rojo sync

---

## Verification

- Plugin loads in Roblox Studio without errors
- Edit mode activates on a MeshPart
- Transform, Extrude, Bevel, Dissolve all function
- Undo/redo works
- HUD displays correctly
