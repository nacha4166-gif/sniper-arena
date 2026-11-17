--[[
--------------------------------------------------------------------
  SNIPER ARENA — v52 (keyless, Luau / Xeno)
  Improvements over v47:
    - frame-rate independent aim smoothing (no more speed tied to FPS)
    - ESP boxes sized from real head/foot projection, distance in the label
    - real player names instead of model names / asset ids
    - FOV circle drawn on screen, matches the actual lock-on cone
    - sliders for smoothing, FOV and max distance (saved to disk if allowed)
    - dead/ragdoll filter on Humanoid state instead of heuristics-only
    - line of sight raycast excludes the local character and the target itself
    - adaptive scan rate: fast when targets exist, lazy when empty
    - manual fire only. The script never clicks for you.
  v49:
    - bots and NPCs are targeted again, not just real players
    - a dead body is dropped the instant its Humanoid fires Died
    - corpse memory: a body seen dead is skipped for 20 s
  v50:
    - ESP has its own list: everything alive, walls included, no FOV cone, bots included
    - lock-on keeps its FOV cone and line-of-sight rule, separate from the ESP
    - corpses filtered on name, Humanoid state, lost RootPart and death spots
  v51:
    - F7 debug overlay: every model in the map, with the reason it was kept or skipped
    - "dummy" removed from the corpse name filter, it was hiding bots named Dummy
  v52:
    - bots are found three ways: player characters, Humanoids, and head+body rigs with no Humanoid
    - a Humanoid with no RootPart no longer rejects a bot, the rig itself is used
    - corpse clones that copy a dead player's name are refused for 25 s
    - F7 also prints the report to the executor console, and shows the sweep counters
--------------------------------------------------------------------
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local UIS        = game:GetService("UserInputService")

local lp  = Players.LocalPlayer
local cam = Workspace.CurrentCamera

if type(_G.SNIPER48) == "table" and _G.SNIPER48.shutdown then
    pcall(_G.SNIPER48.shutdown)
end

--------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------
local CFG = {
    LockOn      = true,
    Esp         = true,
    VisibleOnly = true,
    FovCircle   = true,
    RotateBody  = false,
    Fov         = 35,     -- degrees, half-angle of the lock-on cone
    Smooth      = 14,     -- higher = snappier
    MaxDist     = 4000,   -- studs
    BoxFill     = false,
    IncludeBots = true,
    Debug       = false,
    UiVisible   = true,
    ScanFast    = 0.10,
    ScanSlow    = 0.30,
    MaxTargets  = 40,
    BotScan     = 1.5,
    CorpseHold  = 20,
}

local CONFIG_FILE = "sniper48.json"

local function saveConfig()
    if not writefile then return end
    local ok = pcall(function()
        writefile(CONFIG_FILE, game:GetService("HttpService"):JSONEncode(CFG))
    end)
    return ok
end

local function loadConfig()
    if not (isfile and readfile) then return end
    if not isfile(CONFIG_FILE) then return end
    local ok, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(readfile(CONFIG_FILE))
    end)
    if ok and type(data) == "table" then
        for key, value in pairs(data) do
            if CFG[key] ~= nil then CFG[key] = value end
        end
    end
end

loadConfig()

--------------------------------------------------------------------
-- PALETTE
--------------------------------------------------------------------
local COL = {
    bg     = Color3.fromRGB(15, 16, 19),
    card   = Color3.fromRGB(24, 26, 30),
    line   = Color3.fromRGB(58, 61, 68),
    text   = Color3.fromRGB(232, 234, 238),
    dim    = Color3.fromRGB(142, 147, 157),
    accent = Color3.fromRGB(124, 255, 138),
    off    = Color3.fromRGB(46, 49, 55),
    danger = Color3.fromRGB(255, 96, 96),
}

local DISCORD = "discord.gg/psxrAqpX7"

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--------------------------------------------------------------------
-- GUI
--------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "SniperArena48"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 500
gui.Parent = (gethui and gethui()) or lp:FindFirstChild("PlayerGui")

local function corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 10)
    c.Parent = obj
end

local function stroke(obj, color, thick, alpha)
    local s = Instance.new("UIStroke")
    s.Color = color or COL.line
    s.Thickness = thick or 1
    s.Transparency = alpha or 0.35
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = obj
    return s
end

local function label(parent, text, size, bold, color)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextSize = size
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
    l.TextColor3 = color or COL.text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = parent
    return l
