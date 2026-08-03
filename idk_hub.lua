-- idk hub (v6) — Obsidian UI Library native rewrite
-- Zachowuje całą logikę oryginału: anti-kick, renewer maszyn, animowany sprite-sheet icon

-- ═══════════════════════════════════════
--  SERVICES & CONSTANTS
-- ═══════════════════════════════════════
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UIS               = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")
local ContentProvider   = game:GetService("ContentProvider")

-- RemoteEvent resetujący timer AFK
local antiAfkRemote = ReplicatedStorage.Network["Idle Tracking: Stop Timer"]

-- RemoteEvent / Invoke do maszyn losowania
local Event = ReplicatedStorage.Network.GardenChanceMachine_AddTime

local RENEW_INTERVAL = 55  -- sekundy między odnowieniem tej samej maszyny

-- ═══════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════
local MACHINES = {
    { tier = "Huge",       slot = "Slot1", label = "Extra Huge Luck",  enabled = false, count = 0 },
    { tier = "Titanic",    slot = "Slot1", label = "Titanic Luck",     enabled = false, count = 0 },
    { tier = "Gargantuan", slot = "Slot1", label = "Gargantuan Luck",  enabled = false, count = 0 },
}

local lastRenew = {}

local antiKickEnabled   = false
local antiKickStartTime = nil
local antiKickCount     = 0

-- ═══════════════════════════════════════
--  HELPER FUNCTIONS
-- ═══════════════════════════════════════
local function formatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function resetIdleTimer()
    if antiKickEnabled then
        pcall(function()
            antiAfkRemote:FireServer()
        end)
    end
end

local function fireRenew(machine)
    local ok, err = pcall(function()
        Event:InvokeServer(machine.tier, machine.slot, 600)
    end)
    if ok then
        machine.count += 1
    else
        warn("[idk hub] -> " .. machine.tier .. ": " .. tostring(err))
    end
end

-- Aktualizuje tekst/ kolor statusu maszyn
local machineStatusLabel  -- set po budowaniu UI
local function updateStatus()
    if not machineStatusLabel then return end
    local anyEnabled = false
    for _, m in ipairs(MACHINES) do
        if m.enabled then anyEnabled = true break end
    end
    if anyEnabled then
        machineStatusLabel:SetText("● running")
    else
        machineStatusLabel:SetText("● idle")
    end
end

-- (Re)aktywacja anti-kick
local antiKickStatusLabel
local function setAntiKickActive(state)
    antiKickEnabled = state
    if state then
        antiKickStartTime = tick()
    else
        antiKickStartTime = nil
    end
end

-- ═══════════════════════════════════════
--  LIBRARY (Obsidian UI)
-- ═══════════════════════════════════════
local Library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/NightForRoblox/Obsidian/refs/heads/main/Library.lua"
))()

local SaveManager
local ok_savemanager, savemanager_err = pcall(function()
    SaveManager = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/NightForRoblox/Obsidian/refs/heads/main/addons/SaveManager.lua"
    ))()
end)
if not ok_savemanager then
    -- Fallback na fork deividcomsono (API-kompatybilny superset)
    pcall(function()
        SaveManager = loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/addons/SaveManager.lua"
        ))()
    end)
end

local Options = Library.Options
local Toggles = Library.Toggles

-- Okno główne
local Window = Library:CreateWindow({
    Title         = "idk hub",
    Footer        = "v6",
    Center        = true,
    AutoShow      = true,
    ToggleKeybind = Enum.KeyCode.RightControl,
})

-- ═══════════════════════════════════════
--  TABS (5 zachowanych z oryginału)
-- ═══════════════════════════════════════
local MainTab     = Window:AddTab("main",       "home")
local AutoFarmTab = Window:AddTab("auto farm",  "tractor")
local AutoHatchTab= Window:AddTab("auto hatch", "egg")
local EventTab    = Window:AddTab("event",      "calendar")
local MiscTab     = Window:AddTab("misc",       "shield")

-- Placeholdery dla pustych tabów
do
    local lb = MainTab:AddLeftGroupbox("main")
    lb:AddLabel("coming soon", true)
end
do
    local lb = AutoFarmTab:AddLeftGroupbox("auto farm")
    lb:AddLabel("coming soon", true)
