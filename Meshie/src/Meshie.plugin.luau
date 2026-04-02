-- Meshie.plugin.luau
-- Controller: owns the toolbar, wires HUD signals → Editor calls,
-- and Editor signals → HUD display updates. Neither HUD nor Editor
-- knows the other exists.

local HUD               = require(script.Parent.HUD)
local Editor            = require(script.Parent.Editor)
local RibbonToolManager = require(script.Parent.Editor.RibbonToolManager)
local Selection         = require(script.Parent.Editor.Selection)
local Version           = require(script.Parent.Version)
local NoticePanel       = require(script.Parent.HUD.NoticePanel)

RibbonToolManager.Init(plugin)
Selection.Init(plugin)

-- ─── Toolbar ──────────────────────────────────────────────────────────────────

local toolbar      = plugin:CreateToolbar("Meshie")
local toggleButton = toolbar:CreateButton("Meshie", "Toggle Meshie editor", "")
local vertexButton = toolbar:CreateButton("Vertex", "Switch to Vertex mode", "")
local edgeButton   = toolbar:CreateButton("Edge",   "Switch to Edge mode",   "")
local faceButton   = toolbar:CreateButton("Face",   "Switch to Face mode",   "")

local geoButtons = { Vertex = vertexButton, Edge = edgeButton, Face = faceButton }

local function setGeoButtonActive(mode)
	for name, btn in pairs(geoButtons) do
		btn:SetActive(name == mode)
	end
end

-- ─── Session lifecycle ────────────────────────────────────────────────────────

local enabled = false

local function onEnable()
	enabled = true
	toggleButton:SetActive(true)
	Editor.StartListening()
	HUD.SetVisible(true)
	HUD.SetMainButtonText("Edit")
	HUD.SetMode("Select a MeshPart")
	HUD.SetCounts(nil, nil)
	HUD.SetTool(nil)
	HUD.SetNote("")
	HUD.SetOperatorPanel(nil)
	local initMode = "Vertex"
	Editor.SetGeometryMode(initMode)
	HUD.SetGeometryMode(initMode, Editor.GetValidToolsForMode(initMode))
	setGeoButtonActive(initMode)
end

local function onDisable()
	if Editor.IsSessionActive() then Editor.EndSession() end
	Editor.StopListening()
	HUD.SetVisible(false)
	toggleButton:SetActive(false)
	for _, btn in pairs(geoButtons) do btn:SetActive(false) end
	enabled = false
end

-- ─── Toolbar button wiring ────────────────────────────────────────────────────

toggleButton.Click:Connect(function()
	if enabled then onDisable() else onEnable() end
end)

for mode, btn in pairs(geoButtons) do
	btn.Click:Connect(function()
		if not enabled then return end
		Editor.SetGeometryMode(mode)
	end)
end

-- ─── HUD → Editor ─────────────────────────────────────────────────────────────

HUD.MainActivated:Connect(function()
	if Editor.IsSessionActive() then
		Editor.EndSession()
	elseif not Editor.BeginSession() then
		HUD.SetNote("Select one MeshPart.")
	end
end)

HUD.ToolActivated:Connect(function(name)
	Editor.ActivateTool(name)
end)

HUD.CommitActivated:Connect(function()
	Editor.CommitOperation()
end)

HUD.CancelActivated:Connect(function()
	Editor.CancelOperation()
end)

HUD.GeometryModeActivated:Connect(function(mode)
	Editor.SetGeometryMode(mode)
end)

HUD.DissolveVertsToggled:Connect(function(isEnabled)
	Editor.SetDissolveVerts(isEnabled)
end)

-- ─── Editor → HUD ─────────────────────────────────────────────────────────────

Editor.SessionStarted:Connect(function(v, f)
	HUD.SetMode("Edit")
	HUD.SetMainButtonText("Finalize")
	HUD.SetCounts(v, f)
	HUD.SetTool("Select")
	HUD.SetActiveToolState(nil)
	HUD.SetNote("")
	HUD.SetOperatorPanel(nil)
end)

Editor.SessionEnded:Connect(function()
	HUD.SetMode("Select a MeshPart")
	HUD.SetMainButtonText("Edit")
	HUD.SetCounts(nil, nil)
	HUD.SetTool(nil)
	HUD.SetActiveToolState(nil)
	HUD.SetNote("")
	HUD.SetOperatorPanel(nil)
end)

Editor.OperationStarted:Connect(function(name)
	HUD.SetTool(name)
	HUD.SetActiveToolState(name)
	HUD.SetOperatorPanel(name)
end)

Editor.OperationEnded:Connect(function(v, f)
	HUD.SetTool("Select")
	HUD.SetActiveToolState(nil)
	HUD.SetOperatorPanel(nil)
	HUD.SetCounts(v, f)
end)

Editor.CountsChanged:Connect(function(v, f)
	HUD.SetCounts(v, f)
end)

Editor.GeometryModeSet:Connect(function(mode, validTools)
	HUD.SetGeometryMode(mode, validTools)
	setGeoButtonActive(mode)
end)

-- ─── Plugin lifecycle ─────────────────────────────────────────────────────────

plugin.Unloading:Connect(function()
	if enabled then onDisable() end
	HUD.Destroy()
end)

-- ─── Version notice ───────────────────────────────────────────────────────────

local noticedVersion = plugin:GetSetting("MeshieNoticedVersion")
if noticedVersion ~= Version then
	NoticePanel.Show(plugin, Version, function()
		plugin:SetSetting("MeshieNoticedVersion", Version)
	end)
end
