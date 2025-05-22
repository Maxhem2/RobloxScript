local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TeleportService")
local Player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")

Player:WaitForChild("PlayerGui")
local char = Player.Character or Player.CharacterAdded:Wait()

-- Check for existing GUI - if found, exit immediately
if Player.PlayerGui:FindFirstChild("FarmingGUI") then
    return
end

-- Core state variables
local state = {
    running = false,
    stopping = false,
    busy = false,
    clickDebounce = false,
    scriptActive = true,
    autoHatchEnabled = false,
    autoHatchRunning = false,
    lockedEggId = nil,
    lockedEggModel = nil,
    currentSelection = nil,
    autoRejoinEnabled = false,
    rewardsCheckRunning = false,
    farmHeight = 0,
    autoFarmActive = false,
    -- Just use savedPosition for all coordinates (including height)
    savedPosition = nil
}

-- Settings management
local function saveSettings()
    local settings = {}
    if state.autoHatchEnabled and state.lockedEggId then settings.lockedEggId = state.lockedEggId end
    if state.farmHeight > 0 then settings.farmHeight = state.farmHeight end
    if state.autoFarmActive then settings.autoFarmActive = true end
    if state.autoRejoinEnabled then settings.autoRejoinEnabled = true end
    
    -- Save position if auto rejoin is enabled
    if state.autoRejoinEnabled and state.savedPosition then
        settings.savedPosition = {
            X = state.savedPosition.X,
            Y = state.savedPosition.Y,
            Z = state.savedPosition.Z
        }
    end

    if next(settings) then
        local settingsJson = HttpService:JSONEncode(settings)
        pcall(function() writefile("egg_farm_settings.json", settingsJson) end)
    else
        pcall(function() 
            if isfile("egg_farm_settings.json") then 
                delfile("egg_farm_settings.json") 
            end 
        end)
    end
end

local function loadSettings()
    local success, content = pcall(function() return readfile("egg_farm_settings.json") end)
    
    if success and content then
        local settings = HttpService:JSONDecode(content)
        if settings then
            state.lockedEggId = settings.lockedEggId or nil
            state.autoHatchEnabled = (state.lockedEggId ~= nil)
            state.autoRejoinEnabled = settings.autoRejoinEnabled or false
            state.farmHeight = (settings.farmHeight and settings.farmHeight > 0) and settings.farmHeight or 0
            state.autoFarmActive = settings.autoFarmActive or false
            
            -- Load saved position
            if settings.savedPosition then
                state.savedPosition = Vector3.new(
                    settings.savedPosition.X,
                    settings.savedPosition.Y,
                    settings.savedPosition.Z
                )
                
                -- Teleport player to saved position if found
                task.spawn(function()
                    local character = Player.Character or Player.CharacterAdded:Wait()
                    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
                    
                    if humanoidRootPart and state.savedPosition then
                        -- Teleport the character
                        if character.PrimaryPart then
                            local currentCFrame = character:GetPrimaryPartCFrame()
                            local newCFrame = CFrame.new(state.savedPosition) * CFrame.Angles(
                                currentCFrame:ToEulerAnglesXYZ()
                            )
                            character:SetPrimaryPartCFrame(newCFrame)
                        end
                    end
                end)
            end
        end
    end
end

loadSettings()

-- Create UI helper functions
local function createInstance(className, properties, parent)
    local instance = Instance.new(className)
    for propName, propValue in pairs(properties) do
        instance[propName] = propValue
    end
    if parent then instance.Parent = parent end
    return instance
end

local function applyCorner(instance, radius)
    local corner = createInstance("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, instance)
    return corner
end

-- Create GUI
local gui = createInstance("ScreenGui", {
    Name = "FarmingGUI",
    IgnoreGuiInset = true,
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 100,
    Parent = Player.PlayerGui
})

local frame = createInstance("Frame", {
    Name = "MainFrame",
    Size = UDim2.new(0, 200, 0, 180),
    Position = UDim2.new(0.5, -100, 0.5, -90),
    BackgroundColor3 = Color3.fromRGB(40, 40, 40),
    BorderSizePixel = 0,
    Active = true,
    Parent = gui
})

-- Add corner and stroke
applyCorner(frame)
createInstance("UIStroke", {
    Color = Color3.fromRGB(100, 100, 100),
    Thickness = 2,
    Parent = frame
})

-- Dragging functionality
local dragging, dragInput, dragStart, startPos
local function updateDrag(input)
    local delta = input.Position - dragStart
    frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end

frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)