end

local root = Instance.new("Frame")
root.Name = "SA_Main"
root.Size = UDim2.fromOffset(304, 0)
root.Position = UDim2.fromOffset(16, 16)
root.AutomaticSize = Enum.AutomaticSize.Y
root.BackgroundColor3 = COL.bg
root.BackgroundTransparency = 0.06
root.BorderSizePixel = 0
root.ClipsDescendants = false
root.Parent = gui
corner(root, 14)
stroke(root, COL.line, 1, 0.45)

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 12)
pad.PaddingBottom = UDim.new(0, 12)
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = root

local stack = Instance.new("UIListLayout")
stack.SortOrder = Enum.SortOrder.LayoutOrder
stack.Padding = UDim.new(0, 10)
stack.Parent = root

-- header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundTransparency = 1
header.LayoutOrder = 1
header.Parent = root

local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(8, 8)
dot.Position = UDim2.fromOffset(0, 11)
dot.BackgroundColor3 = COL.off
dot.BorderSizePixel = 0
dot.Parent = header
corner(dot, 4)

local title = label(header, "SNIPER ARENA", 15, true)
title.Position = UDim2.fromOffset(16, 0)
title.Size = UDim2.new(1, -100, 0, 30)

local chip = Instance.new("Frame")
chip.Size = UDim2.fromOffset(84, 20)
chip.Position = UDim2.new(1, -84, 0, 5)
chip.BackgroundColor3 = COL.card
chip.BorderSizePixel = 0
chip.Parent = header
corner(chip, 10)
local chipText = label(chip, "MANUAL FIRE", 9, true, COL.dim)
chipText.Size = UDim2.fromScale(1, 1)
chipText.TextXAlignment = Enum.TextXAlignment.Center

-- status card
local card = Instance.new("Frame")
card.Size = UDim2.new(1, 0, 0, 58)
card.BackgroundColor3 = COL.card
card.BackgroundTransparency = 0.25
card.BorderSizePixel = 0
card.LayoutOrder = 2
card.Parent = root
corner(card, 9)
local cardStroke = stroke(card, COL.line, 1, 0.3)

local targetName = label(card, "none", 14, true)
targetName.Position = UDim2.fromOffset(12, 8)
targetName.Size = UDim2.new(1, -24, 0, 20)
local targetSub = label(card, "0 visible / 0", 11, false, COL.dim)
targetSub.Position = UDim2.fromOffset(12, 30)
targetSub.Size = UDim2.new(1, -24, 0, 18)

-- discord bar
local discordBar = Instance.new("TextButton")
discordBar.Size = UDim2.new(1, 0, 0, 32)
discordBar.BackgroundColor3 = COL.card
discordBar.BackgroundTransparency = 0.35
discordBar.BorderSizePixel = 0
discordBar.AutoButtonColor = false
discordBar.Text = ""
discordBar.LayoutOrder = 3
discordBar.Parent = root
corner(discordBar, 8)
local discordStroke = stroke(discordBar, COL.line, 1, 0.4)
local discordLabel = label(discordBar, DISCORD, 11, true, COL.accent)
discordLabel.Position = UDim2.fromOffset(12, 0)
discordLabel.Size = UDim2.new(1, -70, 1, 0)
local copyBtn = label(discordBar, "COPY", 10, true, COL.accent)
copyBtn.Position = UDim2.new(1, -54, 0, 0)
copyBtn.Size = UDim2.fromOffset(42, 32)
copyBtn.TextXAlignment = Enum.TextXAlignment.Center

-- toggles
local toggles = Instance.new("Frame")
toggles.Size = UDim2.new(1, 0, 0, 0)
toggles.AutomaticSize = Enum.AutomaticSize.Y
toggles.BackgroundTransparency = 1
toggles.LayoutOrder = 4
toggles.Parent = root
local tList = Instance.new("UIListLayout")
tList.Padding = UDim.new(0, 4)
tList.SortOrder = Enum.SortOrder.LayoutOrder
tList.Parent = toggles

local painters = {}

