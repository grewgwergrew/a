local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local buildingActive = false -- true while placing blueprints (disables Click TP)
local moverEquipped = false  -- true while the Move Tool is equipped (disables Click TP)

local player = Players.LocalPlayer
local okGetHiddenGui, executorGui = pcall(function() return gethui() end)
if not okGetHiddenGui or not executorGui then
	error("This script requires the executor's gethui() hidden GUI.")
end
pcall(function()
	if script and script:IsA("LuaSourceContainer") then
		script:SetAttribute("AllPurposeScriptInjected", true)
		script.Parent = executorGui
	end
end)
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")

player.CharacterAdded:Connect(function(char)
	character = char
	hrp = char:WaitForChild("HumanoidRootPart")
	humanoid = char:WaitForChild("Humanoid")
end)

-------------------------------------------------
-- Saved settings (persist between executions)
-------------------------------------------------

local SETTINGS_FILE = "AllPurposeScript_Settings.json"

local DEFAULTS = {
	fastTrucks = false,
	fastSpeed = "5",
	clickTp = false,
	clickTpCargo = true,
	holdKey = "z",
	fog = false,
	water = false,
	snap = "1",
	freecam = false,
	freecamSpeed = "32",
	freecamToggleKey = "",
	advancedMoveEnabled = false,
	advancedMoveKey = "r",
	advancedInfoEnabled = false,
	advancedInfoKey = "i",
}

local Settings = {}

local function loadSettings()
	local data = {}

	pcall(function()
		if isfile and readfile and isfile(SETTINGS_FILE) then
			local decoded = HttpService:JSONDecode(readfile(SETTINGS_FILE))
			if type(decoded) == "table" then
				data = decoded
			end
		end
	end)

	for key, default in pairs(DEFAULTS) do
		if type(data[key]) == type(default) then
			Settings[key] = data[key]
		else
			Settings[key] = default
		end
	end
end

local saveQueued = false

local function saveSettings()
	if saveQueued then
		return
	end
	saveQueued = true

	task.delay(0.5, function()
		saveQueued = false
		pcall(function()
			if writefile then
				writefile(SETTINGS_FILE, HttpService:JSONEncode(Settings))
			end
		end)
	end)
end

loadSettings()

-------------------------------------------------
-- Theme
-------------------------------------------------

local THEME = {
	Background = Color3.fromRGB(12, 12, 14),
	Sidebar    = Color3.fromRGB(18, 18, 21),
	Card       = Color3.fromRGB(26, 26, 30),
	Button     = Color3.fromRGB(38, 38, 44),
	ButtonHover= Color3.fromRGB(52, 52, 60),
	Accent     = Color3.fromRGB(80, 160, 255),
	Text       = Color3.fromRGB(235, 235, 240),
	SubText    = Color3.fromRGB(150, 150, 160),
	Off        = Color3.fromRGB(55, 55, 62),
}

local function round(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = obj
	return c
end

local function hover(btn, normal, over)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = over}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = normal}):Play()
	end)
end

local function makeButton(parent, text, size, pos)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos or UDim2.new()
	b.BackgroundColor3 = THEME.Button
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = THEME.Text
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 14
	b.Parent = parent
	round(b, 8)
	hover(b, THEME.Button, THEME.ButtonHover)
	return b
end

local function makeTextBox(parent, text, size, pos)
	local t = Instance.new("TextBox")
	t.Size = size
	t.Position = pos or UDim2.new()
	t.BackgroundColor3 = THEME.Button
	t.BorderSizePixel = 0
	t.Text = text
	t.ClearTextOnFocus = false
	t.TextColor3 = THEME.Text
	t.PlaceholderColor3 = THEME.SubText
	t.Font = Enum.Font.Gotham
	t.TextSize = 14
	t.Parent = parent
	round(t, 8)
	return t
end

-- On/off switch. Returns set(state) so saved values can be applied on load.
local function makeSwitch(parent, pos, onChanged)
	local tog = Instance.new("TextButton")
	tog.Size = UDim2.new(0, 46, 0, 24)
	tog.Position = pos
	tog.BackgroundColor3 = THEME.Off
	tog.AutoButtonColor = false
	tog.BorderSizePixel = 0
	tog.Text = ""
	tog.Parent = parent
	round(tog, 12)

	local kn = Instance.new("Frame")
	kn.Size = UDim2.new(0, 18, 0, 18)
	kn.Position = UDim2.new(0, 3, 0, 3)
	kn.BackgroundColor3 = Color3.new(1, 1, 1)
	kn.BorderSizePixel = 0
	kn.Parent = tog
	round(kn, 9)

	local state = false

	local function set(newState)
		state = newState
		TweenService:Create(tog, TweenInfo.new(0.15), {
			BackgroundColor3 = state and THEME.Accent or THEME.Off,
		}):Play()
		TweenService:Create(kn, TweenInfo.new(0.15), {
			Position = state and UDim2.new(0, 25, 0, 3) or UDim2.new(0, 3, 0, 3),
		}):Play()
		if onChanged then
			onChanged(state)
		end
	end

	tog.MouseButton1Click:Connect(function()
		set(not state)
	end)

	return set
end

-------------------------------------------------
-- Scan Trees
-------------------------------------------------

local Trees = {}

local function ScanTrees()
	table.clear(Trees)

	for _, region in ipairs(workspace:GetChildren()) do
		if region:IsA("Model") and region.Name == "TreeRegion" then
			for _, tree in ipairs(region:GetChildren()) do
				if tree:IsA("Model") then
					local class = tree:FindFirstChild("TreeClass")
					if class and class:IsA("StringValue") then
						Trees[class.Value] = Trees[class.Value] or {}
						table.insert(Trees[class.Value], tree)
					end
				end
			end
		end
	end
end

ScanTrees()

-------------------------------------------------
-- Main window
-------------------------------------------------

local oldGui = executorGui:FindFirstChild("TreeFinder")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "TreeFinder"
gui.ResetOnSpawn = false
gui.Parent = executorGui

local FULL_SIZE = UDim2.new(0, 500, 0, 480)
local MIN_SIZE = UDim2.new(0, 500, 0, 36)

local frame = Instance.new("Frame")
frame.Size = FULL_SIZE
frame.Position = UDim2.new(1, -520, 1, -500)
frame.BackgroundColor3 = THEME.Background
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
round(frame, 14)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(45, 45, 52)
stroke.Thickness = 1
stroke.Parent = frame

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundTransparency = 1
titleBar.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.BackgroundTransparency = 1
title.Text = "All Purpose Script"
title.TextColor3 = THEME.Text
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local minimize = makeButton(titleBar, "–", UDim2.new(0, 26, 0, 26), UDim2.new(1, -62, 0, 5))
local close = makeButton(titleBar, "X", UDim2.new(0, 26, 0, 26), UDim2.new(1, -32, 0, 5))

-- Body (everything under title bar)
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -36)
body.Position = UDim2.new(0, 0, 0, 36)
body.BackgroundTransparency = 1
body.Parent = frame

-- Sidebar
local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 110, 1, -10)
sidebar.Position = UDim2.new(0, 8, 0, 0)
sidebar.BackgroundColor3 = THEME.Sidebar
sidebar.BorderSizePixel = 0
sidebar.Parent = body
round(sidebar, 10)

local sidePad = Instance.new("UIPadding")
sidePad.PaddingTop = UDim.new(0, 8)
sidePad.PaddingLeft = UDim.new(0, 8)
sidePad.PaddingRight = UDim.new(0, 8)
sidePad.Parent = sidebar

local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 6)
sideLayout.Parent = sidebar

-- Content area
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -134, 1, -10)
content.Position = UDim2.new(0, 126, 0, 0)
content.BackgroundTransparency = 1
content.Parent = body

-------------------------------------------------
-- Tabs
-------------------------------------------------

local pages = {}
local tabButtons = {}

local function selectTab(name)
	for n, page in pairs(pages) do
		page.Visible = (n == name)
	end
	for n, btn in pairs(tabButtons) do
		local active = (n == name)
		btn.BackgroundColor3 = active and THEME.Accent or THEME.Sidebar
		btn.TextColor3 = active and Color3.new(1, 1, 1) or THEME.SubText
	end
end

local function createTab(name)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 32)
	btn.BackgroundColor3 = THEME.Sidebar
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.Text = name
	btn.TextColor3 = THEME.SubText
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 14
	btn.Parent = sidebar
	round(btn, 8)
	tabButtons[name] = btn

	local page = Instance.new("Frame")
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.Visible = false
	page.Parent = content
	pages[name] = page

	btn.MouseButton1Click:Connect(function()
		selectTab(name)
	end)

	return page
end

local function getGuiObjectsAtPosition(x, y)
	local objects = {}
	local seen = {}
	local ok, found = pcall(function()
		return executorGui:GetGuiObjectsAtPosition(x, y)
	end)
	if ok and found then
		for _, object in ipairs(found) do
			if not seen[object] then
				seen[object] = true
				table.insert(objects, object)
			end
		end
	end
	return objects
end

do
	local infoPage = createTab("Info")
local infoCard = Instance.new("Frame")
infoCard.Size = UDim2.new(1, -8, 1, -8)
infoCard.BackgroundColor3 = THEME.Card
infoCard.BorderSizePixel = 0
infoCard.Parent = infoPage
round(infoCard, 10)

local infoTitle = Instance.new("TextLabel")
infoTitle.Size = UDim2.new(1, -24, 0, 28)
infoTitle.Position = UDim2.new(0, 12, 0, 10)
infoTitle.BackgroundTransparency = 1
infoTitle.Text = "Debug Info"
infoTitle.TextColor3 = THEME.Text
infoTitle.Font = Enum.Font.GothamBold
infoTitle.TextSize = 16
infoTitle.TextXAlignment = Enum.TextXAlignment.Left
infoTitle.Parent = infoCard

local function getPath(instance)
	if not instance then return "unavailable" end
	local ok, path = pcall(function() return instance:GetFullName() end)
	return ok and path or instance.Name
end

local scriptLocation = "executor-managed script"
pcall(function()
	if script and script:IsA("LuaSourceContainer") then scriptLocation = getPath(script) end
end)
local infoInfo = Instance.new("TextLabel")
infoInfo.Size = UDim2.new(1, -24, 0, 58)
infoInfo.Position = UDim2.new(0, 12, 0, 42)
infoInfo.BackgroundTransparency = 1
infoInfo.TextColor3 = THEME.SubText
infoInfo.Font = Enum.Font.Gotham
infoInfo.TextSize = 12
infoInfo.TextWrapped = true
infoInfo.TextYAlignment = Enum.TextYAlignment.Top
infoInfo.TextXAlignment = Enum.TextXAlignment.Left
infoInfo.Text = "UI container: " .. getPath(executorGui)
	.. "\nMain window: " .. getPath(gui)
	.. "\nScript instance: " .. scriptLocation
infoInfo.Parent = infoCard


end

local treePage = createTab("Tree Finder")
local movePage = createTab("Player")
local playerPage = movePage
local playerScroll = Instance.new("ScrollingFrame")
playerScroll.Name = "PlayerScroll"
playerScroll.Size = UDim2.new(1, 0, 1, 0)
playerScroll.BackgroundTransparency = 1
playerScroll.BorderSizePixel = 0
playerScroll.ScrollBarThickness = 4
playerScroll.ScrollBarImageColor3 = THEME.ButtonHover
playerScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
playerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
playerScroll.Parent = movePage
movePage = playerScroll
local worldPage = createTab("World")
local buildPage = createTab("Building")

-------------------------------------------------
-- Tree Finder page
-------------------------------------------------

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, -82)
scroll.Position = UDim2.new(0, 0, 0, 40)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = THEME.ButtonHover
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = treePage

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = scroll

do
	local unhighlightAllButton = makeButton(treePage, "Unhighlight All", UDim2.new(0, 130, 0, 32), UDim2.new(0, 0, 0, 2))
	unhighlightAllButton.MouseButton1Click:Connect(function()
		local highlightFolder = gui:FindFirstChild("TreeFinderHighlights")
		if highlightFolder then
			for _, marker in ipairs(highlightFolder:GetChildren()) do
				marker:Destroy()
			end
		end
	end)
end

-- Gets the player out of any seat before teleporting
local function leaveSeat()
	if not humanoid or not humanoid.SeatPart then
		return
	end

	local seat = humanoid.SeatPart

	humanoid.Sit = false
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	local waited = 0
	while humanoid.SeatPart and waited < 0.5 do
		waited += task.wait()
	end

	-- still stuck? remove the seat weld
	if humanoid.SeatPart then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		humanoid.Sit = false
		task.wait(0.1)
	end
end

local function TeleportToTree(tree)
	leaveSeat() -- yields briefly if you were seated

	local cf

	if tree.PrimaryPart then
		cf = tree.PrimaryPart.CFrame
	else
		local part = tree:FindFirstChildWhichIsA("BasePart", true)
		if part then
			cf = part.CFrame
		end
	end

	if cf and hrp then
		hrp.CFrame = cf + Vector3.new(0, 5, 0)
	end
end

local function BuildTreeList()
	for _, child in ipairs(scroll:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local sortedTrees = {}

	for className, list in pairs(Trees) do
		table.insert(sortedTrees, {
			Name = className,
			Trees = list,
			Count = #list,
		})
	end

	table.sort(sortedTrees, function(a, b)
		return a.Count < b.Count -- Least to most
	end)

	for _, info in ipairs(sortedTrees) do
		local list = info.Trees

		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, -8, 0, 70)
		holder.BackgroundColor3 = THEME.Card
		holder.BorderSizePixel = 0
		holder.Parent = scroll
		round(holder, 10)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -20, 0, 22)
		label.Position = UDim2.new(0, 10, 0, 6)
		label.BackgroundTransparency = 1
		label.TextColor3 = THEME.Text
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = info.Name .. "  (" .. info.Count .. ")"
		label.Parent = holder

		local box = makeTextBox(holder, "1", UDim2.new(0, 60, 0, 28), UDim2.new(0, 10, 0, 34))
		local button = makeButton(holder, "Teleport", UDim2.new(0, 76, 0, 28), UDim2.new(0, 78, 0, 34))
		local highlightButton = makeButton(holder, "Highlight", UDim2.new(0, 82, 0, 28), UDim2.new(0, 160, 0, 34))
		local unhighlightButton = makeButton(holder, "Unhighlight", UDim2.new(0, 100, 0, 28), UDim2.new(0, 250, 0, 34))

		button.MouseButton1Click:Connect(function()
			local index = tonumber(box.Text)
			if index and index == math.floor(index) and list[index] then
				task.spawn(TeleportToTree, list[index])
			end
		end)

		highlightButton.MouseButton1Click:Connect(function()
			local index = tonumber(box.Text)
			local tree = index and index == math.floor(index) and list[index]
			if not tree or not tree.Parent then return end
			local highlightFolder = gui:FindFirstChild("TreeFinderHighlights")
			if not highlightFolder then
				highlightFolder = Instance.new("Folder")
				highlightFolder.Name = "TreeFinderHighlights"
				highlightFolder.Parent = gui
			end
			for _, existing in ipairs(highlightFolder:GetChildren()) do
				if existing.Adornee == tree then return end
			end
			local marker = Instance.new("Highlight")
			marker.Name = "TreeHighlight_" .. info.Name .. "_" .. index
			marker.Adornee = tree
			marker.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			marker.FillTransparency = 1
			marker.OutlineColor = Color3.fromRGB(255, 225, 85)
			marker.OutlineTransparency = 0
			marker.Parent = highlightFolder
		end)

		unhighlightButton.MouseButton1Click:Connect(function()
			local index = tonumber(box.Text)
			local tree = index and index == math.floor(index) and list[index]
			if not tree then return end
			local highlightFolder = gui:FindFirstChild("TreeFinderHighlights")
			if not highlightFolder then return end
			for _, marker in ipairs(highlightFolder:GetChildren()) do
				if marker.Adornee == tree then
					marker:Destroy()
					return
				end
			end
		end)
	end
end

BuildTreeList()

local refresh = makeButton(treePage, "Refresh Trees", UDim2.new(1, -8, 0, 32), UDim2.new(0, 0, 1, -32))
refresh.MouseButton1Click:Connect(function()
	ScanTrees()
	BuildTreeList()
	local highlightFolder = gui:FindFirstChild("TreeFinderHighlights")
	if highlightFolder then
		for _, marker in ipairs(highlightFolder:GetChildren()) do
			marker:Destroy()
		end
	end
end)