frame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UIS.InputChanged:Connect(function(input)
    if input == dragInput and dragging then updateDrag(input) end
end)

-- Title bar
local title = createInstance("TextLabel", {
    Name = "TitleLabel",
    Size = UDim2.new(1, 0, 0, 30),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundColor3 = Color3.fromRGB(60, 60, 60),
    BorderSizePixel = 0,
    Text = "Auto Farm",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.SourceSansBold,
    TextSize = 16,
    Parent = frame
})

applyCorner(title)

-- Close button
local closeBtn = createInstance("TextButton", {
    Name = "CloseButton",
    Size = UDim2.new(0, 25, 0, 25),
    Position = UDim2.new(1, -30, 0, 2),
    BackgroundColor3 = Color3.fromRGB(200, 50, 50),
    Text = "X",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.SourceSansBold,
    TextSize = 14,
    Parent = title
})

applyCorner(closeBtn, 4)

-- Height input
local heightLabel = createInstance("TextLabel", {
    Name = "HeightLabel",
    Size = UDim2.new(0.4, 0, 0, 20),
    Position = UDim2.new(0.03, 0, 0, 35),
    BackgroundTransparency = 1,
    Text = "Height:",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.SourceSans,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = frame
})

local heightInput = createInstance("TextBox", {
    Name = "HeightInput",
    Size = UDim2.new(0.53, 0, 0, 20),
    Position = UDim2.new(0.44, 0, 0, 35),
    BackgroundColor3 = Color3.fromRGB(60, 60, 60),
    BorderSizePixel = 0,
    Text = tostring(state.farmHeight > 0 and state.farmHeight or 100),
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.SourceSans,
    TextSize = 14,
    ClearTextOnFocus = false,
    Parent = frame
})

applyCorner(heightInput, 4)

-- Create button helper function
local function createButton(name, text, size, position, color, parent)
    local btn = createInstance("TextButton", {
        Name = name,
        Size = size,
        Position = position,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 16,
        Parent = parent
    })
    applyCorner(btn, 6)
    return btn
end

-- Farm control buttons
local startBtn = createButton("StartButton", "Start", UDim2.new(0.45, 0, 0, 35), 
                             UDim2.new(0.03, 0, 0, 60), Color3.fromRGB(0, 180, 0), frame)

local stopBtn = createButton("StopButton", "Stop", UDim2.new(0.45, 0, 0, 35), 
                            UDim2.new(0.52, 0, 0, 60), Color3.fromRGB(180, 0, 0), frame)

-- Feature buttons
local hatchBtn = createButton("HatchButton", "Auto Hatch: OFF", UDim2.new(0.94, 0, 0, 35), 
                             UDim2.new(0.03, 0, 0, 100), Color3.fromRGB(80, 80, 80), frame)
hatchBtn.TextSize = 14

local rejoinBtn = createButton("RejoinButton", "Auto Rejoin: OFF", UDim2.new(0.94, 0, 0, 35), 
                              UDim2.new(0.03, 0, 0, 140), Color3.fromRGB(80, 80, 80), frame)
rejoinBtn.TextSize = 14

-- Time until rejoin display
local timeUntilRejoinLabel = createInstance("TextLabel", {
    Name = "TimeUntilRejoinLabel",
    Size = UDim2.new(1, -20, 0, 15),
    Position = UDim2.new(0, 10, 1, -25),
    BackgroundTransparency = 1,
    Text = "Rejoin in: Calculating...",
    TextColor3 = Color3.fromRGB(180, 180, 180),
    Font = Enum.Font.SourceSans,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = frame
})

