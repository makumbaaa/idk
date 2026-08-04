-- idk hub (v6) — Obsidian UI Library native
-- Preserves all original logic: anti-kick, luck machine renewer, animated sprite-sheet icon.

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

-- RemoteEvent that resets the AFK idle timer
local antiAfkRemote = ReplicatedStorage.Network["Idle Tracking: Stop Timer"]

-- RemoteFunction/Invoke for the luck machines
local Event = ReplicatedStorage.Network.GardenChanceMachine_AddTime

local RENEW_INTERVAL = 55  -- seconds between successive renewals of the same machine

-- Where this script lives on GitHub; the Reload button re-fetches this URL.
local SCRIPT_URL = "https://raw.githubusercontent.com/makumbaaa/idk/refs/heads/main/idk_hub.lua"

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
        Event:InvokeServer(machine.tier, machine.slot, 10000)
    end)
    if ok then
        machine.count += 1
    else
        warn("[idk hub] -> " .. machine.tier .. ": " .. tostring(err))
    end
end

-- Updates the machine status label text. (Label is assigned after UI build.)
local machineStatusLabel
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

-- (Re)activates anti-kick state
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
--  LIBRARY (Obsidian) + ADDONS (ThemeManager, SaveManager)
-- ═══════════════════════════════════════
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

local Library
local ThemeManager
local SaveManager

local ok_lib, err_lib = pcall(function()
    Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
end)
if not ok_lib then
    error("[idk hub] Failed to load Obsidian Library: " .. tostring(err_lib))
end

pcall(function()
    ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
end)
pcall(function()
    SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
end)

if not ThemeManager then warn("[idk hub] ThemeManager failed to load — themes tab will be missing.") end
if not SaveManager  then warn("[idk hub] SaveManager failed to load — config will not persist.")    end

local Options = Library.Options
local Toggles = Library.Toggles

-- Main window
local Window = Library:CreateWindow({
    Title  = "idk hub",
    Footer = "v6",
    Center = true,
    AutoShow = true,
})

-- ═══════════════════════════════════════
--  TABS (5 preserved from the original)
-- ═══════════════════════════════════════
local AboutTab     = Window:AddTab("about",       "info")
local AutoFarmTab  = Window:AddTab("auto farm",  "tractor")
local AutoHatchTab = Window:AddTab("auto hatch", "egg")
local EventTab     = Window:AddTab("event",      "calendar")
local MiscTab      = Window:AddTab("misc",       "shield")

-- Placeholder content for empty tabs
do
    local AboutBox = AboutTab:AddLeftGroupbox("about")
    AboutBox:AddLabel("Script:   idk hub", true)
    AboutBox:AddLabel("Version:  v6", true)
    AboutBox:AddLabel("Creator:  makumbaaa", true)
    local updateLabel = AboutBox:AddLabel("Last update: loading...", true)

    -- Fetch the latest commit date on the main branch from the GitHub API.
    -- shows "YYYY-MM-DD HH:MM UTC" once it arrives.
    task.spawn(function()
        local api = "https://api.github.com/repos/makumbaaa/idk/commits/main"
        local ok, body = pcall(function()
            return game:HttpGet(api)
        end)
        if not ok or type(body) ~= "string" or body == "" then
            updateLabel:SetText("Last update: unavailable")
            return
        end
        -- Parse the commit date from the JSON. Avoids needing HttpService:JSONDecode.
        local date = body:match('"date":%s*"(%d%d%d%d%-%d%d%-%d%d)')
        if date then
            updateLabel:SetText("Last update: " .. date)
        else
            updateLabel:SetText("Last update: unknown")
        end
    end)
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

-- Status label (updated by updateStatus / Heartbeat)
machineStatusLabel = machineStatusBox:AddLabel("● idle")

-- Save label handles per machine so the Heartbeat loop can update them
local renewLabels = {}

for _, m in ipairs(MACHINES) do
    local toggle = machineRenewBox:AddToggle("Machine_" .. m.tier, {
        Text    = m.label,
        Default = false,
        Tooltip = "Renews '" .. m.tier .. "' machine ",
    })

    -- Renewal counter
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
--  MISC TAB — Anti-Kick + Uptime/Kicks + Minimize/Close
-- ═══════════════════════════════════════
local antiKickBox = MiscTab:AddLeftGroupbox("anti-kick")
local uptimeBox   = MiscTab:AddRightGroupbox("uptime")

antiKickStatusLabel = antiKickBox:AddLabel("Status: disabled")

local antiKickToggle = antiKickBox:AddToggle("AntiKick", {
    Text    = "Anti-Kick",
    Default = false,
    Tooltip = "Resets the idle timer every 30s and on Idled",
})
antiKickToggle:OnChanged(function(value)
    setAntiKickActive(value)
end)