-- Keep the finder list in sync with trees appearing or disappearing.
local treeRegionConnections = {}
local treeRefreshQueued = false

local function scheduleTreeRefresh()
	if treeRefreshQueued then return end
	treeRefreshQueued = true
	task.defer(function()
		treeRefreshQueued = false
		ScanTrees()
		BuildTreeList()
	end)
end

local function watchTreeRegion(region)
	if not (region:IsA("Model") and region.Name == "TreeRegion") then return false end
	if treeRegionConnections[region] then return true end
	treeRegionConnections[region] = {
		region.ChildAdded:Connect(scheduleTreeRefresh),
		region.ChildRemoved:Connect(scheduleTreeRefresh),
	}
	return true
end

for _, child in ipairs(workspace:GetChildren()) do
	watchTreeRegion(child)
end

workspace.ChildAdded:Connect(function(child)
	if watchTreeRegion(child) then
		scheduleTreeRefresh()
	end
end)

workspace.ChildRemoved:Connect(function(child)
	local connections = treeRegionConnections[child]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		treeRegionConnections[child] = nil
		scheduleTreeRefresh()
	end
end)

-------------------------------------------------
-- Movement page: Fast Trucks
-------------------------------------------------

local fastTrucksOn = false
local originals = {} -- [NumberValue] = original value
local lastDebugSeat = nil

local function restoreOriginals()
	for value, original in pairs(originals) do
		if value and value.Parent then
			value.Value = original
		end
	end
	table.clear(originals)
end

local moveLayout = Instance.new("UIListLayout")
moveLayout.Padding = UDim.new(0, 8)
moveLayout.Parent = movePage

local ftCard = Instance.new("Frame")
ftCard.Size = UDim2.new(1, -8, 0, 96)
ftCard.BackgroundColor3 = THEME.Card
ftCard.BorderSizePixel = 0
ftCard.Parent = movePage
round(ftCard, 10)

local ftLabel = Instance.new("TextLabel")
ftLabel.Size = UDim2.new(1, -90, 0, 24)
ftLabel.Position = UDim2.new(0, 12, 0, 10)
ftLabel.BackgroundTransparency = 1
ftLabel.Text = "Fast Trucks"
ftLabel.TextColor3 = THEME.Text
ftLabel.Font = Enum.Font.GothamMedium
ftLabel.TextSize = 15
ftLabel.TextXAlignment = Enum.TextXAlignment.Left
ftLabel.Parent = ftCard

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0, 70, 0, 28)
speedLabel.Position = UDim2.new(0, 12, 0, 46)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Speed"
speedLabel.TextColor3 = THEME.SubText
speedLabel.Font = Enum.Font.Gotham
speedLabel.TextSize = 14
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Parent = ftCard

local speedBox = makeTextBox(ftCard, Settings.fastSpeed, UDim2.new(0, 80, 0, 28), UDim2.new(0, 70, 0, 46))
speedBox.FocusLost:Connect(function()
	Settings.fastSpeed = speedBox.Text
	saveSettings()
end)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 16)
status.Position = UDim2.new(0, 12, 1, -20)
status.BackgroundTransparency = 1
status.Text = "Off"
status.TextColor3 = THEME.SubText
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = ftCard

local setFastTrucks = makeSwitch(ftCard, UDim2.new(1, -58, 0, 10), function(on)
	fastTrucksOn = on
	Settings.fastTrucks = on
	saveSettings()

	if not on then
		restoreOriginals()
		status.Text = "Off"
	end
end)

-- Collect every DirectionFactor inside the PowerWheels folders
local function getDirectionFactors(seat)
	local result = {}
	local powerWheels = seat.Parent and seat.Parent:FindFirstChild("PowerWheels")

	if powerWheels then
		for _, folder in ipairs(powerWheels:GetChildren()) do
			if folder:IsA("Folder") then
				local factor = folder:FindFirstChild("DirectionFactor")
				if factor and factor:IsA("IntValue") then
					table.insert(result, factor)
				end
			end
		end
	end

	return result, powerWheels
end

task.spawn(function()
	while gui.Parent do
		if fastTrucksOn then
			local seat = humanoid and humanoid.SeatPart
			local amount = tonumber(speedBox.Text)

			if seat and seat.Name ~= "DriveSeat" then
				if next(originals) then
					restoreOriginals()
				end
				status.Text = "Sitting in " .. seat.Name .. " (needs DriveSeat)"
			elseif seat and amount then
				local factors, powerWheels = getDirectionFactors(seat)

				if #factors > 0 then
					for _, factor in ipairs(factors) do
						if originals[factor] == nil then
							originals[factor] = factor.Value
						end

						-- keep the original sign, replace the magnitude
						local sign = originals[factor] < 0 and -1 or 1
						local target = sign * math.floor(math.abs(amount) + 0.5) -- IntValue, so whole numbers

						if factor.Value ~= target then
							factor.Value = target
						end
					end
					status.Text = "Active (" .. #factors .. " DirectionFactors)"
				elseif powerWheels then
					status.Text = "PowerWheels found, no folder with a DirectionFactor IntValue"
					if lastDebugSeat ~= seat then
						lastDebugSeat = seat
						print("[TreeFinder] PowerWheels:", powerWheels:GetFullName())
						for _, d in ipairs(powerWheels:GetDescendants()) do
							print("   ", d.ClassName, d:GetFullName())
						end
					end
				else
					status.Text = "No PowerWheels beside " .. seat:GetFullName()
				end
			else
				-- left the seat: put things back
				if next(originals) then
					restoreOriginals()
				end
				status.Text = seat and "Enter a valid number" or "Waiting for you to sit..."
			end
		end

		task.wait(0.1)
	end

	restoreOriginals()
end)

-- apply the saved state
if Settings.fastTrucks then
	setFastTrucks(true)
end

-------------------------------------------------
-- Movement page: Click TP
-------------------------------------------------

-- Finds every model (or part) in workspace.LogModels / workspace.PlayerModels that is
-- inside / touching the truck's box. Checks one bounding box per model rather than
-- every part, and doesn't depend on CanQuery, so it stays reasonably fast.
local function getTruckCargo(boxCF, boxSize)
	local cargo = {}
	local half = boxSize / 2

	local function inBox(center, size)
		local rel = boxCF:PointToObjectSpace(center)
		local pad = size.Magnitude / 2 -- generous so "touching" counts
		return math.abs(rel.X) <= half.X + pad
			and math.abs(rel.Y) <= half.Y + pad
			and math.abs(rel.Z) <= half.Z + pad
	end

	-- anchored things (or models containing anchored parts) are never taken along
	local function hasAnchoredPart(obj)
		if obj:IsA("BasePart") and obj.Anchored then
			return true
		end
		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("BasePart") and d.Anchored then
				return true
			end
		end
		return false
	end

	local function scan(container)
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") then
				local cf, size = child:GetBoundingBox()
				if inBox(cf.Position, size) and not hasAnchoredPart(child) then
					table.insert(cargo, child)
				end
			elseif child:IsA("BasePart") then
				if inBox(child.Position, child.Size) and not child.Anchored then
					table.insert(cargo, child)
				end
			elseif child:IsA("Folder") then
				scan(child) -- e.g. per-player sub folders
			end
		end
	end

	for _, name in ipairs({"LogModels", "PlayerModels"}) do
		local folder = workspace:FindFirstChild(name)
		if folder then
			scan(folder)
		end
	end

	return cargo
end

-- Zero velocity once per physics assembly instead of once per part
local function zeroVelocity(container)
	local done = {}

	local function zero(part)
		local root = part.AssemblyRootPart or part
		if not done[root] then
			done[root] = true
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end

	if container:IsA("BasePart") then
		zero(container)
	end
	for _, obj in ipairs(container:GetDescendants()) do
		if obj:IsA("BasePart") then
			zero(obj)
		end
	end
end

local clickTpOn = false
local takeCargoOn = true
local holdKey = nil
local binding = false

local ctCard = Instance.new("Frame")
ctCard.Size = UDim2.new(1, -8, 0, 130)
ctCard.BackgroundColor3 = THEME.Card
ctCard.BorderSizePixel = 0
ctCard.Parent = movePage
round(ctCard, 10)

local ctLabel = Instance.new("TextLabel")
ctLabel.Size = UDim2.new(1, -90, 0, 24)
ctLabel.Position = UDim2.new(0, 12, 0, 10)
ctLabel.BackgroundTransparency = 1
ctLabel.Text = "Click TP"
ctLabel.TextColor3 = THEME.Text
ctLabel.Font = Enum.Font.GothamMedium
ctLabel.TextSize = 15
ctLabel.TextXAlignment = Enum.TextXAlignment.Left
ctLabel.Parent = ctCard

local keyLabel = Instance.new("TextLabel")
keyLabel.Size = UDim2.new(0, 70, 0, 28)
keyLabel.Position = UDim2.new(0, 12, 0, 46)
keyLabel.BackgroundTransparency = 1
keyLabel.Text = "Hold key"
keyLabel.TextColor3 = THEME.SubText
keyLabel.Font = Enum.Font.Gotham
keyLabel.TextSize = 14
keyLabel.TextXAlignment = Enum.TextXAlignment.Left
keyLabel.Parent = ctCard

local keyButton = makeButton(ctCard, "None", UDim2.new(0, 110, 0, 28), UDim2.new(0, 80, 0, 46))

local cargoLabel = Instance.new("TextLabel")
cargoLabel.Size = UDim2.new(1, -90, 0, 24)
cargoLabel.Position = UDim2.new(0, 12, 0, 80)
cargoLabel.BackgroundTransparency = 1
cargoLabel.Text = "Take cargo with truck"
cargoLabel.TextColor3 = THEME.SubText
cargoLabel.Font = Enum.Font.Gotham
cargoLabel.TextSize = 14
cargoLabel.TextXAlignment = Enum.TextXAlignment.Left
cargoLabel.Parent = ctCard

local keyHint = Instance.new("TextLabel")
keyHint.Size = UDim2.new(1, -24, 0, 16)
keyHint.Position = UDim2.new(0, 12, 1, -20)
keyHint.BackgroundTransparency = 1
keyHint.Text = "Left click to teleport (truck + cargo in DriveSeat). Esc clears key."
keyHint.TextColor3 = THEME.SubText
keyHint.Font = Enum.Font.Gotham
keyHint.TextSize = 11
keyHint.TextXAlignment = Enum.TextXAlignment.Left
keyHint.Parent = ctCard

local setClickTp = makeSwitch(ctCard, UDim2.new(1, -58, 0, 10), function(on)
	clickTpOn = on
	Settings.clickTp = on
	saveSettings()
end)

local setTakeCargo = makeSwitch(ctCard, UDim2.new(1, -58, 0, 80), function(on)
	takeCargoOn = on
	Settings.clickTpCargo = on
	saveSettings()
end)

keyButton.MouseButton1Click:Connect(function()
	binding = true
	keyButton.Text = "Press a key..."
end)

-- apply saved state
if Settings.holdKey ~= "" then
	local ok, keyCode = pcall(function()
		return Enum.KeyCode[Settings.holdKey]
	end)
	if ok and keyCode then
		holdKey = keyCode
		keyButton.Text = keyCode.Name
	end
end
if Settings.clickTp then
	setClickTp(true)
end
if Settings.clickTpCargo then
	setTakeCargo(true)
end

local clickParams = RaycastParams.new()
clickParams.FilterType = Enum.RaycastFilterType.Exclude

local inputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- key binding
	if binding and input.UserInputType == Enum.UserInputType.Keyboard then
		binding = false
		if input.KeyCode == Enum.KeyCode.Escape then
			holdKey = nil
			keyButton.Text = "None"
			Settings.holdKey = ""
		else
			holdKey = input.KeyCode
			keyButton.Text = input.KeyCode.Name
			Settings.holdKey = input.KeyCode.Name
		end
		saveSettings()
		return
	end

	-- click teleport
	if clickTpOn
		and not buildingActive
		and not moverEquipped
		and not gameProcessed
		and input.UserInputType == Enum.UserInputType.MouseButton1 then

		if holdKey and not UserInputService:IsKeyDown(holdKey) then
			return
		end

		local camera = workspace.CurrentCamera
		if not camera or not hrp then
			return
		end

		-- Work out what we're moving: the truck, or just the character
		local seat = humanoid and humanoid.SeatPart
		local vehicle = nil

		if seat then
			if seat.Name ~= "DriveSeat" then
				return -- sitting somewhere that isn't the DriveSeat: never teleport
			end
			vehicle = seat.Parent
			if not (vehicle and vehicle:IsA("Model")) then
				return -- the truck model must be the direct parent of the DriveSeat
			end
		end

		clickParams.FilterDescendantsInstances = vehicle and {character, vehicle} or {character}

		-- GetMouseLocation matches ViewportPointToRay (input.Position is offset by the top bar)
		local mousePos = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 5000, clickParams)

		if not result then
			return
		end

		local hit = result.Position

		if vehicle then
			-- Put the DriveSeat over the clicked spot and the bottom of the truck on the ground
			local boxCF, boxSize = vehicle:GetBoundingBox()
			local bottomY = boxCF.Position.Y - boxSize.Y / 2
			local shift = Vector3.new(
				hit.X - seat.Position.X,
				hit.Y + 0.5 - bottomY,
				hit.Z - seat.Position.Z
			)

			-- find the cargo BEFORE the truck moves (only if the cargo toggle is on)
			local cargo = takeCargoOn and getTruckCargo(boxCF, boxSize) or {}
			if takeCargoOn then
				keyHint.Text = "Moved truck + " .. #cargo .. " cargo"
			else
				keyHint.Text = "Moved truck only (cargo toggle off)"
			end

			-- Record absolute targets BEFORE anything moves (welded cargo gets dragged
			-- along with the truck, so adding the shift afterwards would double-move it)
			local targets = {}
			for _, item in ipairs(cargo) do
				if item:IsA("Model") then
					targets[item] = item:GetPivot() + shift
				elseif item:IsA("BasePart") then
					targets[item] = item.CFrame + shift
				end
			end

			vehicle:PivotTo(vehicle:GetPivot() + shift)

			for item, target in pairs(targets) do
				if item.Parent then
					if item:IsA("Model") then
						item:PivotTo(target)
					else
						item.CFrame = target
					end
					zeroVelocity(item)
				end
			end

			zeroVelocity(vehicle)
		else
			-- Stand exactly on the clicked spot (root part height above the ground)
			local height = (humanoid and humanoid.HipHeight or 2) + hrp.Size.Y / 2
			local rotation = hrp.CFrame - hrp.CFrame.Position
			hrp.CFrame = CFrame.new(hit + Vector3.new(0, height, 0)) * rotation
		end
	end
end)

gui.Destroying:Connect(function()
	inputConn:Disconnect()
end)

-------------------------------------------------
-- World tab
-------------------------------------------------

local worldLayout = Instance.new("UIListLayout")
worldLayout.Padding = UDim.new(0, 8)
worldLayout.Parent = worldPage

-- Builds a card with a title, small status text and an on/off switch.
-- onChanged(state) may return a string to show as the status text.
-- If initial is true the switch is turned on right away (used for saved settings).
local function makeToggleRow(parent, labelText, onChanged, initial)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -8, 0, 56)
	card.BackgroundColor3 = THEME.Card
	card.BorderSizePixel = 0
	card.Parent = parent
	round(card, 10)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -80, 0, 22)
	label.Position = UDim2.new(0, 12, 0, 8)
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = THEME.Text
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = card

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -80, 0, 16)
	sub.Position = UDim2.new(0, 12, 0, 31)
	sub.BackgroundTransparency = 1
	sub.Text = "Off"
	sub.TextColor3 = THEME.SubText
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 12
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Parent = card

	local set = makeSwitch(card, UDim2.new(1, -58, 0.5, -12), function(state)
		local text = onChanged(state)
		sub.Text = text or (state and "On" or "Off")
	end)

	if initial then
		set(true)
	end
end

-- Disable Fog
-- The game keeps rewriting the fog values, so while this is on we put them back
-- the moment they change (and every frame as a backup).
local FOG_DISTANCE = 1000000
local fogConnections = {}
local gameFog = {} -- last values the game tried to set, restored when toggled off

local function enforceFog()
	if Lighting.FogStart ~= FOG_DISTANCE then
		gameFog.start = Lighting.FogStart
		Lighting.FogStart = FOG_DISTANCE
	end
	if Lighting.FogEnd ~= FOG_DISTANCE then
		gameFog.finish = Lighting.FogEnd
		Lighting.FogEnd = FOG_DISTANCE
	end
