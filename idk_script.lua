-- idk script 

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ContentProvider = game:GetService("ContentProvider")

-- ═══════════════════════════════════════
--  CONFIGURATION (SAVE/LOAD)
-- ═══════════════════════════════════════
local CONFIG_FILE = "idk_script_config.json"

local config = {
    antiKick = false,
    machines = {
        Huge = false,
        Titanic = false,
        Gargantuan = false
    }
}

local function saveConfig()
    if writefile then
        local success, err = pcall(function()
            writefile(CONFIG_FILE, HttpService:JSONEncode(config))
        end)
        if not success then
            warn("[idk script] Failed to save config: " .. tostring(err))
        end
    end
end

local function loadConfig()
    if isfile and readfile and isfile(CONFIG_FILE) then
        local success, result = pcall(function()
            return HttpService:JSONDecode(readfile(CONFIG_FILE))
        end)
        if success and type(result) == "table" then
            if type(result.antiKick) == "boolean" then
                config.antiKick = result.antiKick
            end
            if type(result.machines) == "table" then
                for k, v in pairs(result.machines) do
                    if type(v) == "boolean" then
                        config.machines[k] = v
                    end
                end
            end
        end
    end
end

loadConfig()

-- ═══════════════════════════════════════
--  ANTI-KICK / ANTI-AFK STATE
-- ═══════════════════════════════════════
local VirtualUser = game:GetService("VirtualUser")
local antiKickEnabled = false
local antiKickStartTime = nil
local antiKickCount = 0

local function simulateActivity()
    local success = pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
    if not success then
        local vu = game:GetService("VirtualUser")
        vu:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
        task.wait(1)
        vu:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
    end
end

Players.LocalPlayer.Idled:Connect(function()
    if antiKickEnabled then
        simulateActivity()
        antiKickCount += 1
    end
end)

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
--  ICON
-- ═══════════════════════════════════════

local ICON_DECAL_ID = "72164665440799"

local StarBtn = Instance.new("TextButton")
StarBtn.Size = UDim2.new(0, 52, 0, 52)
StarBtn.Position = UDim2.new(0, 20, 0.5, -26)
StarBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
StarBtn.BorderSizePixel = 0
StarBtn.Text = ""
StarBtn.Visible = false
StarBtn.ZIndex = 10
StarBtn.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(1, 0)
Corner.Parent = StarBtn

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(62, 62, 62)
Stroke.Parent = StarBtn

local StarFallback = Instance.new("TextLabel")
StarFallback.Size = UDim2.new(1, 0, 1, 0)
StarFallback.BackgroundTransparency = 1
StarFallback.Text = "*"
StarFallback.TextColor3 = Color3.fromRGB(185, 185, 185)
StarFallback.TextSize = 34
StarFallback.Font = Enum.Font.GothamBold
StarFallback.ZIndex = 9
StarFallback.Parent = StarBtn

-- Ikona
local StarIcon = Instance.new("ImageLabel")
StarIcon.Size = UDim2.new(0.86, 0, 0.86, 0)
StarIcon.Position = UDim2.new(0.07, 0, 0.07, 0)
StarIcon.BackgroundTransparency = 1
StarIcon.Image = "rbxassetid://" .. ICON_DECAL_ID
StarIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
StarIcon.ScaleType = Enum.ScaleType.Fit
StarIcon.ZIndex = 10
StarIcon.Parent = StarBtn

local function resolveIconImage()
    local ok, objects = pcall(function()
        return game:GetObjects("rbxassetid://" .. ICON_DECAL_ID)
    end)

    if ok and type(objects) == "table" then
        local decal = objects[1]
        if decal and decal:IsA("Decal") and decal.Texture ~= "" then
            StarIcon.Image = decal.Texture
        end
    end

    pcall(function()
        ContentProvider:PreloadAsync({ StarIcon })
    end)

    if StarIcon.Image ~= "" then
        StarFallback.Visible = false
    end
end

task.spawn(resolveIconImage)

-- Pulsowanie obramowania
local pulseTween = TweenService:Create(
    Stroke,
    TweenInfo.new(
        0.85,
        Enum.EasingStyle.Sine,
        Enum.EasingDirection.InOut,
        -1,
        true
    ),
    {
        Color = Color3.fromRGB(125, 125, 125)
    }
)

pulseTween:Play()

