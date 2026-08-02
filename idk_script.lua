-- idk script | ENI for LO

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")

local Event = ReplicatedStorage.Network.GardenChanceMachine_AddTime

local RENEW_INTERVAL = 55
local lastRenew = {}

local MACHINES = {
    { tier = "Huge",       slot = "Slot1", label = "Extra Huge Luck",  enabled = false, count = 0 },
    { tier = "Titanic",    slot = "Slot1", label = "Titanic Luck",     enabled = false, count = 0 },
    { tier = "Gargantuan", slot = "Slot1", label = "Gargantuan Luck",  enabled = false, count = 0 },
}

-- ═══════════════════════════════════════
--  SCREEN GUI
-- ═══════════════════════════════════════
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "idk_script"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════
--  STAR BUTTON
-- ═══════════════════════════════════════
local StarBtn = Instance.new("TextButton")
StarBtn.Size = UDim2.new(0, 52, 0, 52)
StarBtn.Position = UDim2.new(0, 20, 0.5, -26)
StarBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
StarBtn.BorderSizePixel = 0
StarBtn.Text = ""
StarBtn.Visible = false
StarBtn.ZIndex = 10
StarBtn.Parent = ScreenGui
Instance.new("UICorner", StarBtn).CornerRadius = UDim.new(1, 0)

Instance.new("UIStroke", StarBtn).Color = Color3.fromRGB(200, 155, 40)

local StarLabel = Instance.new("TextLabel")
StarLabel.Size = UDim2.new(1, 0, 1, 0)
StarLabel.BackgroundTransparency = 1
StarLabel.Text = "★"
StarLabel.TextColor3 = Color3.fromRGB(240, 185, 40)
StarLabel.TextSize = 28
StarLabel.Font = Enum.Font.GothamBold
StarLabel.ZIndex = 10
StarLabel.Parent = StarBtn

local pulseTween = TweenService:Create(StarLabel,
    TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
    { TextColor3 = Color3.fromRGB(255, 220, 80) }
)

-- star drag
local starDragging, starDragStart, starPosStart = false, nil, nil
StarBtn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        starDragging = true
        starDragStart = i.Position
        starPosStart = StarBtn.Position
    end
end)
StarBtn.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        starDragging = false
    end
end)
UIS.InputChanged:Connect(function(i)
    if starDragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - starDragStart
        StarBtn.Position = UDim2.new(
            starPosStart.X.Scale, starPosStart.X.Offset + d.X,
            starPosStart.Y.Scale, starPosStart.Y.Offset + d.Y
        )
    end
end)

-- ═══════════════════════════════════════
--  MAIN FRAME
-- ═══════════════════════════════════════
local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 440, 0, 340)
Frame.Position = UDim2.new(0.5, -220, 0.3, -170)
Frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Draggable = true
Frame.ClipsDescendants = true
Frame.Parent = ScreenGui
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 7)
Instance.new("UIStroke", Frame).Color = Color3.fromRGB(44, 44, 44)

-- ── Title bar ──
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 38)
TitleBar.Position = UDim2.new(0, 0, 0, 0)
TitleBar.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
TitleBar.BorderSizePixel = 0
TitleBar.ZIndex = 2
TitleBar.Parent = Frame

local AccentLine = Instance.new("Frame")
AccentLine.Size = UDim2.new(1, 0, 0, 2)
AccentLine.Position = UDim2.new(0, 0, 1, -2)
AccentLine.BackgroundColor3 = Color3.fromRGB(105, 75, 215)
AccentLine.BorderSizePixel = 0
AccentLine.ZIndex = 3
AccentLine.Parent = TitleBar