end

local function setFogDisabled(on)
	if on then
		if #fogConnections > 0 then
			return
		end
		table.clear(gameFog)
		enforceFog()
		table.insert(fogConnections, Lighting:GetPropertyChangedSignal("FogStart"):Connect(enforceFog))
		table.insert(fogConnections, Lighting:GetPropertyChangedSignal("FogEnd"):Connect(enforceFog))
		table.insert(fogConnections, RunService.RenderStepped:Connect(enforceFog))
	else
		for _, conn in ipairs(fogConnections) do
			conn:Disconnect()
		end
		table.clear(fogConnections)

		if gameFog.start then
			Lighting.FogStart = gameFog.start
		end
		if gameFog.finish then
			Lighting.FogEnd = gameFog.finish
		end
		table.clear(gameFog)
	end
end

makeToggleRow(worldPage, "Disable Fog", function(on)
	setFogDisabled(on)
	Settings.fog = on
	saveSettings()
end, Settings.fog)

-- Water Collision (default off)
local waterOriginals = {} -- [part] = original CanCollide

local function getWaterParts()
	local parts = {}
	local model = workspace:FindFirstChild("Water")

	if model then
		for _, obj in ipairs(model:GetDescendants()) do
			if obj:IsA("BasePart") and obj.Name == "Water" then
				table.insert(parts, obj)
			end
		end
	end

	return parts
end

local function setWaterCollision(on)
	if on then
		local parts = getWaterParts()
		for _, part in ipairs(parts) do
			if waterOriginals[part] == nil then
				waterOriginals[part] = part.CanCollide
			end
			part.CanCollide = true
		end
		return #parts
	end

	for part, original in pairs(waterOriginals) do
		if part.Parent then
			part.CanCollide = original
		end
	end
	table.clear(waterOriginals)
	return 0
end

makeToggleRow(worldPage, "Water Collision", function(on)
	local count = setWaterCollision(on)
	Settings.water = on
	saveSettings()
	if on then
		return count > 0 and ("On (" .. count .. " water parts)") or "On (no water parts found)"
	end
	return "Off"
end, Settings.water)

-- put the world back the way it was when the window closes
-- (these call the setters directly, so your saved on/off choices are kept)
gui.Destroying:Connect(function()
	setFogDisabled(false)
	setWaterCollision(false)
end)

-------------------------------------------------
-- Building tab
-------------------------------------------------

local worldBounds, stylePreview
do
local previewModel = nil
local previewPos = Vector3.zero
local rotCF = CFrame.new() -- pure rotation
local selectedEntry = nil
local holdingMouse = false
local placedCount = 0
local keysBound = false
local KEY_ACTIONS = {"BP_Yaw", "BP_Pitch", "BP_Place", "BP_Done"}

-- Building tab controls ---------------------------------------------

local buildingOptionsLayout = Instance.new("UIListLayout")
buildingOptionsLayout.Padding = UDim.new(0, 8)
buildingOptionsLayout.Parent = buildPage

local giveToolButton = makeButton(buildPage, "Give Blueprint Tool", UDim2.new(1, -8, 0, 42))
giveToolButton.LayoutOrder = 1

local advancedInfoEnabled = Settings.advancedInfoEnabled == true
local advancedInfoCard = Instance.new("Frame")
advancedInfoCard.Size = UDim2.new(1, -8, 0, 100)
advancedInfoCard.BackgroundColor3 = THEME.Card
advancedInfoCard.BorderSizePixel = 0
advancedInfoCard.LayoutOrder = 2
advancedInfoCard.Parent = buildPage
round(advancedInfoCard, 10)

local advancedInfoLabel = Instance.new("TextLabel")
advancedInfoLabel.Size = UDim2.new(1, -78, 0, 22)
advancedInfoLabel.Position = UDim2.new(0, 12, 0, 8)
advancedInfoLabel.BackgroundTransparency = 1
advancedInfoLabel.Text = "Advanced Info"
advancedInfoLabel.TextColor3 = THEME.Text
advancedInfoLabel.Font = Enum.Font.GothamMedium
advancedInfoLabel.TextSize = 15
advancedInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
advancedInfoLabel.Parent = advancedInfoCard

local advancedInfoStatus = Instance.new("TextLabel")
advancedInfoStatus.Size = UDim2.new(1, -78, 0, 16)
advancedInfoStatus.Position = UDim2.new(0, 12, 0, 31)
advancedInfoStatus.BackgroundTransparency = 1
advancedInfoStatus.Text = advancedInfoEnabled and "On" or "Off"
advancedInfoStatus.TextColor3 = THEME.SubText
advancedInfoStatus.Font = Enum.Font.Gotham
advancedInfoStatus.TextSize = 12
advancedInfoStatus.TextXAlignment = Enum.TextXAlignment.Left
advancedInfoStatus.Parent = advancedInfoCard

local advancedInfoKeyLabel = Instance.new("TextLabel")
advancedInfoKeyLabel.Size = UDim2.new(0, 105, 0, 28)
advancedInfoKeyLabel.Position = UDim2.new(0, 12, 0, 64)
advancedInfoKeyLabel.BackgroundTransparency = 1
advancedInfoKeyLabel.Text = "Open info key"
advancedInfoKeyLabel.TextColor3 = THEME.SubText
advancedInfoKeyLabel.Font = Enum.Font.Gotham
advancedInfoKeyLabel.TextSize = 13
advancedInfoKeyLabel.TextXAlignment = Enum.TextXAlignment.Left
advancedInfoKeyLabel.Parent = advancedInfoCard

local advancedInfoKeyButton = makeButton(advancedInfoCard, string.upper(Settings.advancedInfoKey or "i"), UDim2.new(0, 72, 0, 28), UDim2.new(0, 120, 0, 62))
local waitingForInfoKey = false
local setAdvancedInfo = makeSwitch(advancedInfoCard, UDim2.new(1, -58, 0, 10), function(on)
	advancedInfoEnabled = on
	Settings.advancedInfoEnabled = on
	advancedInfoStatus.Text = on and ("On - press " .. string.upper(Settings.advancedInfoKey or "i") .. " over a PlayerModel") or "Off"
	saveSettings()
end)
if advancedInfoEnabled then setAdvancedInfo(true) end

advancedInfoKeyButton.MouseButton1Click:Connect(function()
	waitingForInfoKey = true
	advancedInfoKeyButton.Text = "..."
end)

local blueprintTool = nil
local createBlueprintTool

-- Blueprint picker styled to match the main script UI.
local pickerGui = Instance.new("ScreenGui")
pickerGui.Name = "BlueprintPicker"
pickerGui.ResetOnSpawn = false
pickerGui.Enabled = false
pickerGui.Parent = executorGui

local pickerFrame = Instance.new("Frame")
pickerFrame.Size = UDim2.new(0, 800, 0, 550)
pickerFrame.Position = UDim2.new(0.5, -400, 0.5, -275)
pickerFrame.BackgroundColor3 = THEME.Background
pickerFrame.BorderColor3 = THEME.ButtonHover
pickerFrame.BorderSizePixel = 1
pickerFrame.Parent = pickerGui
round(pickerFrame, 12)

local pickerTitle = Instance.new("TextLabel")
pickerTitle.Size = UDim2.new(1, -70, 0, 56)
pickerTitle.Position = UDim2.new(0, 20, 0, 4)
pickerTitle.BackgroundTransparency = 1
pickerTitle.Text = "Blueprints"
pickerTitle.TextColor3 = THEME.Text
pickerTitle.TextStrokeTransparency = 1
pickerTitle.Font = Enum.Font.GothamBold
pickerTitle.TextSize = 28
pickerTitle.Parent = pickerFrame

local pickerClose = makeButton(pickerFrame, "X", UDim2.new(0, 32, 0, 30), UDim2.new(1, -42, 0, 12))
local categoryScroll = Instance.new("ScrollingFrame")
categoryScroll.Size = UDim2.new(0, 116, 1, -90)
categoryScroll.Position = UDim2.new(0, 16, 0, 74)
categoryScroll.BackgroundColor3 = THEME.Sidebar
categoryScroll.BorderColor3 = THEME.ButtonHover
categoryScroll.ScrollBarThickness = 6
categoryScroll.ScrollBarImageColor3 = THEME.Accent
categoryScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
categoryScroll.CanvasSize = UDim2.new()
categoryScroll.Parent = pickerFrame
local categoryLayout = Instance.new("UIListLayout")
categoryLayout.Padding = UDim.new(0, 8)
categoryLayout.Parent = categoryScroll

local blueprintItemsScroll = Instance.new("ScrollingFrame")
blueprintItemsScroll.Size = UDim2.new(1, -166, 1, -90)
blueprintItemsScroll.Position = UDim2.new(0, 142, 0, 74)
blueprintItemsScroll.BackgroundColor3 = THEME.Sidebar
blueprintItemsScroll.BorderColor3 = THEME.ButtonHover
blueprintItemsScroll.ScrollBarThickness = 6
blueprintItemsScroll.ScrollBarImageColor3 = THEME.Accent
blueprintItemsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
blueprintItemsScroll.CanvasSize = UDim2.new()
blueprintItemsScroll.Parent = pickerFrame
local blueprintItemsLayout = Instance.new("UIGridLayout")
blueprintItemsLayout.CellSize = UDim2.new(0, 104, 0, 118)
blueprintItemsLayout.CellPadding = UDim2.new(0, 10, 0, 10)
blueprintItemsLayout.SortOrder = Enum.SortOrder.LayoutOrder
blueprintItemsLayout.Parent = blueprintItemsScroll

local placementGui = Instance.new("ScreenGui")
placementGui.Name = "BlueprintPlacementControls"
placementGui.ResetOnSpawn = false
placementGui.Parent = executorGui
local placementRoot = Instance.new("Frame")
placementRoot.Size = UDim2.new(1, 0, 1, 0)
placementRoot.BackgroundTransparency = 1
placementRoot.Visible = false
placementRoot.Parent = placementGui

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 360, 0, 260)
panel.Position = UDim2.new(0, 20, 1, -270)
panel.BackgroundColor3 = THEME.Card
panel.BorderSizePixel = 0
panel.Parent = placementRoot
round(panel, 10)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 32)
statusLabel.Position = UDim2.new(0, 10, 0, 6)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Equip the Blueprint Tool to browse your blueprints."
statusLabel.TextColor3 = THEME.SubText
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Parent = panel

local function setStatus(text)
	statusLabel.Text = text
end

local function makeSmallLabel(text, y)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(0, 36, 0, 28)
	l.Position = UDim2.new(0, 10, 0, y)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = THEME.SubText
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = panel
end

local function makeRow(label, y, defaults)
	makeSmallLabel(label, y)
	local boxes = {}
	for i = 1, 3 do
		boxes[i] = makeTextBox(panel, defaults, UDim2.new(0, 70, 0, 28), UDim2.new(0, 50 + (i - 1) * 76, 0, y))
	end
	return boxes
end

local posBoxes = makeRow("Pos", 42, "0")
local rotBoxes = makeRow("Rot", 76, "0")

makeSmallLabel("Snap", 110)
local snapBox = makeTextBox(panel, Settings.snap, UDim2.new(0, 70, 0, 28), UDim2.new(0, 50, 0, 110))
snapBox.FocusLost:Connect(function()
	Settings.snap = snapBox.Text
	saveSettings()
end)
local applyButton = makeButton(panel, "Apply Pos/Rot", UDim2.new(0, 110, 0, 28), UDim2.new(0, 130, 0, 110))

makeSmallLabel("Copies", 146)
posBoxes.copyCount = makeTextBox(panel, "1", UDim2.new(0, 70, 0, 28), UDim2.new(0, 50, 0, 146))
posBoxes.copyCount.PlaceholderText = "Count"
makeSmallLabel("Offset", 180)
rotBoxes.offsetBoxes = {
	makeTextBox(panel, "0", UDim2.new(0, 70, 0, 28), UDim2.new(0, 50, 0, 180)),
	makeTextBox(panel, "0", UDim2.new(0, 70, 0, 28), UDim2.new(0, 126, 0, 180)),
	makeTextBox(panel, "0", UDim2.new(0, 70, 0, 28), UDim2.new(0, 202, 0, 180)),
}
for index, axis in ipairs({"X", "Y", "Z"}) do
	rotBoxes.offsetBoxes[index].PlaceholderText = axis
end

local placeButton = makeButton(panel, "Place (E)", UDim2.new(0, 108, 0, 28), UDim2.new(0, 10, 0, 220))
local doneButton = makeButton(panel, "Done (B)", UDim2.new(0, 108, 0, 28), UDim2.new(0, 124, 0, 220))
local refreshBpButton = makeButton(panel, "Cancel", UDim2.new(0, 108, 0, 28), UDim2.new(0, 238, 0, 220))

-- Helpers ----------------------------------------------------------

local function fmt(n)
	n = math.floor(n * 100 + 0.5) / 100
	if n == 0 then
		n = 0
	end
	return tostring(n)
end

local function refreshBoxes()
	if not previewModel then
		return
	end

	local p = {previewPos.X, previewPos.Y, previewPos.Z}
	for i, box in ipairs(posBoxes) do
		if not box:IsFocused() then
			box.Text = fmt(p[i])
		end
	end

	local rx, ry, rz = rotCF:ToOrientation()
	local r = {math.deg(rx), math.deg(ry), math.deg(rz)}
	for i, box in ipairs(rotBoxes) do
		if not box:IsFocused() then
			box.Text = fmt(r[i])
		end
	end
end

local function applyPreview()
	if previewModel then
		local firstCFrame = CFrame.new(previewPos) * rotCF
		previewModel:PivotTo(firstCFrame)
		if selectedEntry and selectedEntry.kind == "blueprint" then
			local count = math.floor(tonumber(posBoxes.copyCount.Text) or 1)
			count = math.clamp(count, 1, 100)
			local offsets = rotBoxes.offsetBoxes
			local x = tonumber(offsets[1].Text)
			local y = tonumber(offsets[2].Text)
			local z = tonumber(offsets[3].Text)
			if x and y and z then
				local offset = Vector3.new(x, y, z)
				if not selectedEntry.copyPreviewFolder then
					selectedEntry.copyPreviewFolder = Instance.new("Folder")
					selectedEntry.copyPreviewFolder.Name = "BlueprintCopyPreviews"
					selectedEntry.copyPreviewFolder.Parent = workspace
					selectedEntry.copyPreviews = {}
				end
				for index = 1, count - 1 do
					local copyPreview = selectedEntry.copyPreviews[index]
					if not copyPreview or not copyPreview.Parent then
						copyPreview = previewModel:Clone()
						copyPreview.Name = "BlueprintCopyPreview_" .. (index + 1)
						copyPreview.Parent = selectedEntry.copyPreviewFolder
						selectedEntry.copyPreviews[index] = copyPreview
					end
					copyPreview:PivotTo(firstCFrame + offset * index)
				end
				for index = count, #selectedEntry.copyPreviews do
					local copyPreview = selectedEntry.copyPreviews[index]
					if copyPreview then copyPreview:Destroy() end
					selectedEntry.copyPreviews[index] = nil
				end
			end
		end
		refreshBoxes()
	end
end

local function setPreviewRotation(newRotation)
	if not previewModel then
		rotCF = newRotation
		return
	end
	-- Keep the model's bounds center fixed while its orientation changes, so
	-- rotation behaves as if it were around the middle instead of the pivot.
	local centerBefore = worldBounds(previewModel)
	rotCF = newRotation
	previewModel:PivotTo(CFrame.new(previewPos) * rotCF)
	local centerAfter = worldBounds(previewModel)
	previewPos += centerBefore - centerAfter
	applyPreview()
end

-- World-aligned bounds of a model (center, size)
worldBounds = function(model)
	local minV, maxV
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local h = part.Size / 2
			local cf = part.CFrame
			for _, x in ipairs({-1, 1}) do
				for _, y in ipairs({-1, 1}) do
					for _, z in ipairs({-1, 1}) do
						local corner = cf * Vector3.new(h.X * x, h.Y * y, h.Z * z)
						minV = minV and minV:Min(corner) or corner
						maxV = maxV and maxV:Max(corner) or corner
					end
				end
			end
		end
	end
	if not minV then
		return model:GetPivot().Position, Vector3.zero
	end
	return (minV + maxV) / 2, maxV - minV