-- star drag
local starDragging = false
local starMoved    = false
local starDragStart, starPosStart

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
--  SIDEBAR
-- ═══════════════════════════════════════
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 100, 1, -40)
Sidebar.Position = UDim2.new(0, 0, 0, 40)
Sidebar.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
Sidebar.BorderSizePixel = 0
Sidebar.ZIndex = 2
Sidebar.Parent = Frame

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
--  PAGES + TAB BUTTONS
-- ═══════════════════════════════════════
local TABS = { "main", "auto farm", "event", "misc" }
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

local tabYPositions = { 12, 52, 92, 132 }
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
        config.machines[machine.tier] = state
        saveConfig()
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

    if config.machines[machine.tier] then
        setActive(true)
        updateStatus()
    end
end

makeCheckbox(MACHINES[1], 52)
makeCheckbox(MACHINES[2], 94)
makeCheckbox(MACHINES[3], 136)

-- ═══════════════════════════════════════
--  MISC PAGE
-- ═══════════════════════════════════════
local miscPage = tabPages["misc"]

local MiscSectionLbl = Instance.new("TextLabel")
MiscSectionLbl.Size = UDim2.new(1, -16, 0, 18)
MiscSectionLbl.Position = UDim2.new(0, 10, 0, 8)
MiscSectionLbl.BackgroundTransparency = 1
MiscSectionLbl.Text = "anti-kick"
MiscSectionLbl.TextColor3 = Color3.fromRGB(60, 60, 60)
MiscSectionLbl.TextSize = 10
MiscSectionLbl.Font = Enum.Font.Gotham
MiscSectionLbl.TextXAlignment = Enum.TextXAlignment.Left
MiscSectionLbl.Parent = miscPage

local AKDotRow = Instance.new("Frame")
AKDotRow.Size = UDim2.new(1, -16, 0, 18)
AKDotRow.Position = UDim2.new(0, 10, 0, 28)
AKDotRow.BackgroundTransparency = 1
AKDotRow.Parent = miscPage

local AKStatusDot = Instance.new("Frame")
AKStatusDot.Size = UDim2.new(0, 7, 0, 7)
AKStatusDot.Position = UDim2.new(0, 0, 0.5, -3)
AKStatusDot.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
AKStatusDot.BorderSizePixel = 0
AKStatusDot.Parent = AKDotRow
Instance.new("UICorner", AKStatusDot).CornerRadius = UDim.new(1, 0)

local AKStatusLbl = Instance.new("TextLabel")
AKStatusLbl.Size = UDim2.new(1, -14, 1, 0)
AKStatusLbl.Position = UDim2.new(0, 14, 0, 0)
AKStatusLbl.BackgroundTransparency = 1
AKStatusLbl.Text = "disabled"
AKStatusLbl.TextColor3 = Color3.fromRGB(60, 60, 60)
AKStatusLbl.TextSize = 10
AKStatusLbl.Font = Enum.Font.Gotham
AKStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
AKStatusLbl.Parent = AKDotRow

local AKRow = Instance.new("Frame")
AKRow.Size = UDim2.new(1, -16, 0, 36)
AKRow.Position = UDim2.new(0, 8, 0, 52)
AKRow.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
AKRow.BorderSizePixel = 0
AKRow.Parent = miscPage
Instance.new("UICorner", AKRow).CornerRadius = UDim.new(0, 5)

local AKRS = Instance.new("UIStroke")
AKRS.Color = Color3.fromRGB(36, 36, 36)
AKRS.Thickness = 1
AKRS.Parent = AKRow

local AKBox = Instance.new("Frame")
AKBox.Size = UDim2.new(0, 15, 0, 15)
AKBox.Position = UDim2.new(0, 10, 0.5, -7)
AKBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
AKBox.BorderSizePixel = 0
AKBox.Parent = AKRow
Instance.new("UICorner", AKBox).CornerRadius = UDim.new(0, 3)

local AKBS = Instance.new("UIStroke")
AKBS.Color = Color3.fromRGB(60, 60, 60)
AKBS.Thickness = 1
AKBS.Parent = AKBox

local AKFill = Instance.new("Frame")
AKFill.Size = UDim2.new(0, 7, 0, 7)
AKFill.Position = UDim2.new(0.5, -3, 0.5, -3)
AKFill.BackgroundColor3 = Color3.fromRGB(110, 80, 220)
AKFill.BorderSizePixel = 0
AKFill.Visible = false
AKFill.Parent = AKBox
Instance.new("UICorner", AKFill).CornerRadius = UDim.new(0, 2)

