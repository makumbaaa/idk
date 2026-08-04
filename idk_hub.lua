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

-- Spotify integration endpoints + config (PKCE Authorization Code flow).
local SPOTIFY_TOKEN_ENDPOINT = "https://accounts.spotify.com/api/token"
local SPOTIFY_AUTHORIZE_URL  = "https://accounts.spotify.com/authorize"
local SPOTIFY_API_BASE       = "https://api.spotify.com/v1"
local SPOTIFY_REDIRECT_URI   = "http://localhost/callback"
local SPOTIFY_SCOPES         = "user-read-currently-playing user-read-playback-state user-modify-playback-state"
local SPOTIFY_POLL_SEC       = 5  -- interval between /me/player polls

-- Persisted Spotify OAuth state (saved outside of Obsidian via writefile/readfile).
local SPOTIFY_TOKENS_FILE = "idk_hub_spotify_tokens.json"
local spotify = {
    access_token  = "",
    refresh_token = "",
    expires_at    = 0,          -- os.time() at which access_token expires
    code_verifier = "",          -- PKCE verifier for the current auth attempt
    client_id     = "",          -- user-provided, from developer.spotify.com
}

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
--  HTTPS REQUEST ADAPTER (executor HTTP API auto-detection)
--  Returns a function with signature `request({ Url, Method, Headers, Body })`
--  -> table containing { Body, StatusCode, Success }.
--  Returns nil if no executor HTTP API is available.
-- ═══════════════════════════════════════
local httpRequestFn
do
    local candidates = {
        function() return request end,
        function() return syn and syn.request end,
        function() return http and http.request end,
        function() return fluxus and fluxus.request end,
        function() return getgenv and getgenv().request end,
    }
    for _, getter in ipairs(candidates) do
        local ok, fn = pcall(getter)
        if ok and type(fn) == "function" then
            httpRequestFn = fn
            break
        end
    end
end

-- Wraps the executor HTTP API into a uniform interface.
-- Returns (bodyString, statusCode) or (nil, errorString) on failure.
local function httpSend(method, url, headers, body)
    if not httpRequestFn then return nil, "no executor HTTP API available" end
    local ok, response = pcall(httpRequestFn, {
        Url     = url,
        Method  = method,
        Headers = headers or {},
        Body    = body or "",
    })
    if not ok then return nil, tostring(response) end
    if type(response) ~= "table" then return nil, "non-table response" end
    return response.Body or "", response.StatusCode or 0
end