end

-- Snap one axis; odd-sized pieces centre on a half cell, even-sized ones on a grid line
local function snapAxis(value, size, grid)
	local n = math.floor(size / grid + 0.5)
	if n % 2 == 1 then
		return math.floor(value / grid) * grid + grid / 2
	end
	return math.floor(value / grid + 0.5) * grid
end

local function snapAxisWithOffset(value, size, grid, offset)
	return snapAxis(value - offset, size, grid) + offset
end

stylePreview = function(model)
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = true
			obj.CanCollide = false
			obj.CanQuery = false
			obj.CanTouch = false
			if obj.Transparency < 0.5 then
				obj.Transparency = 0.5
			end
		elseif obj:IsA("Script") or obj:IsA("LocalScript") then
			obj:Destroy()
		end
	end
end

-- Reading the game's blueprint data ---------------------------------

local function getInfoEntry(id)
	local info = ReplicatedStorage:FindFirstChild("ClientItemInfo")
	return info and info:FindFirstChild(id)
end

-- Display name = ClientItemInfo.<BlueprintID>.ItemName (a StringValue), same as the game's menu
local function getDisplayName(id)
	local entry = getInfoEntry(id)
	local itemName = entry and entry:FindFirstChild("ItemName")

	if itemName and itemName:IsA("ValueBase") and tostring(itemName.Value) ~= "" then
		return tostring(itemName.Value)
	end

	return id -- no entry: fall back to the internal ID
end

local function resolveModelRef(ref)
	if not ref then
		return nil
	end
	if ref:IsA("ObjectValue") then
		ref = ref.Value
	end
	if ref and (ref:IsA("Model") or ref:IsA("BasePart")) then
		return ref
	end
	return nil
end

-- PlacingModel first, then Model (same as the normal building UI)
local function getPlacementModel(id)
	local entry = getInfoEntry(id)
	if not entry then
		return nil
	end
	return resolveModelRef(entry:FindFirstChild("PlacingModel"))
		or resolveModelRef(entry:FindFirstChild("Model"))
end

local function collectBlueprints()
	local categories = {}

	local pb = player:FindFirstChild("PlayerBlueprints")
	local folder = pb and pb:FindFirstChild("Blueprints")
	if folder then
	for _, bp in ipairs(folder:GetChildren()) do
		local id = bp.Name
		local nameValue = bp:FindFirstChild("Name")
		if nameValue and nameValue:IsA("ValueBase") then
			id = tostring(nameValue.Value)
		end

		local cat = "Other"
		local catValue = bp:FindFirstChild("ItemCategory")
		if catValue and catValue:IsA("ValueBase") then
			cat = tostring(catValue.Value)
		else
			local attr = bp:GetAttribute("ItemCategory")
			if attr then
				cat = tostring(attr)
			end
		end

		categories[cat] = categories[cat] or {}
		table.insert(categories[cat], {id = id, display = getDisplayName(id), kind = "blueprint"})
	end
	end

	return categories
end

-- Placement control ---------------------------------------------------

local function unbindKeys()
	if not keysBound then
		return
	end
	keysBound = false
	for _, name in ipairs(KEY_ACTIONS) do
		ContextActionService:UnbindAction(name)
	end
end

local endPlacing
local placeBlueprint

endPlacing = function()
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	if selectedEntry and selectedEntry.copyPreviewFolder then
		selectedEntry.copyPreviewFolder:Destroy()
		selectedEntry.copyPreviewFolder = nil
		selectedEntry.copyPreviews = nil
	end
	placementRoot.Visible = false
	unbindKeys()
	buildingActive = false
	holdingMouse = false
	selectedEntry = nil
	setStatus("Equip the Blueprint Tool to choose a blueprint.")
end

placeBlueprint = function()
	if not previewModel or not selectedEntry then
		return
	end

	local cf = CFrame.new(previewPos) * rotCF
	previewModel:PivotTo(cf)

	if selectedEntry.kind == "model" then
		local structure = selectedEntry.model
		if not structure or not structure.Parent then
			setStatus("That PlayerModel is no longer available. Refresh the list.")
			return
		end
		local itemName = structure:FindFirstChild("ItemName")
		local ownerValue = structure:FindFirstChild("Owner")
		local woodClass = structure:FindFirstChild("BlueprintWoodClass")
		local info = itemName and getInfoEntry(itemName.Value)
		local placeFolder = ReplicatedStorage:FindFirstChild("PlaceStructure")
		local remote = placeFolder and placeFolder:FindFirstChild("ClientPlacedStructure")
		local blueprintMoveRemote = placeFolder and placeFolder:FindFirstChild("ClientPlacedBlueprint")
		local itemTypeValue = structure:FindFirstChild("Type")
		local isBlueprintModel = itemTypeValue and itemTypeValue:IsA("StringValue")
			and itemTypeValue.Value == "Blueprint"
		if not (itemName and itemName:IsA("StringValue") and info) then
			setStatus("Cannot move this model: item info is missing.")
			return
		end
		local requiredRemote = remote
		if isBlueprintModel then requiredRemote = blueprintMoveRemote end
		if not (requiredRemote and requiredRemote:IsA("RemoteEvent")) then
			setStatus(isBlueprintModel and "Cannot move this Blueprint: ClientPlacedBlueprint remote is missing."
				or "Cannot move this model: ClientPlacedStructure remote is missing.")
			return
		end

		local owner = ownerValue and ownerValue.Value or player
		local originalParent = structure.Parent
		local fired = pcall(function()
			structure.Parent = nil
			if isBlueprintModel then
				blueprintMoveRemote:FireServer(itemName.Value, cf, owner, structure, true)
			else
				remote:FireServer(itemName.Value, cf, owner, woodClass and woodClass.Value or nil, structure, true)
			end
		end)
		if not fired then
			if not structure.Parent then structure.Parent = originalParent end
			setStatus("The move request could not be sent.")
			return
		end

		local display = selectedEntry.display
		placedCount += 1
		endPlacing()
		setStatus("Moved " .. display .. " (#" .. placedCount .. ").")
		return
	end

	-- Parse the batch count and per-copy world-space offset.
	local requestedCopies = tonumber(posBoxes.copyCount.Text)
	if not requestedCopies then
		setStatus("Copies must be a whole number from 1 to 100.")
		return
	end
	local copyCount = math.floor(requestedCopies)
	if requestedCopies ~= copyCount or copyCount < 1 or copyCount > 100 then
		setStatus("Copies must be a whole number from 1 to 100.")
		return
	end
	local offsetValues = {}
	for index, box in ipairs(rotBoxes.offsetBoxes) do
		offsetValues[index] = tonumber(box.Text)
		if not offsetValues[index] then
			setStatus("Enter a numeric X, Y, and Z offset.")
			return
		end
	end
	local copyOffset = Vector3.new(offsetValues[1], offsetValues[2], offsetValues[3])
	local firstCFrame = CFrame.new(previewPos) * rotCF

	local note = ""

	local placeFolder = ReplicatedStorage:FindFirstChild("PlaceStructure")
	local remote = placeFolder and placeFolder:FindFirstChild("ClientPlacedBlueprint")
	if not remote then
		setStatus("ClientPlacedBlueprint remote not found.")
		return
	end

	if selectedEntry.placingCopies then return end
	selectedEntry.placingCopies = true
	local batchEntry = selectedEntry
	local batchPreview = previewModel
	local placedThisBatch = 0
	for index = 1, copyCount do
		local cfForCopy = firstCFrame + copyOffset * (index - 1)
		batchPreview:PivotTo(cfForCopy)
		local ok = pcall(function()
			remote:FireServer(batchEntry.id, cfForCopy, player)
		end)
		if not ok then
			batchEntry.placingCopies = false
			if batchPreview.Parent then batchPreview:PivotTo(firstCFrame) end
			setStatus("Placed " .. placedThisBatch .. " of " .. copyCount .. "; the next request failed.")
			return
		end
		placedThisBatch += 1
		placedCount += 1
		if index < copyCount then
			if batchPreview.Parent then batchPreview:PivotTo(firstCFrame) end
			setStatus("Placed " .. placedThisBatch .. " of " .. copyCount .. "... next in 0.6s" .. note)
			task.wait(0.6)
			if not batchPreview.Parent then
				batchEntry.placingCopies = false
				return
			end
		end
	end
	batchEntry.placingCopies = false
	if batchPreview.Parent then batchPreview:PivotTo(firstCFrame) end
	setStatus("Placed " .. placedThisBatch .. " " .. batchEntry.display
		.. (placedThisBatch == 1 and " copy" or " copies") .. " (#" .. placedCount .. ")" .. note)
end

local function bindKeys()
	if keysBound then
		return
	end
	keysBound = true

	local function bind(name, key, fn)
		ContextActionService:BindActionAtPriority(name, function(_, state)
			if state == Enum.UserInputState.Begin then
				fn()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, key)
	end

	bind("BP_Yaw", Enum.KeyCode.R, function()
		setPreviewRotation(CFrame.Angles(0, math.rad(90), 0) * rotCF)
	end)
	bind("BP_Pitch", Enum.KeyCode.T, function()
		setPreviewRotation(rotCF * CFrame.Angles(math.rad(90), 0, 0))
	end)
	bind("BP_Place", Enum.KeyCode.E, function()
		placeBlueprint()
	end)
	bind("BP_Done", Enum.KeyCode.B, function()
		endPlacing()
	end)
end

local function selectBlueprint(entry)
	local source = entry.kind == "model" and (entry.previewSource or entry.model) or getPlacementModel(entry.id)
	if not source then
		setStatus("No placement model found for " .. entry.display .. ".")
		return
	end

	local clone = source:Clone()
	if not clone then
		setStatus("Couldn't clone the model for " .. entry.display .. ".")
		return
	end

	local hadPreview = previewModel ~= nil
	if selectedEntry and selectedEntry.copyPreviewFolder then
		selectedEntry.copyPreviewFolder:Destroy()
		selectedEntry.copyPreviewFolder = nil
		selectedEntry.copyPreviews = nil
	end
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end

	if clone:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		clone.Parent = wrapper
		wrapper.PrimaryPart = clone
		clone = wrapper
	end
	clone.Name = "BlueprintPreview"
	stylePreview(clone)
	clone.Parent = workspace

	previewModel = clone
	selectedEntry = entry
	placementRoot.Visible = true
	pickerGui.Enabled = false

	if entry.kind == "model" then
		local pivot = entry.model:GetPivot()
		previewPos = pivot.Position
		rotCF = pivot - pivot.Position
	elseif not hadPreview and hrp then
		previewPos = hrp.Position + hrp.CFrame.LookVector * 12
	end

	buildingActive = true
	bindKeys()
	applyPreview()

	setStatus(entry.display .. ": hold left click to move, R yaw, T pitch, E place/move, B done.")
end

local function buildBlueprintList()
	local categories = collectBlueprints()
	local names = {}
	for name in pairs(categories) do
		table.insert(names, name)
	end
	table.sort(names)

	if #names == 0 then
		setStatus("No blueprints found in your inventory.")
		return
	end
	local function clearList(container, layout)
		for _, child in ipairs(container:GetChildren()) do
			if child ~= layout then child:Destroy() end
		end
	end
	local function itemImage(entry)
		local info = getInfoEntry(entry.id)
		local image = info and info:FindFirstChild("ItemImage")
		return image and image:IsA("StringValue") and image.Value or ""
	end
	local function showCategory(categoryName)
		clearList(blueprintItemsScroll, blueprintItemsLayout)
		local entries = categories[categoryName] or {}
		table.sort(entries, function(a, b) return a.display < b.display end)
		for index, entry in ipairs(entries) do
			local tile = Instance.new("TextButton")
			tile.Size = UDim2.new(0, 104, 0, 118)
			tile.BackgroundColor3 = THEME.Button
			tile.BorderColor3 = THEME.ButtonHover
			tile.BorderSizePixel = 1
			tile.Text = ""
			tile.AutoButtonColor = false
			tile.LayoutOrder = index
			tile.Parent = blueprintItemsScroll
			round(tile, 8)
			hover(tile, THEME.Button, THEME.ButtonHover)
			local image = Instance.new("ImageLabel")
			image.Size = UDim2.new(1, -12, 0, 78)
			image.Position = UDim2.new(0, 6, 0, 6)
			image.BackgroundColor3 = THEME.Card
			image.BorderSizePixel = 0
			image.ScaleType = Enum.ScaleType.Fit
			image.Image = itemImage(entry)
			image.Parent = tile
			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, -6, 0, 30)
			title.Position = UDim2.new(0, 3, 0, 84)
			title.BackgroundTransparency = 1
			title.Text = entry.display
			title.TextColor3 = THEME.Text
			title.Font = Enum.Font.Gotham
			title.TextSize = 12
			title.TextWrapped = true
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.Parent = tile
			tile.MouseButton1Click:Connect(function()
				selectBlueprint(entry)
				if previewModel and blueprintTool then
					blueprintTool.Parent = player:WaitForChild("Backpack")
				end
			end)
		end
	end
	clearList(categoryScroll, categoryLayout)
	clearList(blueprintItemsScroll, blueprintItemsLayout)
	for index, catName in ipairs(names) do
		local catButton = Instance.new("TextButton")
		catButton.Size = UDim2.new(1, -8, 0, 100)
		catButton.BackgroundColor3 = THEME.Button
		catButton.BorderColor3 = THEME.ButtonHover
		catButton.BorderSizePixel = 1
		catButton.Text = ""
		catButton.AutoButtonColor = false
		catButton.LayoutOrder = index
		catButton.Parent = categoryScroll
		round(catButton, 8)
		hover(catButton, THEME.Button, THEME.ButtonHover)
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.new(1, -12, 0, 60)
		image.Position = UDim2.new(0, 6, 0, 5)
		image.BackgroundColor3 = THEME.Card
		image.BorderSizePixel = 0
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = itemImage(categories[catName][1])
		image.Parent = catButton
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -4, 0, 28)
		title.Position = UDim2.new(0, 2, 0, 65)
		title.BackgroundTransparency = 1
		title.Text = catName
		title.TextColor3 = THEME.Text
		title.Font = Enum.Font.Gotham
		title.TextSize = 12
		title.TextWrapped = true
		title.Parent = catButton
		catButton.MouseButton1Click:Connect(function() showCategory(catName) end)
	end
	showCategory(names[1])
end

createBlueprintTool = function()
	local backpack = player:WaitForChild("Backpack")
	local existing = backpack:FindFirstChild("Blueprint Tool") or (character and character:FindFirstChild("Blueprint Tool"))
	if existing then existing:Destroy() end
	local tool = Instance.new("Tool")
	tool.Name = "Blueprint Tool"
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = "Equip to browse and place owned blueprints"
	tool.Equipped:Connect(function()
		buildBlueprintList()
		pickerGui.Enabled = true
	end)
	tool.Unequipped:Connect(function()
		pickerGui.Enabled = false
	end)
	tool.Destroying:Connect(function()
		pickerGui.Enabled = false
	end)
	blueprintTool = tool
	tool.Parent = backpack
	setStatus("Blueprint Tool added to your Backpack.")
end

giveToolButton.MouseButton1Click:Connect(function()
	createBlueprintTool()
end)

pickerClose.MouseButton1Click:Connect(function()
	pickerGui.Enabled = false
	if blueprintTool and blueprintTool.Parent == character then
		blueprintTool.Parent = player:WaitForChild("Backpack")
	end
end)