local uptimeLabel = uptimeBox:AddLabel("Uptime: 00:00:00")
local kicksLabel   = uptimeBox:AddLabel("Kicks prevented: 0")

-- ═══════════════════════════════════════
--  ICON — animated sprite-sheet (preserved from the working version)
-- ═══════════════════════════════════════
local ICON_DECAL_ID = "91252878133096"

-- Sprite-sheet 1024x1024, 4x4 grid -> 16 frames of 256x256 px each
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
ScreenGui.DisplayOrder = 999999  -- always render above Obsidian's ScreenGui

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

-- Resolve the Decal -> its Texture (prevents the double-image bug)
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

-- Sprite-sheet animation loop (only renders while visible)
task.spawn(function()
    while true do
        if StarBtn.Visible then
            currentFrame = (currentFrame + 1) % SPRITE_FRAMES
            showFrame(currentFrame)
        end
        task.wait(FRAME_TIME)
    end
end)

-- Border pulse tween (played only when the icon is showing)
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

-- ═══════════════════════════════════════
--  STAR CONNECTIONS (drag + click = unhide window)
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
            -- Show the Obsidian window back again
            Library:Toggle(true)
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

-- Sync StarBtn visibility with Library.Toggled on every frame.
-- The icon appears whenever the window is hidden (via RightCtrl keybind OR
-- the "Minimize (hide UI)" button), and hides the moment it's restored.
RunService.Heartbeat:Connect(function()
    if not Library or Library.Unloaded then return end
    local libraryHidden = (Library.Toggled == false)
    if libraryHidden and not StarBtn.Visible then
        StarBtn.Visible = true
        pulseTween:Play()
    elseif (not libraryHidden) and StarBtn.Visible then
        StarBtn.Visible = false
        pulseTween:Cancel()
        Stroke.Color = Color3.fromRGB(62, 62, 62)
    end
end)

-- ═══════════════════════════════════════
--  LOOPS (anti-kick + renewer + display updater)
-- ═══════════════════════════════════════

-- Anti-kick: cyclic idle-timer reset every 30s
task.spawn(function()
    while true do
        resetIdleTimer()
        task.wait(30)
    end
end)

-- Extra safety net on Idled
Players.LocalPlayer.Idled:Connect(function()
    if antiKickEnabled then
        resetIdleTimer()
        antiKickCount += 1
    end
end)

-- Single Heartbeat: renewer + label updates (rate-limited to ~5 Hz)
local lastDisplayUpdate = 0
RunService.Heartbeat:Connect(function()
    local now = tick()

    -- Machine renewer loop
    for _, m in ipairs(MACHINES) do
        if m.enabled then
            local last = lastRenew[m.tier] or 0
            if now - last >= RENEW_INTERVAL then
                lastRenew[m.tier] = now
                fireRenew(m)
            end
        end
    end

    -- UI updates throttled to ~5 times per second
    if now - lastDisplayUpdate >= 0.2 then
        lastDisplayUpdate = now

        -- Renewal counters
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
    -- StarBtn + ScreenGui are destroyed together via ScreenGui:Destroy()
    pcall(function() ScreenGui:Destroy() end)
end)

-- ═══════════════════════════════════════
--  UI SETTINGS TAB (mirrors the official Obsidian Example.lua)
-- ═══════════════════════════════════════
local SettingsTab = Window:AddTab("UI Settings", "settings")

-- ── "Menu" groupbox ──
local MenuGroup = SettingsTab:AddLeftGroupbox("Menu", "wrench")

MenuGroup:AddToggle("KeybindMenuOpen", {
    Default  = Library.KeybindFrame.Visible,
    Text     = "Open Keybind Menu",
    Callback = function(value)
        Library.KeybindFrame.Visible = value
    end,
})

MenuGroup:AddToggle("ShowCustomCursor", {
    Text     = "Custom Cursor",
    Default  = Library.ShowCustomCursor,
    Callback = function(Value)
        Library.ShowCustomCursor = Value
    end,
})

MenuGroup:AddDropdown("NotificationSide", {
    Values   = { "Left", "Right" },
    Default  = "Right",
    Text     = "Notification Side",
    Callback = function(Value)
        Library:SetNotifySide(Value)
    end,
})

MenuGroup:AddDropdown("DPIDropdown", {
    Values   = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
    Default  = "100%",
    Text     = "DPI Scale",
    Callback = function(Value)
        Value = Value:gsub("%%", "")
        local DPI = tonumber(Value)
        Library:SetDPIScale(DPI)
    end,
})