-- Helper function to format time
local function formatTime(seconds)
    if seconds <= 0 then
        return "Ready!"
    end
    
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    
    if hours > 0 then
        return string.format("%02d:%02d:%02d", hours, minutes, secs)
    else
        return string.format("%02d:%02d", minutes, secs)
    end
end

-- Update UI elements
local function updateButtonStates()
    -- Start button
    local startDisabled = state.running or state.busy
    startBtn.BackgroundTransparency = startDisabled and 0.7 or 0
    startBtn.TextTransparency = startDisabled and 0.5 or 0
    startBtn.AutoButtonColor = not startDisabled
    startBtn.BackgroundColor3 = startDisabled and Color3.fromRGB(100, 100, 100) or Color3.fromRGB(0, 180, 0)

    -- Stop button
    local stopDisabled = not state.running or state.busy or state.stopping
    stopBtn.BackgroundTransparency = stopDisabled and 0.7 or 0
    stopBtn.TextTransparency = stopDisabled and 0.5 or 0
    stopBtn.AutoButtonColor = not stopDisabled
    stopBtn.BackgroundColor3 = stopDisabled and Color3.fromRGB(100, 100, 100) or Color3.fromRGB(180, 0, 0)

    -- Close button
    closeBtn.BackgroundTransparency = state.busy and 0.7 or 0
    closeBtn.TextTransparency = state.busy and 0.5 or 0
    closeBtn.AutoButtonColor = not state.busy

    -- Feature buttons
    hatchBtn.BackgroundColor3 = state.autoHatchEnabled and Color3.fromRGB(0, 150, 0) or Color3.fromRGB(80, 80, 80)
    hatchBtn.Text = state.autoHatchEnabled and "Auto Hatch: ON" or "Auto Hatch: OFF"
    
    rejoinBtn.BackgroundColor3 = state.autoRejoinEnabled and Color3.fromRGB(0, 150, 0) or Color3.fromRGB(80, 80, 80)
    rejoinBtn.Text = state.autoRejoinEnabled and "Auto Rejoin: ON" or "Auto Rejoin: OFF"
end

-- Get online rewards data
local function getOnlineRewardsData()
    local CfgFind = require(RS.Tool.CfgFind)
    local onlineRewardsConf = CfgFind.GetCfgByName("onlinerewardsConf")
    local onlineTimeObj = Player:FindFirstChild("OnlineTime")
    
    if not onlineTimeObj or not onlineRewardsConf then
        return nil, nil, nil
    end
    
    local onlineTime = onlineTimeObj.Value
    
    -- Keep trying to get player data until it exists
    local playerData = nil
    
    -- Keep checking in a loop until we find the data
    while not playerData and state.scriptActive do
        for _, v in pairs(getgc(true)) do
            if type(v) == "table" and v.OnlineAward ~= nil then
                playerData = v
                break
            end
        end
        
        if playerData then
            break
        end
        
        -- Wait a short time before trying again
        task.wait(0.5)
    end
    
    -- If script is no longer active, return nil
    if not state.scriptActive then
        return nil, nil, nil
    end
    
    return onlineRewardsConf, onlineTime, playerData
end

-- Rewards check functionality
local function checkOnlineRewards()
    local onlineRewardsConf, onlineTime, playerData = getOnlineRewardsData()
    
    if not onlineRewardsConf or not onlineTime or not playerData then
        return 0, 0, false, 0
    end
    
    -- Count ready and claimed rewards
    local claimedCount = 0
    local readyCount = 0
    local allReady = false
    local totalRewards = 0
    local timeUntilTargetReward = 0
    
    -- Find the last reward index
    local lastIndex = 0
    for index, _ in pairs(onlineRewardsConf) do
        if index > lastIndex then
            lastIndex = index
        end
    end
    
    -- Calculate target index (2 spots before the last reward, but at least index 1)
    local targetIndex = math.max(1, lastIndex - 2)
    
    -- Calculate time until target reward and count rewards
    for index, config in pairs(onlineRewardsConf) do
        totalRewards = totalRewards + 1
        local requiredTime = config.OnlinTime * 60
        local timeLeft = requiredTime - onlineTime
        
        -- Check if claimed - handle nil case
        local claimed = false
        if playerData.OnlineAward and type(playerData.OnlineAward) == "table" then
            claimed = (playerData.OnlineAward[index] == 1)
        end
        
        if claimed then
            claimedCount = claimedCount + 1
        elseif timeLeft <= 0 then
            readyCount = readyCount + 1
        end
        
        -- If this is the target reward, track time until it's ready
        if index == targetIndex then
            timeUntilTargetReward = timeLeft
            if timeLeft <= 0 and not claimed then
                allReady = true
            end
        end
    end
    
    return readyCount, totalRewards, allReady, timeUntilTargetReward