-- Manual position / rotation input
local function applyBoxes()
	if not previewModel then
		return
	end

	local p = {}
	for i, box in ipairs(posBoxes) do
		p[i] = tonumber(box.Text)
	end
	local r = {}
	for i, box in ipairs(rotBoxes) do
		r[i] = tonumber(box.Text)
	end
	local hasPosition = p[1] and p[2] and p[3]
	local hasRotation = r[1] and r[2] and r[3]
	local position = hasPosition and Vector3.new(p[1], p[2], p[3]) or nil
	if hasRotation then
		local newRotation = CFrame.fromOrientation(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
		local positionWasEdited = position and (position - previewPos).Magnitude > 0.005
		if positionWasEdited then
			-- Explicit coordinates are the requested pivot position; don't let
			-- center-preserving rotation adjustment override them.
			rotCF = newRotation
			previewPos = position
			applyPreview()
		else
			setPreviewRotation(newRotation)
		end
	elseif hasPosition then
		previewPos = position
		applyPreview()
	else
		applyPreview()
	end
end

applyButton.MouseButton1Click:Connect(applyBoxes)
posBoxes.copyCount.FocusLost:Connect(applyPreview)
for _, box in ipairs(rotBoxes.offsetBoxes) do
	box.FocusLost:Connect(applyPreview)
end
for _, box in ipairs(posBoxes) do
	box.FocusLost:Connect(applyBoxes)
end
for _, box in ipairs(rotBoxes) do
	box.FocusLost:Connect(applyBoxes)
end

placeButton.MouseButton1Click:Connect(function()
	placeBlueprint()
end)
doneButton.MouseButton1Click:Connect(function()
	endPlacing()
end)
refreshBpButton.MouseButton1Click:Connect(endPlacing)

-- Move the preview only while left click is held
local buildRayParams = RaycastParams.new()
buildRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function pointerOverUi()
	local mouse = UserInputService:GetMouseLocation()
	-- GetGuiObjectsAtPosition expects screen coordinates; GetMouseLocation already
	-- returns those coordinates, so subtracting the top-bar inset misses UI controls.
	local objects = getGuiObjectsAtPosition(mouse.X, mouse.Y)
	-- UI created by the game can live in PlayerGui rather than the executor GUI.
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		local ok, found = pcall(function()
			return playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
		end)
		if ok and found then
			for _, object in ipairs(found) do
				table.insert(objects, object)
			end
		end
	end
	-- Executor interfaces may be parented directly under CoreGui, outside both
	-- PlayerGui and the hidden executor GUI returned by gethui().
	local coreGui = game:GetService("CoreGui")
	local coreOk, coreFound = pcall(function()
		return coreGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
	end)
	if coreOk and coreFound then
		for _, object in ipairs(coreFound) do
			table.insert(objects, object)
		end
	end
	for _, uiObject in ipairs(objects) do
		if uiObject ~= placementRoot and (
			uiObject:IsA("GuiButton")
			or uiObject:IsA("TextBox")
			or uiObject.Active
			or uiObject:IsDescendantOf(gui)
			or uiObject:IsDescendantOf(placementGui)
			or uiObject:IsDescendantOf(pickerGui)
		) then
			return true
		end
	end
	return false
end

local advancedInfoGui = Instance.new("ScreenGui")
advancedInfoGui.Name = "AdvancedItemInfo"
advancedInfoGui.ResetOnSpawn = false
advancedInfoGui.Enabled = false
advancedInfoGui.DisplayOrder = 50
advancedInfoGui.Parent = executorGui

local infoOverlay = Instance.new("Frame")
infoOverlay.Size = UDim2.new(1, 0, 1, 0)
infoOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
infoOverlay.BackgroundTransparency = 1
infoOverlay.BorderSizePixel = 0
infoOverlay.Parent = advancedInfoGui

local infoPanel = Instance.new("Frame")
infoPanel.Size = UDim2.new(0, 400, 0, 282)
infoPanel.Position = UDim2.new(0.5, -200, 0.5, -170)
infoPanel.BackgroundColor3 = THEME.Card
infoPanel.BorderColor3 = THEME.ButtonHover
infoPanel.BorderSizePixel = 1
infoPanel.Parent = infoOverlay
round(infoPanel, 12)

local function capInfoTextSize(textObject, maxTextSize)
	textObject.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 8
	constraint.MaxTextSize = maxTextSize
	constraint.Parent = textObject
end

local infoName = Instance.new("TextLabel")
infoName.Size = UDim2.new(0, 228, 0, 44)
infoName.Position = UDim2.new(0, 18, 0, 8)
infoName.BackgroundTransparency = 1
infoName.TextColor3 = THEME.Text
infoName.Font = Enum.Font.GothamBold
infoName.TextSize = 21
infoName.TextWrapped = true
infoName.TextScaled = true
infoName.TextXAlignment = Enum.TextXAlignment.Left
infoName.Parent = infoPanel
capInfoTextSize(infoName, 21)

local infoType = Instance.new("TextLabel")
infoType.Size = UDim2.new(0, 240, 0, 24)
infoType.Position = UDim2.new(0, 18, 0, 48)
infoType.BackgroundTransparency = 1
infoType.TextColor3 = THEME.SubText
infoType.Font = Enum.Font.GothamBold
infoType.TextSize = 16
infoType.TextXAlignment = Enum.TextXAlignment.Left
infoType.Parent = infoPanel
capInfoTextSize(infoType, 16)

local infoCost = Instance.new("TextLabel")
infoCost.Size = UDim2.new(0, 220, 0, 22)
infoCost.Position = UDim2.new(0, 18, 0, 76)
infoCost.BackgroundTransparency = 1
infoCost.TextColor3 = THEME.SubText
infoCost.Font = Enum.Font.Gotham
infoCost.TextSize = 14
infoCost.TextXAlignment = Enum.TextXAlignment.Left
infoCost.Parent = infoPanel
capInfoTextSize(infoCost, 14)

local infoOwner = Instance.new("TextLabel")
infoOwner.Size = UDim2.new(1, -36, 0, 22)
infoOwner.Position = UDim2.new(0, 18, 0, 100)
infoOwner.BackgroundTransparency = 1
infoOwner.TextColor3 = THEME.SubText
infoOwner.Font = Enum.Font.Gotham
infoOwner.TextSize = 14
infoOwner.TextXAlignment = Enum.TextXAlignment.Left
infoOwner.Parent = infoPanel
capInfoTextSize(infoOwner, 14)

local infoWoodClass = Instance.new("TextLabel")
infoWoodClass.Size = UDim2.new(1, -36, 0, 22)
infoWoodClass.Position = UDim2.new(0, 18, 0, 122)
infoWoodClass.BackgroundTransparency = 1
infoWoodClass.TextColor3 = THEME.SubText
infoWoodClass.Font = Enum.Font.Gotham
infoWoodClass.TextSize = 14
infoWoodClass.TextXAlignment = Enum.TextXAlignment.Left
infoWoodClass.Visible = false
infoWoodClass.Parent = infoPanel
capInfoTextSize(infoWoodClass, 14)

local infoDetail = Instance.new("TextLabel")
infoDetail.Size = UDim2.new(1, -36, 0, 22)
infoDetail.Position = UDim2.new(0, 18, 0, 122)
infoDetail.BackgroundTransparency = 1
infoDetail.TextColor3 = THEME.SubText
infoDetail.Font = Enum.Font.Gotham
infoDetail.TextSize = 14
infoDetail.TextXAlignment = Enum.TextXAlignment.Left
infoDetail.Visible = false
infoDetail.Parent = infoPanel
capInfoTextSize(infoDetail, 14)

local infoImage = Instance.new("ImageLabel")
infoImage.Size = UDim2.new(0, 112, 0, 112)
infoImage.Position = UDim2.new(1, -126, 0, 24)
infoImage.BackgroundColor3 = THEME.Background
infoImage.BorderSizePixel = 0
infoImage.ScaleType = Enum.ScaleType.Stretch
infoImage.ClipsDescendants = true
infoImage.Visible = true
infoImage.Parent = infoPanel

local infoWoodViewport = Instance.new("ViewportFrame")
infoWoodViewport.Size = infoImage.Size
infoWoodViewport.Position = infoImage.Position
infoWoodViewport.BackgroundColor3 = THEME.Background
infoWoodViewport.BorderSizePixel = 0
infoWoodViewport.Visible = false
infoWoodViewport.Parent = infoPanel

local infoDescription = Instance.new("TextLabel")
infoDescription.Size = UDim2.new(1, -36, 0, 76)
infoDescription.Position = UDim2.new(0, 18, 0, 150)
infoDescription.BackgroundTransparency = 1
infoDescription.TextColor3 = THEME.Text
infoDescription.Font = Enum.Font.GothamBold
infoDescription.TextSize = 14
infoDescription.TextScaled = true
infoDescription.TextWrapped = true
infoDescription.TextYAlignment = Enum.TextYAlignment.Top
infoDescription.TextXAlignment = Enum.TextXAlignment.Left
infoDescription.Parent = infoPanel
capInfoTextSize(infoDescription, 14)

local infoMoveButton = Instance.new("TextButton")
infoMoveButton.Size = UDim2.new(0, 135, 0, 36)
infoMoveButton.Position = UDim2.new(0, 8, 1, -44)
infoMoveButton.BackgroundColor3 = THEME.Button
infoMoveButton.BorderSizePixel = 0
infoMoveButton.Text = "Move"
infoMoveButton.TextColor3 = THEME.Text
infoMoveButton.Font = Enum.Font.GothamBold
infoMoveButton.TextSize = 20
infoMoveButton.Visible = false
infoMoveButton.Parent = infoPanel
capInfoTextSize(infoMoveButton, 20)
round(infoMoveButton, 8)
hover(infoMoveButton, THEME.Button, THEME.ButtonHover)

local infoDestroyButton = Instance.new("TextButton")
infoDestroyButton.Size = UDim2.new(0, 135, 0, 36)
infoDestroyButton.Position = UDim2.new(1, -143, 1, -44)
infoDestroyButton.BackgroundColor3 = THEME.Button
infoDestroyButton.BorderSizePixel = 0
infoDestroyButton.Text = "Destroy"
infoDestroyButton.TextColor3 = THEME.Text
infoDestroyButton.Font = Enum.Font.GothamBold
infoDestroyButton.TextSize = 20
infoDestroyButton.Visible = false
infoDestroyButton.Parent = infoPanel
capInfoTextSize(infoDestroyButton, 20)
round(infoDestroyButton, 8)
hover(infoDestroyButton, THEME.Button, THEME.ButtonHover)

local infoCloseButton = Instance.new("TextButton")
infoCloseButton.Size = UDim2.new(0, 130, 0, 40)
infoCloseButton.Position = UDim2.new(0.5, -65, 0.5, 122)
infoCloseButton.BackgroundColor3 = THEME.Button
infoCloseButton.BorderColor3 = THEME.ButtonHover
infoCloseButton.BorderSizePixel = 1
infoCloseButton.Text = "Close"
infoCloseButton.TextColor3 = THEME.Text
infoCloseButton.Font = Enum.Font.GothamBold
infoCloseButton.TextSize = 20
infoCloseButton.Parent = infoOverlay
capInfoTextSize(infoCloseButton, 20)
round(infoCloseButton, 8)
hover(infoCloseButton, THEME.Button, THEME.ButtonHover)

local infoTarget
local infoIsMovable = false
local function closeAdvancedInfo()
	advancedInfoGui.Enabled = false
	infoWoodViewport:ClearAllChildren()
	infoWoodViewport.Visible = false
	infoTarget = nil
end

infoCloseButton.MouseButton1Click:Connect(closeAdvancedInfo)
infoMoveButton.MouseButton1Click:Connect(function()
	if not infoTarget or not infoIsMovable then return end
	local target = infoTarget
	local itemName = target:FindFirstChild("ItemName")
	if not (itemName and itemName:IsA("StringValue") and itemName.Value ~= "") then
		advancedInfoStatus.Text = "This model has no ItemName StringValue."
		return
	end
	local id = itemName.Value
	local clientItemInfo = ReplicatedStorage:FindFirstChild("ClientItemInfo")
	local itemInfo = clientItemInfo and clientItemInfo:FindFirstChild(id)
	local previewSource = itemInfo and itemInfo:FindFirstChild("Model")
	if not (previewSource and previewSource:IsA("Model")) then
		advancedInfoStatus.Text = "No Model preview found in ClientItemInfo for " .. id .. "."
		return
	end
	local display = infoName.Text .. " [" .. infoType.Text .. "]"
	closeAdvancedInfo()
	selectBlueprint({id = id, display = display, kind = "model", model = target, previewSource = previewSource})
end)
-- Destroy is intentionally display-only for now.

local function readInfoString(entry, name)
	local value = entry and entry:FindFirstChild(name)
	if value and value:IsA("StringValue") then return value.Value end
	return ""
end

local function getPlayerModelItemId(target)
	local itemName = target:FindFirstChild("ItemName")
	if itemName and itemName:IsA("StringValue") and itemName.Value ~= "" then
		return itemName.Value
	end
	local purchasedBoxItemName = target:FindFirstChild("PurchasedBoxItemName")
	if purchasedBoxItemName and purchasedBoxItemName:IsA("StringValue") and purchasedBoxItemName.Value ~= "" then
		return purchasedBoxItemName.Value
	end
	return nil
end

local function isShopItem(target)
	local stores = workspace:FindFirstChild("Stores")
	if not stores or not target:IsDescendantOf(stores) then return false end
	local current = target
	while current and current ~= stores do
		if current.Name == "ShopItems" then return true end
		current = current.Parent
	end
	return false
end

local function isLogModel(target)
	local logs = workspace:FindFirstChild("LogModels")
	if not target:IsA("Model") then return false end
	if logs and target:IsDescendantOf(logs) then return true end
	local ancestor = target.Parent
	while ancestor and ancestor ~= workspace do
		if ancestor.Name == "TreeRegion" and ancestor:IsA("Model") then return true end
		ancestor = ancestor.Parent
	end
	return false
end

local function showAdvancedInfo(target)
	local isTree = isLogModel(target)
	local isPlank = not isTree and target.Name == "Plank"
	local shopItem = not isPlank and isShopItem(target)
	local itemId
	local itemInfo
	local modelTypeValue = target:FindFirstChild("Type")
	if not (modelTypeValue and modelTypeValue:IsA("StringValue")) then
		modelTypeValue = target:FindFirstChild("Type", true)
	end
	local modelTypeName = modelTypeValue and modelTypeValue:IsA("StringValue") and modelTypeValue.Value or ""
	if not isPlank and not isTree then
		if shopItem then
			local boxItemName = target:FindFirstChild("BoxItemName", true)
			if boxItemName and boxItemName:IsA("StringValue") and boxItemName.Value ~= "" then
				itemId = boxItemName.Value
			end
		else
			itemId = getPlayerModelItemId(target)
		end
		if not itemId then
			advancedInfoStatus.Text = shopItem and "Shop item has no BoxItemName" or "Model has no ItemName or PurchasedBoxItemName"
			return
		end
		local infoFolder = ReplicatedStorage:FindFirstChild("ClientItemInfo")
		local infoReference = itemId
		if modelTypeName == "Vehicle" then
			infoReference = infoReference:gsub("_Vehicle", "")
		end
		itemInfo = infoFolder and infoFolder:FindFirstChild(infoReference)
		if not itemInfo then
			advancedInfoStatus.Text = "No item info found for " .. itemId
			return
		end
	end

	local itemName = (isPlank or isTree) and target.Name or readInfoString(itemInfo, "ItemName")
	local itemType = isPlank and "Plank" or (isTree and "Tree" or modelTypeName)
	local description = (isPlank or isTree) and "" or readInfoString(itemInfo, "Description")
	local imageId = (isPlank or isTree) and "" or readInfoString(itemInfo, "ItemImage")
	local price = itemInfo and itemInfo:FindFirstChild("Price")
	local volumeInfoText
	if isTree then
		local treeClass = target:FindFirstChild("TreeClass")
		local treeClassName = treeClass and treeClass:IsA("StringValue") and treeClass.Value or ""
		itemName = (treeClassName ~= "" and (treeClassName .. " ") or "") .. "Tree"
		local totalVolume = 0
		for _, part in ipairs(target:GetDescendants()) do
			if part:IsA("BasePart") and part.Name == "WoodSection" then
				totalVolume = totalVolume + part.Size.X * part.Size.Y * part.Size.Z
			end
		end
		volumeInfoText = "Volume: " .. fmt(totalVolume)
	elseif isPlank then
		local treeClass = target:FindFirstChild("TreeClass")
		local treeClassName = treeClass and treeClass:IsA("StringValue") and treeClass.Value or ""
		itemName = (treeClassName ~= "" and (treeClassName .. " ") or "") .. "Plank"
		local woodSection = target:FindFirstChild("WoodSection", true)
		if woodSection and woodSection:IsA("BasePart") then
			local size = woodSection.Size
			volumeInfoText = "Volume: " .. fmt(size.X * size.Y * size.Z)
		end
		local typeValue = target:FindFirstChild("Type")
		if typeValue and typeValue:IsA("StringValue") then itemType = typeValue.Value end
	else
		if itemName == "" then itemName = itemId end
		if itemType == "" then itemType = "Unknown" end
	end
	infoName.Text = itemName
	infoType.Text = itemType
	infoDescription.Text = description
	infoCost.Text = "Cost: " .. (price and price:IsA("IntValue") and tostring(price.Value) or "N/A")
	local owner = target:FindFirstChild("Owner")
	infoOwner.Text = "Owner: " .. (owner and owner:IsA("ObjectValue") and owner.Value and owner.Value.Name or "Unknown")
	local typeValue = target:FindFirstChild("Type")
	local blueprintWoodClass = target:FindFirstChild("BlueprintWoodClass")
	local showWoodClass = typeValue and typeValue:IsA("StringValue") and typeValue.Value == "Structure"
		and blueprintWoodClass and blueprintWoodClass:IsA("StringValue")
	infoWoodClass.Visible = showWoodClass == true
	if infoWoodClass.Visible then
		infoWoodClass.Text = "Wood Type: " .. blueprintWoodClass.Value
	else
		infoWoodClass.Text = ""
	end
	local itemNameValue = target:FindFirstChild("ItemName")
	local isPumpkinItem = itemNameValue ~= nil and itemNameValue:IsA("StringValue")
		and (itemNameValue.Value == "Pumpkin" or itemNameValue.Value == "PumpkinCarved")
	local mainUnion = target:FindFirstChild("Main", true)
	local numIdText
	local playerModelsFolder = workspace:FindFirstChild("PlayerModels")
	if playerModelsFolder and target:IsDescendantOf(playerModelsFolder) then
		local mainPart = target:FindFirstChild("Main")
		if mainPart and mainPart:IsA("BasePart") then
			local surfaceGui = mainPart:FindFirstChild("SurfaceGui")
			if surfaceGui and surfaceGui:IsA("SurfaceGui") then
				local numLabel = surfaceGui:FindFirstChild("NumID", true)
				if numLabel and numLabel:IsA("TextLabel") and numLabel.Text ~= "" then
					numIdText = "Num: " .. numLabel.Text
				end
			end
		end
	end
	local vehicleColorText
	if modelTypeName == "Vehicle" then
		local paintParts = target:FindFirstChild("PaintParts")
		local colorPart = paintParts and paintParts:FindFirstChildWhichIsA("BasePart", true)
		if colorPart then
			local colorName = colorPart.BrickColor.Name:gsub("%S+", function(word)
				return word:sub(1, 1):upper() .. word:sub(2):lower()
			end)
			local color = colorPart.Color
			local red = math.floor(color.R * 255 + 0.5)
			local green = math.floor(color.G * 255 + 0.5)
			local blue = math.floor(color.B * 255 + 0.5)
			vehicleColorText = string.format("Color: %s [%d, %d, %d]", colorName, red, green, blue)
		end
	end
	if numIdText then
		infoDetail.Text = numIdText
		infoDetail.Visible = true
	elseif isPumpkinItem and mainUnion and mainUnion:IsA("UnionOperation") then
		infoDetail.Text = "Height: " .. string.format("%.5f", mainUnion.Size.Y)
		infoDetail.Visible = true
	elseif vehicleColorText then
		infoDetail.Text = vehicleColorText
		infoDetail.Visible = true
	elseif volumeInfoText then
		infoDetail.Text = volumeInfoText
		infoDetail.Visible = true
	else
		infoDetail.Text = ""
		infoDetail.Visible = false
	end
	local modelItemName = target:FindFirstChild("ItemName")
	local purchasedBoxItemName = target:FindFirstChild("PurchasedBoxItemName")
	local hasItemName = modelItemName and modelItemName:IsA("StringValue") and modelItemName.Value ~= ""
	local isBoxedForm = not hasItemName
		and purchasedBoxItemName and purchasedBoxItemName:IsA("StringValue")
		and purchasedBoxItemName.Value ~= ""
	local inPlayerModels = false
	local playerModels = workspace:FindFirstChild("PlayerModels")
	if playerModels then inPlayerModels = target:IsDescendantOf(playerModels) end
	local movableType = inPlayerModels and not isTree and not shopItem and not isBoxedForm and (modelTypeName == "Structure"
		or modelTypeName == "Vehicle Spot"
		or modelTypeName == "Furniture"
		or modelTypeName == "Blueprint")
	infoIsMovable = movableType
	infoTarget = target
	infoMoveButton.Visible = movableType
	infoDestroyButton.Visible = movableType
	if isTree then
		local innerWood = target:FindFirstChild("InnerWood", true)
		local bark = target:FindFirstChild("WoodSection", true)
		if bark and bark:IsA("BasePart") then
			infoImage.Visible = false
			infoWoodViewport:ClearAllChildren()
			infoWoodViewport.Ambient = Color3.new(1, 1, 1)
			infoWoodViewport.LightColor = Color3.new(1, 1, 1)
			infoWoodViewport.LightDirection = Vector3.new(-1, -1, -1)
			local function makeSwatch(name, source, size, depth)
				local swatch = Instance.new("Part")
				swatch.Name = name
				swatch.Size = Vector3.new(size, size, depth)
				swatch.Material = source.Material
				swatch.MaterialVariant = source.MaterialVariant
				swatch.Color = source.Color
				swatch.Anchored = true
				swatch.CanCollide = false
				swatch.CanTouch = false
				swatch.CanQuery = false
				swatch.Parent = infoWoodViewport
				for _, child in ipairs(source:GetDescendants()) do
					if child:IsA("Texture") or child:IsA("Decal") then
						local texture = child:Clone()
						texture.Face = Enum.NormalId.Back
						texture.Parent = swatch
					end
				end
				return swatch
			end
			makeSwatch("BarkOutline", bark, 1, 0.04)
			if innerWood and innerWood:IsA("BasePart") then
				local innerSwatch = makeSwatch("InnerWood", innerWood, 0.78, 0.05)
				innerSwatch.CFrame = CFrame.new(0, 0, 0.05)
			end
			local camera = Instance.new("Camera")
			camera.FieldOfView = 10
			camera.CFrame = CFrame.new(Vector3.new(0, 0, 5.7), Vector3.zero)
			camera.Parent = infoWoodViewport
			infoWoodViewport.CurrentCamera = camera
			infoWoodViewport.Visible = true
		else
			infoImage.Visible = true
			infoImage.Image = ""
			infoWoodViewport:ClearAllChildren()
			infoWoodViewport.Visible = false
		end
	elseif isPlank then
		local woodSection = target:FindFirstChild("WoodSection", true)
		if woodSection and woodSection:IsA("BasePart") then
			infoImage.Visible = false
			infoWoodViewport:ClearAllChildren()
		infoWoodViewport.Ambient = Color3.new(1, 1, 1)
		infoWoodViewport.LightColor = Color3.new(1, 1, 1)
		infoWoodViewport.LightDirection = Vector3.new(-1, -1, -1)
			local swatch = Instance.new("Part")
			swatch.Name = "FlatWoodMaterial"
			swatch.Size = Vector3.new(1, 1, 0.04)
			swatch.Material = woodSection.Material
			swatch.MaterialVariant = woodSection.MaterialVariant
			swatch.Color = woodSection.Color
			swatch.Anchored = true
			swatch.CanCollide = false
			swatch.CanTouch = false
			swatch.CanQuery = false
			swatch.Parent = infoWoodViewport
			for _, child in ipairs(woodSection:GetDescendants()) do
				if child:IsA("Texture") or child:IsA("Decal") then
					local texture = child:Clone()
					texture.Face = Enum.NormalId.Back
					texture.Parent = swatch
				end
			end
			local camera = Instance.new("Camera")
			camera.FieldOfView = 10
			camera.CFrame = CFrame.new(Vector3.new(0, 0, 5.7), Vector3.zero)
			camera.Parent = infoWoodViewport
			infoWoodViewport.CurrentCamera = camera
			infoWoodViewport.Visible = true
		else
			infoImage.Visible = true
			infoImage.BackgroundColor3 = THEME.Background
			infoImage.ImageColor3 = Color3.new(1, 1, 1)
			infoImage.Image = ""
			infoWoodViewport:ClearAllChildren()
			infoWoodViewport.Visible = false
		end
	else
		infoWoodViewport:ClearAllChildren()
		infoWoodViewport.Visible = false
		infoImage.Visible = true
		infoImage:ClearAllChildren()
		infoImage.BackgroundColor3 = THEME.Background
		infoImage.ImageColor3 = Color3.new(1, 1, 1)
		infoImage.Image = imageId:match("^%d+$") and ("rbxassetid://" .. imageId) or imageId
		infoImage.Visible = true
	end
	advancedInfoGui.Enabled = true
end

local function getHoveredInfoTarget()
	local camera = workspace.CurrentCamera
	local playerModels = workspace:FindFirstChild("PlayerModels")
	local stores = workspace:FindFirstChild("Stores")
	local logs = workspace:FindFirstChild("LogModels")
	if not camera then return nil end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	local result = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
	if not result then return nil end
	if playerModels and result.Instance:IsDescendantOf(playerModels) then
		local target
		local ancestor = result.Instance
		while ancestor and ancestor ~= playerModels do
			if ancestor:IsA("Model") then target = ancestor end
			ancestor = ancestor.Parent
		end
		return target
	end
	if logs and result.Instance:IsDescendantOf(logs) then
		local target = result.Instance
		while target and target.Parent ~= logs do target = target.Parent end
		return target and target:IsA("Model") and target or nil
	end
	local treeTarget
	local ancestor = result.Instance
	while ancestor and ancestor ~= workspace do
		if ancestor.Name == "TreeRegion" and ancestor:IsA("Model") then
			return treeTarget
		end
		if ancestor:IsA("Model") then treeTarget = ancestor end
		ancestor = ancestor.Parent
	end
	if not stores or not result.Instance:IsDescendantOf(stores) then return nil end
	local shopTarget
	local ancestor = result.Instance
	while ancestor and ancestor ~= stores do
		if ancestor.Name == "ShopItems" then return shopTarget end
		if ancestor:IsA("Model") or ancestor:IsA("BasePart") then shopTarget = ancestor end
		ancestor = ancestor.Parent
	end
	return nil
end

local advancedInfoInputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if waitingForInfoKey then
		waitingForInfoKey = false
		if input.KeyCode == Enum.KeyCode.Escape then
			advancedInfoKeyButton.Text = string.upper(Settings.advancedInfoKey or "i")
			return
		end
		Settings.advancedInfoKey = input.KeyCode.Name
		advancedInfoKeyButton.Text = input.KeyCode.Name
		advancedInfoStatus.Text = advancedInfoEnabled and ("On - press " .. input.KeyCode.Name .. " over a PlayerModel") or "Off"
		saveSettings()
		return
	end
	if gameProcessed or not advancedInfoEnabled or UserInputService:GetFocusedTextBox() or advancedInfoGui.Enabled then return end
	local keyName = Settings.advancedInfoKey or "i"
	local infoKey = Enum.KeyCode[keyName] or Enum.KeyCode[string.upper(keyName)]
	if input.KeyCode ~= infoKey or pointerOverUi() then return end
	local target = getHoveredInfoTarget()
	if target then showAdvancedInfo(target) end
end)

local mouseDownConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		and previewModel and not pointerOverUi() then
		holdingMouse = true
	end
end)

local mouseUpConn = UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holdingMouse = false
	end
end)

local dragConn = RunService.RenderStepped:Connect(function()
	if not previewModel or not holdingMouse or pointerOverUi() then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local excluded = {character, previewModel}
	if selectedEntry and selectedEntry.kind == "model" and selectedEntry.model then
		table.insert(excluded, selectedEntry.model)
	end
	buildRayParams.FilterDescendantsInstances = excluded

	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, buildRayParams)

	-- offset between the model's pivot and the centre of its bounds (current rotation)
	local center, size = worldBounds(previewModel)
	local offset = previewPos - center

	local hit
	if result then
		hit = result.Position
	elseif math.abs(ray.Direction.Y) > 1e-6 then
		-- Keep dragging responsive even when the game marks ground parts CanQuery=false.
		local targetY = previewPos.Y - size.Y / 2
		local distance = (targetY - ray.Origin.Y) / ray.Direction.Y
		if distance > 0 then hit = ray.Origin + ray.Direction * distance end
	end
	if not hit then return end
	local grid = tonumber(snapBox.Text) or 0
	local desired
	if result and result.Instance:IsA("BasePart") then
		-- Put the closest face of the preview flush against the hit face. The
		-- raycast normal tells us which of the six sides the cursor touched.
		local normal = result.Normal
		local axis = "X"
		if math.abs(normal.Y) > math.abs(normal.X) and math.abs(normal.Y) >= math.abs(normal.Z) then
			axis = "Y"
		elseif math.abs(normal.Z) > math.abs(normal.X) and math.abs(normal.Z) > math.abs(normal.Y) then
			axis = "Z"
		end
		local sign = normal[axis] >= 0 and 1 or -1
		-- The ray hit lies on the contacted face, so its coordinate is the
		-- face plane even when the target part is rotated.
		local faceCoordinate = hit[axis]
		local previewHalf = size[axis] / 2
		local coords = {X = hit.X, Y = hit.Y, Z = hit.Z}
		coords[axis] = faceCoordinate + sign * previewHalf
		if grid > 0 then
			-- Keep the grid phase of the structure being attached to. This
			-- preserves fractional dimensions such as a 1.1-stud wall height.
			local support = result.Instance
			local playerModelsFolder = workspace:FindFirstChild("PlayerModels")
			local ancestor = result.Instance.Parent
			while ancestor and ancestor ~= playerModelsFolder do
				if ancestor:IsA("Model") then support = ancestor end
				ancestor = ancestor.Parent
			end
			-- Map scenery can be nested under very large models. Only aggregate
			-- bounds for a model explicitly contained by PlayerModels; for other
			-- geometry, use the hit part so dragging never scans the whole map.
			local isPlayerModel = playerModelsFolder and support ~= result.Instance
				and support:IsDescendantOf(playerModelsFolder)
			local supportCenter, supportSize
			if isPlayerModel then
				supportCenter, supportSize = worldBounds(support)
			else
				supportCenter = result.Instance.Position
				supportSize = result.Instance.Size
			end
			for _, otherAxis in ipairs({"X", "Y", "Z"}) do
				if otherAxis ~= axis then
					-- Keep unit spacing, but phase the grid from the support's
					-- lower bound (for example, a wall whose base is at Y=1.1
					-- yields Y positions 1.1, 2.1, 3.1, ...).
					local offset = (supportCenter[otherAxis] - supportSize[otherAxis] / 2) % grid
					coords[otherAxis] = snapAxisWithOffset(coords[otherAxis], size[otherAxis], grid, offset)
				end
			end
		end
		desired = Vector3.new(coords.X, coords.Y, coords.Z)
	else
		-- No surface was hit: retain ground-plane placement and grid snapping.
		desired = Vector3.new(hit.X, hit.Y + size.Y / 2, hit.Z)
		if grid > 0 then
			desired = Vector3.new(
				snapAxis(desired.X, size.X, grid),
				snapAxis(desired.Y, size.Y, grid),
				snapAxis(desired.Z, size.Z, grid)
			)
		end
	end

	previewPos = desired + offset
	applyPreview()
end)

buildBlueprintList()

gui.Destroying:Connect(function()
	endPlacing()
	mouseDownConn:Disconnect()
	mouseUpConn:Disconnect()
	dragConn:Disconnect()
	advancedInfoInputConn:Disconnect()
	if blueprintTool then blueprintTool:Destroy() end
	pickerGui:Destroy()
	placementGui:Destroy()
	advancedInfoGui:Destroy()
end)
end

-------------------------------------------------
-- Player tab: Freecam and Move Tool
-------------------------------------------------
-- Keep these sections in separate scopes to stay within Luau register limits.