MenuGroup:AddSlider("UICornerSlider", {
    Text     = "Corner Radius",
    Default  = Library.CornerRadius,
    Min      = 0,
    Max      = 20,
    Rounding = 0,
    Callback = function(value)
        Window:SetCornerRadius(value)
    end,
})

MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind")
    :AddKeyPicker("MenuKeybind", {
        Default = "RightShift",
        NoUI    = true,
        Text    = "Menu keybind",
    })

MenuGroup:AddDivider()

-- Reload: tear down this instance, then re-fetch and re-run the script from SCRIPT_URL.
-- Useful for picking up edits committed to GitHub without unload+execute.
MenuGroup:AddButton("Reload script", function()
    -- Show a quick notification before the window disappears
    if Library.Notify then
        pcall(function() Library:Notify("Reloading idk hub...", 3) end)
    end

    task.spawn(function()
        -- 1) Fetch the new source first. If it fails, abort the reload entirely.
        local okFetch, source = pcall(function()
            return game:HttpGet(SCRIPT_URL)
        end)

        if not okFetch or type(source) ~= "string" or source == "" then
            warn("[idk hub] Reload aborted: failed to fetch " .. SCRIPT_URL)
            if Library.Notify then
                pcall(function() Library:Notify("Reload failed (fetch error)", 4) end)
            end
            return
        end

        -- 2) Compile the new source separately.
        -- If there's a syntax error, abort and keep the running instance intact.
        local okCompile, compiled = pcall(function()
            return loadstring(source)
        end)
        if not okCompile or type(compiled) ~= "function" then
            warn("[idk hub] Reload aborted: syntax error in fetched script")
            if Library.Notify then
                pcall(function() Library:Notify("Reload failed (syntax error)", 4) end)
            end
            return
        end

        -- 3) Tear down the current instance cleanly. OnUnload destroys the icon ScreenGui.
        pcall(function() Library:Unload() end)

        -- 4) Give Roblox a frame to finish cleanup before re-running.
        task.wait(0.05)

        -- 5) Run the freshly compiled code.
        local okRun, runErr = pcall(compiled)
        if not okRun then
            warn("[idk hub] Re-loaded script errored at runtime: " .. tostring(runErr))
        end
    end)
end)

MenuGroup:AddButton("Unload", function()
    Library:Unload()
end)

-- Wire the keypicker back into the library so RightShift toggles the menu
Library.ToggleKeybind = Options.MenuKeybind

-- ── Theme & Save managers auto-build Themes / Theme list / Configuration groupboxes on this tab ──
if ThemeManager and SaveManager then
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)

    SaveManager:IgnoreThemeSettings()                   -- don't double-save UI Settings
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })      -- keybind should not persist
    ThemeManager:SetFolder("idk_hub")
    SaveManager:SetFolder("idk_hub")

    SaveManager:BuildConfigSection(SettingsTab)          -- adds "Configuration" groupbox
    ThemeManager:ApplyToTab(SettingsTab)                  -- adds "Themes" + "Theme list" groupboxes

    -- Background Image input: auto-resolve an rbxassetid:// decal to its Texture ID
    -- (Roblox ImageLabel.Image needs the texture URL, not the decal asset ID).
    local bgInput = Options.BackgroundImage
    if bgInput then
        local function applyResolvedImage(raw)
            if not raw or raw == "" then return end
            -- Accept "rbxassetid://1234" or just "1234"
            local id = tostring(raw):match("(%d+)$")
            if not id then return end

            task.spawn(function()
                local ok, objects = pcall(function()
                    return game:GetObjects("rbxassetid://" .. id)
                end)
                if ok and type(objects) == "table" then
                    local decal = objects[1]
                    if decal and decal:IsA("Decal") and decal.Texture ~= "" then
                        -- Push the resolved texture into Obsidian's background ImageLabel
                        pcall(function()
                            Library.Scheme.BackgroundImage = decal.Texture
                            if Library.UpdateColorsUsingRegistry then
                                Library:UpdateColorsUsingRegistry()
                            end
                        end)
                    end
                end
            end)
        end

        bgInput:OnChanged(applyResolvedImage)
        -- Run once on already-populated values (e.g. autoloaded theme)
        if bgInput.Value then applyResolvedImage(bgInput.Value) end
    end

    SaveManager:LoadAutoloadConfig()
elseif ThemeManager and not SaveManager then
    ThemeManager:SetLibrary(Library)
    ThemeManager:SetFolder("idk_hub")
    ThemeManager:ApplyToTab(SettingsTab)
elseif SaveManager and not ThemeManager then
    SaveManager:SetLibrary(Library)
    SaveManager:SetFolder("idk_hub")
    SaveManager:BuildConfigSection(SettingsTab)
    SaveManager:LoadAutoloadConfig()
end
