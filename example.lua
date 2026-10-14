-- NovaUI libray example: one of every element
local NovaUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/kn4ght-security/NovaUI_Library/refs/heads/main/NovaUI_Libray.lua"))()

local Players = game:GetService("Players")
local player = Players.LocalPlayer

NovaUI:CatchErrors(true) -- red popup for console errors
NovaUI:SetWatermark("My Hub")

local window = NovaUI:CreateWindow({
	Title = "My Hub",
	Subtitle = "v1.0",
	ToggleKey = Enum.KeyCode.RightShift,
})

-- Main tab
local main = window:CreateTab("Main")

main:Section("Player")

main:Slider({
	Name = "Walk Speed",
	Flag = "WalkSpeed",
	Min = 16,
	Max = 100,
	Default = 16,
	Increment = 1,
	Callback = function(value)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = value
		end
	end,
})

main:Toggle({
	Name = "Example toggle",
	Flag = "ExampleToggle",
	Default = false,
	Callback = function(state)
		print("toggle:", state)
	end,
})

main:Button({
	Name = "Say hello",
	Callback = function()
		NovaUI:Notify({
			Title = "Hello",
			Content = "Button clicked",
			Duration = 3,
			Type = "Success",
		})
	end,
})

main:Button({
	Name = "Reset character (click twice)",
	DoubleClick = true,
	Callback = function()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = 0
		end
	end,
})

main:Divider()

main:Label("This is a label")
main:Paragraph({
	Title = "About",
	Content = "Paragraphs hold longer text under a title.",
})

-- Inputs tab
local inputs = window:CreateTab("Inputs")

inputs:Section("Choices")

inputs:Dropdown({
	Name = "Single select",
	Flag = "Mode",
	Options = { "Easy", "Normal", "Hard" },
	Default = "Normal",
	Callback = function(choice)
		print("picked:", choice)
	end,
})

inputs:Dropdown({
	Name = "Multi select",
	Flag = "Targets",
	Options = { "Players", "NPCs", "Items", "Vehicles" },
	Multi = true,
	Searchable = true,
	Default = { "Players" },
	Callback = function(list)
		print("selected:", table.concat(list, ", "))
	end,
})

inputs:Section("Typing and keys")

inputs:Textbox({
	Name = "Name",
	Flag = "PlayerName",
	Default = "",
	Placeholder = "type here",
	Callback = function(text)
		print("text:", text)
	end,
})

inputs:Keybind({
	Name = "Action key",
	Flag = "ActionKey",
	Default = Enum.KeyCode.F,
	Mode = "Press", -- "Press", "Toggle" or "Hold"
	Callback = function()
		print("key pressed")
	end,
})

inputs:ColorPicker({
	Name = "Accent colour",
	Flag = "Accent",
	Default = Color3.fromRGB(120, 90, 255),
	Callback = function(color)
		print("colour:", color)
	end,
})

-- Extras tab
local extras = window:CreateTab("Extras")

extras:Section("Progress")
local bar = extras:Progress({ Name = "Loading", Default = 0 })
task.spawn(function()
	for i = 0, 10 do
		bar:Set(i / 10)
		task.wait(0.2)
	end
end)

extras:Section("Dialog")
extras:Button({
	Name = "Open dialog",
	Callback = function()
		NovaUI:Dialog({
			Title = "Are you sure?",
			Content = "This can't be undone.",
			Buttons = {
				{ Name = "Yes", Callback = function() print("confirmed") end },
				{ Name = "No" },
			},
		})
	end,
})

extras:Section("Code")
extras:CodeBox({
	Name = "Script",
	Default = 'print("hello from the code box")',
	Height = 120,
})

-- Settings tab
local settings = window:CreateTab("Settings")
settings:Section("Configs")
settings:ConfigManager() -- save / load every element that has a Flag

settings:Section("Window")
settings:Button({
	Name = "Unload UI",
	DoubleClick = true,
	Callback = function()
		NovaUI:Unload()
	end,
})

window:SelectTab("Main")
