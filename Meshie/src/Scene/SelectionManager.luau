-- SelectionManager.luau
-- Single owner of SelectionService for the plugin.
--
-- Responsibilities:
--   • Track which proxies the user has selected. Proxy Part references are
--     captured directly from Selection:Get() at selection time — always fresh,
--     no resync required (Highlights only live during SELECT_MODE; proxies are
--     rebuilt during tool drags when no Highlights are active).
--   • Manage Highlight instances on selected proxies (TODO sites below).
--   • Focus a handle in Studio's selection and fire a one-shot callback when
--     the handle is deselected (replaces the ad-hoc autoCommitConn in MPE).
--
-- Begin() / End() gate the SelectionChanged listener to the active session.
-- No other module should import game:GetService("Selection").

local Selection    = game:GetService("Selection")
local GeometryMode = require(script.Parent.GeometryMode)

local SelectionManager = {}

-- ─── State ────────────────────────────────────────────────────────────────────

-- Each entry: { proxyType, id, name, proxy }
-- proxy is the live Part reference captured at selection time via Selection:Get().
local orderedEntries = {}
local entrySet       = {}  -- keyed by proxy.Name for O(1) duplicate check
local selectionConn  = nil
local handleDeselectedCallback = nil

-- ─── Internal ─────────────────────────────────────────────────────────────────

local function entryFromProxy(proxy)
	local pt   = proxy:GetAttribute("ProxyType")
	local name = proxy.Name
	local id
	if     pt == "Vertex" then id = proxy:GetAttribute("VertId")
	elseif pt == "Edge"   then id = proxy:GetAttribute("EdgeId")
	elseif pt == "Face"   then id = proxy:GetAttribute("FaceId")
	end
	if not pt or not id then return nil end
	return { proxyType = pt, id = id, name = name, proxy = proxy }
end

local function onStudioSelectionChanged()
	local sel = Selection:Get()

	-- Handle-deselection watch: fires once when the handle leaves the selection.
	if handleDeselectedCallback then
		for _, inst in ipairs(sel) do
			if inst:GetAttribute("IsToolHandle") then
				return -- handle still present
			end
		end
		local cb = handleDeselectedCallback
		handleDeselectedCallback = nil
		cb()
		return
	end

	-- Proxy selection: accumulate newly selected proxies matching the current
	-- geometry mode. Part references are fresh from Selection:Get() here.
	for _, inst in ipairs(sel) do
		if inst:GetAttribute("IsToolHandle") then continue end
		local pt = inst:GetAttribute("ProxyType")
		if not pt then continue end
		if pt ~= GeometryMode.Get() then continue end
		SelectionManager.Add(inst)
	end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

-- Call at session start. Clears state, resets Studio selection, begins tracking.
function SelectionManager.Begin()
	SelectionManager.Clear()
	Selection:Set({})
	selectionConn = Selection.SelectionChanged:Connect(onStudioSelectionChanged)
end

-- Call at session end. Stops tracking, clears state, optionally restores a
-- Part to Studio's selection (pass nil to leave selection empty).
function SelectionManager.End(restorePart)
	handleDeselectedCallback = nil
	if selectionConn then
		selectionConn:Disconnect()
		selectionConn = nil
	end
	SelectionManager.Clear()
	if restorePart then
		Selection:Set({ restorePart })
	end
end

-- ─── Proxy selection ──────────────────────────────────────────────────────────

function SelectionManager.Add(proxy)
	if entrySet[proxy.Name] then return end
	local entry = entryFromProxy(proxy)
	if not entry then return end
	orderedEntries[#orderedEntries + 1] = entry
	entrySet[proxy.Name] = entry
	-- TODO: create Highlight on proxy
end

function SelectionManager.Clear()
	-- TODO: destroy all Highlights
	orderedEntries = {}
	entrySet       = {}
end

-- ─── Handle focus ─────────────────────────────────────────────────────────────

-- Set handle as Studio's active selection and register a one-shot callback
-- that fires the first time the handle leaves the selection.
-- Deferred one frame so the SelectionChanged fired by Set itself is ignored.
function SelectionManager.FocusHandle(handle, onDeselected)
	Selection:Set({ handle })
	task.defer(function()
		handleDeselectedCallback = onDeselected
	end)
end

-- Cancel the deselection watch without firing the callback.
-- Call on explicit commit or cancel so the callback does not double-fire.
function SelectionManager.UnfocusHandle()
	handleDeselectedCallback = nil
end

-- ─── Queries ──────────────────────────────────────────────────────────────────

function SelectionManager.GetLast()
	return orderedEntries[#orderedEntries]
end

function SelectionManager.GetAll()
	return orderedEntries
end

function SelectionManager.HasSelection()
	return #orderedEntries > 0
end

function SelectionManager.Count()
	return #orderedEntries
end

-- Raw Studio selection — use only for pre-session MeshPart detection in MPE.
-- All other Selection access goes through the tracked API above.
function SelectionManager.GetStudioSelection()
	return Selection:Get()
end

return SelectionManager