end

-- Claim claimable rewards function
local function claimClaimableRewards()
    local onlineRewardsConf, onlineTime, playerData = getOnlineRewardsData()
    
    if not onlineRewardsConf or not onlineTime or not playerData then
        return
    end
    
    -- Make sure OnlineAward table exists
    if not playerData.OnlineAward or type(playerData.OnlineAward) ~= "table" then
        return
    end
    
    -- Claim each ready reward except for reward #2
    for index, config in pairs(onlineRewardsConf) do
        if index ~= 2 then -- Skip reward #2
            local requiredTime = config.OnlinTime * 60
            local timeLeft = requiredTime - onlineTime
            local claimed = (playerData.OnlineAward[index] == 1)
            
            if timeLeft <= 0 and not claimed then
                pcall(function()
                    RS.Msg.RemoteEvent:FireServer("领取在线奖励", index)
                end)

                task.wait(1)

                -- Use buff items
                pcall(function()
                    local StarterScripts = game:GetService("StarterPlayer").StarterPlayerScripts
                    local localData = require(StarterScripts:WaitForChild("LocalData"))
                    local data = localData:GetLocalData()
                    
                    if data and data.Bag then
                        local CfgFind = require(RS.Tool.CfgFind)
                        local EnumMgr = require(RS.Tool.EnumMgr)
                        
                        for _, entry in ipairs(data.Bag) do
                            if entry.tp == EnumMgr.ItemType.Item and entry.count > 0 then
                                local cfg = CfgFind.FindCfgByID(entry.id, entry.tp)
                                if cfg and cfg.UseScript == "AddBUFF" then
                                    local onlyID = entry.onlyID
                                    for i = 1, entry.count do
                                        pcall(function() RS.ServerMsg.UseItem:InvokeServer(onlyID) end)
                                    end
                                end
                            end
                        end
                    end
                end)
            end
        end
    end
end

-- Update time until rejoin display
local function updateTimeDisplay()
    -- Try to get rewards data, waiting until it exists
    local readyCount, totalRewards, allReady, timeUntilTargetReward
    
    -- Use task.spawn to prevent blocking the main thread
    task.spawn(function()
        -- Keep trying until we get valid data
        while state.scriptActive do
            readyCount, totalRewards, allReady, timeUntilTargetReward = checkOnlineRewards()
            
            if allReady ~= nil then -- If we got valid data
                break
            end
            
            task.wait(1) -- Wait before trying again
        end
        
        -- Only proceed if the script is still active
        if not state.scriptActive then return end
        
        -- Update the display based on obtained data
        if allReady then
            timeUntilRejoinLabel.Text = "Rejoin in: Ready!"
            timeUntilRejoinLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        elseif timeUntilTargetReward then
            timeUntilRejoinLabel.Text = "Rejoin in: " .. formatTime(timeUntilTargetReward)
            
            if timeUntilTargetReward <= 300 then -- Less than 5 minutes
                timeUntilRejoinLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
            else
                timeUntilRejoinLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
            end
        else
            timeUntilRejoinLabel.Text = "Rejoin in: Loading..."
            timeUntilRejoinLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
        end
        
        -- Claim any rewards that are ready, if data is available
        if readyCount ~= nil then
            claimClaimableRewards()
        end
    end)
end

-- Egg selection handling
local function clearSelection()
    if state.currentSelection and state.currentSelection.Parent then
        state.currentSelection:Destroy()
        state.currentSelection = nil
    end