local AKLbl = Instance.new("TextLabel")
AKLbl.Size = UDim2.new(1, -55, 1, 0)
AKLbl.Position = UDim2.new(0, 32, 0, 0)
AKLbl.BackgroundTransparency = 1
AKLbl.Text = "Anti-Kick"
AKLbl.TextColor3 = Color3.fromRGB(86, 86, 86)
AKLbl.TextSize = 12
AKLbl.Font = Enum.Font.Gotham
AKLbl.TextXAlignment = Enum.TextXAlignment.Left
AKLbl.Parent = AKRow

local function setAntiKickActive(state)
    antiKickEnabled = state
    AKFill.Visible = state
    AKBS.Color             = state and Color3.fromRGB(110, 80, 220) or Color3.fromRGB(60, 60, 60)
    AKBox.BackgroundColor3 = state and Color3.fromRGB(20, 16, 36)  or Color3.fromRGB(30, 30, 30)
    AKLbl.TextColor3       = state and Color3.fromRGB(192, 185, 215) or Color3.fromRGB(86, 86, 86)
    AKRS.Color             = state and Color3.fromRGB(70, 46, 140) or Color3.fromRGB(36, 36, 36)
    AKRow.BackgroundColor3 = state and Color3.fromRGB(26, 20, 44)  or Color3.fromRGB(26, 26, 26)
    if state then
        antiKickStartTime = tick()
        AKStatusDot.BackgroundColor3 = Color3.fromRGB(110, 80, 220)
        AKStatusLbl.Text = "active"
        AKStatusLbl.TextColor3 = Color3.fromRGB(138, 118, 200)
    else
        antiKickStartTime = nil
        AKStatusDot.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        AKStatusLbl.Text = "disabled"
        AKStatusLbl.TextColor3 = Color3.fromRGB(60, 60, 60)
    end
    config.antiKick = state
    saveConfig()
end

local AKBtn = Instance.new("TextButton")
AKBtn.Size = UDim2.new(1, 0, 1, 0)
AKBtn.BackgroundTransparency = 1
AKBtn.Text = ""
AKBtn.Parent = AKRow
AKBtn.MouseButton1Click:Connect(function()
    setAntiKickActive(not antiKickEnabled)
end)

if config.antiKick then
    setAntiKickActive(true)
end

-- uptime
local UptimeRow = Instance.new("Frame")
UptimeRow.Size = UDim2.new(1, -16, 0, 44)
UptimeRow.Position = UDim2.new(0, 8, 0, 98)
UptimeRow.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
UptimeRow.BorderSizePixel = 0
UptimeRow.Parent = miscPage
Instance.new("UICorner", UptimeRow).CornerRadius = UDim.new(0, 5)

local UptimeRS = Instance.new("UIStroke")
UptimeRS.Color = Color3.fromRGB(36, 36, 36)
UptimeRS.Thickness = 1
UptimeRS.Parent = UptimeRow

local UptimeTitleLbl = Instance.new("TextLabel")
UptimeTitleLbl.Size = UDim2.new(1, -40, 0, 16)
UptimeTitleLbl.Position = UDim2.new(0, 34, 0, 4)
UptimeTitleLbl.BackgroundTransparency = 1
UptimeTitleLbl.Text = "uptime"
UptimeTitleLbl.TextColor3 = Color3.fromRGB(60, 60, 60)
UptimeTitleLbl.TextSize = 9
UptimeTitleLbl.Font = Enum.Font.Gotham
UptimeTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
UptimeTitleLbl.Parent = UptimeRow

local UptimeValueLbl = Instance.new("TextLabel")
UptimeValueLbl.Size = UDim2.new(1, -40, 0, 20)
UptimeValueLbl.Position = UDim2.new(0, 34, 0, 20)
UptimeValueLbl.BackgroundTransparency = 1
UptimeValueLbl.Text = "00:00:00"
UptimeValueLbl.TextColor3 = Color3.fromRGB(86, 86, 86)
UptimeValueLbl.TextSize = 14
UptimeValueLbl.Font = Enum.Font.GothamBold
UptimeValueLbl.TextXAlignment = Enum.TextXAlignment.Left
UptimeValueLbl.Parent = UptimeRow

