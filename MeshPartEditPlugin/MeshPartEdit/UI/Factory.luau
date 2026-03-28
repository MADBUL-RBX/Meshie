local UIConfig = require(script.Parent.UIConfig)

local Factory = {}

local function apply(instance, props)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	return instance
end

function Factory.Create(className, props, children)
	local instance = apply(Instance.new(className), props)

	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end

	return instance
end

local function connectButtonHover(button)
	button:SetAttribute("IsActive", false)

	button.MouseEnter:Connect(function()
		if not button:GetAttribute("IsActive") then
			button.BackgroundColor3 = UIConfig.ButtonHoverColor
		end
	end)

	button.MouseLeave:Connect(function()
		if not button:GetAttribute("IsActive") then
			button.BackgroundColor3 = UIConfig.ButtonColor
		end
	end)
end

function Factory.MakePanel(name, size, anchorPoint, position, parent)
	return Factory.Create("Frame", {
		Name = name,
		Size = size,
		AnchorPoint = anchorPoint,
		Position = position,
		BackgroundColor3 = UIConfig.PanelColor,
		BackgroundTransparency = UIConfig.PanelTransparency,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		Factory.Create("UICorner", {
			CornerRadius = UDim.new(0, UIConfig.CornerRadius),
		}),
		Factory.Create("UIStroke", {
			Color = UIConfig.PanelStrokeColor,
			Thickness = UIConfig.StrokeThickness,
			Transparency = 0.2,
		}),
	})
end

function Factory.MakeDivider(name, size, position, parent)
	return Factory.Create("Frame", {
		Name = name,
		Size = size,
		Position = position,
		BackgroundColor3 = UIConfig.PanelStrokeColor,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = parent,
	})
end

function Factory.MakeLabel(name, text, size, position, parent, textColor, textSize, alignment, verticalAlignment)
	return Factory.Create("TextLabel", {
		Name = name,
		Size = size,
		Position = position,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = textColor or UIConfig.TextColor,
		Font = UIConfig.Font,
		TextSize = textSize or UIConfig.TextSizeBody,
		TextWrapped = true,
		TextXAlignment = alignment or Enum.TextXAlignment.Left,
		TextYAlignment = verticalAlignment or Enum.TextYAlignment.Center,
		Parent = parent,
	})
end

function Factory.MakeButton(name, text, size, position, parent)
	local button = Factory.Create("TextButton", {
		Name = name,
		Size = size,
		Position = position,
		BackgroundColor3 = UIConfig.ButtonColor,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text,
		TextColor3 = UIConfig.TextColor,
		Font = UIConfig.Font,
		TextSize = UIConfig.TextSizeButton,
		Parent = parent,
	}, {
		Factory.Create("UICorner", {
			CornerRadius = UDim.new(0, UIConfig.CornerRadius),
		}),
		Factory.Create("UIStroke", {
			Color = UIConfig.PanelStrokeColor,
			Thickness = 1,
			Transparency = 0.35,
		}),
	})

	connectButtonHover(button)

	return button
end

function Factory.MakeToolButton(name, icon, hotkey, parent)
	local button = Factory.Create("TextButton", {
		Name = name,
		Size = UDim2.new(1, 0, 0, UIConfig.ToolRailButtonHeight),
		BackgroundColor3 = UIConfig.ButtonColor,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	}, {
		Factory.Create("UICorner", {
			CornerRadius = UDim.new(0, UIConfig.CornerRadius),
		}),
		Factory.Create("UIStroke", {
			Color = UIConfig.PanelStrokeColor,
			Thickness = 1,
			Transparency = 0.35,
		}),
	})

	connectButtonHover(button)

	local iconObject = nil
	if icon and icon ~= "" then
		iconObject = Factory.Create("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, -14, 1, -14),
			BackgroundTransparency = 1,
			Image = icon,
			ImageColor3 = UIConfig.TextColor,
			ScaleType = Enum.ScaleType.Fit,
			Parent = button,
		})
	else
		iconObject = Factory.Create("TextLabel", {
			Name = "IconFallback",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, -12, 1, -12),
			BackgroundTransparency = 1,
			Text = "?",
			TextColor3 = UIConfig.TextColor,
			Font = UIConfig.Font,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			Parent = button,
		})
	end

	local hotkeyLabel = Factory.Create("TextLabel", {
		Name = "HotkeyLabel",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -5, 1, -4),
		Size = UDim2.new(0, 20, 0, 12),
		BackgroundTransparency = 1,
		Text = hotkey or "",
		TextColor3 = UIConfig.SubTextColor,
		Font = UIConfig.Font,
		TextSize = UIConfig.TextSizeSmall,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Visible = hotkey ~= nil and hotkey ~= "",
		Parent = button,
	})

	return button, hotkeyLabel, iconObject
end

return Factory