end
do
    local lb = AutoHatchTab:AddLeftGroupbox("auto hatch")
    lb:AddLabel("coming soon", true)
end

-- ═══════════════════════════════════════
--  EVENT TAB — Luck Machine Renewer
-- ═══════════════════════════════════════
local machineRenewBox  = EventTab:AddLeftGroupbox("luck machine renewer")
local machineStatusBox = EventTab:AddRightGroupbox("status")

-- Status tekstowy (aktualizowany przez updateStatus/Heartbeat)
machineStatusLabel = machineStatusBox:AddLabel("● idle")

-- Trzymamy referencje do label-liczników, by Heartbeat je aktualizował
local renewLabels = {}

for _, m in ipairs(MACHINES) do
    local toggle = machineRenewBox:AddToggle("Machine_" .. m.tier, {
        Text    = m.label,
        Default = false,
        Tooltip = "Co 55s odnawia maszynę '" .. m.tier .. "' (+600s)",
    })

    -- Licznik odnowień
    local counter = machineRenewBox:AddLabel("Renews: 0")
    renewLabels[m.tier] = counter

    toggle:OnChanged(function(value)
        m.enabled = value
        if value then
            fireRenew(m)
            lastRenew[m.tier] = tick()
        end
        updateStatus()
    end)
end

-- ═══════════════════════════════════════
--  MISC TAB — Anti-Kick + Uptime/Kicks
-- ═══════════════════════════════════════
local antiKickBox = MiscTab:AddLeftGroupbox("anti-kick")
local uptimeBox   = MiscTab:AddRightGroupbox("uptime")

antiKickStatusLabel = antiKickBox:AddLabel("Status: disabled")

local antiKickToggle = antiKickBox:AddToggle("AntiKick", {
    Text    = "Anti-Kick",
    Default = false,
    Tooltip = "Resetuje timer bezczynności co 30s + na Idled",
})
antiKickToggle:OnChanged(function(value)
    setAntiKickActive(value)
end)

-- Przyciski minimize/close (par with oryginałem)
antiKickBox:AddButton({
    Text = "Minimize (hide UI)",
    Func = function()
        Library:Toggle(false)
        StarBtn.Visible = true
        pulseTween:Play()
    end,
    Tooltip = "Ukrywa okno i pokazuje animowaną ikonę",
})

antiKickBox:AddButton({
    Text     = "Close (unload)",
    Func     = function() Library:Unload() end,
    Risky    = true,
    Tooltip  = "Całkowicie zamyka skrypt",
})

local uptimeLabel = uptimeBox:AddLabel("Uptime: 00:00:00")
local kicksLabel   = uptimeBox:AddLabel("Kicks prevented: 0")

-- ═══════════════════════════════════════
--  ICON — animowany sprite-sheet (zachowany z działającej wersji)
-- ═══════════════════════════════════════
local ICON_DECAL_ID = "91252878133096"

-- Sprite-sheet 1024x1024, siatka 4x4 -> 16 klatek 256x256 px
local SPRITE_COLS   = 4
local SPRITE_ROWS   = 4
local FRAME_W       = 256
local FRAME_H       = 256
local SPRITE_FRAMES = SPRITE_COLS * SPRITE_ROWS
local FRAME_TIME    = 0.1  -- 10 FPS
local currentFrame  = 0

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "idk_hub_icon"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true

local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local oldGui = PlayerGui:FindFirstChild(ScreenGui.Name)
if oldGui then oldGui:Destroy() end
ScreenGui.Parent = PlayerGui

local StarBtn = Instance.new("ImageButton")
StarBtn.Size = UDim2.new(0, 76, 0, 76)
StarBtn.Position = UDim2.new(0.5, -38, 0, 20)  -- middle-top
StarBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
StarBtn.BorderSizePixel = 0
StarBtn.ClipsDescendants = true
StarBtn.Image = "rbxassetid://" .. ICON_DECAL_ID
StarBtn.ImageColor3 = Color3.fromRGB(255, 255, 255)
StarBtn.ScaleType = Enum.ScaleType.Stretch
StarBtn.AutoButtonColor = false
StarBtn.Visible = false
StarBtn.ZIndex = 10
StarBtn.Parent = ScreenGui