-- ═══════════════════════════════════════
--  PKCE HELPERS (random verifier + SHA-256 base64url challenge)
-- ═══════════════════════════════════════
local function randomPKCEString(length)
    length = length or 64
    -- Use unreserved characters per RFC 7636: A-Z a-z 0-9 - . _ ~
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    local n = #chars
    local s = {}
    for _ = 1, length do
        s[#s + 1] = string.char(string.byte(chars, math.random(1, n)))
    end
    return table.concat(s)
end

-- Base64url encode (no padding). Used for the PKCE code_challenge.
local b64urlChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local function base64UrlEncode(bytes)
    local out, i = {}, 1
    local len = #bytes
    while i <= len do
        local a = string.byte(bytes, i) or 0
        local b = (i + 1 <= len) and string.byte(bytes, i + 1) or 0
        local c = (i + 2 <= len) and string.byte(bytes, i + 2) or 0
        local n = a * 65536 + b * 256 + c
        local x1 = math.floor(n / 262144) % 64
        local x2 = math.floor(n / 4096) % 64
        local x3 = math.floor(n / 64) % 64
        local x4 = n % 64
        out[#out + 1] = string.sub(b64urlChars, x1 + 1, x1 + 1)
        out[#out + 1] = string.sub(b64urlChars, x2 + 1, x2 + 1)
        if i + 1 <= len then out[#out + 1] = string.sub(b64urlChars, x3 + 1, x3 + 1) end
        if i + 2 <= len then out[#out + 1] = string.sub(b64urlChars, x4 + 1, x4 + 1) end
        i = i + 3
    end
    return table.concat(out)
end

-- SHA-256 in pure Lua (small vendored impl). Used if executors don't expose `crypt.hash`.
-- Returns a 32-byte binary string.
local function pureLuaSha256(input)
    -- SHA-256 constants
    local h = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
    local k = { 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
                0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
                0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
                0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
                0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
                0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
                0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
                0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2 }
    local function rotr(x, n) return (x >> n) | (x << (32 - n)) end
    local function add32(...) local r = 0 for _, v in ipairs({...}) do r = (r + v) % 2^32 end return r end

    -- Pre-processing: append 0x80, pad to 56 mod 64, append 8-byte big-endian length
    local bytes = { input:byte(1, -1) }
    local len = #bytes
    bytes[#bytes + 1] = 0x80
    while #bytes % 64 ~= 56 do bytes[#bytes + 1] = 0 end
    local bitLen = len * 8
    for i = 7, 0, -1 do bytes[#bytes + 1] = math.floor(bitLen / 2^(i*8)) % 256 end

    -- Process each 512-bit (64-byte) chunk
    local w = {}
    for chunkStart = 1, #bytes, 64 do
        for t = 0, 15 do
            w[t] = (bytes[chunkStart + t*4]   * 16777216 +
                    bytes[chunkStart + t*4+1] * 65536 +
                    bytes[chunkStart + t*4+2] * 256 +
                    bytes[chunkStart + t*4+3])
        end
        for t = 16, 63 do
            local s0 = rotr(w[t-15], 7) ~ rotr(w[t-15], 18) ~ (w[t-15] >> 3)
            local s1 = rotr(w[t-2], 17) ~ rotr(w[t-2], 19) ~ (w[t-2] >> 10)
            w[t] = (w[t-16] + s0 + w[t-7] + s1) % 2^32
        end

        local a, b, c, d, e, f, g, h0 = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
        for t = 0, 63 do
            local S1 = rotr(e, 6) ~ rotr(e, 11) ~ rotr(e, 25)
            local ch = (e & f) ~ ((~e) & g)
            local temp1 = add32(h0, k[t+1], S1, ch, w[t])
            local S0 = rotr(a, 2) ~ rotr(a, 13) ~ rotr(a, 22)
            local maj = (a & b) ~ (a & c) ~ (b & c)
            local temp2 = add32(S0, maj)
            h0 = g; g = f; f = e; e = add32(d, temp1)
            d = c; c = b; b = a; a = add32(temp1, temp2)
        end
        h[1] = add32(h[1], a); h[2] = add32(h[2], b)
        h[3] = add32(h[3], c); h[4] = add32(h[4], d)
        h[5] = add32(h[5], e); h[6] = add32(h[6], f)
        h[7] = add32(h[7], g); h[8] = add32(h[8], h0)
    end

    -- Pack into 32-byte binary string
    local out = {}
    for i = 1, 8 do
        local x = h[i]
        out[#out + 1] = string.char(
            math.floor(x / 16777216) % 256,
            math.floor(x / 65536) % 256,
            math.floor(x / 256) % 256,
            x % 256
        )
    end
    return table.concat(out)
end

-- Sets `spotify.code_verifier` to a fresh random verifier and returns the matching
-- base64url(SHA-256(verifier)) code_challenge (for the authorize URL).
local function generatePKCEPair()
    spotify.code_verifier = randomPKCEString(64)
    local hash
    -- Prefer executor's built-in crypto if available (faster + battle-tested).
    if crypt and crypt.hash then
        local ok, result = pcall(function()
            return crypt.hash("sha256", spotify.code_verifier)
        end)
        if ok and result then hash = result end
    end
    if not hash then hash = pureLuaSha256(spotify.code_verifier) end
    return base64UrlEncode(hash)
end

-- ═══════════════════════════════════════
--  SPOTIFY TOKEN SWAP + REFRESH + HTTP REQUESTS
-- ═══════════════════════════════════════
-- POSTs an x-www-form-urlencoded body to Spotify's token endpoint.
-- Returns parsed table { access_token, refresh_token, expires_in, error } or nil.
local function spotifyPostToken(formTable)
    local body = {}
    for k, v in pairs(formTable) do
        body[#body + 1] = HttpService:UrlEncode(k) .. "=" .. HttpService:UrlEncode(tostring(v))
    end
    local requestBody = table.concat(body, "&")
    local responseBody, status = httpSend("POST", SPOTIFY_TOKEN_ENDPOINT, {
        ["Content-Type"]  = "application/x-www-form-urlencoded",
        ["Accept"]        = "application/json",
    }, requestBody)
    if not responseBody then return nil, status end
    if status ~= 200 then return nil, "HTTP " .. tostring(status) .. ": " .. tostring(responseBody) end

    local okDecode, decoded = pcall(function()
        return HttpService:JSONDecode(responseBody)
    end)
    if not okDecode or type(decoded) ~= "table" then return nil, "bad JSON" end
    return decoded
end

-- Swap an authorization code for access + refresh tokens using the cached PKCE verifier.
-- Returns (true, nil) on success or (nil, errorString) on failure.
local function swapSpotifyCode(authCode)
    if spotify.code_verifier == "" then return nil, "no PKCE verifier — click 'Open auth page' first" end
    if spotify.client_id == "" then return nil, "no Client ID set" end
    local decoded, err = spotifyPostToken({
        grant_type      = "authorization_code",
        code            = authCode,
        redirect_uri    = SPOTIFY_REDIRECT_URI,
        client_id       = spotify.client_id,
        code_verifier   = spotify.code_verifier,
    })
    if not decoded then return nil, err end
    if decoded.error then return nil, decoded.error end
    spotify.access_token  = decoded.access_token or ""
    spotify.refresh_token = decoded.refresh_token or spotify.refresh_token
    spotify.expires_at    = os.time() + tonumber(decoded.expires_in or 3600)
    spotify.code_verifier = ""  -- one-time use
    return true
end

-- Refresh the access token using the cached refresh_token.
-- Returns (true, nil) or (nil, errorString).
local function refreshSpotifyToken()
    if spotify.refresh_token == "" then return nil, "no refresh token" end
    local decoded, err = spotifyPostToken({
        grant_type      = "refresh_token",
        refresh_token   = spotify.refresh_token,
        client_id       = spotify.client_id,
    })
    if not decoded then return nil, err end
    if decoded.error then return nil, decoded.error end
    spotify.access_token = decoded.access_token or spotify.access_token
    if decoded.refresh_token then spotify.refresh_token = decoded.refresh_token end
    spotify.expires_at = os.time() + tonumber(decoded.expires_in or 3600)
    return true
end

-- Convenience header for authenticated Spotify API requests.
local function spotifyAuthHeaders()
    return { ["Authorization"] = "Bearer " .. spotify.access_token, ["Accept"] = "application/json" }
end

-- GET /v1/me/player. Returns the parsed JSON table (or {} when 204 No Content).
local function spotifyGetPlayer()
    local body, status = httpSend("GET", SPOTIFY_API_BASE .. "/me/player", spotifyAuthHeaders())
    if not body then return nil, status end
    if status == 204 or body == "" then return {} end  -- nothing currently playing
    if status == 401 then return nil, "401"  end        -- caller will refresh and retry
    if status ~= 200 then return nil, "HTTP " .. tostring(status) end
    local okDecode, decoded = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if not okDecode or type(decoded) ~= "table" then return nil, "bad JSON" end
    return decoded
end

-- Issue a Spotify Player PUT/POST command (play / pause / next / previous).
local function spotifyPlayerCommand(method, path)
    return httpSend(method, SPOTIFY_API_BASE .. path, spotifyAuthHeaders())
end

-- Match a JSON string value for a given key. Naive but sufficient for the few
-- fields we need (used as a fallback for HttpService:JSONDecode on hosts that
-- block it -- but our executors generally allow JSONDecode so this is rarely used).
local function jsonStringField(body, key)
    return body:match('"' .. key .. '"%s*:%s*"([^"]*)"')
end

-- ═══════════════════════════════════════
--  SPOTIFY TOKEN PERSISTENCE
--  Saves access/refresh/expires_at/client_id to a JSON file so they survive reloads.
--  Falls back to getgenv() if readfile/writefile aren't available.
-- ═══════════════════════════════════════
local function saveSpotifyTokens()
    local payload = HttpService:JSONEncode({
        access_token  = spotify.access_token,
        refresh_token = spotify.refresh_token,
        expires_at    = spotify.expires_at,
        client_id     = spotify.client_id,
    })
    if writefile then
        pcall(function() writefile(SPOTIFY_TOKENS_FILE, payload) end)
    elseif getgenv then
        getgenv().idk_hub_spotify_tokens = payload
    end
end

local function loadSpotifyTokens()
    local payload
    if isfile and readfile and isfile(SPOTIFY_TOKENS_FILE) then
        payload = readfile(SPOTIFY_TOKENS_FILE)
    elseif getgenv and getgenv().idk_hub_spotify_tokens then
        payload = getgenv().idk_hub_spotify_tokens
    end
    if not payload then return end
    local okDecode, decoded = pcall(function()
        return HttpService:JSONDecode(payload)
    end)
    if not okDecode or type(decoded) ~= "table" then return end
    spotify.access_token  = decoded.access_token  or ""
    spotify.refresh_token = decoded.refresh_token or ""
    spotify.expires_at    = tonumber(decoded.expires_at) or 0
    spotify.client_id     = decoded.client_id     or ""
end

-- Run on startup
loadSpotifyTokens()

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
local SpotifyTab   = Window:AddTab("spotify",     "music")
local EventTab     = Window:AddTab("event",      "calendar")
local MiscTab      = Window:AddTab("misc",       "shield")

-- Placeholder content for empty tabs
do
    local AboutBox = AboutTab:AddLeftGroupbox("about")
    AboutBox:AddLabel("Script:   idk hub", true)
    AboutBox:AddLabel("Version:  v6", true)
    AboutBox:AddLabel("Creator:  makumbaaa", true)
    local updateLabel     = AboutBox:AddLabel("Last update: loading...", true)
    local relativeLabel   = AboutBox:AddLabel("Latest update: loading...", true)

    -- Convert a full ISO 8601 timestamp "YYYY-MM-DDTHH:MM:SSZ" to epoch seconds.
    local function isoToEpoch(iso)
        local y, mo, d, h, mi, s = iso:match("(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
        if not (y and mo and d and h and mi and s) then return nil end
        return os.time({
            year = tonumber(y), month = tonumber(mo), day = tonumber(d),
            hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
            isdst = false,
        })
    end

    -- Build a "X unit ago" string using the rules the user asked for:
    --   < 1 hour  -> "X minutes ago"
    --   < 24 h    -> "X hours X minutes ago"
    --   < 7 days  -> "X days X hours ago"
    --   >= 7 days -> "X weeks X days ago"
    local function relativeTime(delta)
        delta = math.max(0, math.floor(delta))
        local weeks  = math.floor(delta / 604800)
        local days   = math.floor((delta % 604800) / 86400)
        local hours  = math.floor((delta % 86400) / 3600)
        local mins   = math.floor((delta % 3600) / 60)

        if weeks >= 1 then
            return weeks .. " week" .. (weeks == 1 and "" or "s") .. " "
                .. days .. " day" .. (days == 1 and "" or "s") .. " ago"
        elseif days >= 1 then
            return days .. " day" .. (days == 1 and "" or "s") .. " "
                .. hours .. " hour" .. (hours == 1 and "" or "s") .. " ago"
        elseif hours >= 1 then
            return hours .. " hour" .. (hours == 1 and "" or "s") .. " "
                .. mins .. " minute" .. (mins == 1 and "" or "s") .. " ago"
        else
            return mins .. " minute" .. (mins == 1 and "" or "s") .. " ago"
        end
    end

    -- Fetch the latest commit date on the main branch from the GitHub API
    -- and refresh the relative-time label once a minute thereafter.
    task.spawn(function()
        local api = "https://api.github.com/repos/makumbaaa/idk/commits/main"
        local ok, body = pcall(function()
            return game:HttpGet(api)
        end)

        local commitEpoch

        if not ok or type(body) ~= "string" or body == "" then
            updateLabel:SetText("Last update: unavailable")
            relativeLabel:SetText("Latest update: unavailable")
            return
        end

        -- The commit date appears twice in the JSON (committer + author). The
        -- first match is committer.date, which we use as the canonical timestamp.
        local iso = body:match('"date":%s*"(%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ)"')
        if not iso then
            updateLabel:SetText("Last update: unknown")
            relativeLabel:SetText("Latest update: unknown")
            return
        end

        commitEpoch = isoToEpoch(iso)
        if not commitEpoch then
            updateLabel:SetText("Last update: " .. iso)
            relativeLabel:SetText("Latest update: unavailable")
            return
        end

        -- Format the absolute timestamp as "YYYY-MM-DD HH:MM"
        local y, mo, d, h, mi = iso:match("(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)")
        local pretty = string.format("%s-%s-%s %s:%s", y, mo, d, h, mi)
        updateLabel:SetText("Last update: " .. pretty)

        -- Update the relative label now, and re-run every 60s so it stays fresh
        relativeLabel:SetText("Latest update: " .. relativeTime(os.time() - commitEpoch))
        while true do
            task.wait(60)
            pcall(function()
                relativeLabel:SetText("Latest update: " .. relativeTime(os.time() - commitEpoch))
            end)
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
--  SPOTIFY TAB — Setup + Now Playing + popup window
-- ═══════════════════════════════════════
local spotifySetupBox   = SpotifyTab:AddLeftGroupbox("Setup", "key")
local spotifyNowBox    = SpotifyTab:AddRightGroupbox("Now Playing", "music")

-- Inside-tab view references (kept for the polling loop to update)
local spotifyStatusLabel
local spotifyArtImage
local spotifyTrackLabel
local spotifyArtistLabel
local spotifyProgressLabel
local spotifyNextLabel

-- "not authenticated" status reporting
local function updateSpotifyStatusText()
    if not spotifyStatusLabel then return end
    if spotify.access_token == "" then
        spotifyStatusLabel:SetText("Status: not authenticated")
    elseif os.time() >= spotify.expires_at then
        spotifyStatusLabel:SetText("Status: token expired (will refresh on next poll)")
    else
        spotifyStatusLabel:SetText("Status: connected")
    end
end

-- Client ID input (persisted via the tokens file, not via Obsidian Options).
local clientIdInput = spotifySetupBox:AddInput("SpotifyClientId", {
    Text        = "Client ID",
    Placeholder = "from developer.spotify.com dashboard",
    Default     = spotify.client_id,
    Tooltip    = "Create a free app at developer.spotify.com and paste its Client ID here. Redirect URI must be set to " .. SPOTIFY_REDIRECT_URI,
    Callback    = function(value)
        spotify.client_id = value or ""
        saveSpotifyTokens()
    end,
})

-- "Open auth page" — generates a PKCE pair and constructs the authorize URL.
-- The user opens this in their browser, approves the app, gets redirected to
-- http://localhost/callback?code=XXX — they grab the XXX part.
spotifySetupBox:AddButton("Open auth page", function()
    if spotify.client_id == "" then
        Library:Notify("Enter your Spotify Client ID first", 5)
        return
    end
    local challenge = generatePKCEPair()  -- stashes spotify.code_verifier
    local state     = randomPKCEString(16)
    local params = {
        response_type         = "code",
        client_id             = spotify.client_id,
        redirect_uri          = SPOTIFY_REDIRECT_URI,
        scope                 = SPOTIFY_SCOPES,
        code_challenge_method = "S256",
        code_challenge        = challenge,
        state                 = state,
    }
    local query = {}
    for k, v in pairs(params) do
        query[#query + 1] = HttpService:UrlEncode(k) .. "=" .. HttpService:UrlEncode(v)
    end
    local url = SPOTIFY_AUTHORIZE_URL .. "?" .. table.concat(query, "&")

    -- Use executor's browser-open if available; otherwise prompt user to copy URL.
    if type(prompt) == "function" then
        pcall(prompt, url)
    else
        pcall(function()
            if setclipboard then setclipboard(url) end
        end)
        Library:Notify("Authorize URL copied to clipboard — open it in your browser", 8)
    end
end)

-- Auth code paste input (one-time use; we don't save this Obsidian control's value).
local authCodeInput = spotifySetupBox:AddInput("SpotifyAuthCode", {
    Text        = "Auth code",
    Placeholder = "paste the ?code=... part from the URL bar",
    Tooltip    = "After approving in the browser, copy the code=XXX value from the redirect URL and paste it here.",
})

-- "Swap code for token" — exchanges the auth code + PKCE verifier for tokens.
spotifySetupBox:AddButton("Swap code for token", function()
    if not httpRequestFn then
        Library:Notify("Executor HTTP API missing — can't reach Spotify", 8)
        return
    end
    local code = authCodeInput.Value
    if not code or code == "" then
        Library:Notify("Paste your auth code first", 5)
        return
    end
    local ok, err = swapSpotifyCode(code)
    if ok then
        saveSpotifyTokens()
        Library:Notify("Spotify connected!", 4)
        updateSpotifyStatusText()
        authCodeInput:SetValue("")
    else
        Library:Notify("Token swap failed: " .. tostring(err), 8)
        warn("[idk hub] Spotify token swap failed: " .. tostring(err))
    end
end)

-- Persistent status label
spotifyStatusLabel = spotifySetupBox:AddLabel("Status: not authenticated")
updateSpotifyStatusText()

spotifySetupBox:AddDivider()

-- "Open popup window" toggle (second popup, the floating mini-player)
local SpotifyPopupGui  -- forward reference; defined below
spotifySetupBox:AddButton("Toggle mini player", function()
    if not SpotifyPopupGui then return end
    SpotifyPopupGui.Enabled = not SpotifyPopupGui.Enabled
end)

spotifySetupBox:AddButton("Disconnect", function()
    spotify.access_token  = ""
    spotify.refresh_token = ""
    spotify.expires_at    = 0
    saveSpotifyTokens()
    updateSpotifyStatusText()
    if spotifyArtImage    then spotifyArtImage:SetImage("") end
    if spotifyTrackLabel  then spotifyTrackLabel:SetText("(not playing)") end
    if spotifyArtistLabel then spotifyArtistLabel:SetText("") end
    if spotifyProgressLabel then spotifyProgressLabel:SetText("--:-- / --:--") end
    if spotifyNextLabel   then spotifyNextLabel:SetText("Next: (queue empty)") end
    Library:Notify("Spotify disconnected", 4)
end, true)  -- Risky styling so it's clearly a destructive action

spotifySetupBox:AddLabel("Tip: register a free app at developer.spotify.com.", true)
spotifySetupBox:AddLabel("Redirect URI must be " .. SPOTIFY_REDIRECT_URI, true)
spotifySetupBox:AddLabel("Play/pause/skip requires Spotify Premium.", true)

-- ── Right groupbox: Now Playing ──
spotifyArtImage   = spotifyNowBox:AddImage("SpotifyAlbumArt", {
    Image      = "",
    ScaleType  = Enum.ScaleType.Fit,
    Height     = 100,
})
spotifyTrackLabel   = spotifyNowBox:AddLabel("Track: (not playing)", true)
spotifyArtistLabel  = spotifyNowBox:AddLabel("Artist: ", true)
spotifyProgressLabel = spotifyNowBox:AddLabel("Progress: --:-- / --:--", true)
spotifyNextLabel    = spotifyNowBox:AddLabel("Next: (queue empty)", true)

-- ═══════════════════════════════════════
--  SPOTIFY MINI PLAYER POPUP (separate floating GUI)
-- ═══════════════════════════════════════
SpotifyPopupGui = Instance.new("ScreenGui")
SpotifyPopupGui.Name = "idk_hub_spotify_popup"
SpotifyPopupGui.ResetOnSpawn = false
SpotifyPopupGui.IgnoreGuiInset = true
SpotifyPopupGui.DisplayOrder = 999998  -- just below the icon's 999999
SpotifyPopupGui.Enabled = false  -- hidden until the user toggles it on
SpotifyPopupGui.Parent = PlayerGui

local PopupFrame = Instance.new("Frame")
PopupFrame.Size = UDim2.new(0, 280, 0, 130)
PopupFrame.Position = UDim2.new(1, -300, 1, -150)  -- bottom-right
PopupFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
PopupFrame.BorderSizePixel = 0
PopupFrame.ClipsDescendants = true
PopupFrame.Active = true
PopupFrame.Draggable = true
PopupFrame.ZIndex = 5
PopupFrame.Parent = SpotifyPopupGui
Instance.new("UICorner", PopupFrame).CornerRadius = UDim.new(0, 7)
local popupStroke = Instance.new("UIStroke", PopupFrame)
popupStroke.Color = Color3.fromRGB(105, 75, 215)
popupStroke.Thickness = 1
popupStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

-- Album art thumbnail (top-left of popup)
local popupArt = Instance.new("ImageLabel")
popupArt.Size = UDim2.new(0, 60, 0, 60)
popupArt.Position = UDim2.new(0, 10, 0, 10)
popupArt.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
popupArt.BorderSizePixel = 0
popupArt.Image = ""
popupArt.ScaleType = Enum.ScaleType.Fit
popupArt.ZIndex = 6
popupArt.Parent = PopupFrame
Instance.new("UICorner", popupArt).CornerRadius = UDim.new(0, 5)

-- Track title + artist (top-right of popup)
local popupTrackLabel = Instance.new("TextLabel")
popupTrackLabel.Size = UDim2.new(1, -85, 0, 28)
popupTrackLabel.Position = UDim2.new(0, 78, 0, 10)
popupTrackLabel.BackgroundTransparency = 1
popupTrackLabel.Text = "(not playing)"
popupTrackLabel.TextColor3 = Color3.fromRGB(225, 225, 225)
popupTrackLabel.TextSize = 13
popupTrackLabel.Font = Enum.Font.GothamBold
popupTrackLabel.TextXAlignment = Enum.TextXAlignment.Left
popupTrackLabel.TextTruncate = Enum.TextTruncate.AtEnd
popupTrackLabel.ZIndex = 6
popupTrackLabel.Parent = PopupFrame

local popupArtistLabel = Instance.new("TextLabel")
popupArtistLabel.Size = UDim2.new(1, -85, 0, 18)
popupArtistLabel.Position = UDim2.new(0, 78, 0, 38)
popupArtistLabel.BackgroundTransparency = 1
popupArtistLabel.Text = ""
popupArtistLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
popupArtistLabel.TextSize = 11
popupArtistLabel.Font = Enum.Font.Gotham
popupArtistLabel.TextXAlignment = Enum.TextXAlignment.Left
popupArtistLabel.TextTruncate = Enum.TextTruncate.AtEnd
popupArtistLabel.ZIndex = 6
popupArtistLabel.Parent = PopupFrame

-- Progress bar (track)
local popupProgressTrack = Instance.new("Frame")
popupProgressTrack.Size = UDim2.new(1, -20, 0, 4)
popupProgressTrack.Position = UDim2.new(0, 10, 0, 78)
popupProgressTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
popupProgressTrack.BorderSizePixel = 0
popupProgressTrack.ZIndex = 6
popupProgressTrack.Parent = PopupFrame
Instance.new("UICorner", popupProgressTrack).CornerRadius = UDim.new(1, 0)

local popupProgressFill = Instance.new("Frame")
popupProgressFill.Size = UDim2.new(0, 0, 1, 0)
popupProgressFill.Position = UDim2.new(0, 0, 0, 0)
popupProgressFill.BackgroundColor3 = Color3.fromRGB(105, 75, 215)
popupProgressFill.BorderSizePixel = 0
popupProgressFill.ZIndex = 7
popupProgressFill.Parent = popupProgressTrack
Instance.new("UICorner", popupProgressFill).CornerRadius = UDim.new(1, 0)

-- Progress text label
local popupProgressLabel = Instance.new("TextLabel")
popupProgressLabel.Size = UDim2.new(1, -20, 0, 14)
popupProgressLabel.Position = UDim2.new(0, 10, 0, 84)
popupProgressLabel.BackgroundTransparency = 1
popupProgressLabel.Text = "--:-- / --:--"
popupProgressLabel.TextColor3 = Color3.fromRGB(130, 130, 130)
popupProgressLabel.TextSize = 10
popupProgressLabel.Font = Enum.Font.Gotham
popupProgressLabel.TextXAlignment = Enum.TextXAlignment.Left
popupProgressLabel.ZIndex = 6
popupProgressLabel.Parent = PopupFrame

-- Bottom row: prev / play-pause / next buttons + close X
local function makePopupButton(xOff, glyph, onClick)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 32, 0, 28)
    b.Position = UDim2.new(0, xOff, 0, 100)
    b.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    b.BorderSizePixel = 0
    b.Text = glyph
    b.TextColor3 = Color3.fromRGB(220, 220, 220)
    b.TextSize = 16
    b.Font = Enum.Font.GothamBold
    b.ZIndex = 7
    b.Parent = PopupFrame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    b.MouseButton1Click:Connect(function()
        if onClick then pcall(onClick) end
    end)
    return b
end

makePopupButton(10,  "⏮", function()
    pcall(function() spotifyPlayerCommand("POST", "/me/player/previous") end)
end)
local playPauseBtn = makePopupButton(48, "⏯", function()
    if isPlaying then
        pcall(function() spotifyPlayerCommand("PUT", "/me/player/pause") end)
    else
        pcall(function() spotifyPlayerCommand("PUT", "/me/player/play") end)
    end
end)
makePopupButton(86, "⏭", function()
    pcall(function() spotifyPlayerCommand("POST", "/me/player/next") end)
end)

-- Close X (hides the popup but leaves the script running)
local popupCloseBtn = Instance.new("TextButton")
popupCloseBtn.Size = UDim2.new(0, 22, 0, 22)
popupCloseBtn.Position = UDim2.new(1, -28, 0, 6)
popupCloseBtn.BackgroundColor3 = Color3.fromRGB(155, 40, 40)
popupCloseBtn.BorderSizePixel = 0
popupCloseBtn.Text = "×"
popupCloseBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
popupCloseBtn.TextSize = 14
popupCloseBtn.Font = Enum.Font.GothamBold
popupCloseBtn.ZIndex = 8
popupCloseBtn.Parent = PopupFrame
Instance.new("UICorner", popupCloseBtn).CornerRadius = UDim.new(1, 0)
popupCloseBtn.MouseButton1Click:Connect(function()
    SpotifyPopupGui.Enabled = false
end)

-- Interpolation state (updated by the poll loop and consumed by RenderStepped).
local spotifySyncedAt   = 0     -- tick() of the most recent successful poll
local spotifySyncedMs    = 0     -- progress_ms at the most recent poll
local spotifyTotalMs     = 0     -- current track duration in ms
local spotifyIsPlaying   = false -- whether Spotify reports playback as playing

-- Format a millisecond count as M:SS or MM:SS
local function msToClock(ms)
    if not ms or ms < 0 then return "--:--" end
    local total = math.floor(ms / 1000)
    local m = math.floor(total / 60)
    local s = total % 60
    return string.format("%02d:%02d", m, s)
end

-- Apply a new now-playing snapshot to both Obsidian tab labels + popup GUI labels.
local function applyNowPlaying(playerState, queuePreview)
    if not playerState then return end

    -- No track currently playing -> reset everything except the popup visibility.
    if not playerState.item then
        spotifyIsPlaying = false
        spotifyTotalMs   = 0
        if spotifyArtImage       then spotifyArtImage:SetImage("") end
        if spotifyTrackLabel     then spotifyTrackLabel:SetText("Track: (nothing playing)") end
        if spotifyArtistLabel    then spotifyArtistLabel:SetText("Artist: ") end
        if spotifyProgressLabel  then spotifyProgressLabel:SetText("Progress: --:-- / --:--") end
        popupTrackLabel.Text     = "(not playing)"
        popupArtistLabel.Text    = ""
        popupProgressFill:Size   = UDim2.new(0, 0, 1, 0)
        popupProgressLabel.Text  = "--:-- / --:--"
        return
    end

    local item     = playerState.item
    local trackName = item.name or "(unknown)"
    local artists  = {}
    if item.artists then
        for _, a in ipairs(item.artists) do
            artists[#artists + 1] = a.name or ""
        end
    end
    local artistStr = table.concat(artists, ", ")

    -- Album art: pick the smallest image (less bandwidth for Roblox fetch)
    local artUrl = ""
    if item.album and item.album.images and #item.album.images > 0 then
        artUrl = item.album.images[#item.album.images].url or ""
    end

    -- Progress + duration
    local progressMs = tonumber(playerState.progress_ms) or 0
    local durationMs = tonumber(item.duration_ms) or 0
    spotifySyncedAt  = tick()
    spotifySyncedMs  = progressMs
    spotifyTotalMs   = durationMs
    spotifyIsPlaying = playerState.is_playing == true

    -- Update Obsidian tab labels
    if spotifyArtImage    and artUrl ~= "" then spotifyArtImage:SetImage(artUrl) end
    if spotifyTrackLabel  then spotifyTrackLabel:SetText("Track: " .. trackName) end
    if spotifyArtistLabel then spotifyArtistLabel:SetText("Artist: " .. artistStr) end
    if spotifyProgressLabel then
        spotifyProgressLabel:SetText("Progress: " .. msToClock(progressMs) .. " / " .. msToClock(durationMs))
    end

    -- Update popup labels
    popupTrackLabel.Text  = trackName
    popupArtistLabel.Text = artistStr
    if artUrl ~= "" then popupArt.Image = artUrl end
    playPauseBtn.Text = spotifyIsPlaying and "⏸" or "▶"

    -- Next track preview (from /me/player/queue if available)
    local nextName = "(queue empty)"
    if queuePreview and queuePreview.queue and queuePreview.queue[1] then
        local nextItem = queuePreview.queue[1]
        local nextTitle = nextItem.name or "(unknown)"
        local nextArtists = {}
        if nextItem.artists then
            for _, a in ipairs(nextItem.artists) do
                nextArtists[#nextArtists + 1] = a.name or ""
            end
        end
        local nextArtistStr = table.concat(nextArtists, ", ")
        if nextArtistStr ~= "" then
            nextName = nextTitle .. " — " .. nextArtistStr
        else
            nextName = nextTitle
        end
    end
    if spotifyNextLabel then spotifyNextLabel:SetText("Next: " .. nextName) end

    -- Initial progress-bar fill (RenderStepped interpolates from here every frame)
    if durationMs > 0 then
        popupProgressFill:Size = UDim2.new(progressMs / durationMs, 0, 1, 0)
    else
        popupProgressFill:Size = UDim2.new(0, 0, 1, 0)
    end
    popupProgressLabel.Text = msToClock(progressMs) .. " / " .. msToClock(durationMs)
end

-- ═══════════════════════════════════════
--  SPOTIFY POLL LOOP (5s cadence)
-- ═══════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(SPOTIFY_POLL_SEC)
        if Library.Unloaded then break end
        if not httpRequestFn then continue end
        if spotify.access_token == "" then continue end

        -- Refresh token if expired (or about to expire)
        if os.time() >= spotify.expires_at and spotify.refresh_token ~= "" then
            local ok = refreshSpotifyToken()
            if ok then
                saveSpotifyTokens()
                updateSpotifyStatusText()
            else
                warn("[idk hub] Spotify refresh failed; user may need to re-authenticate")
                spotify.access_token = ""
                saveSpotifyTokens()
                updateSpotifyStatusText()
                continue
            end
        end

        -- GET /me/player (status table)
        local playerState, err = spotifyGetPlayer()
        if not playerState then
            if err == "401" then
                -- Force a refresh + retry once on the next tick (loop iteration)
                if spotify.refresh_token ~= "" then
                    local ok = refreshSpotifyToken()
                    if ok then saveSpotifyTokens() end
                end
            end
            continue
        end

        -- Optionally also GET /me/player/queue for the upcoming-track preview.
        -- (Lightweight enough; cheaper than separate timing logic.)
        local queuePreview
        do
            local qBody, qStatus = httpSend("GET", SPOTIFY_API_BASE .. "/me/player/queue", spotifyAuthHeaders())
            if qBody and qStatus == 200 and qBody ~= "" then
                local okQ, decoded = pcall(function()
                    return HttpService:JSONDecode(qBody)
                end)
                if okQ and type(decoded) == "table" then
                    queuePreview = decoded
                end
            end
        end

        applyNowPlaying(playerState, queuePreview)
    end
end)

-- ═══════════════════════════════════════
--  SPOTIFY PROGRESS BAR LOCAL INTERPOLATION
-- ═══════════════════════════════════════
RunService.RenderStepped:Connect(function()
    if not SpotifyPopupGui or not SpotifyPopupGui.Enabled then return end
    if not spotifyIsPlaying or spotifyTotalMs <= 0 then return end
    local elapsedReal = (tick() - spotifySyncedAt) * 1000
    local currentMs   = spotifySyncedMs + elapsedReal
    if currentMs > spotifyTotalMs then currentMs = spotifyTotalMs end
    if currentMs < 0 then currentMs = 0 end

    popupProgressFill:Size = UDim2.new(currentMs / spotifyTotalMs, 0, 1, 0)
    popupProgressLabel.Text = msToClock(currentMs) .. " / " .. msToClock(spotifyTotalMs)
end)
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
    -- Spotify popup ScreenGui cleans up alongside the rest of the script
    pcall(function() SpotifyPopupGui:Destroy() end)
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
    SaveManager:SetIgnoreIndexes({
        "MenuKeybind",       -- keybind should not persist
        "SpotifyAuthCode",   -- one-time auth code; should never be saved
    })
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