end

local function createSelection(model)
    clearSelection()
    if not model then return end

    state.currentSelection = createInstance("SelectionBox", {
        Name = "EggSelection",
        Color3 = Color3.fromRGB(0, 255, 0),
        LineThickness = 0.03,
        Adornee = model,
        Parent = workspace
    })
end

-- Find nearest egg
local function findNearestEgg()
    local humanoidRootPart = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return nil, nil end
    
    -- Return locked egg if valid
    if state.lockedEggId and state.lockedEggModel and state.lockedEggModel.Parent then
        return state.lockedEggModel, state.lockedEggId
    end
    
    local playerPos = humanoidRootPart.Position
    local nearestEgg = nil
    local nearestDist = math.huge
    local eggId = nil
    local sceneFolder = workspace["场景"]
    
    if not sceneFolder then return nil, nil end
    
    -- Find folders containing eggs
    local function findDrawFolders(parent)
        local drawFolders = {}
        for _, child in pairs(parent:GetChildren()) do
            if child.Name == "抽奖" and child:IsA("Folder") then
                table.insert(drawFolders, child)
            elseif child:IsA("Folder") or child:IsA("Model") then
                for _, folder in pairs(findDrawFolders(child)) do
                    table.insert(drawFolders, folder)
                end
            end
        end
        return drawFolders
    end
    
    -- Process egg models to find nearest or matching ID
    local function processEggModels(drawFolders, matchSpecificId)
        local result, resultId, bestDist = nil, nil, math.huge
        
        for _, drawFolder in pairs(drawFolders) do
            for _, parent in pairs(drawFolder:GetChildren()) do
                for _, descendant in pairs(parent:GetDescendants()) do
                    if descendant.Name == "EggId" then
                        local currentEggId
                        if descendant:IsA("StringValue") then
                            currentEggId = tonumber(descendant.Value)
                        elseif descendant:IsA("IntValue") or descendant:IsA("NumberValue") then
                            currentEggId = descendant.Value
                        end
                        
                        -- Skip if we're looking for a specific ID and this isn't it
                        if matchSpecificId and currentEggId ~= state.lockedEggId then
                            break
                        end
                        
                        local model = parent
                        local part = model:FindFirstChildWhichIsA("BasePart")
                        if part then
                            local dist = (part.Position - playerPos).Magnitude
                            if dist < bestDist then
                                bestDist = dist
                                result = model
                                resultId = currentEggId
                            end
                        end
                        break
                    end
                end
            end
        end
        
        return result, resultId
    end
    
    local drawFolders = findDrawFolders(sceneFolder)
    
    -- First try to find an egg matching lockedEggId
    if state.lockedEggId then
        nearestEgg, eggId = processEggModels(drawFolders, true)
    end
    
    -- If no matching egg found, find the nearest egg regardless of ID
    if not nearestEgg then
        nearestEgg, eggId = processEggModels(drawFolders, false)
    end
    
    -- If still no egg found and looking for specific ID, do a deeper search
    if state.lockedEggId and not nearestEgg then
        local function findModelWithEggId(parent)
            for _, child in pairs(parent:GetChildren()) do
                if child:IsA("Model") or child:IsA("Folder") then
                    for _, desc in pairs(child:GetDescendants()) do
                        if desc.Name == "EggId" then
                            local value
                            if desc:IsA("StringValue") then
                                value = tonumber(desc.Value)
                            elseif desc:IsA("IntValue") or desc:IsA("NumberValue") then
                                value = desc.Value
                            end
                            if value == state.lockedEggId then
                                return child
                            end
                        end
                    end
                    local result = findModelWithEggId(child)
                    if result then return result end
                end
            end
            return nil
        end
        
        local model = findModelWithEggId(sceneFolder)
        if model then
            nearestEgg = model
            eggId = state.lockedEggId
        end
    end
    
    return nearestEgg, eggId
end

