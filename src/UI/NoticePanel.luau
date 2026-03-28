-- NoticePanel.luau
-- First-launch / new-version welcome notice for Meshie.
-- NoticePanel.Show(plugin, version, onDismiss)

local UIConfig = require(script.Parent.UIConfig)

local ACCENT  = Color3.fromRGB(236, 169, 39)  -- matches ButtonActiveColor
local DIVIDER = UIConfig.PanelStrokeColor

local NoticePanel = {}

local function makeLabel(parent, text, textSize, color, bold, wrap, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size                   = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize          = Enum.AutomaticSize.Y
	l.Text                   = text
	l.TextSize               = textSize
	l.TextColor3             = color
	l.Font                   = bold and Enum.Font.GothamBold or UIConfig.Font
	l.TextXAlignment         = Enum.TextXAlignment.Left
	l.TextWrapped            = wrap
	l.RichText               = false
	l.LayoutOrder            = order
	l.Parent                 = parent
	return l
end

local function makeDivider(parent, order)
	local f = Instance.new("Frame")
	f.Size             = UDim2.new(1, 0, 0, 1)
	f.BackgroundColor3 = DIVIDER
	f.BorderSizePixel  = 0
	f.LayoutOrder      = order
	f.Parent           = parent
	return f
end

function NoticePanel.Show(plugin, version, onDismiss)
	local widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,
		true,   -- initially enabled
		true,   -- override previous state
		420,    -- default width
		500,    -- default height
		420,    -- min width
		400     -- min height
	)

	local widget = plugin:CreateDockWidgetPluginGui("MeshieNotice_" .. version, widgetInfo)
	widget.Title          = "Welcome to Meshie " .. version
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- ── Background ────────────────────────────────────────────────────────────

	local bg = Instance.new("Frame")
	bg.Size             = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = UIConfig.PanelColor
	bg.BorderSizePixel  = 0
	bg.Parent           = widget

	-- ── Scrollable content ────────────────────────────────────────────────────

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size                  = UDim2.new(1, 0, 1, -(UIConfig.MainButtonHeight + UIConfig.Margin * 2))
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel        = 0
	scroll.ScrollBarThickness     = 4
	scroll.ScrollBarImageColor3   = UIConfig.PanelStrokeColor
	scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	scroll.Parent                 = bg

	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingLeft   = UDim.new(0, UIConfig.Margin)
	scrollPad.PaddingRight  = UDim.new(0, UIConfig.Margin)
	scrollPad.PaddingTop    = UDim.new(0, UIConfig.Margin)
	scrollPad.PaddingBottom = UDim.new(0, UIConfig.Spacing)
	scrollPad.Parent        = scroll

	local layout = Instance.new("UIListLayout")
	layout.SortOrder  = Enum.SortOrder.LayoutOrder
	layout.Padding    = UDim.new(0, UIConfig.Padding)
	layout.Parent     = scroll

	-- ── Content ───────────────────────────────────────────────────────────────

	local o = 0
	local function next() o += 1; return o end

	makeLabel(scroll, "Meshie",                              20, ACCENT,             true,  false, next())
	makeLabel(scroll, "MeshIE — Mesh Internal Editor · " .. version, UIConfig.TextSizeSmall, UIConfig.SubTextColor, false, false, next())
	makeDivider(scroll, next())

	makeLabel(scroll, "Thank you for your support ♥",        UIConfig.TextSizeTitle, UIConfig.TextColor, true, false, next())
	makeLabel(scroll,
		"Meshie is in active early development, and every purchase goes directly toward building it into something great. "
		.. "If you bought this plugin, you're genuinely helping shape what it becomes — and that means a lot. Thank you.",
		UIConfig.TextSizeBody, UIConfig.SubTextColor, false, true, next())

	makeDivider(scroll, next())

	makeLabel(scroll, "What Meshie can do right now",        UIConfig.TextSizeTitle, UIConfig.TextColor, true, false, next())
	makeLabel(scroll,
		"· Transform vertices, edges, and faces\n"
		.. "· Extrude, Bevel, and Dissolve geometry\n"
		.. "· Full undo / redo with N-gon preservation\n"
		.. "· Face color painting — bakes on Finalize\n"
		.. "· N-gon topology preserved across edit sessions",
		UIConfig.TextSizeBody, UIConfig.SubTextColor, false, true, next())

	makeDivider(scroll, next())

	makeLabel(scroll, "Uploading your mesh",                 UIConfig.TextSizeTitle, UIConfig.TextColor, true, false, next())
	makeLabel(scroll,
		"Meshie edits your MeshPart directly. To publish your work, Finalize the mesh first — "
		.. "this writes all changes back to the MeshPart. From there, upload it through Studio's "
		.. "Asset Manager exactly as you would any other mesh.\n\n"
		.. "One-click upload from inside Meshie is on the roadmap.",
		UIConfig.TextSizeBody, UIConfig.SubTextColor, false, true, next())

	makeDivider(scroll, next())

	makeLabel(scroll, "Documentation & updates",             UIConfig.TextSizeTitle, UIConfig.TextColor, true, false, next())
	makeLabel(scroll,
		"Full documentation and the public GitHub are coming soon. "
		.. "Check back in a future update!",
		UIConfig.TextSizeBody, UIConfig.SubTextColor, false, true, next())

	-- ── Dismiss button ────────────────────────────────────────────────────────

	local btnArea = Instance.new("Frame")
	btnArea.Size             = UDim2.new(1, 0, 0, UIConfig.MainButtonHeight + UIConfig.Margin * 2)
	btnArea.Position         = UDim2.new(0, 0, 1, -(UIConfig.MainButtonHeight + UIConfig.Margin * 2))
	btnArea.BackgroundColor3 = UIConfig.PanelColor
	btnArea.BorderSizePixel  = 0
	btnArea.Parent           = bg

	local topStroke = Instance.new("Frame")
	topStroke.Size             = UDim2.new(1, 0, 0, 1)
	topStroke.BackgroundColor3 = DIVIDER
	topStroke.BorderSizePixel  = 0
	topStroke.Parent           = btnArea

	local btnPad = Instance.new("UIPadding")
	btnPad.PaddingLeft   = UDim.new(0, UIConfig.Margin)
	btnPad.PaddingRight  = UDim.new(0, UIConfig.Margin)
	btnPad.PaddingTop    = UDim.new(0, UIConfig.Margin)
	btnPad.PaddingBottom = UDim.new(0, UIConfig.Margin)
	btnPad.Parent        = btnArea

	local btn = Instance.new("TextButton")
	btn.Size             = UDim2.new(1, 0, 0, UIConfig.MainButtonHeight)
	btn.Position         = UDim2.new(0, 0, 0, UIConfig.Margin)
	btn.BackgroundColor3 = ACCENT
	btn.Text             = "Got it, let's go!"
	btn.TextColor3       = Color3.fromRGB(20, 20, 20)
	btn.Font             = Enum.Font.GothamBold
	btn.TextSize         = UIConfig.TextSizeButton
	btn.BorderSizePixel  = 0
	btn.Parent           = btnArea

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UIConfig.CornerRadius)
	corner.Parent       = btn

	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		widget:Destroy()
		if onDismiss then onDismiss() end
	end

	btn.MouseButton1Click:Connect(dismiss)
	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not widget.Enabled then dismiss() end
	end)
end

return NoticePanel
