--!strict
--[[
	Small declarative UI kit. Everything the HUD and panels are made of lives
	here so spacing, corners, strokes and motion stay consistent.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Kit = {}

export type Props = {
	[string]: any,
}

local function apply(instance: Instance, props: Props?)
	if not props then
		return
	end
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
end

function Kit.tween(instance: Instance, props: Props, duration: number?): Tween
	local info = TweenInfo.new(duration or Theme.Motion.base, Theme.Motion.ease, Theme.Motion.out)
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

function Kit.corner(parent: Instance, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.Radius.panel
	corner.Parent = parent
	return corner
end

function Kit.stroke(
	parent: Instance,
	color: Color3?,
	thickness: number?,
	transparency: number?
): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Color.strokeDim
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0.35
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Kit.padding(parent: Instance, horizontal: number, vertical: number?): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, horizontal)
	padding.PaddingRight = UDim.new(0, horizontal)
	padding.PaddingTop = UDim.new(0, vertical or horizontal)
	padding.PaddingBottom = UDim.new(0, vertical or horizontal)
	padding.Parent = parent
	return padding
end

function Kit.frame(parent: Instance, props: Props?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.Color.panel
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	apply(frame, props)
	frame.Parent = parent
	return frame
end

function Kit.label(parent: Instance, text: string, props: Props?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Theme.Color.text
	label.Font = Theme.Font.body
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.RichText = true
	apply(label, props)
	label.Parent = parent
	return label
end

function Kit.button(parent: Instance, text: string, props: Props?): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Theme.Color.inkSoft
	button.BackgroundTransparency = 0.1
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = text
	button.TextColor3 = Theme.Color.text
	button.Font = Theme.Font.heading
	button.TextSize = 15
	apply(button, props)
	button.Parent = parent

	Kit.corner(button, Theme.Radius.chip)
	local stroke = Kit.stroke(button, Theme.Color.strokeDim, 1, 0.5)

	button.MouseEnter:Connect(function()
		Kit.tween(button, { BackgroundTransparency = 0.0 })
		Kit.tween(stroke, { Transparency = 0.05, Color = Theme.Color.stroke })
	end)
	button.MouseLeave:Connect(function()
		Kit.tween(button, { BackgroundTransparency = 0.1 })
		Kit.tween(stroke, { Transparency = 0.5, Color = Theme.Color.strokeDim })
	end)
	button.MouseButton1Down:Connect(function()
		Kit.tween(button, { Size = button.Size - UDim2.fromOffset(0, 2) }, Theme.Motion.fast)
	end)
	button.MouseButton1Up:Connect(function()
		Kit.tween(button, { Size = button.Size + UDim2.fromOffset(0, 2) }, Theme.Motion.fast)
	end)

	return button
end

export type Bar = {
	root: Frame,
	fill: Frame,
	gradient: UIGradient,
}

function Kit.bar(parent: Instance, props: Props?): Bar
	local root = Kit.frame(parent, props)
	root.BackgroundColor3 = Theme.Color.ink
	root.BackgroundTransparency = 0.25
	Kit.corner(root, UDim.new(1, 0))

	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Theme.Color.amber
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = root
	Kit.corner(fill, UDim.new(1, 0))

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Color.amber),
		ColorSequenceKeypoint.new(1, Theme.Color.mint),
	})
	gradient.Parent = fill

	return { root = root, fill = fill, gradient = gradient }
end

function Kit.divider(parent: Instance, props: Props?): Frame
	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	line.BackgroundColor3 = Theme.Color.strokeDim
	line.BackgroundTransparency = 0.55
	line.Size = UDim2.new(1, 0, 0, 1)
	apply(line, props)
	line.Parent = parent
	return line
end

return Kit