local TitleText = Instance.new("TextLabel")
TitleText.Size = UDim2.new(1, -90, 1, 0)
TitleText.Position = UDim2.new(0, 14, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text = "idk script"
TitleText.TextColor3 = Color3.fromRGB(205, 205, 205)
TitleText.TextSize = 13
TitleText.Font = Enum.Font.GothamBold
TitleText.TextXAlignment = Enum.TextXAlignment.Left
TitleText.ZIndex = 2
TitleText.Parent = TitleBar

local VerTag = Instance.new("TextLabel")
VerTag.Size = UDim2.new(0, 28, 1, 0)
VerTag.Position = UDim2.new(1, -88, 0, 0)
VerTag.BackgroundTransparency = 1
VerTag.Text = "v6"
VerTag.TextColor3 = Color3.fromRGB(58, 58, 58)
VerTag.TextSize = 11
VerTag.Font = Enum.Font.Gotham
VerTag.ZIndex = 2
VerTag.Parent = TitleBar

local function makeTitleBtn(xOff, bg, sym)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 22, 0, 22)
    b.Position = UDim2.new(1, xOff, 0.5, -11)
    b.BackgroundColor3 = bg
    b.BorderSizePixel = 0
    b.Text = sym
    b.TextColor3 = Color3.fromRGB(200, 200, 200)
    b.TextSize = 12
    b.Font = Enum.Font.GothamBold
    b.ZIndex = 3
    b.Parent = TitleBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
    return b
end

local MinBtn   = makeTitleBtn(-54, Color3.fromRGB(175, 135, 25), "—")
local CloseBtn = makeTitleBtn(-28, Color3.fromRGB(155, 40, 40),  "×")

-- ═══════════════════════════════════════
--  SIDEBAR  (manual positions, no layout)
-- ═══════════════════════════════════════
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 100, 1, -40)
Sidebar.Position = UDim2.new(0, 0, 0, 40)
Sidebar.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
Sidebar.BorderSizePixel = 0
Sidebar.ZIndex = 2
Sidebar.Parent = Frame

-- right border
local SideLine = Instance.new("Frame")
SideLine.Size = UDim2.new(0, 1, 1, 0)
SideLine.Position = UDim2.new(1, -1, 0, 0)
SideLine.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
SideLine.BorderSizePixel = 0
SideLine.Parent = Sidebar

-- ═══════════════════════════════════════
--  CONTENT AREA
-- ═══════════════════════════════════════
local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -102, 1, -42)
ContentArea.Position = UDim2.new(0, 102, 0, 42)
ContentArea.BackgroundTransparency = 1
ContentArea.BorderSizePixel = 0
ContentArea.Parent = Frame

-- ═══════════════════════════════════════
--  PAGES + TAB BUTTONS  (manual y pos)
-- ═══════════════════════════════════════
local TABS = { "main", "auto farm", "event" }
local tabButtons = {}
local tabPages   = {}

for _, name in ipairs(TABS) do
    local page = Instance.new("Frame")
    page.Size = UDim2.new(1, 0, 1, 0)
    page.Position = UDim2.new(0, 0, 0, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.Visible = false
    page.Parent = ContentArea
    tabPages[name] = page
end

local function switchTab(name)
    for _, n in ipairs(TABS) do
        tabPages[n].Visible = (n == name)
        local b = tabButtons[n]
        if b then
            if n == name then
                b.BackgroundColor3 = Color3.fromRGB(30, 24, 52)
                b.TextColor3 = Color3.fromRGB(200, 190, 230)
                b.ActiveBar.Visible = true
            else
                b.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
                b.TextColor3 = Color3.fromRGB(70, 70, 70)
                b.ActiveBar.Visible = false
            end
        end
    end
end

-- build tab buttons with explicit Y positions
local tabYPositions = { 12, 52, 92 }
for i, name in ipairs(TABS) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 84, 0, 32)
    btn.Position = UDim2.new(0, 8, 0, tabYPositions[i])
    btn.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
    btn.BorderSizePixel = 0
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(70, 70, 70)
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamBold
    btn.ZIndex = 3
    btn.Parent = Sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    tabButtons[name] = btn

    local bar = Instance.new("Frame")
    bar.Name = "ActiveBar"
    bar.Size = UDim2.new(0, 3, 0.6, 0)
    bar.Position = UDim2.new(0, 0, 0.2, 0)
    bar.BackgroundColor3 = Color3.fromRGB(110, 80, 220)
    bar.BorderSizePixel = 0
    bar.Visible = false
    bar.ZIndex = 4
    bar.Parent = btn
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    btn.MouseButton1Click:Connect(function() switchTab(name) end)
end