do
	local freecamActive = false
	local freecamPosition = Vector3.zero
	local freecamYaw = 0
	local freecamPitch = 0
	local freecamKeys = {}
	local freecamRotating = false
	local freecamSpeed = math.clamp(tonumber(Settings.freecamSpeed) or 32, 1, 500)
	local freecamToggleKey = nil
	if Settings.freecamToggleKey ~= "" then
		local ok, keyCode = pcall(function() return Enum.KeyCode[Settings.freecamToggleKey] end)
		if ok then freecamToggleKey = keyCode end
	end
	local waitingForFreecamKey = false
	local freecamRenderConn = nil
	local savedCamera = nil
	local savedCameraCFrame = nil
	local savedCameraFocus = nil
	local savedCameraType = nil
	local savedCameraSubject = nil
	local savedCameraFov = nil
	local savedMouseSensitivity = nil
	local savedMouseDeltaSensitivity = nil
	local freecamInputBeganConn = nil
	local freecamInputEndedConn = nil
	local freecamDebugDeltaLogged = false
	local savedMouseBehavior = nil
	local controls = nil
	local playerModule = nil
	local FREECAM_ACTION = "AllPurposeScript_FreecamMovement"
	local FREECAM_KEYS = {
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Space, Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl,
		Enum.UserInputType.MouseButton2,
	}

	local function stopFreecam()
		if not freecamActive then
			return
		end
		freecamActive = false
		freecamRotating = false
		if freecamRenderConn then freecamRenderConn:Disconnect(); freecamRenderConn = nil end
		if freecamInputBeganConn then freecamInputBeganConn:Disconnect(); freecamInputBeganConn = nil end
		if freecamInputEndedConn then freecamInputEndedConn:Disconnect(); freecamInputEndedConn = nil end
		ContextActionService:UnbindAction(FREECAM_ACTION)
		table.clear(freecamKeys)
		if savedCamera and savedCamera.Parent then
			pcall(function()
				-- Return every camera property this freecam session may affect to its prior value.
				savedCamera.CameraSubject = savedCameraSubject
				savedCamera.CameraType = savedCameraType
				savedCamera.FieldOfView = savedCameraFov
				savedCamera.Focus = savedCameraFocus
				savedCamera.CFrame = savedCameraCFrame
			end)
		end
		savedCamera = nil
		savedCameraCFrame = nil
		savedCameraFocus = nil
		savedCameraType = nil
		savedCameraSubject = nil
		savedCameraFov = nil
		local currentMouseSensitivity, currentMouseDeltaSensitivity
		pcall(function() currentMouseSensitivity = UserSettings():GetService("UserGameSettings").MouseSensitivity end)
		pcall(function() currentMouseDeltaSensitivity = UserInputService.MouseDeltaSensitivity end)
		print("[Freecam] sensitivity check; MouseSensitivity:", tostring(savedMouseSensitivity), "->", tostring(currentMouseSensitivity), "MouseDeltaSensitivity:", tostring(savedMouseDeltaSensitivity), "->", tostring(currentMouseDeltaSensitivity))
		savedMouseSensitivity = nil
		savedMouseDeltaSensitivity = nil
		if savedMouseBehavior ~= nil then
			UserInputService.MouseBehavior = savedMouseBehavior
			savedMouseBehavior = nil
		end
		print("[Freecam] stopped; restored camera transform and prior mouse behavior")

		if controls then
			pcall(function() controls:Enable() end)
		end


	end

	local function startFreecam()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		freecamActive = true
		savedCamera = camera
		savedCameraCFrame = camera.CFrame
		savedCameraFocus = camera.Focus
		savedCameraType = camera.CameraType
		savedCameraSubject = camera.CameraSubject
		savedCameraFov = camera.FieldOfView
		savedMouseBehavior = UserInputService.MouseBehavior
		pcall(function() savedMouseSensitivity = UserSettings():GetService("UserGameSettings").MouseSensitivity end)
		pcall(function() savedMouseDeltaSensitivity = UserInputService.MouseDeltaSensitivity end)
		camera.CameraType = Enum.CameraType.Scriptable
		freecamPosition = camera.CFrame.Position
		local look = camera.CFrame.LookVector
		freecamYaw = math.atan2(-look.X, -look.Z)
		freecamPitch = math.asin(math.clamp(look.Y, -1, 1))

		-- Disable normal character controls and sink movement keys while freecam is active.
		pcall(function()
			playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
			controls = playerModule:GetControls()
			controls:Disable()
		end)
		ContextActionService:BindActionAtPriority(FREECAM_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 100, table.unpack(FREECAM_KEYS))


		freecamInputBeganConn = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Keyboard then
				freecamKeys[input.KeyCode] = true
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				freecamRotating = true
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
				print("[Freecam] right mouse pressed; cursor locked for mouse deltas")
			end
		end)
		freecamInputEndedConn = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Keyboard then
				freecamKeys[input.KeyCode] = nil
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				freecamRotating = false
				if savedMouseBehavior ~= nil then
					UserInputService.MouseBehavior = savedMouseBehavior
				end
				print("[Freecam] right mouse released; prior mouse behavior restored")
			end
		end)
		freecamDebugDeltaLogged = false
		print("[Freecam] started; Roblox sensitivity properties are not written")
		freecamRenderConn = RunService.RenderStepped:Connect(function(dt)
			local currentCamera = workspace.CurrentCamera
			if not currentCamera then return end
			if freecamRotating then
				local mouseDelta = UserInputService:GetMouseDelta()
				if mouseDelta.Magnitude > 0 then
					if not freecamDebugDeltaLogged then
						freecamDebugDeltaLogged = true
						print("[Freecam] mouse delta received:", mouseDelta)
					end
					-- Match Roblox's default camera rotation rate and vertical scaling.
					local lookScale = Vector2.new(math.rad(0.5), math.rad(0.5) * 0.77)
					freecamYaw -= mouseDelta.X * lookScale.X
					freecamPitch = math.clamp(freecamPitch - mouseDelta.Y * lookScale.Y, -math.pi / 2 + 0.01, math.pi / 2 - 0.01)
				end
			end
			local rotation = CFrame.fromOrientation(freecamPitch, freecamYaw, 0)
			local planarMove = Vector3.zero
			if freecamKeys[Enum.KeyCode.W] then planarMove += Vector3.new(0, 0, -1) end
			if freecamKeys[Enum.KeyCode.S] then planarMove += Vector3.new(0, 0, 1) end
			if freecamKeys[Enum.KeyCode.A] then planarMove += Vector3.new(-1, 0, 0) end
			if freecamKeys[Enum.KeyCode.D] then planarMove += Vector3.new(1, 0, 0) end
			local verticalMove = 0
			if freecamKeys[Enum.KeyCode.Space] then verticalMove += 1 end
			if freecamKeys[Enum.KeyCode.LeftControl] or freecamKeys[Enum.KeyCode.RightControl] then
				verticalMove -= 1
			end
			local move = CFrame.fromOrientation(0, freecamYaw, 0):VectorToWorldSpace(planarMove)
			move += Vector3.new(0, verticalMove, 0)
			if move.Magnitude > 0 then
				local speed = (freecamKeys[Enum.KeyCode.LeftShift] or freecamKeys[Enum.KeyCode.RightShift]) and freecamSpeed * 3 or freecamSpeed
				freecamPosition += move.Unit * speed * dt
			end
			currentCamera.CFrame = CFrame.new(freecamPosition) * rotation
		end)
	end

	local freecamCard = Instance.new("Frame")
	freecamCard.Size = UDim2.new(1, -8, 0, 144)
	freecamCard.Position = UDim2.new(0, 0, 0, 140)
	freecamCard.BackgroundColor3 = THEME.Card
	freecamCard.BorderSizePixel = 0
	freecamCard.Parent = movePage
	round(freecamCard, 10)

	local freecamLabel = Instance.new("TextLabel")
	freecamLabel.Size = UDim2.new(1, -90, 0, 24)
	freecamLabel.Position = UDim2.new(0, 12, 0, 10)
	freecamLabel.BackgroundTransparency = 1
	freecamLabel.Text = "Freecam"
	freecamLabel.TextColor3 = THEME.Text
	freecamLabel.Font = Enum.Font.GothamMedium
	freecamLabel.TextSize = 15
	freecamLabel.TextXAlignment = Enum.TextXAlignment.Left
	freecamLabel.Parent = freecamCard

	local freecamHint = Instance.new("TextLabel")
	freecamHint.Size = UDim2.new(1, -24, 0, 18)
	freecamHint.Position = UDim2.new(0, 12, 1, -22)
	freecamHint.BackgroundTransparency = 1
	freecamHint.Text = "WASD move • hold right mouse to look • Space/Ctrl up/down • Shift faster"
	freecamHint.TextColor3 = THEME.SubText
	freecamHint.Font = Enum.Font.Gotham
	freecamHint.TextSize = 11
	freecamHint.TextXAlignment = Enum.TextXAlignment.Left
	freecamHint.TextWrapped = true
	freecamHint.Parent = freecamCard

	local setFreecam = makeSwitch(freecamCard, UDim2.new(1, -58, 0, 10), function(on)
		Settings.freecam = on
		saveSettings()
		if on then
			startFreecam()
		else
			stopFreecam()
		end
	end)

	local speedLabel = Instance.new("TextLabel")
	speedLabel.Size = UDim2.new(0, 48, 0, 26)
	speedLabel.Position = UDim2.new(0, 12, 0, 42)
	speedLabel.BackgroundTransparency = 1
	speedLabel.Text = "Speed"
	speedLabel.TextColor3 = THEME.SubText
	speedLabel.Font = Enum.Font.Gotham
	speedLabel.TextSize = 13
	speedLabel.TextXAlignment = Enum.TextXAlignment.Left
	speedLabel.Parent = freecamCard

	local speedBox = makeTextBox(freecamCard, tostring(freecamSpeed), UDim2.new(0, 72, 0, 28), UDim2.new(0, 66, 0, 40))
	speedBox.PlaceholderText = "1–500"
	speedBox.FocusLost:Connect(function()
		local entered = tonumber(speedBox.Text)
		if entered then
			freecamSpeed = math.clamp(math.floor(entered), 1, 500)
			Settings.freecamSpeed = tostring(freecamSpeed)
			saveSettings()
		end
		speedBox.Text = tostring(freecamSpeed)
	end)

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Size = UDim2.new(0, 74, 0, 26)
	keyLabel.Position = UDim2.new(0, 12, 0, 78)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Text = "Toggle key"
	keyLabel.TextColor3 = THEME.SubText
	keyLabel.Font = Enum.Font.Gotham
	keyLabel.TextSize = 13
	keyLabel.TextXAlignment = Enum.TextXAlignment.Left
	keyLabel.Parent = freecamCard

	local keyButton = makeButton(freecamCard, freecamToggleKey and freecamToggleKey.Name or "None", UDim2.new(0, 90, 0, 28), UDim2.new(0, 90, 0, 76))
	keyButton.MouseButton1Click:Connect(function()
		waitingForFreecamKey = true
		keyButton.Text = "Press key"
	end)

	if Settings.freecam then setFreecam(true) end

	local toggleKeyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if waitingForFreecamKey then
			waitingForFreecamKey = false
			if input.KeyCode == Enum.KeyCode.Escape then
				freecamToggleKey = nil
				Settings.freecamToggleKey = ""
				saveSettings()
				keyButton.Text = "None"
			else
				freecamToggleKey = input.KeyCode
				Settings.freecamToggleKey = input.KeyCode.Name
				saveSettings()
				keyButton.Text = input.KeyCode.Name
			end
			return
		end
		if not gameProcessed and input.KeyCode == freecamToggleKey then
			setFreecam(not freecamActive)
		end
	end)

	gui.Destroying:Connect(function()
		stopFreecam()
		toggleKeyConn:Disconnect()
	end)
end

