--------------------------------------------------------------------
-- SNIPER ARENA — v47 (public UI + discord copy)
-- Xeno / Luau — ESP + lock-on, manual fire
--------------------------------------------------------------------
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local UIS        = game:GetService("UserInputService")

local lp  = Players.LocalPlayer
local cam = Workspace.CurrentCamera

local INVITE   = "https://discord.gg/psxrAqpX7"
local INVITE_UI = "discord.gg/psxrAqpX7"

if _G.SNIPER47 and _G.SNIPER47.shutdown then
    pcall(_G.SNIPER47.shutdown)
end

local CFG = {
    Enabled     = true,
    ESP         = true,
    VisibleOnly = true,
    UiVisible   = true,
    MaxAngle    = 40,
    MaxDist     = 6000,
    Smooth      = 16,
    RotateBody  = true,
    ScanRate    = 0.35,
    LinkRadius  = 9,
    SigRadius   = 8,
    LinkHold    = 5,
    SigHold     = 5,
    DeadHold    = 6,
    ManualHold  = 30,
    IgnoreFor   = 60,
    MinUpright  = 0.9,
    FlatHold    = 0.4,
    WakeSpeed   = 2.0,
    WakeHold    = 6,
    NameSlack   = 3.0,
}

local State = {
    scan      = {},
    ragdolls  = {},
    sigs      = {},
    nameCount = {},
    corpses   = {},
    dead      = {},
    manual    = {},
    noLink    = {},
    flatAt    = {},
    ignored   = {},
    target    = nil,
    visibles  = 0,
    total     = 0,
    errors    = 0,
    copyUntil = 0,
}

local UUID_PAT = "(%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)"

--------------------------------------------------------------------
-- PALETTE
--------------------------------------------------------------------
local COL = {
    bg      = Color3.fromRGB(15, 16, 19),
    card    = Color3.fromRGB(24, 26, 30),
    line    = Color3.fromRGB(58, 61, 68),
    text    = Color3.fromRGB(232, 234, 238),
    dim     = Color3.fromRGB(142, 147, 157),
    accent  = Color3.fromRGB(124, 255, 138),
    off     = Color3.fromRGB(46, 49, 55),
    danger  = Color3.fromRGB(255, 96, 96),
}

--------------------------------------------------------------------
-- UI HELPERS
--------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "SniperArena47"
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
    s.Color = color
    s.Thickness = thick or 1
    s.Transparency = alpha or 0.35
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = obj
    return s
end

local function label(parent, text, size, font, color)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextSize = size
    l.Font = font or Enum.Font.GothamMedium
    l.TextColor3 = color or COL.text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.Parent = parent
    return l
end

local function copyText(text)
    local ok = pcall(function() setclipboard(text) end)
    if ok then return true end
    local ok2 = pcall(function() toclipboard(text) end)
    return ok2
end

--------------------------------------------------------------------
-- WINDOW
--------------------------------------------------------------------
local root = Instance.new("Frame")
root.Name = "SA_Main"
root.Size = UDim2.fromOffset(300, 0)
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

--------------------------------------------------------------------
-- HEADER
--------------------------------------------------------------------
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

local title = label(header, "SNIPER ARENA", 15, Enum.Font.GothamBold, COL.text)
title.Position = UDim2.fromOffset(16, 0)
title.Size = UDim2.new(1, -90, 0, 30)

local chip = Instance.new("Frame")
chip.Size = UDim2.fromOffset(82, 20)
chip.Position = UDim2.new(1, -82, 0, 5)
chip.BackgroundColor3 = COL.card
chip.BorderSizePixel = 0
chip.Parent = header
corner(chip, 10)

local chipText = label(chip, "MANUAL FIRE", 9, Enum.Font.GothamBold, COL.dim)
chipText.Size = UDim2.fromScale(1, 1)
chipText.TextXAlignment = Enum.TextXAlignment.Center