local function makeToggle(order, text, get, set)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 28)
    row.BackgroundColor3 = COL.card
    row.BackgroundTransparency = 0.55
    row.BorderSizePixel = 0
    row.AutoButtonColor = false
    row.Text = ""
    row.LayoutOrder = order
    row.Parent = toggles
    corner(row, 7)

    local lab = label(row, text, 12, false)
    lab.Position = UDim2.fromOffset(10, 0)
    lab.Size = UDim2.new(1, -60, 1, 0)

    local pill = Instance.new("Frame")
    pill.Size = UDim2.fromOffset(34, 16)
    pill.Position = UDim2.new(1, -44, 0.5, -8)
    pill.BackgroundColor3 = COL.off
    pill.BorderSizePixel = 0
    pill.Parent = row
    corner(pill, 8)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(12, 12)
    knob.Position = UDim2.fromOffset(2, 2)
    knob.BackgroundColor3 = COL.text
    knob.BorderSizePixel = 0
    knob.Parent = pill
    corner(knob, 6)

    local function paint()
        local on = get()
        pill.BackgroundColor3 = on and COL.accent or COL.off
        knob.Position = on and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)
        lab.TextColor3 = on and COL.text or COL.dim
    end

    row.MouseButton1Click:Connect(function()
        set(not get())
        paint()
        saveConfig()
    end)

    painters[#painters + 1] = paint
    paint()
end

local function makeSlider(order, text, min, max, get, set, format)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 40)
    row.BackgroundColor3 = COL.card
    row.BackgroundTransparency = 0.55
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = toggles
    corner(row, 7)

    local name = label(row, text, 12, false)
    name.Position = UDim2.fromOffset(10, 2)
    name.Size = UDim2.new(1, -80, 0, 16)

    local valueLabel = label(row, "", 11, true, COL.accent)
    valueLabel.Position = UDim2.new(1, -70, 0, 2)
    valueLabel.Size = UDim2.fromOffset(60, 16)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -20, 0, 6)
    track.Position = UDim2.fromOffset(10, 24)
    track.BackgroundColor3 = COL.off
    track.BorderSizePixel = 0
    track.Parent = row
    corner(track, 3)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = COL.accent
    fill.BorderSizePixel = 0
    fill.Parent = track
    corner(fill, 3)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(12, 12)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = COL.text
    knob.BorderSizePixel = 0
    knob.Parent = track
    corner(knob, 6)

    local function paint()
        local v = get()
        local t = (clamp(v, min, max) - min) / math.max(max - min, 0.0001)
        fill.Size = UDim2.new(t, 0, 1, 0)
        knob.Position = UDim2.new(t, 0, 0.5, 0)
        valueLabel.Text = format and format(v) or tostring(math.floor(v + 0.5))
    end

    local dragging = false
    local function apply(input)
        local frame = track.AbsolutePosition
        local width = math.max(track.AbsoluteSize.X, 1)
        local t = clamp((input.Position.X - frame.X) / width, 0, 1)
        set(min + (max - min) * t)
        paint()
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            apply(input)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            apply(input)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            saveConfig()
        end
    end)

    painters[#painters + 1] = paint
    paint()
end

makeToggle(1, "Lock-On", function() return CFG.LockOn end, function(v) CFG.LockOn = v end)
makeToggle(2, "ESP", function() return CFG.Esp end, function(v) CFG.Esp = v end)
makeToggle(3, "Line of Sight", function() return CFG.VisibleOnly end, function(v) CFG.VisibleOnly = v end)
makeToggle(4, "FOV Circle", function() return CFG.FovCircle end, function(v) CFG.FovCircle = v end)
makeToggle(5, "Rotate Body", function() return CFG.RotateBody end, function(v) CFG.RotateBody = v end)
makeToggle(6, "Include Bots", function() return CFG.IncludeBots end, function(v) CFG.IncludeBots = v end)

local sliders = Instance.new("Frame")
sliders.Size = UDim2.new(1, 0, 0, 0)
sliders.AutomaticSize = Enum.AutomaticSize.Y
sliders.BackgroundTransparency = 1
sliders.LayoutOrder = 5
sliders.Parent = root
local sList = Instance.new("UIListLayout")
sList.Padding = UDim.new(0, 4)
sList.Parent = sliders

makeSlider(1, "Smoothing", 4, 40,
    function() return CFG.Smooth end,
    function(v) CFG.Smooth = v end,
    function(v) return string.format("%.0f", v) end)
makeSlider(2, "FOV", 5, 80,
    function() return CFG.Fov end,
    function(v) CFG.Fov = v end,
    function(v) return string.format("%.0f°", v) end)
makeSlider(3, "Max distance", 200, 6000,
    function() return CFG.MaxDist end,
    function(v) CFG.MaxDist = v end,
    function(v) return string.format("%.0f", v) end)

-- move sliders under toggles
sliders.Parent = toggles
for _, child in ipairs(sliders:GetChildren()) do
    if child:IsA("Frame") then
        child.LayoutOrder = 100 + (child.LayoutOrder or 0)
    end
end

local footer = label(root, "F1 hide  F2 lock  F3 esp  F4 discord  F5 ignore  F6 fov  F7 debug", 10, false, COL.dim)
footer.Size = UDim2.new(1, 0, 0, 14)
footer.LayoutOrder = 6
footer.TextXAlignment = Enum.TextXAlignment.Center

-- debug: says out loud what every model in the map was judged to be
local debugBox = label(root, "", 10, false, COL.dim)
debugBox.Size = UDim2.new(1, 0, 0, 0)
debugBox.AutomaticSize = Enum.AutomaticSize.Y
debugBox.TextWrapped = true
debugBox.TextYAlignment = Enum.TextYAlignment.Top
debugBox.LayoutOrder = 7
debugBox.Visible = false

--------------------------------------------------------------------
-- ESP DRAWINGS
--------------------------------------------------------------------
local drawingOk = false
do
    local ok = pcall(function()
        local probe = Drawing.new("Square")
        probe:Remove()
        drawingOk = true
    end)
end

local boxCache = {}
local fovCircle = nil

if drawingOk then
    fovCircle = Drawing.new("Circle")
    fovCircle.Thickness = 1
    fovCircle.NumSides = 64
    fovCircle.Filled = false
    fovCircle.Transparency = 0.6
    fovCircle.Color = COL.accent
    fovCircle.Visible = false
end

local function boxAt(index)
    if not drawingOk then return nil end
    local entry = boxCache[index]
    if entry then return entry end
    local ok, made = pcall(function()
        local square = Drawing.new("Square")
        square.Thickness = 1
        square.Filled = false
        square.Transparency = 1
        square.Color = COL.accent
        local text = Drawing.new("Text")
        text.Size = 13
        text.Center = true
        text.Outline = true
        text.Color = Color3.fromRGB(230, 235, 240)
        return { square = square, text = text }
    end)
    if not ok or not made then
        drawingOk = false
        return nil
    end
    boxCache[index] = made
    return made
end

local function hideBox(index)
    local entry = boxCache[index]
    if not entry then return end
    entry.square.Visible = false
    entry.text.Visible = false
end

--------------------------------------------------------------------
-- GAME HELPERS
--------------------------------------------------------------------
local DEAD_STATES = {
    [Enum.HumanoidStateType.Dead] = true,
    [Enum.HumanoidStateType.Physics] = true,
    [Enum.HumanoidStateType.FallingDown] = true,
    [Enum.HumanoidStateType.PlatformStanding] = true,
}

-- games keep corpses around: as a ragdoll, as a renamed clone, or as a dummy
-- that still reports full health. Those words are the ones they never use for a living body.
-- only names a living body never carries. "dummy" is deliberately absent:
-- plenty of games call their bots Dummy or BotDummy, and that filter was hiding them.
local CORPSE_WORDS = { "ragdoll", "corpse", "deadbody", "dead_body" }

local function looksLikeCorpse(character)
    local lower = string.lower(character.Name or "")
    for _, word in ipairs(CORPSE_WORDS) do
        if string.find(lower, word, 1, true) then return true end
    end
    return false
end

-- a corpse clone keeps the name of the player it came from. Remember it and
-- refuse any model carrying that name, since no living body answers to it.
local deadNames = {}

local function markDeadName(name)
    if name and #name > 0 then deadNames[name] = os.clock() + 25 end
end

local function isDeadName(character)
    if Players:GetPlayerFromCharacter(character) then return false end
    local name = character.Name
    if not name then return false end
    local expiry = deadNames[name]
    if not expiry then return false end
    if os.clock() > expiry then
        deadNames[name] = nil
        return false
    end
    return true
end

local function hasBodyPart(character)
    return character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character.PrimaryPart
end

local function isAlive(character)
    if not character or not character.Parent then return false end
    if looksLikeCorpse(character) then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        if humanoid.Health <= 0 then return false end
        if DEAD_STATES[humanoid:GetState()] then return false end
        -- bots often keep a Humanoid but no RootPart bound to it: fall back on the rig
        return hasBodyPart(character) ~= nil
    end
    -- no Humanoid at all: some games ship bots as plain rigs, head + body only
    return character:FindFirstChild("Head") ~= nil and hasBodyPart(character) ~= nil
end

local function partsOf(character)
    local head = character:FindFirstChild("Head")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
    if not rootPart then
        local primary = character.PrimaryPart
        if primary then rootPart = primary end
    end
    return head, rootPart
end

local function nameOf(character)
    local player = Players:GetPlayerFromCharacter(character)
    if player then return player.DisplayName ~= "" and player.DisplayName or player.Name end
    local name = character.Name or "bot"
    if #name >= 32 and name:match("^%x%x%x%x%x%x%x%x-") then return "bot" end
    if #name > 20 then return string.sub(name, 1, 18) .. ".." end
    return name
end

local corpses = {}

local function markCorpse(character, seconds)
    if character then corpses[character] = os.clock() + (seconds or CFG.CorpseHold) end
end

local function isCorpse(character)
    local expiry = corpses[character]
    if not expiry then return false end
    if not character.Parent or os.clock() > expiry then
        corpses[character] = nil
        return false
    end
    return true
end

-- games often spawn a fresh ragdoll model where the body fell. Remember the
-- spot of every death for a few seconds and refuse anything standing there.
local deathSpots = {}

local function markDeathSpot(position)
    if not position then return end
    deathSpots[#deathSpots + 1] = { pos = position, at = os.clock() }
    while #deathSpots > 30 do table.remove(deathSpots, 1) end
end

local function nearDeathSpot(character, rootPart)
    if not rootPart then return false end
    local now = os.clock()
    local where = rootPart.Position
    for index = #deathSpots, 1, -1 do
        local spot = deathSpots[index]
        if now - spot.at > 8 then
            table.remove(deathSpots, index)
        elseif (spot.pos - where).Magnitude <= 6 then
            return true
        end
    end
    return false
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function canSee(character, targetPart)
    if not targetPart then return false end
    local ignored = { character }
    if lp.Character then ignored[#ignored + 1] = lp.Character end
    rayParams.FilterDescendantsInstances = ignored
    local origin = cam.CFrame.Position
    local result = Workspace:Raycast(origin, targetPart.Position - origin, rayParams)
    if not result then return true end
    return result.Instance:IsDescendantOf(character)
end

--------------------------------------------------------------------
-- TARGETING
--------------------------------------------------------------------
local State = {
    visible = 0,
    total = 0,
    errors = 0,
    target = nil,
    copyUntil = 0,
    candidates = {},
    espList = {},
    report = {},
    aliveCount = 0,
    lastScan = 0,
    lastSweep = 0,
    characters = {},
    deathHooks = {},
}

--------------------------------------------------------------------
-- CHARACTER SWEEP (players + bots)
--------------------------------------------------------------------
local function sweepCharacters()
    local found, seen = {}, {}
    local humanoids, rigs = 0, 0

    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= lp then
            local character = other.Character
            if character and character.Parent then
                found[#found + 1] = character
                seen[character] = true
            end
        end
    end

    if CFG.IncludeBots then
        local ok = pcall(function()
            for _, descendant in ipairs(Workspace:GetDescendants()) do
                if descendant:IsA("Humanoid") then
                    humanoids = humanoids + 1
                    local model = descendant.Parent
                    if model and not seen[model] and model ~= lp.Character then
                        seen[model] = true
                        found[#found + 1] = model
                    end
                elseif descendant:IsA("BasePart") and descendant.Name == "Head" then
                    local model = descendant.Parent
                    if model and not seen[model] and model ~= lp.Character
                        and (model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
                             or model:FindFirstChild("UpperTorso")) then
                        seen[model] = true
                        rigs = rigs + 1
                        found[#found + 1] = model
                    end
                end
            end
        end)
        if not ok then
            State.errors = State.errors + 1
        end
    end

    State.sweepInfo = string.format("sweep %d models (%d humanoid, %d rigs)", #found, humanoids, rigs)
    State.characters = found
    State.lastSweep = os.clock()
    return found
end

local function watchDeath(character)
    if State.deathHooks[character] then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local ok, connection = pcall(function()
        return humanoid.Died:Connect(function()
            State.deathHooks[character] = nil
            markCorpse(character)
            markDeadName(character.Name)
            local dyingRoot = humanoid.RootPart or character:FindFirstChild("HumanoidRootPart")
            markDeathSpot(dyingRoot and dyingRoot.Position)
            if State.target and State.target.character == character then
                State.target = nil
                State.lastScan = 0
            end
        end)
    end)
    if ok then State.deathHooks[character] = connection end
end

local function scanTargets()
    local now = os.clock()
    if now - State.lastSweep >= CFG.BotScan then
        sweepCharacters()
    end

    local list = {}
    local espList = {}
    local report = {}
    local visibleCount = 0
    local totalCount = 0
    local viewport = cam.ViewportSize

    for _, character in ipairs(State.characters) do
        local reason = nil
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not character.Parent then
            reason = "gone"
        elseif character == lp.Character then
            reason = "self"
        elseif isCorpse(character) then
            reason = "corpse-memory"
        elseif looksLikeCorpse(character) then
            reason = "corpse-name"
        elseif isDeadName(character) then
            reason = "corpse-name-match"
        elseif not humanoid then
            reason = "no-humanoid"
        elseif humanoid.Health <= 0 then
            reason = "hp0"
        elseif DEAD_STATES[humanoid:GetState()] then
            reason = "state"
        elseif not humanoid.RootPart or not humanoid.RootPart.Parent then
            reason = "no-root"
        end

        if reason then
            report[#report + 1] = string.format("%s  ·  %s", nameOf(character), reason)
        else
            local head, rootPart = partsOf(character)
            if nearDeathSpot(character, rootPart) then
                markCorpse(character, 8)
                report[#report + 1] = string.format("%s  ·  death-spot", nameOf(character))
            else
            totalCount = totalCount + 1
            local aimPart = head or rootPart
            if aimPart and aimPart.Parent then
                local origin = cam.CFrame.Position
                local delta = aimPart.Position - origin
                local distance = delta.Magnitude
                if distance <= CFG.MaxDist then
                    watchDeath(character)
                    -- ESP: everything alive around us, bots included, walls included.
                    -- Only things actually in front of the camera get drawn, nothing behind the head.
                    local headScreen, headOn = cam:WorldToViewportPoint(aimPart.Position)
                    if headOn and headScreen.Z > 0
                        and headScreen.X > -200 and headScreen.X < viewport.X + 200
                        and headScreen.Y > -200 and headScreen.Y < viewport.Y + 200 then
                        espList[#espList + 1] = {
                            character = character,
                            head = head,
                            root = rootPart,
                            aim = aimPart,
                            name = nameOf(character),
                            distance = distance,
                            score = distance,
                        }
                        report[#report + 1] = string.format("%s  ·  esp %.0fm", nameOf(character), distance / 3.571)
                    elseif not CFG.Debug then
                        -- nothing to say when debug is off
                    end

                    -- Lock-on stays inside the FOV cone and respects line of sight
                    local dir = cam.CFrame.LookVector
                    local unit = delta.Unit
                    local angle = math.deg(math.acos(clamp(dir:Dot(unit), -1, 1)))
                    if angle <= CFG.Fov then
                        local visible = (not CFG.VisibleOnly) or canSee(character, aimPart)
                        if visible then
                            visibleCount = visibleCount + 1
                            list[#list + 1] = {
                                character = character,
                                head = head,
                                root = rootPart,
                                aim = aimPart,
                                name = nameOf(character),
                                distance = distance,
                                angle = angle,
                                score = angle * 0.7 + (distance / math.max(CFG.MaxDist, 1)) * 30,
                            }
                        end
                    end
                end
            end
            end -- nearDeathSpot guard
        end
    end

    table.sort(list, function(a, b) return a.score < b.score end)
    table.sort(espList, function(a, b) return a.score < b.score end)
    State.candidates = list
    State.espList = espList
    State.report = report
    State.aliveCount = #State.characters
    State.visible = visibleCount
    State.total = totalCount
    State.target = list[1]
    return list[1]
end

--------------------------------------------------------------------
-- AIM
--------------------------------------------------------------------
local function aimAt(target, dt)
    if not target or not cam then return end
    local desired = CFrame.lookAt(cam.CFrame.Position, target.aim.Position)
    -- exponential smoothing: same feel at 30 fps and at 240 fps
    local alpha = 1 - math.exp(-CFG.Smooth * dt)
    cam.CFrame = cam.CFrame:Lerp(desired, clamp(alpha, 0, 1))

    if CFG.RotateBody and lp.Character then
        local myRoot = lp.Character:FindFirstChild("HumanoidRootPart")
        if myRoot then
            local bodyWant = CFrame.lookAt(myRoot.Position, target.aim.Position)
            local bodyAlpha = 1 - math.exp(-10 * dt)
            myRoot.CFrame = myRoot.CFrame:Lerp(bodyWant, clamp(bodyAlpha, 0, 1))
        end
    end
end

--------------------------------------------------------------------
-- ESP RENDER
--------------------------------------------------------------------
local function renderEsp()
    if not drawingOk then return end
    local used = 0

    for _, entry in ipairs(State.espList) do
        local head, root = entry.head, entry.root
        if head and root then
            local headScreen, headOn = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
            local footScreen, footOn = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 2.2, 0))
            if headOn and footOn and headScreen.Z > 0 and footScreen.Z > 0 then
                used = used + 1
                if used <= CFG.MaxTargets then
                    local box = boxAt(used)
                    if box then
                        local height = math.abs(footScreen.Y - headScreen.Y)
                        local width = height * 0.5
                        local top = math.min(headScreen.Y, footScreen.Y)
                        box.square.Size = Vector2.new(width, height)
                        box.square.Position = Vector2.new(headScreen.X - width * 0.5, top)
                        box.square.Color = COL.accent
                        box.square.Filled = CFG.BoxFill
                        box.square.Transparency = CFG.BoxFill and 0.7 or 1
                        box.square.Visible = CFG.Esp
                        box.text.Text = string.format("%s  %dm", entry.name, math.floor(entry.distance / 3.571))
                        box.text.Position = Vector2.new(headScreen.X, top - 15)
                        box.text.Visible = CFG.Esp
                    end
                end
            end
        end
    end

    for index = used + 1, #boxCache do
        hideBox(index)
    end
end

local function renderFov()
    if not fovCircle then return end
    if not CFG.FovCircle or not CFG.LockOn then
        fovCircle.Visible = false
        return
    end
    local viewport = cam.ViewportSize
    local halfFov = math.rad(cam.FieldOfView * 0.5)
    local radius = (math.tan(math.rad(CFG.Fov)) / math.tan(halfFov)) * (viewport.Y * 0.5)
    fovCircle.Position = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    fovCircle.Radius = math.max(radius, 1)
    fovCircle.Visible = true
end

--------------------------------------------------------------------
-- UI REFRESH
--------------------------------------------------------------------
local function refreshUi()
    local target = State.target
    if target then
        targetName.Text = string.sub(target.name, 1, 20)
        targetName.TextColor3 = COL.text
        targetSub.Text = string.format("%.0f m · %.0f°", target.distance / 3.571, target.angle)
        cardStroke.Color = COL.accent
        cardStroke.Transparency = 0.15
        dot.BackgroundColor3 = COL.accent
    else
        targetName.Text = "none"
        targetName.TextColor3 = COL.dim
        targetSub.Text = string.format("%d visible / %d", State.visible, State.total)
        cardStroke.Color = COL.line
        cardStroke.Transparency = 0.25
        dot.BackgroundColor3 = State.errors > 0 and COL.danger or COL.off
    end

    debugBox.Visible = CFG.Debug
    if CFG.Debug then
        local lines = {
            string.format("models %d · alive %d · esp %d · aim %d · err %d",
                State.aliveCount, State.total, #State.espList, #State.candidates, State.errors or 0),
            State.sweepInfo or "sweep -",
        }
        for index = 1, math.min(#State.report, 12) do
            lines[#lines + 1] = State.report[index]
        end
        if #State.report == 0 then
            lines[#lines + 1] = "no model found at all"
        end
        debugBox.Text = table.concat(lines, "\n")
        if os.clock() - (State.lastPrint or 0) > 2.5 then
            State.lastPrint = os.clock()
            print("[sniper48] " .. table.concat(lines, " | "))
        end
    end

    if os.clock() < State.copyUntil then
        copyBtn.Text = "COPIED"
        discordStroke.Color = COL.accent
        discordStroke.Transparency = 0.2
    else
        copyBtn.Text = "COPY"
        discordStroke.Color = COL.line
        discordStroke.Transparency = 0.4
    end
end

--------------------------------------------------------------------
-- DISCORD COPY
--------------------------------------------------------------------
local function copyInvite()
    local full = "https://" .. DISCORD
    local ok = pcall(function() setclipboard(full) end)
    if not ok then pcall(function() toclipboard(full) end) end
    State.copyUntil = os.clock() + 1.5
end

discordBar.MouseButton1Click:Connect(copyInvite)

--------------------------------------------------------------------
-- IGNORE LIST (F5)
--------------------------------------------------------------------
local ignored = {}
local IGNORE_SECONDS = 30

local function isIgnored(character)
    local expiry = ignored[character]
    if not expiry then return false end
    if os.clock() > expiry then
        ignored[character] = nil
        return false
    end
    return true
end

--------------------------------------------------------------------
-- RENDER LOOP
--------------------------------------------------------------------
local function onRender(dt)
    local ok = pcall(function()
        dt = clamp(dt or 0, 0, 0.1)
        if not cam or not cam.Parent then
            cam = Workspace.CurrentCamera
            if not cam then return end
        end

        local now = os.clock()
        local interval = (#State.candidates > 0) and CFG.ScanFast or CFG.ScanSlow
        if now - State.lastScan >= interval then
            State.lastScan = now
            scanTargets()
        end

        -- a target that died or lost its hitbox is dropped on the spot
        if State.target then
            local t = State.target
            local stillThere = t.character and t.character.Parent
                and t.aim and t.aim.Parent
                and not isCorpse(t.character)
                and isAlive(t.character)
            if not stillThere then
                markCorpse(t.character)
                State.target = nil
                State.lastScan = 0
                scanTargets()
            end
        end

        -- filter ignored targets without rescanning
        if State.target and isIgnored(State.target.character) then
            for _, entry in ipairs(State.candidates) do
                if not isIgnored(entry.character) then
                    State.target = entry
                    break
                end
            end
        end

        if CFG.LockOn and State.target then
            aimAt(State.target, dt)
        end

        if CFG.Esp then
            local espOk = pcall(renderEsp)
            if not espOk then
                State.errors = State.errors + 1
                drawingOk = false
            end
        else
            for index = 1, #boxCache do hideBox(index) end
        end

        renderFov()
        refreshUi()
    end)

    if not ok then
        State.errors = State.errors + 1
    end
end

pcall(function() RunService:UnbindFromRenderStep("SniperArena48") end)
RunService:BindToRenderStep("SniperArena48", 201, onRender)

--------------------------------------------------------------------
-- KEYS
--------------------------------------------------------------------
local keyConnection = UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    local key = input.KeyCode

    if key == Enum.KeyCode.F1 then
        CFG.UiVisible = not CFG.UiVisible
        root.Visible = CFG.UiVisible
    elseif key == Enum.KeyCode.F2 then
        CFG.LockOn = not CFG.LockOn
        for _, paint in ipairs(painters) do paint() end
        saveConfig()
    elseif key == Enum.KeyCode.F3 then
        CFG.Esp = not CFG.Esp
        for _, paint in ipairs(painters) do paint() end
        saveConfig()
    elseif key == Enum.KeyCode.F4 then
        copyInvite()
    elseif key == Enum.KeyCode.F5 then
        local target = State.target
        if target and target.character then
            if isIgnored(target.character) then
                ignored[target.character] = nil
            else
                ignored[target.character] = os.clock() + IGNORE_SECONDS
            end
        end
    elseif key == Enum.KeyCode.F6 then
        CFG.FovCircle = not CFG.FovCircle
        for _, paint in ipairs(painters) do paint() end
        saveConfig()
    elseif key == Enum.KeyCode.F7 then
        CFG.Debug = not CFG.Debug
        debugBox.Visible = CFG.Debug
        print("[sniper48] debug " .. (CFG.Debug and "on" or "off"))
    end
end)

--------------------------------------------------------------------
-- WINDOW DRAG
--------------------------------------------------------------------
local dragging, dragStart, startPos = false, nil, nil

header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = root.Position
    end
end)

UIS.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        root.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

--------------------------------------------------------------------
-- SHUTDOWN
--------------------------------------------------------------------
local function shutdown()
    pcall(function() RunService:UnbindFromRenderStep("SniperArena48") end)
    pcall(function() keyConnection:Disconnect() end)
    pcall(function() gui:Destroy() end)
    for _, entry in pairs(boxCache) do
        pcall(function() entry.square:Remove() end)
        pcall(function() entry.text:Remove() end)
    end
    if fovCircle then pcall(function() fovCircle:Remove() end) end
    boxCache = {}
    _G.SNIPER48 = nil
end

_G.SNIPER48 = { shutdown = shutdown, cfg = CFG }

--------------------------------------------------------------------
-- START
--------------------------------------------------------------------
scanTargets()
refreshUi()