StarBtn.ImageRectSize   = Vector2.new(FRAME_W, FRAME_H)
StarBtn.ImageRectOffset = Vector2.new(0, 0)

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(1, 0)
Corner.Parent = StarBtn

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(62, 62, 62)
Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
Stroke.Parent = StarBtn

local function showFrame(idx)
    local col = idx % SPRITE_COLS
    local row = math.floor(idx / SPRITE_COLS) % SPRITE_ROWS
    StarBtn.ImageRectOffset = Vector2.new(col * FRAME_W, row * FRAME_H)
end

-- Resolve decala -> jego Texture (zapobiega podwójnemu obrazkowi)
local function resolveIconImage()
    local ok, objects = pcall(function()
        return game:GetObjects("rbxassetid://" .. ICON_DECAL_ID)
    end)
    if ok and type(objects) == "table" then
        local first = objects[1]
        if first and first:IsA("Decal") and first.Texture ~= "" then
            showFrame(currentFrame)
            StarBtn.Image = first.Texture
            StarBtn.ImageRectSize = Vector2.new(FRAME_W, FRAME_H)
            showFrame(currentFrame)
        end
    end
    pcall(function()
        ContentProvider:PreloadAsync({ StarBtn })
    end)
end
task.spawn(resolveIconImage)

-- Pętla animacji sprite-sheetu (tylko gdy widoczny)
task.spawn(function()
    while true do
        if StarBtn.Visible then
            currentFrame = (currentFrame + 1) % SPRITE_FRAMES
            showFrame(currentFrame)
        end
        task.wait(FRAME_TIME)
    end
end)

-- Pulsowanie obramowania ikony
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
-- pulseTween gra tylko gdy ikona widoczna (uruchamiany przez minimize)

-- ═══════════════════════════════════════
--  STAR CONNECTIONS (drag + klik = pokaż okno)
-- ═══════════════════════════════════════
local starDragging = false
local starMoved    = false
local starDragStart, starPosStart

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
            -- Pokaż z powrotem okno Obsidian
            Library:Toggle(true)
            StarBtn.Visible = false
            pulseTween:Cancel()
            Stroke.Color = Color3.fromRGB(62, 62, 62)
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
--  LOOPS (anti-kick + renewer + display updater)
-- ═══════════════════════════════════════

-- Anti-kick: cykliczne resetowanie timera co 30s
task.spawn(function()
    while true do
        resetIdleTimer()
        task.wait(30)
    end
end)

-- Dodatkowe zabezpieczenie Idled
Players.LocalPlayer.Idled:Connect(function()
    if antiKickEnabled then
        resetIdleTimer()
        antiKickCount += 1
    end
end)

-- Heartbeat: renewer + aktualizacja labeli (rate-limit do ~5 Hz)
local lastDisplayUpdate = 0
RunService.Heartbeat:Connect(function()
    local now = tick()

    -- Renewer maszyn
    for _, m in ipairs(MACHINES) do
        if m.enabled then
            local last = lastRenew[m.tier] or 0
            if now - last >= RENEW_INTERVAL then
                lastRenew[m.tier] = now
                fireRenew(m)
            end
        end
    end

    -- Aktualizacja UI ~5 razy na sekundę
    if now - lastDisplayUpdate >= 0.2 then
        lastDisplayUpdate = now

        -- Liczniki renewals
        for _, m in ipairs(MACHINES) do
            local lbl = renewLabels[m.tier]
            if lbl then
                lbl:SetText("Renews: " .. tostring(m.count))
            end
        end

        -- Anti-kick status
        if antiKickStatusLabel then
            if antiKickEnabled and antiKickStartTime then
                antiKickStatusLabel:SetText("Status: active")
            else
                antiKickStatusLabel:SetText("Status: disabled")
            end
        end

        -- Uptime + kicks
        if antiKickEnabled and antiKickStartTime then
            uptimeLabel:SetText("Uptime: " .. formatTime(now - antiKickStartTime))
        else
            uptimeLabel:SetText("Uptime: 00:00:00")
        end
        kicksLabel:SetText("Kicks prevented: " .. tostring(antiKickCount))
    end
end)