-- Auto-hatching functionality
local function startAutoHatch()
    if state.autoHatchRunning then return end

    state.autoHatchEnabled = true
    state.autoHatchRunning = true
    updateButtonStates()

    -- Try to find egg with up to 10 seconds of waiting
    local startTime = tick()
    local timeoutSeconds = 10
    local nearestEgg, eggId = nil, nil

    task.spawn(function()
        while (tick() - startTime) < timeoutSeconds do
            nearestEgg, eggId = findNearestEgg()
            if nearestEgg and eggId then
                -- Found an egg, proceed with auto hatching
                state.lockedEggId = eggId
                state.lockedEggModel = nearestEgg
                createSelection(nearestEgg)
                
                -- Start the hatching loop
                while state.autoHatchEnabled and state.scriptActive do
                    local egg, id = findNearestEgg()
                    if egg and id then
                        createSelection(egg)
                        -- Hatch egg
                        RS.Tool.DrawUp.Msg.DrawHero:InvokeServer(id, 1)
                        RS.Msg.RemoteEvent:FireServer("装备最佳宠物")
                    else
                        -- Try to find a new egg
                        local newEgg, newId = findNearestEgg()
                        if newEgg and newId then
                            state.lockedEggId = newId
                            state.lockedEggModel = newEgg
                            createSelection(newEgg)
                        end
                    end
                    task.wait(2)
                    if not state.autoHatchEnabled or not state.scriptActive then break end
                end
                
                state.autoHatchRunning = false
                if not state.autoHatchEnabled then
                    clearSelection()
                    state.lockedEggId = nil
                    state.lockedEggModel = nil
                end
                
                return
            end
            
            -- Wait before trying again
            task.wait(0.5)
        end
        
        -- If we get here, we couldn't find an egg within the timeout period
        state.autoHatchEnabled = false
        state.autoHatchRunning = false
        updateButtonStates()
    end)

    saveSettings()
end

local function stopAutoHatch()
    state.autoHatchEnabled = false
    state.lockedEggId = nil
    state.lockedEggModel = nil
    clearSelection()
    updateButtonStates()
    saveSettings()
end

-- Claim daily rewards functionality
local function claimDailyRewards()
    -- Claim daily tasks
    RS.Msg.RemoteEvent:FireServer("领取每日任务奖励")
    
    -- Claim lottery spin
    for i = 1, 3 do
        RS.System.SystemDailyLottery.Spin:InvokeServer()
    end
    
end

-- Rewards monitoring for auto-rejoin
local function startRewardsMonitor()
    if state.rewardsCheckRunning then return end
    state.rewardsCheckRunning = true

    task.spawn(function()
        while state.scriptActive do
            updateTimeDisplay()
            
            -- Keep trying to check rewards status until valid data is received
            local allReady = false
            local dataObtained = false
            
            -- Keep trying until we get valid data
            local checkingTask = task.spawn(function()
                while state.scriptActive and not dataObtained do
                    local readyCount, totalRewards, ready, timeUntilTargetReward = checkOnlineRewards()
                    
                    if ready ~= nil then -- If we got valid data
                        allReady = ready
                        dataObtained = true
                        break
                    end
                    
                    task.wait(2) -- Wait before trying again
                end
            end)
            
            -- Wait for the checking task to complete
            task.wait(10)
            
            -- If we have valid data and all rewards are ready
            if dataObtained and allReady then
                if state.autoRejoinEnabled and state.scriptActive then
                    -- Try to claim daily rewards
                    pcall(claimDailyRewards)
                    saveSettings()
                    
                    -- Queue script for after teleport
                    queue_on_teleport([[
                        loadstring(game:HttpGet("https://raw.githubusercontent.com/Maxhem2/RobloxScript/refs/heads/main/main.lua"))()
                    ]])
                    
                    -- Teleport to same place
                    TS:Teleport(game.PlaceId, Player)
                end
                break
            end
            
            if not state.scriptActive then break end
        end
        
        state.rewardsCheckRunning = false
    end)
end