--------------------------------------------------------------------
-- TARGET CARD
--------------------------------------------------------------------
local card = Instance.new("Frame")
card.Size = UDim2.new(1, 0, 0, 66)
card.BackgroundColor3 = COL.card
card.BorderSizePixel = 0
card.LayoutOrder = 2
card.Parent = root
corner(card, 10)
local cardStroke = stroke(card, COL.line, 1, 0.25)

local cardTag = label(card, "TARGET", 9, Enum.Font.GothamBold, COL.dim)
cardTag.Position = UDim2.fromOffset(12, 8)
cardTag.Size = UDim2.new(1, -24, 0, 12)

local targetName = label(card, "none", 16, Enum.Font.GothamBold, COL.text)
targetName.Position = UDim2.fromOffset(12, 20)
targetName.Size = UDim2.new(1, -24, 0, 22)

local targetSub = label(card, "—", 11, Enum.Font.GothamMedium, COL.dim)
targetSub.Position = UDim2.fromOffset(12, 42)
targetSub.Size = UDim2.new(1, -24, 0, 16)

--------------------------------------------------------------------
-- DISCORD BAR
--------------------------------------------------------------------
local discordBar = Instance.new("TextButton")
discordBar.Size = UDim2.new(1, 0, 0, 34)
discordBar.BackgroundColor3 = COL.card
discordBar.BackgroundTransparency = 0.35
discordBar.BorderSizePixel = 0
discordBar.AutoButtonColor = false
discordBar.Text = ""
discordBar.LayoutOrder = 3
discordBar.Parent = root
corner(discordBar, 8)
local discordStroke = stroke(discordBar, COL.line, 1, 0.4)

local discordTag = label(discordBar, "DISCORD", 9, Enum.Font.GothamBold, COL.dim)
discordTag.Position = UDim2.fromOffset(12, 0)
discordTag.Size = UDim2.fromOffset(64, 34)

local discordValue = label(discordBar, INVITE_UI, 11, Enum.Font.GothamMedium, COL.text)
discordValue.Position = UDim2.fromOffset(72, 0)
discordValue.Size = UDim2.new(1, -132, 1, 0)

local copyBtn = label(discordBar, "COPY", 9, Enum.Font.GothamBold, COL.accent)
copyBtn.Size = UDim2.fromOffset(52, 34)
copyBtn.Position = UDim2.new(1, -58, 0, 0)
copyBtn.TextXAlignment = Enum.TextXAlignment.Center