-- ═══════════════════════════════════════
--  CLEANUP
-- ═══════════════════════════════════════
Library:OnUnload(function()
    -- StarBtn + ScreenGui są usuwane razem przez ScreenGui:Destroy()
    pcall(function() ScreenGui:Destroy() end)
end)

-- ═══════════════════════════════════════
--  UI SETTINGS TAB (z oficjalnego Example.lua Obsidian)
-- ═══════════════════════════════════════
do
    local SettingsTab = Window:AddTab("ui settings", "settings")

    -- ── lewy groupbox: Theme Manager ──
    local ThemeBox = SettingsTab:AddLeftGroupbox("Theme")

    local ThemeManager
    pcall(function()
        ThemeManager = loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/NightForRoblox/Obsidian/refs/heads/main/addons/ThemeManager.lua"
        ))()
    end)
    if not ThemeManager then
        pcall(function()
            ThemeManager = loadstring(game:HttpGet(
                "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/addons/ThemeManager.lua"
            ))()
        end)
    end

    if ThemeManager then
        pcall(function() ThemeManager:SetLibrary(Library) end)
        pcall(function() ThemeManager:SetFolder("idk_hub") end)
        pcall(function() ThemeManager:ApplyToTheme() end)

        ThemeBox:AddLabel("Theme color", true)
        local colorPicker = ThemeBox:AddLabel("Accent color")
        colorPicker:AddColorPicker("ThemeColor", {
            Default = Color3.fromRGB(105, 75, 215),
            Title   = "Accent color",
            Callback = function(c)
                Library.Scheme.AccentColor = c
            end,
        })

        ThemeBox:AddButton({
            Text  = "Save theme",
            Func  = function() pcall(function() ThemeManager:SaveTheme("default") end) end,
        })
        ThemeBox:AddButton({
            Text  = "Load theme",
            Func  = function() pcall(function() ThemeManager:LoadTheme("default") end) end,
        })
        ThemeBox:AddButton({
            Text  = "Open theme picker",
            Func  = function() pcall(function() ThemeManager:ShowWindow() end) end,
        })
    else
        ThemeBox:AddLabel("ThemeManager nie załadował się", true)
    end

    -- ── prawy groupbox: Window settings ──
    local WindowBox = SettingsTab:AddRightGroupbox("Window")

    WindowBox:AddSlider("CornerRadius", {
        Text     = "Corner radius",
        Default  = 4,
        Min      = 0,
        Max      = 12,
        Rounding = 0,
        Suffix   = "px",
        Callback = function(v) Window:SetCornerRadius(v) end,
    })

    WindowBox:AddSlider("DPI Scale", {
        Text     = "DPI scale",
        Default  = 100,
        Min      = 50,
        Max      = 200,
        Rounding = 0,
        Suffix   = "%",
        Callback = function(v) Library:SetDPIScale(v / 100) end,
    })

    WindowBox:AddToggle("ShowCustomCursor", {
        Text     = "Custom cursor",
        Default  = true,
        Callback = function(v) Library.ShowCustomCursor = v end,
    })

    WindowBox:AddButton({
        Text  = "Open theme picker",
        Func  = function()
            if ThemeManager then ThemeManager:ShowWindow() end
        end,
    })
end

-- ═══════════════════════════════════════
--  SAVEMANAGER (config persistence)
-- ═══════════════════════════════════════
if SaveManager then
    SaveManager:SetLibrary(Library)
    SaveManager:SetIgnoreIndexes({})  -- wszystkie toggle/idx powinny być zapisywane
    SaveManager:SetFolder("idk_hub")
    -- Configuration tab z save/load slots + autoload (BuildConfigTab jest w tej
    -- wersji SaveManagera; fallback do BuildConfigGroupbox dla starszych wersji).
    local ConfigTab = Window:AddTab("config", "save")
    local ok1 = pcall(function() SaveManager:BuildConfigTab(ConfigTab) end)
    if not ok1 then
        pcall(function() SaveManager:BuildConfigGroupbox(ConfigTab) end)
    end
    local ok2 = pcall(function() SaveManager:LoadAutoloadConfig() end)
    if not ok2 then
        warn("[idk hub] SaveManager:LoadAutoloadConfig zawiódł.")
    end
else
    warn("[idk hub] SaveManager nie załadował się — config nie będzie się zapisywał.")
end