-- ═══════════════════════════════════════
--  EVENT PAGE
-- ═══════════════════════════════════════
local eventPage = tabPages["event"]

local SectionLbl = Instance.new("TextLabel")
SectionLbl.Size = UDim2.new(1, -16, 0, 18)
SectionLbl.Position = UDim2.new(0, 10, 0, 8)
SectionLbl.BackgroundTransparency = 1
SectionLbl.Text = "luck machine renewer"
SectionLbl.TextColor3 = Color3.fromRGB(60, 60, 60)
SectionLbl.TextSize = 10
SectionLbl.Font = Enum.Font.Gotham
SectionLbl.TextXAlignment = Enum.TextXAlignment.Left
SectionLbl.Parent = eventPage

local DotRow = Instance.new("Frame")
DotRow.Size = UDim2.new(1, -16, 0, 18)
DotRow.Position = UDim2.new(0, 10, 0, 28)
DotRow.BackgroundTransparency = 1
DotRow.Parent = eventPage

local StatusDot = Instance.new("Frame")
StatusDot.Size = UDim2.new(0, 7, 0, 7)
StatusDot.Position = UDim2.new(0, 0, 0.5, -3)
StatusDot.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
StatusDot.BorderSizePixel = 0
StatusDot.Parent = DotRow
Instance.new("UICorner", StatusDot).CornerRadius = UDim.new(1, 0)

local StatusLbl = Instance.new("TextLabel")
StatusLbl.Size = UDim2.new(1, -14, 1, 0)
StatusLbl.Position = UDim2.new(0, 14, 0, 0)
StatusLbl.BackgroundTransparency = 1
StatusLbl.Text = "idle"
StatusLbl.TextColor3 = Color3.fromRGB(60, 60, 60)
StatusLbl.TextSize = 10
StatusLbl.Font = Enum.Font.Gotham
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
StatusLbl.Parent = DotRow

local function updateStatus()
    local any = false
    for _, m in ipairs(MACHINES) do if m.enabled then any = true break end end
    if any then
        StatusDot.BackgroundColor3 = Color3.fromRGB(110, 80, 220)
        StatusLbl.Text             = "running"
        StatusLbl.TextColor3       = Color3.fromRGB(138, 118, 200)
    else
        StatusDot.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        StatusLbl.Text             = "idle"
        StatusLbl.TextColor3       = Color3.fromRGB(60, 60, 60)
    end
end

local function fireRenew(machine)
    local ok, err = pcall(function()
        Event:InvokeServer(machine.tier, machine.slot, 600)
    end)
    if ok then machine.count += 1
    else warn("[idk] -> " .. machine.tier .. ": " .. tostring(err)) end
end