local KicksRow = Instance.new("Frame")
KicksRow.Size = UDim2.new(1, -16, 0, 44)
KicksRow.Position = UDim2.new(0, 8, 0, 150)
KicksRow.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
KicksRow.BorderSizePixel = 0
KicksRow.Parent = miscPage
Instance.new("UICorner", KicksRow).CornerRadius = UDim.new(0, 5)

local KicksRS = Instance.new("UIStroke")
KicksRS.Color = Color3.fromRGB(36, 36, 36)
KicksRS.Thickness = 1
KicksRS.Parent = KicksRow

local KicksTitleLbl = Instance.new("TextLabel")
KicksTitleLbl.Size = UDim2.new(1, -40, 0, 16)
KicksTitleLbl.Position = UDim2.new(0, 34, 0, 4)
KicksTitleLbl.BackgroundTransparency = 1
KicksTitleLbl.Text = "kicks prevented"
KicksTitleLbl.TextColor3 = Color3.fromRGB(60, 60, 60)
KicksTitleLbl.TextSize = 9
KicksTitleLbl.Font = Enum.Font.Gotham
KicksTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
KicksTitleLbl.Parent = KicksRow

local KicksValueLbl = Instance.new("TextLabel")
KicksValueLbl.Size = UDim2.new(1, -40, 0, 20)
KicksValueLbl.Position = UDim2.new(0, 34, 0, 20)
KicksValueLbl.BackgroundTransparency = 1
KicksValueLbl.Text = "0"
KicksValueLbl.TextColor3 = Color3.fromRGB(86, 86, 86)
KicksValueLbl.TextSize = 14
KicksValueLbl.Font = Enum.Font.GothamBold
KicksValueLbl.TextXAlignment = Enum.TextXAlignment.Left
KicksValueLbl.Parent = KicksRow

local function formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

RunService.Heartbeat:Connect(function()
    if antiKickEnabled and antiKickStartTime then
        UptimeValueLbl.Text = formatTime(tick() - antiKickStartTime)
        UptimeValueLbl.TextColor3 = Color3.fromRGB(132, 112, 198)
        UptimeRS.Color = Color3.fromRGB(70, 46, 140)
        UptimeRow.BackgroundColor3 = Color3.fromRGB(26, 20, 44)
    else
        UptimeValueLbl.Text = "00:00:00"
        UptimeValueLbl.TextColor3 = Color3.fromRGB(86, 86, 86)
        UptimeRS.Color = Color3.fromRGB(36, 36, 36)
        UptimeRow.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
    end
    KicksValueLbl.Text = tostring(antiKickCount)
    if antiKickCount > 0 then
        KicksValueLbl.TextColor3 = Color3.fromRGB(132, 112, 198)
        KicksRS.Color = Color3.fromRGB(70, 46, 140)
        KicksRow.BackgroundColor3 = Color3.fromRGB(26, 20, 44)
    else
        KicksValueLbl.TextColor3 = Color3.fromRGB(86, 86, 86)
        KicksRS.Color = Color3.fromRGB(36, 36, 36)
        KicksRow.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
    end
end)

-- ═══════════════════════════════════════
--  MINIMIZE / CLOSE
-- ═══════════════════════════════════════
MinBtn.MouseButton1Click:Connect(function()
    Frame.Visible = false
    StarBtn.Visible = true
    pulseTween:Play()
end)

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- ═══════════════════════════════════════
--  STAR CONNECTIONS (down here so Frame exists)
-- ═══════════════════════════════════════
StarBtn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        starDragging  = true
        starMoved     = false
        starDragStart = i.Position
        starPosStart  = StarBtn.Position
    end
end)

StarBtn.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        local wasClick = not starMoved
        starDragging   = false
        starMoved      = false
        if wasClick then
            Frame.Visible        = true
            StarBtn.Visible      = false
            pulseTween:Cancel()
            Stroke.Color         = Color3.fromRGB(62, 62, 62)
        end
    end
end)

UIS.InputChanged:Connect(function(i)
    if starDragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - starDragStart
        if math.abs(d.X) > 4 or math.abs(d.Y) > 4 then
            starMoved = true
        end
        if starMoved then
            StarBtn.Position = UDim2.new(
                starPosStart.X.Scale, starPosStart.X.Offset + d.X,
                starPosStart.Y.Scale, starPosStart.Y.Offset + d.Y
            )
        end
    end
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