do
	local moverStatus -- assigned when the card is built below
	local moverTool = nil
	local dragTarget = nil
	local previewModel = nil
	local dragHighlight = nil
	local moverDragConn = nil
	local moverMenu = nil
	local destinationButton = nil
	local destinationList = nil
	local selectedDestination = nil
	local waypointPosition = nil

	local hoverConn = nil
	local hoverHighlight = nil
	local hoverShown = nil -- model/part currently outlined
	local lastRayTarget = nil
	local lastRayOk = false

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local DEFAULT_TEXT = "Equip the tool, select an item, choose a destination, then teleport it."

	-- Center + world-aligned size for a model or a single part
	local function getBounds(obj)
		if obj:IsA("Model") then
			return worldBounds(obj)
		end

		local cf, s = obj.CFrame, obj.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local size = Vector3.new(
			math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
			math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
			math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
		)
		return cf.Position, size
	end

	-- Selectable only if nothing in the selected model is anchored.
	local function isUnanchored(obj)
		if obj:IsA("BasePart") and obj.Anchored then
			return false
		end
		for _, descendant in ipairs(obj:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Anchored then
				return false
			end
		end
		return true
	end

	-- What's under the cursor: the outermost Model it belongs to, or the lone part.
	-- (Doesn't check anchoring; use isUnanchored for that.)
	local function findTarget()
		local camera = workspace.CurrentCamera
		if not camera then
			return nil
		end

		rayParams.FilterDescendantsInstances = {character}

		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
		if not (result and result.Instance) then
			return nil
		end

		local target = result.Instance
		local outermostModel
		local secondOutermostModel
		local cur = result.Instance
		while cur and cur ~= workspace do
			if cur:IsA("Model") then
				secondOutermostModel = outermostModel
				outermostModel = cur
			end
			cur = cur.Parent
		end
		if outermostModel then
			target = outermostModel.Name == "ShopItems" and secondOutermostModel or outermostModel
		end

		-- never grab other players
		local model = target:IsA("Model") and target or target:FindFirstAncestorOfClass("Model")
		if model and Players:GetPlayerFromCharacter(model) then
			return nil
		end

		return target
	end

	local function pointerOverAnyGui()
		local mouse = UserInputService:GetMouseLocation()
		local found = {}
		local function collect(container)
			if not container then return end
			local ok, objects = pcall(function()
				return container:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
			end)
			if ok and objects then
				for _, object in ipairs(objects) do
					table.insert(found, object)
				end
			end
		end
		collect(executorGui)
		collect(player:FindFirstChildOfClass("PlayerGui"))
		collect(game:GetService("CoreGui"))
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
		for _, object in ipairs(found) do
			if object:IsDescendantOf(gui) or object:IsA("GuiButton") or object:IsA("TextBox") then
				return true
			end
			-- Ignore passive full-screen HUD layers; they often span the world view
			-- without receiving the click. Small active panels still block selection.
			if object.Active
				and object.AbsoluteSize.X < viewport.X * 0.9
				and object.AbsoluteSize.Y < viewport.Y * 0.9 then
				return true
			end
		end
		return false
	end

	local function mouseOverOwnGui()
		return pointerOverAnyGui()
	end

	-- Hover outline ---------------------------------------------------

	local function setHover(target)
		if target == hoverShown then
			return
		end
		hoverShown = target
		if hoverHighlight then
			hoverHighlight.Adornee = target
		end
	end

	local function stopHover()
		if hoverConn then
			hoverConn:Disconnect()
			hoverConn = nil
		end
		if hoverHighlight then
			hoverHighlight:Destroy()
			hoverHighlight = nil
		end
		hoverShown = nil
		lastRayTarget = nil
		lastRayOk = false
	end

	local function startHover()
		stopHover()

		hoverHighlight = Instance.new("Highlight")
		hoverHighlight.FillTransparency = 1 -- outline only
		hoverHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		hoverHighlight.OutlineTransparency = 0
		hoverHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hoverHighlight.Parent = gui

		hoverConn = RunService.RenderStepped:Connect(function()
			if dragTarget or mouseOverOwnGui() then
				setHover(nil)
				return
			end

			local target = findTarget()
			if target ~= lastRayTarget then
				-- only re-check anchoring when the thing under the cursor changes
				lastRayTarget = target
				lastRayOk = target ~= nil and isUnanchored(target)
			end

			setHover(lastRayOk and target or nil)
		end)
	end

	-- Ghost preview movement --------------------------------------------

	local function clearPreview()
		if moverDragConn then
			moverDragConn:Disconnect()
			moverDragConn = nil
		end
		if dragHighlight then
			dragHighlight:Destroy()
			dragHighlight = nil
		end
		if dragTarget and dragTarget.Parent then
			lastRayTarget = nil -- re-check what's under the cursor now
			setHover(nil)
		end
		if previewModel then
			previewModel:Destroy()
			previewModel = nil
		end
		dragTarget = nil
		if moverMenu then moverMenu.Visible = moverEquipped end
		moverStatus.Text = DEFAULT_TEXT
	end

	local function cancelMove()
		clearPreview()
	end

	local function commitMove(destinationPivot)
		if not dragTarget or not dragTarget.Parent or not destinationPivot then
			clearPreview()
			return
		end

		local item = dragTarget
		local finalPivot = destinationPivot
		local currentPivot = item:GetPivot()
		local transform = finalPivot * currentPivot:Inverse()
		local rootPart = item:IsA("BasePart") and item or item.PrimaryPart
		if not rootPart then
			rootPart = item:FindFirstChildWhichIsA("BasePart", true)
		end
		if not rootPart or rootPart.Anchored then
			moverStatus.Text = "Can't move this item with the game's drag system."
			clearPreview()
			return
		end
		local desiredRootCFrame = transform * rootPart.CFrame
		local originalRotation = rootPart.CFrame - rootPart.CFrame.Position

		local interaction = ReplicatedStorage:FindFirstChild("Interaction")
		local draggingRemote = interaction and interaction:FindFirstChild("ClientIsDragging")
		local util = ReplicatedStorage:FindFirstChild("Util")
		local getItemModule = util and util:FindFirstChild("GetItem")
		if not (draggingRemote and draggingRemote:IsA("RemoteEvent")) then
			moverStatus.Text = "Game drag remote not found; move wasn't applied."
			clearPreview()
			return
		end

		local gameItem = item
		if getItemModule and getItemModule:IsA("ModuleScript") then
			local ok, getItem = pcall(require, getItemModule)
			if ok and type(getItem) == "function" then
				local itemOk, resolved = pcall(getItem, rootPart)
				if itemOk and resolved then
					gameItem = resolved
				end
			end
		end

		local dragger = Instance.new("Part")
		dragger.Name = "MoveToolDragger"
		dragger.Size = Vector3.new(0.2, 0.2, 0.2)
		dragger.Transparency = 1
		dragger.Anchored = false
		dragger.CanCollide = false
		dragger.CanTouch = false
		dragger.CanQuery = false
		dragger.CFrame = rootPart.CFrame
		dragger.Parent = workspace

		local bodyPosition = Instance.new("BodyPosition")
		bodyPosition.MaxForce = Vector3.new(1700000, 1700000, 1700000)
		bodyPosition.D = 800
		bodyPosition.Position = rootPart.Position
		bodyPosition.Parent = dragger

		local bodyGyro = Instance.new("BodyGyro")
		bodyGyro.MaxTorque = Vector3.new(200, 200, 200)
		bodyGyro.P = 1200
		bodyGyro.D = 140
		bodyGyro.CFrame = rootPart.CFrame
		bodyGyro.Parent = dragger

		local welds = {}
		local itemParts = item:IsA("BasePart") and {item} or item:GetDescendants()

		for _, part in ipairs(itemParts) do
			if part:IsA("BasePart") then
				local weld = Instance.new("Weld")
				weld.Part0 = dragger
				weld.Part1 = part
				weld.C0 = dragger.CFrame:ToObjectSpace(part.CFrame)
				weld.Parent = dragger
				table.insert(welds, weld)
			end
		end

		clearPreview()
		moverStatus.Text = "Starting game drag, then teleporting item..."

		-- Register the grabbed item before moving the welded assembly, matching
		-- the game's drag flow and giving its physics ownership a moment to update.
		local remoteOk = pcall(function()
			draggingRemote:FireServer(gameItem)
		end)
		if not remoteOk then
			for _, weld in ipairs(welds) do
				if weld.Parent then weld:Destroy() end
			end
			dragger:Destroy()
			moverStatus.Text = "The game rejected the drag request."
			return
		end
		task.wait(0.1)
		if not rootPart.Parent or not dragger.Parent then
			if dragger.Parent then dragger:Destroy() end
			return
		end

		-- Snap through the welded dragger, then keep the physics constraints and
		-- game drag notification active briefly to settle the replicated assembly.
		dragger.CFrame = desiredRootCFrame
		bodyPosition.Position = desiredRootCFrame.Position
		bodyGyro.CFrame = CFrame.new(desiredRootCFrame.Position) * originalRotation

		local startedAt = os.clock()
		local lastNotify = 0
		while rootPart.Parent and os.clock() - startedAt < 0.2 do
			local now = os.clock()
			if now - lastNotify >= 0.1 then
				pcall(function()
					draggingRemote:FireServer(gameItem)
				end)
				lastNotify = now
			end
			RunService.Heartbeat:Wait()
		end

		for _, weld in ipairs(welds) do
    		if weld.Parent then
        		weld:Destroy()
    		end
		end
		bodyPosition:Destroy()
		bodyGyro:Destroy()
		dragger:Destroy()
		zeroVelocity(item)
		moverStatus.Text = "Move finished."
	end

	local function startDragging(target)
		local clone = target:Clone()
		if not clone then
			moverStatus.Text = "Couldn't create a preview for " .. target.Name .. "."
			return
		end

		if clone:IsA("BasePart") then
			local wrapper = Instance.new("Model")
			clone.Parent = wrapper
			wrapper.PrimaryPart = clone
			clone = wrapper
		end

		clone.Name = "MoveToolPreview"
		stylePreview(clone)
		clone:PivotTo(target:GetPivot())
		clone.Parent = workspace

		dragTarget = target
		previewModel = clone
		setHover(nil)

		local previewHighlight = Instance.new("Highlight")
		previewHighlight.FillTransparency = 0.75
		previewHighlight.FillColor = THEME.Accent
		previewHighlight.OutlineColor = THEME.Accent
		previewHighlight.Adornee = clone
		previewHighlight.Parent = gui
		dragHighlight = previewHighlight

		moverStatus.Text = "Selected " .. target.Name .. ". Choose a destination in the Move Tool menu."
		if moverMenu then moverMenu.Visible = true end

		-- Keep the original mouse placement workflow available alongside the
		-- destination menu: the selected item's preview follows the cursor, and
		-- clicking the world commits it at that spot.
		moverDragConn = RunService.RenderStepped:Connect(function()
			if not dragTarget or not dragTarget.Parent or not previewModel or not previewModel.Parent then
				cancelMove()
				return
			end
			local camera = workspace.CurrentCamera
			if not camera then return end
			rayParams.FilterDescendantsInstances = {character, dragTarget, previewModel}
			local mouse = UserInputService:GetMouseLocation()
			local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
			local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
			if not result then return end
			local pivot = previewModel:GetPivot()
			local center, size = getBounds(previewModel)
			local offset = pivot.Position - center
			local hit = result.Position
			local newCenter = Vector3.new(hit.X, hit.Y + size.Y / 2, hit.Z)
			previewModel:PivotTo(CFrame.new(newCenter + offset) * (pivot - pivot.Position))
		end)
	end

	local function setDestinationOptions()
		if not destinationList then return end
		for _, child in ipairs(destinationList:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		local options = {}
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			table.insert(options, {label = "Player: " .. otherPlayer.Name, kind = "player", target = otherPlayer})
		end
		local properties = workspace:FindFirstChild("Properties")
		if properties then
			for _, property in ipairs(properties:GetChildren()) do
				if property:IsA("Model") then
					local owner = property:FindFirstChild("Owner")
					local ownerName = "Unowned"
					if owner and owner:IsA("ObjectValue") and owner.Value then
						ownerName = owner.Value.Name
					elseif owner and owner:IsA("StringValue") and owner.Value ~= "" then
						ownerName = owner.Value
					end
					table.insert(options, {label = "Property: " .. property.Name .. " (" .. ownerName .. ")", kind = "property", target = property})
				end
			end
		end
		table.insert(options, {label = "Custom waypoint", kind = "waypoint"})
		destinationList.CanvasSize = UDim2.new(0, 0, 0, #options * 30)
		for index, option in ipairs(options) do
			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, -6, 0, 27)
			button.Position = UDim2.new(0, 3, 0, (index - 1) * 30)
			button.BackgroundColor3 = THEME.Button
			button.BorderSizePixel = 0
			button.Text = option.label
			button.TextColor3 = THEME.Text
			button.Font = Enum.Font.Gotham
			button.TextSize = 12
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.ZIndex = 36
			button.Parent = destinationList
			round(button, 5)
			button.MouseButton1Click:Connect(function()
				selectedDestination = option
				destinationButton.Text = option.label
				destinationList.Visible = false
			end)
		end
	end

	local function buildMoveMenu()
		moverMenu = Instance.new("Frame")
		moverMenu.Name = "MoveToolDestinationMenu"
		moverMenu.Size = UDim2.new(0, 330, 0, 290)
		moverMenu.Position = UDim2.new(1, -350, 0.5, -145)
		moverMenu.BackgroundColor3 = THEME.Card
		moverMenu.BorderSizePixel = 0
		moverMenu.Visible = false
		moverMenu.ZIndex = 30
		moverMenu.Parent = gui
		round(moverMenu, 10)

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -24, 0, 26)
		title.Position = UDim2.new(0, 12, 0, 9)
		title.BackgroundTransparency = 1
		title.Text = "Teleport selected item"
		title.TextColor3 = THEME.Text
		title.Font = Enum.Font.GothamMedium
		title.TextSize = 15
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.ZIndex = 31
		title.Parent = moverMenu

		destinationButton = Instance.new("TextButton")
		destinationButton.Size = UDim2.new(1, -24, 0, 34)
		destinationButton.Position = UDim2.new(0, 12, 0, 43)
		destinationButton.BackgroundColor3 = THEME.Button
		destinationButton.BorderSizePixel = 0
		destinationButton.Text = "Select destination"
		destinationButton.TextColor3 = THEME.Text
		destinationButton.Font = Enum.Font.Gotham
		destinationButton.TextSize = 12
		destinationButton.ZIndex = 31
		destinationButton.Parent = moverMenu
		round(destinationButton, 6)

		destinationList = Instance.new("ScrollingFrame")
		destinationList.Size = UDim2.new(1, -24, 0, 125)
		destinationList.Position = UDim2.new(0, 12, 0, 81)
		destinationList.BackgroundColor3 = THEME.Background
		destinationList.BorderSizePixel = 0
		destinationList.ScrollBarThickness = 5
		destinationList.Visible = false
		destinationList.ZIndex = 35
		destinationList.Parent = moverMenu
		round(destinationList, 6)
		destinationButton.MouseButton1Click:Connect(function()
			setDestinationOptions()
			destinationList.Visible = not destinationList.Visible
		end)

		local waypointButton = Instance.new("TextButton")
		waypointButton.Size = UDim2.new(0, 145, 0, 32)
		waypointButton.Position = UDim2.new(0, 12, 1, -44)
		waypointButton.BackgroundColor3 = THEME.Button
		waypointButton.BorderSizePixel = 0
		waypointButton.Text = "Set waypoint"
		waypointButton.TextColor3 = THEME.Text
		waypointButton.Font = Enum.Font.Gotham
		waypointButton.TextSize = 12
		waypointButton.ZIndex = 31
		waypointButton.Parent = moverMenu
		round(waypointButton, 6)
		waypointButton.MouseButton1Click:Connect(function()
			waypointPosition = hrp.Position
			selectedDestination = {label = "Custom waypoint", kind = "waypoint"}
			destinationButton.Text = "Custom waypoint"
			moverStatus.Text = "Waypoint set. Choose Teleport to move the selected item there."
		end)

		local teleportButton = Instance.new("TextButton")
		teleportButton.Size = UDim2.new(0, 145, 0, 32)
		teleportButton.Position = UDim2.new(1, -157, 1, -44)
		teleportButton.BackgroundColor3 = THEME.Accent
		teleportButton.BorderSizePixel = 0
		teleportButton.Text = "Teleport"
		teleportButton.TextColor3 = THEME.Text
		teleportButton.Font = Enum.Font.GothamBold
		teleportButton.TextSize = 12
		teleportButton.ZIndex = 31
		teleportButton.Parent = moverMenu
		round(teleportButton, 6)
		teleportButton.MouseButton1Click:Connect(function()
			if not dragTarget or not dragTarget.Parent then
				moverStatus.Text = "Select an item first."
				return
			end
			if not selectedDestination then
				moverStatus.Text = "Select a destination first."
				return
			end
			local option = selectedDestination
			local point
			if option.kind == "player" then
				local char = option.target and option.target.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if not root then moverStatus.Text = "That player has no character right now." return end
				point = root.Position + Vector3.new(0, 5, 0)
			elseif option.kind == "property" then
				local square = option.target and option.target:FindFirstChild("OriginSquare", true)
				if not square or not square:IsA("BasePart") then moverStatus.Text = "That property has no OriginSquare." return end
				point = square.Position + Vector3.new(0, square.Size.Y / 2, 0)
			else
				if not waypointPosition then moverStatus.Text = "Set the custom waypoint first." return end
				point = waypointPosition
			end
			local _, size = getBounds(dragTarget)
			local current = dragTarget:GetPivot()
			local destination = CFrame.new(point + Vector3.new(0, size.Y / 2 + 0.2, 0)) * (current - current.Position)
			moverMenu.Visible = false
			commitMove(destination)
		end)

		setDestinationOptions()
	end

	-- The tool ----------------------------------------------------------

	local function createMoverTool()
		cancelMove()
		stopHover()
		if not moverMenu then buildMoveMenu() end
		if moverTool then
			moverTool:Destroy()
			moverTool = nil
			moverEquipped = false
		end

		local tool = Instance.new("Tool")
		tool.Name = "Move Tool"
		tool.RequiresHandle = false
		tool.CanBeDropped = false
		tool.ToolTip = "Click an item, choose a destination, then press Teleport"

		tool.Equipped:Connect(function()
			moverEquipped = true
			if moverMenu then moverMenu.Visible = true end
			startHover()
		end)

		tool.Unequipped:Connect(function()
			moverEquipped = false
			cancelMove()
			stopHover()
		end)

		tool.Destroying:Connect(function()
			moverEquipped = false
			cancelMove()
			stopHover()
		end)

		tool.Activated:Connect(function()
			if pointerOverAnyGui() then return end
			if dragTarget then
				if previewModel then
					commitMove(previewModel:GetPivot())
				end
				return
			end

			local target = findTarget()
			if not target then
				moverStatus.Text = "Nothing there to grab."
			elseif not isUnanchored(target) then
				moverStatus.Text = "Can't grab " .. target.Name .. " - it's anchored."
			else
				startDragging(target)
			end
		end)

		tool.Parent = player:WaitForChild("Backpack")
		moverTool = tool
	end

	-- UI card
	local mvCard = Instance.new("Frame")
	mvCard.Size = UDim2.new(1, -8, 0, 96)
	mvCard.Position = UDim2.new(0, 0, 0, 294)
	mvCard.BackgroundColor3 = THEME.Card
	mvCard.BorderSizePixel = 0
	mvCard.Parent = movePage
	round(mvCard, 10)

	local mvLabel = Instance.new("TextLabel")
	mvLabel.Size = UDim2.new(1, -24, 0, 24)
	mvLabel.Position = UDim2.new(0, 12, 0, 10)
	mvLabel.BackgroundTransparency = 1
	mvLabel.Text = "Move Tool"
	mvLabel.TextColor3 = THEME.Text
	mvLabel.Font = Enum.Font.GothamMedium
	mvLabel.TextSize = 15
	mvLabel.TextXAlignment = Enum.TextXAlignment.Left
	mvLabel.Parent = mvCard

	local mvButton = makeButton(mvCard, "Get Move Tool", UDim2.new(0, 130, 0, 28), UDim2.new(0, 12, 0, 40))
	mvButton.MouseButton1Click:Connect(createMoverTool)

	moverStatus = Instance.new("TextLabel")
	moverStatus.Size = UDim2.new(1, -24, 0, 16)
	moverStatus.Position = UDim2.new(0, 12, 1, -20)
	moverStatus.BackgroundTransparency = 1
	moverStatus.Text = DEFAULT_TEXT
	moverStatus.TextColor3 = THEME.SubText
	moverStatus.Font = Enum.Font.Gotham
	moverStatus.TextSize = 11
	moverStatus.TextXAlignment = Enum.TextXAlignment.Left
	moverStatus.Parent = mvCard

	gui.Destroying:Connect(function()
		cancelMove()
		stopHover()
		if moverTool then
			moverTool:Destroy()
		end
		moverEquipped = false
	end)
end

-------------------------------------------------
-- Window controls
-------------------------------------------------

selectTab("Info")

close.MouseButton1Click:Connect(function()
	fastTrucksOn = false -- direct variable, so the saved setting stays as you left it
	restoreOriginals()
	gui:Destroy()
end)

local minimized = false

minimize.MouseButton1Click:Connect(function()
	minimized = not minimized
	body.Visible = not minimized
	frame.Size = minimized and MIN_SIZE or FULL_SIZE
	minimize.Text = minimized and "+" or "–"
end)

-------------------------------------------------
-- Dragging (mouse + touch)
-------------------------------------------------

local dragging = false
local dragInput
local dragStart
local startPos

titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

titleBar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input == dragInput then
		local delta = input.Position - dragStart

		frame.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end)