--------------------------------------------------------------------
-- TOGGLES
--------------------------------------------------------------------
local toggles = Instance.new("Frame")
toggles.Size = UDim2.new(1, 0, 0, 95)
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
    row.Size = UDim2.new(1, 0, 0, 29)
    row.BackgroundColor3 = COL.card
    row.BackgroundTransparency = 0.55
    row.BorderSizePixel = 0
    row.AutoButtonColor = false
    row.Text = ""
    row.LayoutOrder = order
    row.Parent = toggles
    corner(row, 8)

    local lab = label(row, text, 12, Enum.Font.GothamMedium, COL.text)
    lab.Position = UDim2.fromOffset(12, 0)
    lab.Size = UDim2.new(1, -70, 1, 0)

    local pill = Instance.new("Frame")
    pill.Size = UDim2.fromOffset(36, 18)
    pill.Position = UDim2.new(1, -48, 0.5, -9)
    pill.BackgroundColor3 = COL.off
    pill.BorderSizePixel = 0
    pill.Parent = row
    corner(pill, 9)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(14, 14)
    knob.Position = UDim2.fromOffset(2, 2)
    knob.BackgroundColor3 = COL.text
    knob.BorderSizePixel = 0
    knob.Parent = pill
    corner(knob, 7)

    local function paint()
        local on = get()
        pill.BackgroundColor3 = on and COL.accent or COL.off
        knob.Position = on and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)
        lab.TextColor3 = on and COL.text or COL.dim
    end

    row.MouseButton1Click:Connect(function()
        set(not get())
        paint()
    end)

    painters[#painters + 1] = paint
    paint()
end

--------------------------------------------------------------------
-- FOOTER
--------------------------------------------------------------------
local footer = label(root, "F1 hide   F2 lock   F3 esp   F4 discord   F5 mark", 10, Enum.Font.GothamMedium, COL.dim)
footer.Size = UDim2.new(1, 0, 0, 14)
footer.LayoutOrder = 5
footer.TextXAlignment = Enum.TextXAlignment.Center

--------------------------------------------------------------------
-- ENGINE
--------------------------------------------------------------------
local HEAD_NAMES = { "Head", "head", "HeadHitbox", "Hitbox", "Neck" }
local ROOT_NAMES = { "HumanoidRootPart", "UpperTorso", "Torso", "Hips", "Root", "Pelvis", "Hitbox" }
local DEAD_STATES = { PlatformStanding = true, Dead = true }

local function isMine(model)
    local mine = lp.Character
    if not mine then return false end
    if model == mine then return true end
    local ok, r = pcall(function() return model:IsDescendantOf(mine) end)
    return ok and r
end

local function findPart(model, names)
    for i = 1, #names do
        local ok, p = pcall(function() return model:FindFirstChild(names[i], true) end)
        if ok and p and p:IsA("BasePart") then return p end
    end
    return nil
end

local function uuidOf(str)
    if type(str) ~= "string" then return nil end
    return string.match(str, UUID_PAT)
end

local function collect()
    local out, seen = {}, {}
    local queue = { { Workspace, 0 } }
    local i, visited = 1, 0

    while i <= #queue and #out < 180 and visited < 800 do
        local node, depth = queue[i][1], queue[i][2]
        i += 1
        visited += 1

        if depth < 4 then
            local okK, kids = pcall(function() return node:GetChildren() end)
            if okK then
                for k = 1, #kids do
                    local d = kids[k]
                    if d:IsA("Model") and not seen[d] and not isMine(d) then
                        local hum  = d:FindFirstChildOfClass("Humanoid")
                        local head = findPart(d, HEAD_NAMES)
                        local rootPart = findPart(d, ROOT_NAMES)
                        if not rootPart then
                            local okP, pp = pcall(function() return d.PrimaryPart end)
                            if okP and pp then rootPart = pp end
                        end
                        if hum or (head and rootPart) then
                            local okE, size = pcall(function() return d:GetExtentsSize() end)
                            local big = okE and (size.X > 25 or size.Y > 25 or size.Z > 25)
                            if not big then
                                seen[d] = true
                                out[#out + 1] = {
                                    model = d, hum = hum, head = head, root = rootPart,
                                    tag = "?", dead = false, key = nil, real = false,
                                }
                            end
                        end
                    end
                    if d:IsA("Model") or d:IsA("Folder") then
                        queue[#queue + 1] = { d, depth + 1 }
                    end
                end
            end
        end
    end
    return out
end

local function bodyGap(c)
    if not (c.head and c.root) then return nil end
    local ok, hp, rp = pcall(function() return c.head.Position, c.root.Position end)
    if not ok then return nil end
    return hp.Y - rp.Y
end

local function rootVel(c)
    local part = c.root or c.head
    if not part then return 0 end
    local ok, v = pcall(function() return part.AssemblyLinearVelocity.Magnitude end)
    if not ok or not v then return 0 end
    return v
end

local function extents(c)
    local ok, s = pcall(function() return c.model:GetExtentsSize() end)
    if not ok or not s then return nil end
    return s
end

local function posOf(c)
    return (c.head and c.head.Position) or (c.root and c.root.Position) or nil
end

local function stateName(hum)
    if not hum then return "?" end
    local ok, s = pcall(function() return hum:GetState() end)
    if not ok or not s then return "?" end
    return (tostring(s):gsub("Enum%.HumanoidStateType%.", ""))
end

local function isRealPlayer(m)
    local ok, p = pcall(function() return Players:GetPlayerFromCharacter(m) end)
    return ok and p ~= nil
end

local function keyOf(m)
    local ok, v = pcall(function() return m:GetAttribute("_entityModel") end)
    if not (ok and type(v) == "string") then
        local ok2, found = pcall(function()
            for _, d in ipairs(m:GetDescendants()) do
                local a = d:GetAttribute("_entityModel")
                if type(a) == "string" then return a end
            end
            return nil
        end)
        if ok2 and type(found) == "string" then v = found end
    end
    if type(v) ~= "string" then return nil end
    local g = uuidOf(v)
    return g and g:sub(1, 8) or nil
end

local function looksCorpse(c, dY)
    if uuidOf(c.model.Name) then return true end
    if c.hum and c.hum.Health <= 0 then return true end
    if DEAD_STATES[stateName(c.hum)] then return true end
    if dY and dY < CFG.MinUpright then return true end
    return false
end

local function buildRagdolls(now)
    local list, alive = {}, {}

    for n = 1, #State.scan do
        local c = State.scan[n]
        local u = uuidOf(c.model.Name)
        if u then
            local p = posOf(c)
            if p then
                local key = u:sub(1, 8)
                list[#list + 1] = { pos = p, key = key }
                alive[key] = true
                State.corpses[key] = now + CFG.LinkHold
            end
        end
    end

    for key, exp in pairs(State.corpses) do
        if not alive[key] and exp <= now then
            State.corpses[key] = nil
        end
    end

    State.ragdolls = list
end

local function buildSigs()
    local sigs = {}
    for n = 1, #State.scan do
        local c = State.scan[n]
        local dY = bodyGap(c)
        if looksCorpse(c, dY) then
            local p = posOf(c)
            if p then
                local u = uuidOf(c.model.Name)
                sigs[#sigs + 1] = {
                    name  = c.model.Name,
                    pos   = p,
                    key   = u and u:sub(1, 8) or nil,
                    model = c.model,
                }
            end
        end
    end
    State.sigs = sigs

    local counts = {}
    for n = 1, #State.scan do
        local name = State.scan[n].model.Name
        if not uuidOf(name) then
            counts[name] = (counts[name] or 0) + 1
        end
    end
    State.nameCount = counts
end

local function nearestRagdoll(c)
    local p = posOf(c)
    if not p then return nil end
    local best = nil
    for i = 1, #State.ragdolls do
        local d = (State.ragdolls[i].pos - p).Magnitude
        if not best or d < best then best = d end
    end
    return best
end

local function sigLink(c)
    local p = posOf(c)
    if not p then return false end
    for i = 1, #State.sigs do
        local s = State.sigs[i]
        if s.model ~= c.model then
            local sameKey = c.key and s.key and (s.key == c.key)
            local sameName = (
                s.name == c.model.Name
                and not uuidOf(s.name)
                and (State.nameCount[s.name] or 0) <= 2
            )
            if sameKey or sameName then
                if (s.pos - p).Magnitude <= CFG.SigRadius then
                    return true
                end
            end
        end
    end
    return false
end

local function guidLink(now)
    for n = 1, #State.scan do
        local c = State.scan[n]
        if c.key and not c.real then
            local exp = State.corpses[c.key]
            if exp and exp > now then
                State.dead[c.model] = now + CFG.LinkHold
                State.noLink[c.model] = nil
            end
        end
    end
end

local function wakeCheck(now)
    for n = 1, #State.scan do
        local c = State.scan[n]
        local m = c.model
        local exp = State.dead[m]
        if exp and exp > now and not c.real then
            local linked = (c.key and (State.corpses[c.key] or 0) > now)
            local manual = (State.manual[m] or 0) > now
            local dY = bodyGap(c)
            if not linked and not manual and dY and dY >= CFG.MinUpright
                and rootVel(c) > CFG.WakeSpeed then
                State.dead[m] = nil
                State.noLink[m] = now + CFG.WakeHold
            end
        end
    end
end

local function evaluate(now)
    for n = 1, #State.scan do
        local c = State.scan[n]
        local m, hum = c.model, c.hum

        local tag, hold = nil, CFG.DeadHold

        if uuidOf(m.Name) then
            tag = "u"
        elseif hum and hum.Health <= 0 then
            tag = "h"
        elseif DEAD_STATES[stateName(hum)] then
            tag = "s"
        elseif (State.manual[m] or 0) > now then
            tag = "m"
            hold = 0
        elseif c.key and not c.real and (State.corpses[c.key] or 0) > now then
            tag = "l"
            hold = CFG.LinkHold
        elseif not c.real and rootVel(c) < CFG.NameSlack and sigLink(c) then
            tag = "n"
            hold = CFG.SigHold
        else
            local exp = State.dead[m]
            if exp and exp > now then
                tag = "t"
                hold = 0
            else
                local dY = bodyGap(c)
                if dY and dY < CFG.MinUpright then
                    tag = "p"
                else
                    local ex = extents(c)
                    local flat = ex and ex.Y < 3.0 and ex.Y < math.max(ex.X, ex.Z) * 0.85
                    if flat then
                        local t0 = State.flatAt[m]
                        if not t0 then
                            State.flatAt[m] = now
                        elseif now - t0 >= CFG.FlatHold then
                            tag = "b"
                        end
                    else
                        State.flatAt[m] = nil
                    end

                    if not tag then
                        local skip = State.noLink[m]
                        if not (skip and skip > now) then
                            local d = nearestRagdoll(c)
                            if d and d <= CFG.LinkRadius and rootVel(c) < 1.5 then
                                tag = "L"
                                hold = CFG.LinkHold
                            end
                        end
                    end
                end
            end
        end

        if tag and hold > 0 then
            State.dead[m] = now + hold
        end

        c.tag  = tag
        c.dead = tag ~= nil
    end
end

--------------------------------------------------------------------
-- TARGETING
--------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function canSee(from, to, model)
    local list = { model }
    if lp.Character then list[#list + 1] = lp.Character end
    rayParams.FilterDescendantsInstances = list
    local ok, hit = pcall(function() return Workspace:Raycast(from, to - from, rayParams) end)
    if not ok then return true end
    return hit == nil
end

local function isIgnored(now, m)
    local untilT = State.ignored[m]
    if not untilT then return false end
    if now >= untilT then
        State.ignored[m] = nil
        return false
    end
    return true
end

local function pick(now)
    local best, bestScore = nil, math.huge
    local camCF = cam.CFrame
    local camPos, look = camCF.Position, camCF.LookVector
    local visibleCount, total = 0, 0

    for n = 1, #State.scan do
        local c = State.scan[n]
        local m = c.model
        if m.Parent and not c.dead and not isIgnored(now, m) then
            local aimPart = c.head or c.root
            if aimPart and aimPart.Parent then
                local pos   = aimPart.Position
                local delta = pos - camPos
                local dist  = delta.Magnitude
                if dist > 0.1 and dist <= CFG.MaxDist then
                    total += 1
                    local ang = math.deg(math.acos(math.clamp(look:Dot(delta.Unit), -1, 1)))
                    if ang <= CFG.MaxAngle then
                        local vis = (not CFG.VisibleOnly) or canSee(camPos, pos, m)
                        if vis then
                            visibleCount += 1
                            local score = dist + ang * 15
                            if score < bestScore then
                                bestScore = score
                                best = { model = m, pos = pos, dist = dist, ang = ang }
                            end
                        end
                    end
                end
            end
        end
    end

    State.visibles = visibleCount
    State.total    = total
    return best
end

local function aim(target, dt)
    local camPos = cam.CFrame.Position
    local want   = CFrame.lookAt(camPos, target.pos)
    cam.CFrame   = cam.CFrame:Lerp(want, math.clamp(dt * CFG.Smooth, 0, 1))

    if CFG.RotateBody and lp.Character then
        local myHrp = lp.Character:FindFirstChild("HumanoidRootPart")
        if myHrp then
            local wantBody = CFrame.lookAt(myHrp.Position, target.pos)
            myHrp.CFrame = myHrp.CFrame:Lerp(wantBody, math.clamp(dt * 12, 0, 1))
        end
    end
end

--------------------------------------------------------------------
-- ESP
--------------------------------------------------------------------
local DrawingOk = false
do
    local ok = pcall(function()
        local t = Drawing.new("Square")
        t:Remove()
        DrawingOk = true
    end)
end

local boxes = {}

local function boxAt(i)
    if not DrawingOk then return nil end
    local b = boxes[i]
    if not b then
        local ok, res = pcall(function()
            local sq = Drawing.new("Square")
            sq.Thickness = 1
            sq.Filled = false
            sq.Transparency = 1
            local tx = Drawing.new("Text")
            tx.Size = 13
            tx.Center = true
            tx.Outline = true
            tx.Color = Color3.fromRGB(230, 235, 240)
            return { sq = sq, txt = tx }
        end)
        if not ok or not res then
            DrawingOk = false
            return nil
        end
        boxes[i] = res
        b = res
    end
    return b
end

local function drawEsp()
    if not DrawingOk then return end
    local used = 0

    for n = 1, #State.scan do
        local c = State.scan[n]
        local part = c.root or c.head
        if c.model.Parent and part and part.Parent and not c.dead then
            local sp, onScreen = cam:WorldToViewportPoint(part.Position)
            if onScreen and sp.Z > 0 then
                used += 1
                if used <= 40 then
                    local b = boxAt(used)
                    if b then
                        local w, h = 40, 70
                        b.sq.Size     = Vector2.new(w, h)
                        b.sq.Position = Vector2.new(sp.X - w * 0.5, sp.Y - h)
                        b.sq.Color    = COL.accent
                        b.sq.Visible  = CFG.ESP
                        b.txt.Text     = c.model.Name
                        b.txt.Position = Vector2.new(sp.X, sp.Y - h - 16)
                        b.txt.Visible  = CFG.ESP
                    end
                end
            end
        end
    end

    for n = used + 1, #boxes do
        local b = boxes[n]
        if b then
            b.sq.Visible  = false
            b.txt.Visible = false
        end
    end
end

--------------------------------------------------------------------
-- UI REFRESH
--------------------------------------------------------------------
local function refreshUi(now)
    local t = State.target

    if t then
        targetName.Text = tostring(t.model.Name):sub(1, 20)
        targetName.TextColor3 = COL.text
        targetSub.Text = string.format("%.0f m   angle %.0f°", t.dist, t.ang)
        cardStroke.Color = COL.accent
        cardStroke.Transparency = 0.15
        dot.BackgroundColor3 = COL.accent
    else
        targetName.Text = "none"
        targetName.TextColor3 = COL.dim
        targetSub.Text = string.format("%d visible / %d", State.visibles, State.total)
        cardStroke.Color = COL.line
        cardStroke.Transparency = 0.25
        dot.BackgroundColor3 = State.errors > 0 and COL.danger or COL.off
    end

    if now < State.copyUntil then
        copyBtn.Text = "COPIED"
        copyBtn.TextColor3 = COL.accent
        discordStroke.Color = COL.accent
        discordStroke.Transparency = 0.2
    else
        copyBtn.Text = "COPY"
        copyBtn.TextColor3 = COL.accent
        discordStroke.Color = COL.line
        discordStroke.Transparency = 0.4
    end
end

--------------------------------------------------------------------
-- DISCORD COPY
--------------------------------------------------------------------
local function copyInvite()
    local ok = copyText(INVITE)
    State.copyUntil = os.clock() + 1.5
    if not ok then
        discordValue.Text = INVITE
    end
end

discordBar.MouseButton1Click:Connect(copyInvite)

--------------------------------------------------------------------
-- LOOP
--------------------------------------------------------------------
local lastScan, lastUi = 0, 0

local function onRender(dt)
    local ok = pcall(function()
        dt = math.clamp(dt or 0, 0, 0.1)
        if not cam or not cam.Parent then
            cam = Workspace.CurrentCamera
            if not cam then return end
        end
        local now = os.clock()

        if now - lastScan >= CFG.ScanRate then
            lastScan = now
            State.scan = collect()

            for n = 1, #State.scan do
                local c = State.scan[n]
                c.key  = keyOf(c.model)
                c.real = isRealPlayer(c.model)
            end

            for m in pairs(State.dead) do
                if not m.Parent then State.dead[m] = nil end
            end
            for m in pairs(State.manual) do
                if not m.Parent then State.manual[m] = nil end
            end
            for m in pairs(State.noLink) do
                if not m.Parent then State.noLink[m] = nil end
            end
            for m in pairs(State.flatAt) do
                if not m.Parent then State.flatAt[m] = nil end
            end

            buildRagdolls(now)
            buildSigs()
            guidLink(now)
            wakeCheck(now)
            evaluate(now)
        end

        if CFG.Enabled then
            local t = pick(now)
            State.target = t
            if t then aim(t, dt) end
        else
            State.target = nil
        end

        if CFG.ESP then
            local okEsp = pcall(drawEsp)
            if not okEsp then DrawingOk = false end
        end

        if now - lastUi >= 0.1 then
            lastUi = now
            refreshUi(now)
        end
    end)

    if not ok then
        State.errors = State.errors + 1
    end
end

pcall(function() RunService:UnbindFromRenderStep("SniperArena47") end)
RunService:BindToRenderStep("SniperArena47", 201, onRender)

--------------------------------------------------------------------
-- TOGGLES
--------------------------------------------------------------------
makeToggle(1, "Lock-On", function() return CFG.Enabled end, function(v) CFG.Enabled = v end)
makeToggle(2, "ESP", function() return CFG.ESP end, function(v) CFG.ESP = v end)
makeToggle(3, "Line of Sight", function() return CFG.VisibleOnly end, function(v) CFG.VisibleOnly = v end)

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
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
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
-- KEYS
--------------------------------------------------------------------
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    local k = input.KeyCode

    if k == Enum.KeyCode.F1 then
        CFG.UiVisible = not CFG.UiVisible
        root.Visible = CFG.UiVisible
    elseif k == Enum.KeyCode.F2 then
        CFG.Enabled = not CFG.Enabled
        for _, p in ipairs(painters) do p() end
    elseif k == Enum.KeyCode.F3 then
        CFG.ESP = not CFG.ESP
        for _, p in ipairs(painters) do p() end
    elseif k == Enum.KeyCode.F4 then
        copyInvite()
    elseif k == Enum.KeyCode.F5 then
        local t = State.target
        if t then
            local m = t.model
            if (State.manual[m] or 0) > os.clock() then
                State.manual[m] = nil
                State.dead[m] = nil
            else
                State.manual[m] = os.clock() + CFG.ManualHold
            end
        end
    end
end)

--------------------------------------------------------------------
-- SHUTDOWN
--------------------------------------------------------------------
local function shutdown()
    pcall(function() RunService:UnbindFromRenderStep("SniperArena47") end)
    pcall(function() gui:Destroy() end)
    if DrawingOk then
        for _, b in pairs(boxes) do
            pcall(function() b.sq:Remove() end)
            pcall(function() b.txt:Remove() end)
        end
    end
end

_G.SNIPER47 = { shutdown = shutdown }

--------------------------------------------------------------------
-- START
--------------------------------------------------------------------
State.scan = collect()
for n = 1, #State.scan do
    local c = State.scan[n]
    c.key  = keyOf(c.model)
    c.real = isRealPlayer(c.model)
end
buildRagdolls(os.clock())
buildSigs()
evaluate(os.clock())
refreshUi(os.clock())
