-- nova ui library (no demo). load it with:
-- local NovaUI = loadstring(game:HttpGet("<raw link>"))()

local NovaUI = (function()
--[[
	quick usage
	window = NovaUI:CreateWindow({Title, Subtitle, Size, ToggleKey})
	tab = window:CreateTab("name")
	tab:Section / Label / Paragraph / Divider / Button / Toggle / Slider
	tab:Dropdown / Textbox / Keybind / ColorPicker / Progress / CodeBox / ConfigManager
	add Flag = "id" to an element and it gets saved with configs
	NovaUI:Notify / Dialog / Run / CheckSyntax / SaveConfig / LoadConfig / OverwriteConfig / DeleteConfig / SetAutoLoad / ClearAutoLoad / AutoLoad / Unload
]]

local cloneref = cloneref or clonereference or function(obj)
	return obj
end
local function GetService(name)
	return cloneref(game:GetService(name))
end

local Players = GetService("Players")
local TweenService = GetService("TweenService")
local UserInputService = GetService("UserInputService")
local LogService = GetService("LogService")
local HttpService = GetService("HttpService")
local RunService = GetService("RunService")

-- optional executor helpers (all safe to be missing)
local protectgui = protectgui or (syn and syn.protect_gui) or function() end

local LocalPlayer = Players.LocalPlayer
do
	local waited = 0
	while not LocalPlayer do
		task.wait(0.1)
		waited = waited + 0.1
		if waited > 5 then
			error("[NovaUI] no LocalPlayer after 5s - run this from a LocalScript while the game is playing")
		end
		LocalPlayer = Players.LocalPlayer
	end
end

local Library = {
	Flags = {},
	_windows = {},
	_conns = {},
}

-- edit Library.Theme BEFORE creating windows to re-skin everything
Library.Theme = {
	Background = Color3.fromRGB(20, 20, 28),
	Topbar = Color3.fromRGB(27, 27, 39),
	Element = Color3.fromRGB(36, 36, 52),
	ElementHover = Color3.fromRGB(46, 46, 68),
	Accent = Color3.fromRGB(124, 92, 255),
	Text = Color3.fromRGB(240, 240, 250),
	SubText = Color3.fromRGB(160, 160, 182),
	Info = Color3.fromRGB(80, 150, 255),
	Success = Color3.fromRGB(80, 200, 120),
	Warning = Color3.fromRGB(255, 190, 70),
	Error = Color3.fromRGB(255, 90, 100),
}
local Theme = Library.Theme

-- top-right notifications and a floating open/close button.
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
Library.IsMobile = IS_MOBILE
local ROW_H = IS_MOBILE and 42 or 36
local TAB_H = IS_MOBILE and 38 or 32
local OPT_H = IS_MOBILE and 34 or 28
local SIDEBAR_W = IS_MOBILE and 104 or 130
local TEXT_SIZE = IS_MOBILE and 15 or 14

-- helpers

local function New(class, props, children)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	inst.Parent = parent
	return inst
end

local function Tween(inst, props, time, style, dir)
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

local function Corner(radius)
	return New("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

local function Stroke(color, thickness, transparency)
	return New("UIStroke", {
		Color = color or Theme.Element,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function Pad(l, t, r, b)
	return New("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0),
		PaddingTop = UDim.new(0, t or 0),
		PaddingRight = UDim.new(0, r or 0),
		PaddingBottom = UDim.new(0, b or 0),
	})
end

local function VList(padding)
	return New("UIListLayout", {
		Padding = UDim.new(0, padding or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

local function Text(props)
	local base = {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextColor3 = Theme.Text,
		TextSize = TEXT_SIZE,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return New("TextLabel", base)
end

local function Hover(frame)
	if IS_MOBILE then
		return
	end
	frame.MouseEnter:Connect(function()
		Tween(frame, { BackgroundColor3 = Theme.ElementHover }, 0.15)
	end)
	frame.MouseLeave:Connect(function()
		Tween(frame, { BackgroundColor3 = Theme.Element }, 0.15)
	end)
end

local function IsPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function Fmt(n)
	return tostring(math.floor(n * 10000 + 0.5) / 10000)
end

local function Register(flag, obj, kind)
	obj.Type = kind
	if flag then
		Library.Flags[flag] = obj
	end
	return obj
end

-- syntax checker
-- 2) otherwise falls back to a built-in scanner that finds unclosed
--    blocks, brackets and strings (it can't catch every mistake)

local EXPR_KW = { ["return"] = true, ["and"] = true, ["or"] = true, ["not"] = true, ["in"] = true }
local OPENERS = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local CLOSERS = { [")"] = "(", ["]"] = "[", ["}"] = "{" }

local function CountLines(s)
	local _, n = s:gsub("\n", "")
	return n
end

-- returns true, or false, message, line
local function LexCheck(src)
	local i, n, line = 1, #src, 1
	local blocks, brackets = {}, {}
	local prevSym, prevKw = nil, nil

	while i <= n do
		local c = src:sub(i, i)
		if c == "\n" then
			line = line + 1
			i = i + 1
		elseif c:match("%s") then
			i = i + 1
		elseif c == "-" and src:sub(i, i + 1) == "--" then
			local eq = src:match("^%-%-%[(=*)%[", i)
			if eq then
				local close = "]" .. eq .. "]"
				local _, e = src:find(close, i + 4 + #eq, true)
				if not e then
					return false, "unfinished long comment", line
				end
				line = line + CountLines(src:sub(i, e))
				i = e + 1
			else
				local e = src:find("\n", i, true)
				i = e or (n + 1)
			end
		elseif c == '"' or c == "'" then
			local startLine, j = line, i + 1
			while true do
				local ch = src:sub(j, j)
				if ch == "" or ch == "\n" then
					return false, "unfinished string", startLine
				elseif ch == "\\" then
					local nx = src:sub(j + 1, j + 1)
					if nx == "\n" then
						line = line + 1
						j = j + 2
					elseif nx == "z" then
						j = j + 2
						while src:sub(j, j):match("%s") do
							if src:sub(j, j) == "\n" then
								line = line + 1
							end
							j = j + 1
						end
					else
						j = j + 2
					end
				elseif ch == c then
					break
				else
					j = j + 1
				end
			end
			i = j + 1
			prevSym, prevKw = nil, nil
		elseif c == "`" then
			local startLine, j = line, i + 1
			while true do
				local ch = src:sub(j, j)
				if ch == "" then
					return false, "unfinished string", startLine
				elseif ch == "\\" then
					if src:sub(j + 1, j + 1) == "\n" then
						line = line + 1
					end
					j = j + 2
				elseif ch == "`" then
					break
				else
					if ch == "\n" then
						line = line + 1
					end
					j = j + 1
				end
			end
			i = j + 1
			prevSym, prevKw = nil, nil
		elseif c == "[" and src:match("^%[=*%[", i) then
			local eq = src:match("^%[(=*)%[", i)
			local close = "]" .. eq .. "]"
			local _, e = src:find(close, i + 2 + #eq, true)
			if not e then
				return false, "unfinished long string", line
			end
			line = line + CountLines(src:sub(i, e))
			i = e + 1
			prevSym, prevKw = nil, nil
		elseif c:match("[%a_]") then
			local word = src:match("^[%a_][%w_]*", i)
			i = i + #word
			if word == "function" then
				table.insert(blocks, { kw = "function", line = line })
			elseif word == "if" then
				-- "x = if a then b else c" is an expression and has no 'end'
				local isExpr = (prevSym ~= nil and prevSym ~= ")" and prevSym ~= "]" and prevSym ~= "}" and prevSym ~= ";")
					or (prevKw ~= nil and EXPR_KW[prevKw] == true)
				if not isExpr then
					table.insert(blocks, { kw = "if", line = line })
				end
			elseif word == "for" or word == "while" then
				table.insert(blocks, { kw = word, line = line, needDo = true })
			elseif word == "do" then
				local t = blocks[#blocks]
				if t and t.needDo then
					t.needDo = false
				else
					table.insert(blocks, { kw = "do", line = line })
				end
			elseif word == "repeat" then
				table.insert(blocks, { kw = "repeat", line = line })
			elseif word == "until" then
				local t = blocks[#blocks]
				if not t or t.kw ~= "repeat" then
					return false, "unexpected 'until' (no matching 'repeat')", line
				end
				table.remove(blocks)
			elseif word == "end" then
				local t = blocks[#blocks]
				if not t then
					return false, "unexpected 'end' (nothing to close)", line
				elseif t.kw == "repeat" then
					return false, "'repeat' from line " .. t.line .. " must be closed with 'until', not 'end'", line
				elseif t.needDo then
					return false, "expected 'do' after '" .. t.kw .. "' from line " .. t.line, line
				end
				table.remove(blocks)
			end
			prevSym = nil
			prevKw = word
		elseif c:match("%d") then
			local num = src:match("^%d[%w_%.]*", i)
			i = i + #num
			prevSym, prevKw = nil, nil
		else
			if OPENERS[c] then
				table.insert(brackets, { ch = c, line = line })
			elseif CLOSERS[c] then
				local b = brackets[#brackets]
				if not b then
					return false, "unexpected '" .. c .. "'", line
				elseif b.ch ~= CLOSERS[c] then
					return false, "expected '" .. OPENERS[b.ch] .. "' to close '" .. b.ch .. "' from line " .. b.line .. ", found '" .. c .. "'", line
				end
				table.remove(brackets)
			end
			prevSym = c
			prevKw = nil
			i = i + 1
		end
	end

	local t = blocks[#blocks]
	if t then
		return false, "missing 'end' for '" .. t.kw .. "' opened at line " .. t.line, t.line
	end
	local b = brackets[#brackets]
	if b then
		return false, "unclosed '" .. b.ch .. "' from line " .. b.line, b.line
	end
	return true
end

local function FormatErr(message, line)
	if line then
		return "Line " .. tostring(line) .. ": " .. tostring(message)
	end
	return tostring(message)
end

-- returns true, or false, message, line
function Library:CheckSyntax(source)
	source = tostring(source or "")
	if typeof(loadstring) == "function" then
		local ok, fn, err = pcall(loadstring, source, "=code")
		if ok then
			if fn then
				return true
			end
			local line, msg = tostring(err):match("^.-:(%d+):%s*(.*)$")
			if line then
				return false, msg, tonumber(line)
			end
			return false, tostring(err), nil
		end
	end
	return LexCheck(source)
end

-- errors

local lastErr, lastErrTime, burst, burstStart = nil, 0, 0, 0

-- callback that fails every frame can't flood the screen
function Library:Error(message, title)
	message = tostring(message)
	local now = os.clock()
	if message == lastErr and now - lastErrTime < 1.5 then
		return
	end
	lastErr, lastErrTime = message, now
	if now - burstStart > 2 then
		burstStart, burst = now, 0
	end
	burst = burst + 1
	if burst > 4 then
		return
	end
	return self:Notify({
		Title = title or "Error",
		Content = message,
		Type = "Error",
		Duration = 7,
	})
end

local function Safe(callback, ...)
	if typeof(callback) ~= "function" then
		return
	end
	local ok, err = pcall(callback, ...)
	if not ok then
		warn("[NovaUI] callback error: " .. tostring(err))
		pcall(function()
			Library:Error(tostring(err), "Script error")
		end)
	end
end

-- Library:Run("print('hi')") or Library:Run(function() ... end)
-- syntax errors and runtime errors both show up as red popups.
function Library:Run(source)
	if type(source) == "function" then
		local ok, err = pcall(source)
		if not ok then
			self:Error(err, "Runtime error")
		end
		return ok
	end

	source = tostring(source or "")
	local okSyntax, message, line = self:CheckSyntax(source)
	if not okSyntax then
		self:Error(FormatErr(message, line), "Syntax error")
		return false
	end
	if typeof(loadstring) ~= "function" then
		self:Error("loadstring isn't available here, so code can't be run from a string.", "Can't run code")
		return false
	end
	local okCompile, fn, compileErr = pcall(loadstring, source, "=code")
	if not okCompile then
		self:Error("loadstring is disabled here: " .. tostring(fn), "Can't run code")
		return false
	end
	if not fn then
		self:Error(tostring(compileErr), "Syntax error")
		return false
	end
	local okRun, runErr = pcall(fn)
	if not okRun then
		self:Error(tostring(runErr), "Runtime error")
		return false
	end
	return true
end

-- also pops up errors printed to the console by any other script
function Library:CatchErrors(on)
	if Library._errConn then
		Library._errConn:Disconnect()
		Library._errConn = nil
	end
	if not on then
		return
	end
	Library._errConn = LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageError then
			Library:Error(message, "Console error")
		end
	end)
	table.insert(Library._conns, Library._errConn)
end

-- root GUI

local function GetGui()
	if Library._gui and Library._gui.Parent then
		return Library._gui
	end
	-- parent candidates, best first: hidden UI > CoreGui > PlayerGui
	local candidates = {}
	if typeof(gethui) == "function" then
		table.insert(candidates, function()
			return gethui()
		end)
	end
	table.insert(candidates, function()
		return GetService("CoreGui")
	end)
	table.insert(candidates, function()
		return LocalPlayer:WaitForChild("PlayerGui", 10)
	end)

	local gui = New("ScreenGui", {
		Name = "NovaUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	pcall(protectgui, gui)

	local parented = false
	for _, getParent in ipairs(candidates) do
		local ok, parent = pcall(getParent)
		if ok and parent then
			-- remove a copy left behind by an earlier run of the script
			local old = parent:FindFirstChild("NovaUI")
			if old then
				pcall(function()
					old:Destroy()
				end)
			end
			if pcall(function()
				gui.Parent = parent
			end) and gui.Parent == parent then
				parented = true
				break
			end
		end
	end
	if not parented then
		error("[NovaUI] could not parent the GUI to gethui / CoreGui / PlayerGui")
	end

	Library._gui = gui
	return gui
end

function Library:Unload()
	if Library._unloaded then
		return
	end
	Library._unloaded = true
	for _, w in ipairs(Library._windows) do
		pcall(function()
			w:Destroy()
		end)
	end
	Library._windows = {}
	for _, c in ipairs(Library._conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	Library._conns = {}
	if Library._gui then
		Library._gui:Destroy()
		Library._gui = nil
	end
end

-- notifications

local function GetNotifHolder()
	local gui = GetGui()
	local holder = gui:FindFirstChild("Notifications")
	if holder then
		return holder
	end
	return New("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		AnchorPoint = IS_MOBILE and Vector2.new(1, 0) or Vector2.new(1, 1),
		Position = IS_MOBILE and UDim2.new(1, -12, 0, 48) or UDim2.new(1, -16, 1, -16),
		Size = IS_MOBILE and UDim2.new(0, 240, 1, -60) or UDim2.new(0, 300, 1, -32),
		ZIndex = 5,
		Parent = gui,
	}, {
		New("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = IS_MOBILE and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom,
		}),
	})
end

--[[
	Library:Notify({
		Title = "Hello", Content = "Body text", Duration = 4,
		Type = "Info" | "Success" | "Warning" | "Error",
	})
	Library:Notify("just text")
]]
function Library:Notify(opts)
	if Library._unloaded then
		return
	end
	if type(opts) ~= "table" then
		opts = { Content = tostring(opts) }
	end
	local duration = opts.Duration or 4
	local color = Theme[opts.Type or "Info"] or Theme.Info
	local holder = GetNotifHolder()

	local wrapper = New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = holder,
	})

	local card = New("Frame", {
		BackgroundColor3 = Theme.Topbar,
		Position = UDim2.new(1.3, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = wrapper,
	}, {
		Corner(8),
		Stroke(color, 1, 0.45),
		Pad(12, 10, 12, 10),
		VList(4),
	})

	Text({
		LayoutOrder = 1,
		Text = opts.Title or "Notification",
		Font = Enum.Font.GothamBold,
		TextColor3 = color,
		TextSize = 15,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})

	if opts.Content and opts.Content ~= "" then
		Text({
			LayoutOrder = 2,
			Text = tostring(opts.Content),
			TextColor3 = Theme.SubText,
			TextSize = 13,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = card,
		})
	end

	local bar = New("Frame", {
		LayoutOrder = 3,
		BackgroundColor3 = Theme.Element,
		Size = UDim2.new(1, 0, 0, 3),
		Parent = card,
	}, { Corner(2) })
	local fill = New("Frame", {
		BackgroundColor3 = color,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = bar,
	}, { Corner(2) })

	local dismissed = false
	local function dismiss()
		if dismissed then
			return
		end
		dismissed = true
		local tw = Tween(card, { Position = UDim2.new(1.3, 0, 0, 0) }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		tw.Completed:Connect(function()
			wrapper:Destroy()
		end)
	end

	card.InputBegan:Connect(function(input)
		if IsPointer(input) then
			dismiss()
		end
	end)

	Tween(card, { Position = UDim2.new(0, 0, 0, 0) }, 0.4, Enum.EasingStyle.Back)
	Tween(fill, { Size = UDim2.new(0, 0, 1, 0) }, duration, Enum.EasingStyle.Linear)
	task.delay(duration, dismiss)

	return { Dismiss = dismiss }
end

-- dialog (modal confirm box)

--[[
	Library:Dialog({
		Title = "Are you sure?", Content = "This can't be undone.",
		Buttons = { { Name = "Yes", Callback = function() end }, { Name = "No" } },
	})
]]
function Library:Dialog(o)
	o = o or {}
	local gui = GetGui()
	local buttons = o.Buttons or { { Name = "OK" } }

	local overlay = New("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = gui,
	})
	Tween(overlay, { BackgroundTransparency = 0.45 }, 0.2)

	local card = New("Frame", {
		BackgroundColor3 = Theme.Topbar,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, IS_MOBILE and 280 or 340, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = overlay,
	}, {
		Corner(10),
		Stroke(Theme.Accent, 1, 0.5),
		Pad(16, 14, 16, 14),
		VList(10),
	})

	Text({
		LayoutOrder = 1,
		Text = o.Title or "Notice",
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	if o.Content and o.Content ~= "" then
		Text({
			LayoutOrder = 2,
			Text = tostring(o.Content),
			TextColor3 = Theme.SubText,
			TextSize = 13,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = card,
		})
	end

	local row = New("Frame", {
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, IS_MOBILE and 38 or 32),
		Parent = card,
	}, {
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local function close()
		if overlay.Parent then
			overlay:Destroy()
		end
	end

	local n = #buttons
	for i, b in ipairs(buttons) do
		local primary = (i == 1)
		local btn = New("TextButton", {
			LayoutOrder = i,
			AutoButtonColor = false,
			BackgroundColor3 = primary and Theme.Accent or Theme.Element,
			Size = UDim2.new(1 / n, -(8 * (n - 1)) / n, 1, 0),
			Font = Enum.Font.GothamMedium,
			Text = b.Name or "OK",
			TextColor3 = Theme.Text,
			TextSize = 13,
			Parent = row,
		}, { Corner(6) })
		btn.MouseButton1Click:Connect(function()
			close()
			Safe(b.Callback)
		end)
	end

	return { Close = close }
end

-- watermark (text + fps)

function Library:SetWatermark(text)
	local gui = GetGui()
	local wm = gui:FindFirstChild("Watermark")
	if not text then
		if wm then
			wm:Destroy()
		end
		if Library._wmConn then
			Library._wmConn:Disconnect()
			Library._wmConn = nil
		end
		return
	end

	if not wm then
		wm = New("Frame", {
			Name = "Watermark",
			BackgroundColor3 = Theme.Topbar,
			Position = UDim2.new(0, 12, 0, 12),
			Size = UDim2.new(0, 0, 0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = gui,
		}, { Corner(6), Stroke(Theme.Accent, 1, 0.5), Pad(10, 0, 10, 0) })
		New("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = Theme.Text,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "",
			Parent = wm,
		})
	end
	Library._wmText = tostring(text)
	wm.Label.Text = Library._wmText

	if not Library._wmConn then
		local frames, last = 0, os.clock()
		Library._wmConn = RunService.Heartbeat:Connect(function()
			frames = frames + 1
			local now = os.clock()
			if now - last >= 1 then
				local fps = math.floor(frames / (now - last) + 0.5)
				frames, last = 0, now
				local w = Library._gui and Library._gui:FindFirstChild("Watermark")
				local l = w and w:FindFirstChild("Label")
				if l then
					l.Text = Library._wmText .. "  |  " .. fps .. " fps"
				end
			end
		end)
		table.insert(Library._conns, Library._wmConn)
	end
end

-- configs (executors with writefile / readfile only)

local CONFIG_DIR = "NovaUI"

local function Serialize(obj)
	local v = obj:Get()
	if obj.Type == "Keybind" then
		return v and v.Name or "None"
	elseif obj.Type == "ColorPicker" then
		return { math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5) }
	end
	return v
end

local function Deserialize(obj, v)
	if obj.Type == "Keybind" then
		obj:Set(v ~= "None" and Enum.KeyCode[v] or nil)
	elseif obj.Type == "ColorPicker" then
		obj:Set(Color3.fromRGB(v[1], v[2], v[3]))
	else
		obj:Set(v)
	end
end

local function CleanName(name)
	name = tostring(name or ""):gsub("[^%w_%-]", "")
	if name == "" then
		name = "default"
	end
	return name
end

local function HasFiles()
	return typeof(writefile) == "function" and typeof(readfile) == "function"
end

function Library:GetConfigs()
	local out = {}
	if typeof(listfiles) ~= "function" or typeof(isfolder) ~= "function" or not isfolder(CONFIG_DIR) then
		return out
	end
	local ok, files = pcall(listfiles, CONFIG_DIR)
	if ok and type(files) == "table" then
		for _, f in ipairs(files) do
			local n = tostring(f):match("([^/\\]+)%.json$")
			if n then
				table.insert(out, n)
			end
		end
	end
	table.sort(out)
	return out
end

function Library:SaveConfig(name, overwrite)
	if not HasFiles() then
		self:Error("This environment has no writefile/readfile, so configs can't be saved.", "Config")
		return false
	end
	name = CleanName(name)
	local data = {}
	for flag, obj in pairs(Library.Flags) do
		local ok, v = pcall(Serialize, obj)
		if ok and v ~= nil then
			data[flag] = v
		end
	end
	local ok, err = pcall(function()
		if typeof(isfolder) == "function" and typeof(makefolder) == "function" and not isfolder(CONFIG_DIR) then
			makefolder(CONFIG_DIR)
		end
		writefile(CONFIG_DIR .. "/" .. name .. ".json", HttpService:JSONEncode(data))
	end)
	if not ok then
		self:Error(tostring(err), "Config save failed")
		return false
	end
	self:Notify({ Title = overwrite and "Config overwritten" or "Config saved", Content = name, Type = "Success", Duration = 2.5 })
	return true
end

function Library:LoadConfig(name, auto)
	if not HasFiles() then
		self:Error("This environment has no writefile/readfile, so configs can't be loaded.", "Config")
		return false
	end
	name = CleanName(name)
	local path = CONFIG_DIR .. "/" .. name .. ".json"
	if typeof(isfile) == "function" and not isfile(path) then
		self:Error("No config named '" .. name .. "'.", "Config")
		return false
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(path))
	end)
	if not ok or type(data) ~= "table" then
		self:Error("Config '" .. name .. "' is not valid JSON.", "Config load failed")
		return false
	end
	for flag, value in pairs(data) do
		local obj = Library.Flags[flag]
		if obj then
			local okSet, err = pcall(Deserialize, obj, value)
			if not okSet then
				warn("[NovaUI] could not load flag '" .. tostring(flag) .. "': " .. tostring(err))
			end
		end
	end
	self:Notify({ Title = auto and "Auto loaded config" or "Config loaded", Content = name, Type = "Success", Duration = 2.5 })
	return true
end

local AUTOLOAD_FILE = CONFIG_DIR .. "/autoload.txt"

local function ConfigPath(name)
	return CONFIG_DIR .. "/" .. name .. ".json"
end

function Library:ConfigExists(name)
	if typeof(isfile) ~= "function" then
		return false
	end
	local ok, found = pcall(isfile, ConfigPath(CleanName(name)))
	return ok and found == true
end

function Library:OverwriteConfig(name)
	name = CleanName(name)
	if not self:ConfigExists(name) then
		self:Error("No config named '" .. name .. "' to overwrite.", "Config")
		return false
	end
	return self:SaveConfig(name, true)
end

function Library:DeleteConfig(name)
	if typeof(delfile) ~= "function" then
		self:Error("This environment has no delfile, so configs can't be deleted.", "Config")
		return false
	end
	name = CleanName(name)
	if not self:ConfigExists(name) then
		self:Error("No config named '" .. name .. "'.", "Config")
		return false
	end
	local ok, err = pcall(delfile, ConfigPath(name))
	if not ok then
		self:Error(tostring(err), "Config delete failed")
		return false
	end
	-- a deleted config can't stay as the auto load one
	if self:GetAutoLoad() == name then
		pcall(delfile, AUTOLOAD_FILE)
	end
	self:Notify({ Title = "Config deleted", Content = name, Type = "Success", Duration = 2.5 })
	return true
end

-- name of the config that loads on startup, or nil
function Library:GetAutoLoad()
	if typeof(isfile) ~= "function" or typeof(readfile) ~= "function" then
		return nil
	end
	local okFile, hasFile = pcall(isfile, AUTOLOAD_FILE)
	if not okFile or not hasFile then
		return nil
	end
	local ok, text = pcall(readfile, AUTOLOAD_FILE)
	if not ok or type(text) ~= "string" then
		return nil
	end
	local name = CleanName((text:gsub("%s+", "")))
	if text:gsub("%s+", "") == "" or not self:ConfigExists(name) then
		return nil
	end
	return name
end

function Library:SetAutoLoad(name)
	if not HasFiles() then
		self:Error("This environment has no writefile/readfile, so auto load can't be set.", "Config")
		return false
	end
	name = CleanName(name)
	if not self:ConfigExists(name) then
		self:Error("No config named '" .. name .. "'.", "Config")
		return false
	end
	local ok, err = pcall(writefile, AUTOLOAD_FILE, name)
	if not ok then
		self:Error(tostring(err), "Auto load failed")
		return false
	end
	self:Notify({ Title = "Auto load set", Content = name, Type = "Success", Duration = 2.5 })
	return true
end

-- pass a name to only clear it when that config is the auto load one
function Library:ClearAutoLoad(name)
	local current = self:GetAutoLoad()
	if not current then
		self:Notify({ Title = "Auto load", Content = "No auto load config is set.", Type = "Warning", Duration = 2.5 })
		return false
	end
	if name ~= nil and CleanName(name) ~= current then
		self:Notify({
			Title = "Auto load",
			Content = "'" .. CleanName(name) .. "' is not the auto load config (it is '" .. current .. "').",
			Type = "Warning",
			Duration = 3.5,
		})
		return false
	end
	if typeof(delfile) ~= "function" then
		self:Error("This environment has no delfile, so auto load can't be removed.", "Config")
		return false
	end
	local ok, err = pcall(delfile, AUTOLOAD_FILE)
	if not ok then
		self:Error(tostring(err), "Auto load failed")
		return false
	end
	self:Notify({ Title = "Auto load removed", Content = current, Type = "Success", Duration = 2.5 })
	return true
end

function Library:AutoLoad()
	local name = self:GetAutoLoad()
	if not name then
		return false
	end
	return self:LoadConfig(name, true)
end

-- window

--[[
	Library:CreateWindow({
		Title = "My Hub", Subtitle = "v1.0",
		Size = UDim2.fromOffset(580, 380),
		ToggleKey = Enum.KeyCode.RightShift,
	})
]]
function Library:CreateWindow(opts)
	opts = opts or {}
	local gui = GetGui()
	local window = { Connections = {}, Tabs = {}, Visible = true }
	local toggleKey = opts.ToggleKey or Enum.KeyCode.RightShift
	local size = opts.Size or (IS_MOBILE and UDim2.fromOffset(460, 290) or UDim2.fromOffset(580, 380))
	table.insert(Library._windows, window)

	local function track(conn)
		table.insert(window.Connections, conn)
		return conn
	end

	-- fit any screen (re-evaluated on rotate / resize)
	local targetScale = 1
	local cam = workspace.CurrentCamera
	local scale -- UIScale, assigned below
	local function fit()
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		if vp.X < 200 or vp.Y < 200 then
			-- studio reports a 1x1 viewport for a moment at startup
			targetScale = 1
		else
			targetScale = math.min(1, vp.X / (size.X.Offset + 40), vp.Y / (size.Y.Offset + 40))
		end
		if scale and window.Visible then
			Tween(scale, { Scale = targetScale }, 0.2)
		end
	end
	fit()

	local main = New("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = Theme.Background,
		ClipsDescendants = true,
		Parent = gui,
	}, { Corner(10), Stroke(Theme.Accent, 1, 0.6) })
	scale = New("UIScale", { Scale = 0, Parent = main })
	Tween(scale, { Scale = targetScale }, 0.45, Enum.EasingStyle.Back)
	if cam then
		track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit))
	end

	-- topbar
	local topbar = New("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Topbar,
		Parent = main,
	})
	Text({
		Text = opts.Title or "NovaUI",
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Position = UDim2.new(0, 14, 0, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Parent = topbar,
	})
	Text({
		Text = opts.Subtitle or "",
		TextColor3 = Theme.SubText,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.4, 0, 0, 0),
		Size = UDim2.new(0.6, -50, 1, 0),
		Parent = topbar,
	})

	local closeBtn = New("TextButton", {
		Text = "X",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = Theme.Text,
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Element,
		Position = UDim2.new(1, IS_MOBILE and -40 or -36, 0, IS_MOBILE and 4 or 6),
		Size = UDim2.fromOffset(IS_MOBILE and 32 or 28, IS_MOBILE and 32 or 28),
		Parent = topbar,
	}, { Corner(6) })
	closeBtn.MouseEnter:Connect(function()
		Tween(closeBtn, { BackgroundColor3 = Theme.Error }, 0.15)
	end)
	closeBtn.MouseLeave:Connect(function()
		Tween(closeBtn, { BackgroundColor3 = Theme.Element }, 0.15)
	end)
	closeBtn.MouseButton1Click:Connect(function()
		window:Toggle(false)
		Library:Notify({
			Title = "Window hidden",
			Content = IS_MOBILE and "Tap the UI button to reopen." or ("Press " .. toggleKey.Name .. " to reopen."),
			Duration = 3,
			Type = "Info",
		})
	end)

	-- dragging (mouse + touch)
	local dragging, dragStart, startPos, dragInput = false, nil, nil, nil
	topbar.InputBegan:Connect(function(input)
		if IsPointer(input) then
			dragging = true
			dragInput = input
			dragStart = input.Position
			startPos = main.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput) then
			local d = (input.Position - dragStart) / math.max(scale.Scale, 0.01)
			main.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
		end
	end))

	-- sidebar + pages
	local sidebar = New("ScrollingFrame", {
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(0, SIDEBAR_W, 1, -40),
		BackgroundColor3 = Theme.Topbar,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 0,
		Parent = main,
	}, {
		VList(4),
		Pad(8, 8, 8, 8),
	})
	local pages = New("Frame", {
		Position = UDim2.new(0, SIDEBAR_W, 0, 40),
		Size = UDim2.new(1, -SIDEBAR_W, 1, -40),
		BackgroundTransparency = 1,
		Parent = main,
	})

	local function selectTab(tab)
		for _, t in ipairs(window.Tabs) do
			local active = (t == tab)
			t.Page.Visible = active
			Tween(t.TabButton, { BackgroundTransparency = active and 0.5 or 1 }, 0.15)
			Tween(t.TabLabel, { TextColor3 = active and Theme.Text or Theme.SubText }, 0.15)
			Tween(t.Indicator, { Size = UDim2.new(0, 3, 0, active and 16 or 0) }, 0.2)
		end
		window.Current = tab
	end

	function window:SelectTab(name)
		for _, t in ipairs(window.Tabs) do
			if t.Name == name then
				selectTab(t)
				return
			end
		end
	end

	-- tabs & elements

	function window:CreateTab(name)
		local tab = { Name = name }

		local button = New("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Element,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, TAB_H),
			LayoutOrder = #window.Tabs + 1,
			Parent = sidebar,
		}, { Corner(6) })
		local label = Text({
			Text = name,
			TextColor3 = Theme.SubText,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.new(0, 14, 0, 0),
			Size = UDim2.new(1, -14, 1, 0),
			Parent = button,
		})
		local indicator = New("Frame", {
			BackgroundColor3 = Theme.Accent,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(0, 3, 0, 0),
			Parent = button,
		}, { Corner(2) })

		local page = New("ScrollingFrame", {
			Visible = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Theme.Accent,
			Parent = pages,
		}, {
			VList(6),
			Pad(10, 10, 12, 10),
		})

		tab.TabButton, tab.TabLabel, tab.Indicator, tab.Page = button, label, indicator, page
		table.insert(window.Tabs, tab)
		button.MouseButton1Click:Connect(function()
			selectTab(tab)
		end)
		if #window.Tabs == 1 then
			selectTab(tab)
		end

		local order = 0
		local function NextOrder()
			order = order + 1
			return order
		end

		local function Row(height)
			local f = New("Frame", {
				BackgroundColor3 = Theme.Element,
				Size = UDim2.new(1, 0, 0, math.max(height or ROW_H, ROW_H)),
				LayoutOrder = NextOrder(),
				Parent = page,
			}, { Corner(6) })
			Hover(f)
			return f
		end

		local function RowLabel(parent, txt)
			return Text({
				Text = txt,
				Position = UDim2.new(0, 12, 0, 0),
				Size = UDim2.new(1, -24, 0, ROW_H),
				Parent = parent,
			})
		end

		local function Overlay(parent)
			return New("TextButton", {
				BackgroundTransparency = 1,
				Text = "",
				Size = UDim2.fromScale(1, 1),
				Parent = parent,
			})
		end

		-- section header
		function tab:Section(txt)
			Text({
				Text = string.upper(txt),
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				TextColor3 = Theme.Accent,
				Size = UDim2.new(1, 0, 0, 22),
				LayoutOrder = NextOrder(),
				Parent = page,
			})
		end

		-- thin separator line
		function tab:Divider()
			local holder = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 10),
				LayoutOrder = NextOrder(),
				Parent = page,
			})
			New("Frame", {
				BackgroundColor3 = Theme.Element,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.new(1, 0, 0, 1),
				Parent = holder,
			})
		end

		-- label (wrapped text)
		function tab:Label(txt)
			local l = Text({
				Text = txt,
				TextColor3 = Theme.SubText,
				TextSize = 13,
				TextWrapped = true,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = NextOrder(),
				Parent = page,
			})
			local obj = {}
			function obj:Set(t)
				l.Text = t
			end
			return obj
		end

		-- paragraph (card with a title and body text)
		function tab:Paragraph(o)
			local card = New("Frame", {
				BackgroundColor3 = Theme.Element,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = NextOrder(),
				Parent = page,
			}, { Corner(6), Pad(12, 10, 12, 10), VList(4) })
			local title = Text({
				LayoutOrder = 1,
				Text = o.Title or "",
				Font = Enum.Font.GothamBold,
				TextWrapped = true,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = card,
			})
			local body = Text({
				LayoutOrder = 2,
				Text = o.Content or "",
				TextColor3 = Theme.SubText,
				TextSize = 13,
				TextWrapped = true,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = card,
			})
			local obj = {}
			function obj:Set(t, c)
				if t ~= nil then
					title.Text = t
				end
				if c ~= nil then
					body.Text = c
				end
			end
			return obj
		end

		-- button (DoubleClick = true asks for a second click to confirm)
		function tab:Button(o)
			local row = Row(36)
			local lbl = RowLabel(row, o.Name or "Button")
			local btn = Overlay(row)
			local lastClick = 0
			btn.MouseButton1Click:Connect(function()
				if o.DoubleClick then
					local now = os.clock()
					if now - lastClick > 0.8 then
						lastClick = now
						lbl.Text = "Click again to confirm"
						task.delay(0.8, function()
							if lbl.Parent then
								lbl.Text = o.Name or "Button"
							end
						end)
						return
					end
					lastClick = 0
					lbl.Text = o.Name or "Button"
				end
				row.BackgroundColor3 = Theme.Accent
				Tween(row, { BackgroundColor3 = Theme.Element }, 0.4)
				Safe(o.Callback)
			end)
			local obj = {}
			function obj:SetText(t)
				lbl.Text = t
			end
			return obj
		end

		-- toggle
		function tab:Toggle(o)
			local state = o.Default == true
			local row = Row(36)
			RowLabel(row, o.Name or "Toggle")
			local track_ = New("Frame", {
				BackgroundColor3 = Theme.Background,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(40, 20),
				Parent = row,
			}, { Corner(10) })
			local knob = New("Frame", {
				BackgroundColor3 = Theme.SubText,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 3, 0.5, 0),
				Size = UDim2.fromOffset(14, 14),
				Parent = track_,
			}, { Corner(7) })
			local btn = Overlay(row)

			local obj = {}
			local function render()
				Tween(track_, { BackgroundColor3 = state and Theme.Accent or Theme.Background }, 0.2)
				Tween(knob, {
					Position = state and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
					BackgroundColor3 = state and Color3.new(1, 1, 1) or Theme.SubText,
				}, 0.2)
			end
			function obj:Set(v, silent)
				state = v and true or false
				render()
				if not silent then
					Safe(o.Callback, state)
				end
			end
			function obj:Get()
				return state
			end
			btn.MouseButton1Click:Connect(function()
				obj:Set(not state)
			end)
			render()
			return Register(o.Flag, obj, "Toggle")
		end

		-- slider
		function tab:Slider(o)
			local min, max = o.Min or 0, o.Max or 100
			local inc = o.Increment or 1
			local range = math.max(max - min, 1e-9)
			local value = math.clamp(o.Default or min, min, max)

			local row = Row(IS_MOBILE and 62 or 54)
			Text({
				Text = o.Name or "Slider",
				Position = UDim2.new(0, 12, 0, 4),
				Size = UDim2.new(0.6, 0, 0, 24),
				Parent = row,
			})
			local valueLabel = Text({
				TextColor3 = Theme.SubText,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.new(0.5, 0, 0, 4),
				Size = UDim2.new(0.5, -12, 0, 24),
				Parent = row,
			})
			local bar = New("Frame", {
				BackgroundColor3 = Theme.Background,
				Position = UDim2.new(0, 12, 0, IS_MOBILE and 44 or 38),
				Size = UDim2.new(1, -24, 0, 6),
				Parent = row,
			}, { Corner(3) })
			local fill = New("Frame", {
				BackgroundColor3 = Theme.Accent,
				Size = UDim2.new(0, 0, 1, 0),
				Parent = bar,
			}, { Corner(3) })
			local knob = New("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(IS_MOBILE and 20 or 14, IS_MOBILE and 20 or 14),
				ZIndex = 2,
				Parent = bar,
			}, { Corner(10) })
			local hit = New("TextButton", {
				BackgroundTransparency = 1,
				Text = "",
				Position = UDim2.new(0, 0, 0, IS_MOBILE and 26 or 28),
				Size = UDim2.new(1, 0, 0, IS_MOBILE and 36 or 26),
				Parent = row,
			})

			local obj = {}
			local function render()
				local a = (value - min) / range
				Tween(fill, { Size = UDim2.new(a, 0, 1, 0) }, 0.08)
				Tween(knob, { Position = UDim2.new(a, 0, 0.5, 0) }, 0.08)
				valueLabel.Text = Fmt(value) .. (o.Suffix or "")
			end
			function obj:Set(v, silent)
				v = tonumber(v) or min
				v = math.clamp(min + math.floor((v - min) / inc + 0.5) * inc, min, max)
				if v == value and not silent then
					return
				end
				value = v
				render()
				if not silent then
					Safe(o.Callback, value)
				end
			end
			function obj:Get()
				return value
			end

			local dragging_ = false
			local activeInput = nil
			local function update(x)
				local a = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
				obj:Set(min + a * range)
			end
			hit.InputBegan:Connect(function(input)
				if IsPointer(input) then
					dragging_ = true
					activeInput = input
					page.ScrollingEnabled = false
					update(input.Position.X)
				end
			end)
			track(UserInputService.InputChanged:Connect(function(input)
				if dragging_ and (input.UserInputType == Enum.UserInputType.MouseMovement or input == activeInput) then
					update(input.Position.X)
				end
			end))
			track(UserInputService.InputEnded:Connect(function(input)
				if dragging_ and (input == activeInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
					dragging_ = false
					page.ScrollingEnabled = true
				end
			end))

			render()
			return Register(o.Flag, obj, "Slider")
		end

		-- progress bar (read-only, Set(0..1))
		function tab:Progress(o)
			local value = math.clamp(o.Default or 0, 0, 1)
			local row = Row(IS_MOBILE and 56 or 50)
			Text({
				Text = o.Name or "Progress",
				Position = UDim2.new(0, 12, 0, 4),
				Size = UDim2.new(0.6, 0, 0, 24),
				Parent = row,
			})
			local pct = Text({
				TextColor3 = Theme.SubText,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.new(0.5, 0, 0, 4),
				Size = UDim2.new(0.5, -12, 0, 24),
				Parent = row,
			})
			local bar = New("Frame", {
				BackgroundColor3 = Theme.Background,
				Position = UDim2.new(0, 12, 0, IS_MOBILE and 40 or 36),
				Size = UDim2.new(1, -24, 0, 8),
				Parent = row,
			}, { Corner(4) })
			local fill = New("Frame", {
				BackgroundColor3 = Theme.Accent,
				Size = UDim2.new(value, 0, 1, 0),
				Parent = bar,
			}, { Corner(4) })
			pct.Text = math.floor(value * 100 + 0.5) .. "%"

			local obj = {}
			function obj:Set(v)
				value = math.clamp(tonumber(v) or 0, 0, 1)
				Tween(fill, { Size = UDim2.new(value, 0, 1, 0) }, 0.2)
				pct.Text = math.floor(value * 100 + 0.5) .. "%"
			end
			function obj:Get()
				return value
			end
			return obj
		end

		function tab:Dropdown(o)
			local options = o.Options or {}
			local multi = o.Multi == true
			local searchable = o.Searchable == true
			local selected = multi and {} or nil
			local isOpen = false
			local query = ""
			local searchH = searchable and (OPT_H + 4) or 0

			if multi then
				for _, v in ipairs(o.Default or {}) do
					selected[v] = true
				end
			else
				selected = o.Default
			end

			local frame = New("Frame", {
				BackgroundColor3 = Theme.Element,
				ClipsDescendants = true,
				Size = UDim2.new(1, 0, 0, ROW_H),
				LayoutOrder = NextOrder(),
				Parent = page,
			}, { Corner(6) })
			Hover(frame)

			Text({
				Text = o.Name or "Dropdown",
				Position = UDim2.new(0, 12, 0, 0),
				Size = UDim2.new(0.5, -12, 0, ROW_H),
				Parent = frame,
			})
			local valueLabel = Text({
				Text = "None",
				TextColor3 = Theme.SubText,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.new(0.5, -36, 0, ROW_H),
				Parent = frame,
			})
			local arrow = Text({
				Text = "v",
				Font = Enum.Font.GothamBold,
				TextColor3 = Theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -18, 0, ROW_H / 2),
				Size = UDim2.fromOffset(20, 20),
				Parent = frame,
			})
			local header = New("TextButton", {
				BackgroundTransparency = 1,
				Text = "",
				Size = UDim2.new(1, 0, 0, ROW_H),
				Parent = frame,
			})

			local searchBox
			if searchable then
				searchBox = New("TextBox", {
					BackgroundColor3 = Theme.Background,
					Position = UDim2.new(0, 6, 0, ROW_H + 4),
					Size = UDim2.new(1, -12, 0, OPT_H),
					Font = Enum.Font.Gotham,
					Text = "",
					PlaceholderText = "Search...",
					PlaceholderColor3 = Theme.SubText,
					TextColor3 = Theme.Text,
					TextSize = 13,
					ClearTextOnFocus = false,
					Parent = frame,
				}, { Corner(5), Pad(8, 0, 8, 0) })
			end

			local list = New("ScrollingFrame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 6, 0, ROW_H + 4 + searchH),
				Size = UDim2.new(1, -12, 0, 0),
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 2,
				ScrollBarImageColor3 = Theme.Accent,
				Parent = frame,
			}, {
				VList(3),
			})

			local obj = {}
			local buttons = {}

			local function isSelected(opt)
				if multi then
					return selected[opt] == true
				end
				return selected == opt
			end

			local function getValue()
				if multi then
					local out = {}
					for _, opt in ipairs(options) do
						if selected[opt] then
							table.insert(out, opt)
						end
					end
					return out
				end
				return selected
			end

			local function refresh()
				for _, item in ipairs(buttons) do
					local sel = isSelected(item.Option)
					Tween(item.Button, {
						BackgroundColor3 = sel and Theme.Accent or Theme.Background,
						TextColor3 = sel and Color3.new(1, 1, 1) or Theme.SubText,
					}, 0.12)
				end
				if multi then
					local names = {}
					for _, v in ipairs(getValue()) do
						table.insert(names, tostring(v))
					end
					valueLabel.Text = #names > 0 and table.concat(names, ", ") or "None"
				else
					valueLabel.Text = selected ~= nil and tostring(selected) or "None"
				end
			end

			local function visibleCount()
				local n = 0
				for _, item in ipairs(buttons) do
					if item.Button.Visible then
						n = n + 1
					end
				end
				return n
			end

			local function setOpen(v)
				isOpen = v
				local n = visibleCount()
				local h = math.min(n * OPT_H + math.max(n - 1, 0) * 3, 140)
				list.Size = UDim2.new(1, -12, 0, h)
				Tween(frame, { Size = UDim2.new(1, 0, 0, v and (ROW_H + 4 + searchH + h + 8) or ROW_H) }, 0.2)
				Tween(arrow, { Rotation = v and 180 or 0 }, 0.2)
			end

			local function applyFilter()
				local q = string.lower(query)
				for _, item in ipairs(buttons) do
					item.Button.Visible = q == "" or string.find(string.lower(tostring(item.Option)), q, 1, true) ~= nil
				end
				if isOpen then
					setOpen(true)
				end
			end

			local function build()
				for _, item in ipairs(buttons) do
					item.Button:Destroy()
				end
				buttons = {}
				for i, opt in ipairs(options) do
					local b = New("TextButton", {
						LayoutOrder = i,
						AutoButtonColor = false,
						BackgroundColor3 = Theme.Background,
						Size = UDim2.new(1, 0, 0, OPT_H),
						Font = Enum.Font.Gotham,
						Text = tostring(opt),
						TextColor3 = Theme.SubText,
						TextSize = 13,
						Parent = list,
					}, { Corner(5) })
					b.MouseButton1Click:Connect(function()
						if multi then
							selected[opt] = not selected[opt] or nil
						else
							selected = opt
							setOpen(false)
						end
						refresh()
						Safe(o.Callback, getValue())
					end)
					table.insert(buttons, { Option = opt, Button = b })
				end
				refresh()
				applyFilter()
			end

			function obj:Set(v, silent)
				if multi then
					selected = {}
					for _, x in ipairs(v or {}) do
						selected[x] = true
					end
				else
					selected = v
				end
				refresh()
				if not silent then
					Safe(o.Callback, getValue())
				end
			end
			function obj:Get()
				return getValue()
			end
			function obj:Refresh(newOptions)
				options = newOptions or {}
				if multi then
					for k in pairs(selected) do
						if not table.find(options, k) then
							selected[k] = nil
						end
					end
				elseif selected ~= nil and not table.find(options, selected) then
					selected = nil
				end
				build()
			end

			header.MouseButton1Click:Connect(function()
				setOpen(not isOpen)
			end)
			if searchBox then
				searchBox:GetPropertyChangedSignal("Text"):Connect(function()
					query = searchBox.Text
					applyFilter()
				end)
			end
			build()
			return Register(o.Flag, obj, "Dropdown")
		end

		-- textbox
		function tab:Textbox(o)
			local row = Row(36)
			RowLabel(row, o.Name or "Textbox")
			local box = New("TextBox", {
				BackgroundColor3 = Theme.Background,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.new(0, IS_MOBILE and 120 or 150, 0, IS_MOBILE and 30 or 24),
				Font = Enum.Font.Gotham,
				Text = o.Default or "",
				PlaceholderText = o.Placeholder or "Type here...",
				PlaceholderColor3 = Theme.SubText,
				TextColor3 = Theme.Text,
				TextSize = 13,
				ClearTextOnFocus = false,
				Parent = row,
			}, { Corner(5), Pad(8, 0, 8, 0) })
			box.Focused:Connect(function()
				Tween(box, { BackgroundColor3 = Theme.ElementHover }, 0.15)
			end)
			box.FocusLost:Connect(function(enter)
				Tween(box, { BackgroundColor3 = Theme.Background }, 0.15)
				Safe(o.Callback, box.Text, enter)
			end)
			local obj = {}
			function obj:Set(t, silent)
				box.Text = tostring(t)
				if not silent then
					Safe(o.Callback, box.Text, false)
				end
			end
			function obj:Get()
				return box.Text
			end
			return Register(o.Flag, obj, "Textbox")
		end

		function tab:Keybind(o)
			local key = o.Default
			local mode = o.Mode or "Press"
			local state = false
			local listening = false
			local row = Row(36)
			RowLabel(row, o.Name or "Keybind")
			local btn = New("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Background,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(80, IS_MOBILE and 30 or 24),
				Font = Enum.Font.GothamMedium,
				Text = key and key.Name or "None",
				TextColor3 = Theme.SubText,
				TextSize = 12,
				Parent = row,
			}, { Corner(5) })
			btn.MouseButton1Click:Connect(function()
				listening = true
				btn.Text = "..."
			end)
			track(UserInputService.InputBegan:Connect(function(input, gp)
				if listening then
					if input.UserInputType == Enum.UserInputType.Keyboard then
						listening = false
						key = (input.KeyCode ~= Enum.KeyCode.Escape) and input.KeyCode or nil
						btn.Text = key and key.Name or "None"
						Safe(o.Changed, key)
					end
					return
				end
				if gp or not key or input.KeyCode ~= key then
					return
				end
				if mode == "Toggle" then
					state = not state
					Safe(o.Callback, state)
				elseif mode == "Hold" then
					state = true
					Safe(o.Callback, true)
				else
					Safe(o.Callback)
				end
			end))
			track(UserInputService.InputEnded:Connect(function(input)
				if mode == "Hold" and state and key and input.KeyCode == key then
					state = false
					Safe(o.Callback, false)
				end
			end))
			local obj = {}
			function obj:Get()
				return key
			end
			function obj:Set(k)
				key = k
				btn.Text = key and key.Name or "None"
			end
			return Register(o.Flag, obj, "Keybind")
		end

		-- colour picker (click the row to expand)
		function tab:ColorPicker(o)
			local color = o.Default or Color3.fromRGB(255, 255, 255)
			local h, s, v = color:ToHSV()
			local isOpen = false
			local SV_H = IS_MOBILE and 150 or 120
			local HUE_H = IS_MOBILE and 20 or 14
			local fullH = ROW_H + 8 + SV_H + 8 + HUE_H + 12

			local frame = New("Frame", {
				BackgroundColor3 = Theme.Element,
				ClipsDescendants = true,
				Size = UDim2.new(1, 0, 0, ROW_H),
				LayoutOrder = NextOrder(),
				Parent = page,
			}, { Corner(6) })
			Hover(frame)
			Text({
				Text = o.Name or "Color",
				Position = UDim2.new(0, 12, 0, 0),
				Size = UDim2.new(1, -70, 0, ROW_H),
				Parent = frame,
			})
			local swatch = New("Frame", {
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, (ROW_H - 20) / 2),
				Size = UDim2.fromOffset(40, 20),
				Parent = frame,
			}, { Corner(5), Stroke(Theme.Background, 1, 0) })
			local header = New("TextButton", {
				BackgroundTransparency = 1,
				Text = "",
				Size = UDim2.new(1, 0, 0, ROW_H),
				Parent = frame,
			})

			-- saturation / value square
			local sv = New("Frame", {
				BackgroundColor3 = Color3.fromHSV(h, 1, 1),
				Position = UDim2.new(0, 12, 0, ROW_H + 8),
				Size = UDim2.new(1, -24, 0, SV_H),
				Parent = frame,
			}, { Corner(5) })
			New("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				Size = UDim2.fromScale(1, 1),
				Parent = sv,
			}, { Corner(5), New("UIGradient", { Transparency = NumberSequence.new(0, 1) }) })
			New("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				Size = UDim2.fromScale(1, 1),
				Parent = sv,
			}, { Corner(5), New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }) })
			local cursor = New("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(12, 12),
				Parent = sv,
			}, { Corner(6), Stroke(Color3.new(1, 1, 1), 2, 0) })
			local svHit = New("TextButton", {
				BackgroundTransparency = 1,
				Text = "",
				Size = UDim2.fromScale(1, 1),
				Parent = sv,
			})

			-- hue bar
			local hue = New("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				Position = UDim2.new(0, 12, 0, ROW_H + 8 + SV_H + 8),
				Size = UDim2.new(1, -24, 0, HUE_H),
				Parent = frame,
			}, {
				Corner(5),
				New("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
						ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
						ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
						ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
						ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
						ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
					}),
				}),
			})
			local hueMark = New("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.new(0, 4, 1, 4),
				Parent = hue,
			}, { Corner(2), Stroke(Color3.new(0, 0, 0), 1, 0.4) })
			local hueHit = New("TextButton", {
				BackgroundTransparency = 1,
				Text = "",
				Size = UDim2.fromScale(1, 1),
				Parent = hue,
			})

			local function apply(fire)
				color = Color3.fromHSV(h, s, v)
				swatch.BackgroundColor3 = color
				sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
				cursor.Position = UDim2.fromScale(s, 1 - v)
				hueMark.Position = UDim2.fromScale(h, 0.5)
				if fire then
					Safe(o.Callback, color)
				end
			end
			apply(false)

			local dragMode, activeInput = nil, nil
			local function updateFrom(x, y)
				if dragMode == "sv" then
					s = math.clamp((x - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
					v = 1 - math.clamp((y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
				elseif dragMode == "hue" then
					h = math.clamp((x - hue.AbsolutePosition.X) / math.max(hue.AbsoluteSize.X, 1), 0, 1)
				end
				apply(true)
			end
			local function begin(mode, input)
				dragMode = mode
				activeInput = input
				page.ScrollingEnabled = false
				updateFrom(input.Position.X, input.Position.Y)
			end
			svHit.InputBegan:Connect(function(input)
				if IsPointer(input) then
					begin("sv", input)
				end
			end)
			hueHit.InputBegan:Connect(function(input)
				if IsPointer(input) then
					begin("hue", input)
				end
			end)
			track(UserInputService.InputChanged:Connect(function(input)
				if dragMode and (input.UserInputType == Enum.UserInputType.MouseMovement or input == activeInput) then
					updateFrom(input.Position.X, input.Position.Y)
				end
			end))
			track(UserInputService.InputEnded:Connect(function(input)
				if dragMode and (input == activeInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
					dragMode = nil
					page.ScrollingEnabled = true
				end
			end))

			header.MouseButton1Click:Connect(function()
				isOpen = not isOpen
				Tween(frame, { Size = UDim2.new(1, 0, 0, isOpen and fullH or ROW_H) }, 0.2)
			end)

			local obj = {}
			function obj:Set(c, silent)
				h, s, v = c:ToHSV()
				apply(not silent)
			end
			function obj:Get()
				return color
			end
			return Register(o.Flag, obj, "ColorPicker")
		end

		-- run compiles and executes it (needs loadstring); Check only checks.
		function tab:CodeBox(o)
			local boxH = o.Height or (IS_MOBILE and 120 or 150)
			local live = o.LiveCheck ~= false
			local row = Row(boxH + 100)

			if o.Name then
				Text({
					Text = o.Name,
					Position = UDim2.new(0, 12, 0, 4),
					Size = UDim2.new(1, -24, 0, 22),
					Parent = row,
				})
			end
			local editor = New("Frame", {
				BackgroundColor3 = Theme.Background,
				Position = UDim2.new(0, 12, 0, 30),
				Size = UDim2.new(1, -24, 0, boxH),
				Parent = row,
			}, { Corner(6) })
			local box = New("TextBox", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.Code,
				Text = o.Default or "",
				PlaceholderText = o.Placeholder or "-- type or paste Luau code here",
				PlaceholderColor3 = Theme.SubText,
				TextColor3 = Theme.Text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				MultiLine = true,
				TextWrapped = false,
				ClearTextOnFocus = false,
				ClipsDescendants = true,
				Parent = editor,
			}, { Pad(8, 6, 8, 6) })
			local status = Text({
				Text = "Waiting for code...",
				TextColor3 = Theme.SubText,
				TextSize = 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.new(0, 12, 0, 30 + boxH + 6),
				Size = UDim2.new(1, -24, 0, 18),
				Parent = row,
			})
			local buttonRow = New("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 12, 0, 30 + boxH + 28),
				Size = UDim2.new(1, -24, 0, IS_MOBILE and 36 or 32),
				Parent = row,
			}, {
				New("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			})

			local lastErrText = nil

			-- mode: "live" (typing pause), "manual" (Check button)
			local function check(mode)
				if box.Text:match("^%s*$") then
					status.Text = "Waiting for code..."
					status.TextColor3 = Theme.SubText
					lastErrText = nil
					return true
				end
				local ok, message, line = Library:CheckSyntax(box.Text)
				if ok then
					status.Text = "Syntax OK"
					status.TextColor3 = Theme.Success
					lastErrText = nil
					if mode == "manual" then
						Library:Notify({ Title = "Syntax OK", Content = "No errors found.", Type = "Success", Duration = 2 })
					end
				else
					local full = FormatErr(message, line)
					status.Text = "Syntax error - " .. full
					status.TextColor3 = Theme.Error
					if mode == "manual" or full ~= lastErrText then
						Library:Error(full, "Syntax error")
					end
					lastErrText = full
				end
				return ok
			end

			local function miniButton(txt, order, callback)
				local b = New("TextButton", {
					LayoutOrder = order,
					AutoButtonColor = false,
					BackgroundColor3 = order == 1 and Theme.Accent or Theme.Background,
					Size = UDim2.new(1 / 3, -4, 1, 0),
					Font = Enum.Font.GothamMedium,
					Text = txt,
					TextColor3 = Theme.Text,
					TextSize = 13,
					Parent = buttonRow,
				}, { Corner(6) })
				b.MouseButton1Click:Connect(callback)
				return b
			end
			miniButton("Run", 1, function()
				if o.OnRun then
					Safe(o.OnRun, box.Text)
				else
					Library:Run(box.Text)
				end
			end)
			miniButton("Check", 2, function()
				check("manual")
			end)
			miniButton("Clear", 3, function()
				box.Text = ""
			end)

			local token = 0
			box:GetPropertyChangedSignal("Text"):Connect(function()
				if not live then
					return
				end
				token = token + 1
				local mine = token
				task.delay(o.Delay or 0.8, function()
					if mine == token and box.Parent then
						check("live")
					end
				end)
			end)
			if box.Text ~= "" then
				check("live")
			end

			local obj = {}
			function obj:Get()
				return box.Text
			end
			function obj:Set(t)
				box.Text = tostring(t)
			end
			function obj:Check()
				return check("manual")
			end
			return obj
		end

		-- config manager: create, load, overwrite, delete and auto load (elements need a Flag)
		-- pass { AutoLoad = false } to stop the saved auto load config running on its own
		function tab:ConfigManager(opts)
			opts = opts or {}
			tab:Section("Configs")
			local status = tab:Label("Auto load: none")
			local nameBox = tab:Textbox({ Name = "New config name", Default = "default", Placeholder = "default" })
			local list = tab:Dropdown({
				Name = "Selected config",
				Options = Library:GetConfigs(),
			})

			local function updateStatus()
				local current = Library:GetAutoLoad()
				status:Set("Auto load: " .. (current or "none"))
			end
			local function refreshAll()
				list:Refresh(Library:GetConfigs())
				updateStatus()
			end
			-- the config picked in the dropdown, or nil with a hint
			local function selected()
				local name = list:Get()
				if not name then
					Library:Notify({
						Title = "Config",
						Content = "Pick a config in 'Selected config' first.",
						Type = "Warning",
						Duration = 3,
					})
				end
				return name
			end

			tab:Button({
				Name = "Create config",
				Callback = function()
					local name = CleanName(nameBox:Get())
					if Library:ConfigExists(name) then
						Library:Notify({
							Title = "Config",
							Content = "'" .. name .. "' already exists. Select it and use Overwrite.",
							Type = "Warning",
							Duration = 3.5,
						})
						return
					end
					if Library:SaveConfig(name) then
						refreshAll()
						list:Set(name, true)
					end
				end,
			})
			tab:Button({
				Name = "Load selected config",
				Callback = function()
					local name = selected()
					if name then
						Library:LoadConfig(name)
					end
				end,
			})
			tab:Button({
				Name = "Overwrite selected config",
				Callback = function()
					local name = selected()
					if not name then
						return
					end
					Library:Dialog({
						Title = "Overwrite config?",
						Content = "'" .. name .. "' will be replaced with your current settings.",
						Buttons = {
							{
								Name = "Overwrite",
								Callback = function()
									Library:OverwriteConfig(name)
								end,
							},
							{ Name = "Cancel" },
						},
					})
				end,
			})
			tab:Button({
				Name = "Delete selected config",
				Callback = function()
					local name = selected()
					if not name then
						return
					end
					Library:Dialog({
						Title = "Delete config?",
						Content = "'" .. name .. "' will be deleted. This can't be undone.",
						Buttons = {
							{
								Name = "Delete",
								Callback = function()
									if Library:DeleteConfig(name) then
										refreshAll()
									end
								end,
							},
							{ Name = "Cancel" },
						},
					})
				end,
			})

			tab:Section("Auto load")
			tab:Button({
				Name = "Set selected as auto load",
				Callback = function()
					local name = selected()
					if name and Library:SetAutoLoad(name) then
						updateStatus()
					end
				end,
			})
			tab:Button({
				Name = "Delete auto load (selected config)",
				Callback = function()
					local name = selected()
					if name and Library:ClearAutoLoad(name) then
						updateStatus()
					end
				end,
			})
			tab:Button({
				Name = "Refresh list",
				Callback = refreshAll,
			})

			updateStatus()

			-- run the auto load config once, after the rest of the UI has been built
			if opts.AutoLoad ~= false and not Library._autoLoaded then
				Library._autoLoaded = true
				task.delay(0.5, function()
					if Library:AutoLoad() then
						updateStatus()
					end
				end)
			end
		end

		return tab
	end

	-- window controls

	function window:Toggle(v)
		if v == nil then
			v = not window.Visible
		end
		window.Visible = v
		if v then
			main.Visible = true
			Tween(scale, { Scale = targetScale }, 0.35, Enum.EasingStyle.Back)
		else
			local tw = Tween(scale, { Scale = 0 }, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tw.Completed:Connect(function()
				if not window.Visible then
					main.Visible = false
				end
			end)
		end
	end

	function window:Notify(o)
		return Library:Notify(o)
	end

	local floating
	function window:Destroy()
		for _, c in ipairs(window.Connections) do
			c:Disconnect()
		end
		window.Connections = {}
		main:Destroy()
		if floating then
			floating:Destroy()
		end
	end

	track(UserInputService.InputBegan:Connect(function(input, gp)
		if not gp and input.KeyCode == toggleKey then
			window:Toggle()
		end
	end))

	if UserInputService.TouchEnabled then
		floating = New("TextButton", {
			Text = "UI",
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundColor3 = Theme.Accent,
			Position = UDim2.new(0, 12, 0.5, -22),
			Size = UDim2.fromOffset(44, 44),
			Parent = gui,
		}, { Corner(22), Stroke(Color3.new(1, 1, 1), 1, 0.7) })

		local fDragging, fStart, fPos, fInput, moved = false, nil, nil, nil, false
		floating.InputBegan:Connect(function(input)
			if IsPointer(input) then
				fDragging, fStart, fPos, fInput, moved = true, input.Position, floating.Position, input, false
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						fDragging = false
						if not moved then
							window:Toggle()
						end
					end
				end)
			end
		end)
		track(UserInputService.InputChanged:Connect(function(input)
			if fDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == fInput) then
				local d = input.Position - fStart
				if d.Magnitude > 8 then
					moved = true
				end
				if moved then
					floating.Position = UDim2.new(fPos.X.Scale, fPos.X.Offset + d.X, fPos.Y.Scale, fPos.Y.Offset + d.Y)
				end
			end
		end))
	end

	return window
end

if typeof(getgenv) == "function" then
	pcall(function()
		local env = getgenv()
		local old = env.NovaUI_Loaded
		if old and old ~= Library and old.Unload then
			old:Unload()
		end
		env.NovaUI_Loaded = Library
	end)
end

return Library

end)()

return NovaUI