local function makeCheckbox(machine, yPos)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, -16, 0, 36)
    Row.Position = UDim2.new(0, 8, 0, yPos)
    Row.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
    Row.BorderSizePixel = 0
    Row.Parent = eventPage
    Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 5)

    local RS = Instance.new("UIStroke")
    RS.Color = Color3.fromRGB(36, 36, 36)
    RS.Thickness = 1
    RS.Parent = Row

    local Box = Instance.new("Frame")
    Box.Size = UDim2.new(0, 15, 0, 15)
    Box.Position = UDim2.new(0, 10, 0.5, -7)
    Box.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    Box.BorderSizePixel = 0
    Box.Parent = Row
    Instance.new("UICorner", Box).CornerRadius = UDim.new(0, 3)

    local BS = Instance.new("UIStroke")
    BS.Color = Color3.fromRGB(60, 60, 60)
    BS.Thickness = 1
    BS.Parent = Box

    local Fill = Instance.new("Frame")
    Fill.Size = UDim2.new(0, 7, 0, 7)
    Fill.Position = UDim2.new(0.5, -3, 0.5, -3)
    Fill.BackgroundColor3 = Color3.fromRGB(110, 80, 220)
    Fill.BorderSizePixel = 0
    Fill.Visible = false
    Fill.Parent = Box
    Instance.new("UICorner", Fill).CornerRadius = UDim.new(0, 2)

    local Lbl = Instance.new("TextLabel")
    Lbl.Size = UDim2.new(1, -55, 1, 0)
    Lbl.Position = UDim2.new(0, 32, 0, 0)
    Lbl.BackgroundTransparency = 1
    Lbl.Text = machine.label
    Lbl.TextColor3 = Color3.fromRGB(86, 86, 86)
    Lbl.TextSize = 12
    Lbl.Font = Enum.Font.Gotham
    Lbl.TextXAlignment = Enum.TextXAlignment.Left
    Lbl.Parent = Row

    local Ctr = Instance.new("TextLabel")
    Ctr.Size = UDim2.new(0, 30, 0, 16)
    Ctr.Position = UDim2.new(1, -38, 0.5, -8)
    Ctr.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    Ctr.BorderSizePixel = 0
    Ctr.Text = "0"
    Ctr.TextColor3 = Color3.fromRGB(66, 66, 66)
    Ctr.TextSize = 10
    Ctr.Font = Enum.Font.GothamBold
    Ctr.TextXAlignment = Enum.TextXAlignment.Center
    Ctr.Parent = Row
    Instance.new("UICorner", Ctr).CornerRadius = UDim.new(0, 3)

    local function setActive(state)
        machine.enabled = state
        Fill.Visible = state
        BS.Color             = state and Color3.fromRGB(110, 80, 220) or Color3.fromRGB(60, 60, 60)
        Box.BackgroundColor3 = state and Color3.fromRGB(20, 16, 36)  or Color3.fromRGB(30, 30, 30)
        Lbl.TextColor3       = state and Color3.fromRGB(192, 185, 215) or Color3.fromRGB(86, 86, 86)
        RS.Color             = state and Color3.fromRGB(70, 46, 140) or Color3.fromRGB(36, 36, 36)
        Row.BackgroundColor3 = state and Color3.fromRGB(26, 20, 44)  or Color3.fromRGB(26, 26, 26)
        Ctr.TextColor3       = state and Color3.fromRGB(132, 112, 198) or Color3.fromRGB(66, 66, 66)
    end

    RunService.Heartbeat:Connect(function()
        Ctr.Text = tostring(machine.count)
    end)

    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 1, 0)
    Btn.BackgroundTransparency = 1
    Btn.Text = ""
    Btn.Parent = Row

    Btn.MouseButton1Click:Connect(function()
        local s = not machine.enabled
        setActive(s)
        updateStatus()
        if s then
            fireRenew(machine)
            lastRenew[machine.tier] = tick()
        end
    end)
end

makeCheckbox(MACHINES[1], 52)
makeCheckbox(MACHINES[2], 94)
makeCheckbox(MACHINES[3], 136)

-- ═══════════════════════════════════════
--  MINIMIZE / CLOSE
-- ═══════════════════════════════════════
MinBtn.MouseButton1Click:Connect(function()
    Frame.Visible = false
    StarBtn.Visible = true
    pulseTween:Play()
end)

StarBtn.MouseButton1Click:Connect(function()
    if not starDragging then
        Frame.Visible = true
        StarBtn.Visible = false
        pulseTween:Cancel()
        StarLabel.TextColor3 = Color3.fromRGB(240, 185, 40)
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- ═══════════════════════════════════════
--  LOOP
-- ═══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    local now = tick()
    for _, m in ipairs(MACHINES) do
        if m.enabled then
            local last = lastRenew[m.tier] or 0
            if now - last >= RENEW_INTERVAL then
                lastRenew[m.tier] = now
                fireRenew(m)
            end
        end
    end
end)

switchTab("main")