-- Save current player position
local function savePlayerPosition()
    local humanoidRootPart = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return false end
    
    -- Save the current position with a small fixed height increase (5 studs)
    -- This will place the player just slightly above their original position
    state.savedPosition = humanoidRootPart.Position + Vector3.new(0, 5, 0)
    
    return true
end

-- Auto-rejoin toggle
local function toggleAutoRejoin()
    if not state.autoRejoinEnabled then
        -- Turning on auto-rejoin, save position
        if savePlayerPosition() then
            state.autoRejoinEnabled = true
        else
            -- Failed to save position
            rejoinBtn.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
            task.delay(0.5, function() 
                rejoinBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
            end)
            return
        end
    else
        -- Turning off auto-rejoin
        state.autoRejoinEnabled = false
        state.savedPosition = nil
        state.savedHeight = 0
    end
    
    updateButtonStates()
    saveSettings()
end

-- GUI unloading
local function unloadGUI()
    if state.busy then return end
    
    state.running = false
    state.stopping = true
    state.scriptActive = false
    state.rewardsCheckRunning = false
    
    saveSettings()
    clearSelection()
    gui:Destroy()
end

-- Farming functionality
local function farm(height)
    if height <= 0 then return end
    
    state.farmHeight = height
    state.running = true
    state.stopping = false
    state.busy = false
    state.autoFarmActive = true
    
    updateButtonStates()
    saveSettings()
    
    task.spawn(function()
        while state.running and not state.stopping and state.scriptActive do
            -- Perform jump and collect rewards
            RS.Msg.RemoteEvent:FireServer("起跳", height)
            RS.Msg.RemoteEvent:FireServer("落地")
            RS.Msg.RemoteEvent:FireServer("领取楼顶wins")
            
            task.wait(1)
            if not state.scriptActive then break end
        end
        
        state.busy = true
        state.running = false
        state.stopping = false
        state.busy = false
        
        updateButtonStates()
    end)
end

-- Stop farming
local function stopFarming()
    state.stopping = true
    state.busy = true
    state.autoFarmActive = false
    
    updateButtonStates()
    saveSettings()
end

-- Helper function for button click handling
local function handleButtonClick(button, action)
    button.MouseButton1Click:Connect(function()
        if state.clickDebounce then return end
        state.clickDebounce = true
        
        action()
        
        task.delay(0.3, function() state.clickDebounce = false end)
    end)
end

-- Button event handlers
closeBtn.MouseButton1Click:Connect(unloadGUI)

handleButtonClick(hatchBtn, function()
    if state.autoHatchEnabled then
        stopAutoHatch()
    else
        startAutoHatch()
    end
end)

handleButtonClick(rejoinBtn, toggleAutoRejoin)

startBtn.MouseButton1Click:Connect(function()
    if state.running or state.busy or state.clickDebounce then return end
    state.clickDebounce = true
    
    local heightValue = tonumber(heightInput.Text)
    if not heightValue or heightValue <= 0 then
        heightInput.TextColor3 = Color3.fromRGB(255, 100, 100)
        task.delay(0.5, function() heightInput.TextColor3 = Color3.fromRGB(255, 255, 255) end)
        state.clickDebounce = false
        return
    end
    
    farm(heightValue)
    
    state.clickDebounce = false
end)

handleButtonClick(stopBtn, function()
    if not state.running or state.busy or state.stopping then return end
    stopFarming()
end)

-- Validate height input
heightInput.FocusLost:Connect(function()
    local numValue = tonumber(heightInput.Text)
    if not numValue or numValue <= 0 then
        heightInput.Text = "100"
        heightInput.TextColor3 = Color3.fromRGB(255, 100, 100)
        task.delay(0.5, function() heightInput.TextColor3 = Color3.fromRGB(255, 255, 255) end)
    end
end)

-- Initialize
updateButtonStates()
startRewardsMonitor()

-- Auto-start features based on saved settings
if state.lockedEggId then
    startAutoHatch()
end

if state.autoFarmActive and state.farmHeight > 0 then
    heightInput.Text = tostring(state.farmHeight)
    farm(state.farmHeight)
elseif state.farmHeight > 0 then
    heightInput.Text = tostring(state.farmHeight)
end
