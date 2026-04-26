local api = require("api")
local Core = api._NuziCore or require("nuzi-core/core")

local Events = Core.Events
local Log = Core.Log
local Require = Core.Require
local Settings = Core.Settings
local CreateNuziSlider = nil
local ZoneStateModule = Require.Try({
    "nuzi-trade/zone_state",
    "nuzi-trade.zone_state"
})
local detectedAddonDir = nil

pcall(function()
    CreateNuziSlider = require("nuzi-core/ui/slider")
end)

local addon = {
    name = "Nuzi Trade",
    author = "Nuzi",
    version = "2.0.0",
    desc = "Trade pack values"
}

local SETTINGS_ID = "nuzi_trade"
local SETTINGS_FILE_PATH = "nuzi-trade/.data/settings.txt"
local LEGACY_SETTINGS_FILE_PATH = "nuzi-trade/settings.txt"
local ROUTE_TIMES_FILE_PATH = "nuzi-trade/.data/route_times.txt"
local LEGACY_ROUTE_TIMES_FILE_PATH = "nuzi-trade/route_times.txt"
local MAX_ROUTE_PERCENT = 130
local LAUNCHER_BUTTON_MIN_SIZE = 32
local LAUNCHER_BUTTON_MAX_SIZE = 96
local ROWS_PER_PAGE = 10
local ALL_PACKS_LABEL = "All Packs"
local ALL_ORIGINS_LABEL = "All Origins"
local ALL_DESTINATIONS_LABEL = "All Destinations"
local VEHICLE_TYPES = { "Hauler", "Car", "Boat" }
local ZONE_STATE_REFRESH_INTERVAL_MS = 5000
local ZONE_WATCH_CATALOG_REFRESH_INTERVAL_MS = 60000
local ZONE_STATE_COLORS = {
    peace = { 120, 220, 140, 255 },
    conflict = { 255, 208, 96, 255 },
    war = { 255, 122, 122, 255 },
    static = { 148, 190, 236, 255 },
    unknown = { 186, 186, 186, 255 }
}
local ZONE_WINDOW_SECTION_COLOR = { 176, 208, 255, 255 }
local ZONE_WINDOW_NAME_COLOR = { 232, 232, 232, 255 }
local LABEL_OUTLINE_COLOR = { 0, 0, 0, 255 }
local ZONE_WATCH_LAYOUT = {
    { kind = "zone", name = "Diamond Shores" },
    { kind = "section", title = "Nuia" },
    { kind = "zone", name = "Cinderstone Moor" },
    { kind = "zone", name = "Halcyona" },
    { kind = "zone", name = "Hellswamp" },
    { kind = "zone", name = "Karkasse Ridgelands" },
    { kind = "zone", name = "Sanddeep" },
    { kind = "section", title = "Haranya" },
    { kind = "zone", name = "Hasla" },
    { kind = "zone", name = "Perinoor Ruins" },
    { kind = "zone", name = "Rookborne Basin" },
    { kind = "zone", name = "Windscour Savannah" },
    { kind = "zone", name = "Ynystere" }
}
local ZONE_WATCH_ZONES = {}
for _, entry in ipairs(ZONE_WATCH_LAYOUT) do
    if entry.kind == "zone" then
        table.insert(ZONE_WATCH_ZONES, entry.name)
    end
end
local DEFAULT_SETTINGS = {
    button_x = 16,
    button_y = 240,
    button_size = 44,
    origin_name = "",
    destination_name = "",
    pack_name = "",
    manual_percent_text = "130",
    timer_window_x = 72,
    timer_window_y = 320,
    trade_window_x = 120,
    trade_window_y = 120,
    zone_window_x = 1000,
    zone_window_y = 120,
    vehicle_type = VEHICLE_TYPES[1]
}

local function normalizePath(path)
    return string.gsub(tostring(path or ""), "\\", "/")
end

local function fileExists(path)
    if type(io) ~= "table" or type(io.open) ~= "function" then
        return false
    end
    local file = nil
    local ok = pcall(function()
        file = io.open(path, "rb")
    end)
    if ok and file ~= nil then
        pcall(function()
            file:close()
        end)
        return true
    end
    return false
end

local function addonDir()
    if detectedAddonDir ~= nil then
        return detectedAddonDir or nil
    end
    detectedAddonDir = false
    if type(debug) == "table" and type(debug.getinfo) == "function" then
        local info = debug.getinfo(1, "S")
        local source = type(info) == "table" and tostring(info.source or "") or ""
        if string.sub(source, 1, 1) == "@" then
            source = normalizePath(string.sub(source, 2))
            local folder = string.match(source, "^(.*)/[^/]+$")
            if type(folder) == "string" and folder ~= "" then
                detectedAddonDir = folder
                return folder
            end
        end
    end
    return nil
end

local function resolveAssetPath(relativePath)
    local rawRelative = normalizePath(relativePath)
    local strippedRelative = string.match(rawRelative, "^[^/]+/(.+)$") or rawRelative
    local candidates = {}
    local seen = {}

    local function addCandidate(path)
        path = normalizePath(path)
        if path == "" or seen[path] then
            return
        end
        seen[path] = true
        table.insert(candidates, path)
    end

    local folder = addonDir()
    if folder ~= nil then
        addCandidate(folder .. "/" .. strippedRelative)
        addCandidate(folder .. "/" .. rawRelative)
    end

    local baseDir = normalizePath(type(api) == "table" and type(api.baseDir) == "string" and api.baseDir or "")
    if baseDir ~= "" then
        addCandidate(baseDir .. "/" .. rawRelative)
        addCandidate(baseDir .. "/" .. strippedRelative)
    end

    addCandidate(rawRelative)
    addCandidate(strippedRelative)

    for _, candidate in ipairs(candidates) do
        if fileExists(candidate) then
            return candidate
        end
    end

    return candidates[1] or rawRelative
end

local STRIP_SUFFIXES = {
    peninsula = true,
    forest = true,
    hills = true,
    plains = true,
    moor = true,
    headlands = true,
    savannah = true,
    ruins = true,
    mountains = true,
    basin = true,
    cradle = true,
    fields = true,
    island = true,
    shores = true
}

local ORIGIN_ALIAS_OVERRIDES = {
    ["solzreed peninsula"] = { "solzreed peninsula", "solzreed" },
    ["gweonid forest"] = { "gweonid forest", "gweonid" },
    ["lilyut hills"] = { "lilyut hills", "lilyut" },
    ["dewstone plains"] = { "dewstone plains", "dewstone" },
    ["white arden"] = { "white arden" },
    ["marianople"] = { "marianople" },
    ["two crowns"] = { "two crowns" },
    ["cinderstone moor"] = { "cinderstone moor", "cinderstone" },
    ["halcyona"] = { "halcyona" },
    ["hellswamp"] = { "hellswamp" },
    ["sanddeep"] = { "sanddeep" },
    ["sunbite wilds"] = { "sunbite wilds", "sunbite" },
    ["rokhala mountains"] = { "rokhala mountains", "rokhala" },
    ["airain rock"] = { "airain rock", "airain" },
    ["aubre cradle"] = { "aubre cradle", "aubre" },
    ["karkasse ridgelands"] = { "karkasse ridgelands", "karkasse" },
    ["ahnimar"] = { "ahnimar" },
    ["arcum iris"] = { "arcum iris" },
    ["falcorth plains"] = { "falcorth plains", "falcorth" },
    ["tigerspine mountains"] = { "tigerspine mountains", "tigerspine" },
    ["mahadevi"] = { "mahadevi" },
    ["solis headlands"] = { "solis headlands", "solis" },
    ["villanelle"] = { "villanelle" },
    ["silent forest"] = { "silent forest" },
    ["windscour savannah"] = { "windscour savannah", "windscour" },
    ["perinoor ruins"] = { "perinoor ruins", "perinoor" },
    ["rookborne basin"] = { "rookborne basin", "rookborne" },
    ["ynystere"] = { "ynystere" },
    ["hasla"] = { "hasla" }
}

local FALLBACK_ORIGINS = {
    "Ahnimar",
    "Airain Rock",
    "Arcum Iris",
    "Aubre Cradle",
    "Cinderstone Moor",
    "Dewstone Plains",
    "Falcorth Plains",
    "Gweonid Forest",
    "Halcyona",
    "Hasla",
    "Hellswamp",
    "Karkasse Ridgelands",
    "Lilyut Hills",
    "Mahadevi",
    "Marianople",
    "Perinoor Ruins",
    "Rokhala Mountains",
    "Rookborne Basin",
    "Sanddeep",
    "Silent Forest",
    "Solis Headlands",
    "Solzreed Peninsula",
    "Sunbite Wilds",
    "Tigerspine Mountains",
    "Two Crowns",
    "Villanelle",
    "White Arden",
    "Windscour Savannah",
    "Ynystere"
}

local ID_KEYS = {
    "zoneId",
    "zone_id",
    "groupId",
    "group_id",
    "zoneGroupId",
    "zone_group_id",
    "id"
}

local NAME_KEYS = {
    "name",
    "zoneName",
    "zone_name",
    "groupName",
    "group_name",
    "zoneGroupName",
    "zone_group_name",
    "label",
    "title",
    "text",
    "displayName",
    "display_name",
    "localizedName",
    "localized_name"
}

local App = {
    settings = nil,
    loaded = false,
    visible = false,
    price_index = nil,
    static_destinations = {},
    origins = {},
    packs = {},
    destinations = {},
    route_rows = {},
    price_rows = nil,
    price_data_loaded = false,
    selected_origin_index = 1,
    selected_pack_index = 1,
    selected_destination_index = 1,
    selected_vehicle_index = 1,
    route_page_index = 1,
    current_percent = nil,
    needs_refresh = true,
    closing_window = false,
    syncing_combo = false,
    syncing_launcher_slider = false,
    zone_window_visible = false,
    timer_window_visible = false,
    zone_watch_rows = {},
    zone_watch_last_refresh_ms = 0,
    zone_watch_countdown_started_ms = 0,
    zone_watch_last_render_second = nil,
    zone_watch_catalog = {},
    zone_watch_catalog_refreshed_at_ms = 0,
    zone_watch_state_cache = {},
    live_origin_name = nil,
    live_origin_id = nil,
    live_destinations = {},
    zone_state_cache = {},
    zone_state_last_refresh_ms = 0,
    route_time_store = {},
    route_timer = {
        running = false,
        started_at_ms = 0,
        elapsed_ms = 0,
        pending_save = false,
        route_key = nil,
        route_label = "",
        vehicle_type = VEHICLE_TYPES[1],
        status_text = "Select one origin, one destination, and one pack to time a route.",
        last_render_second = nil
    },
    ui = {
        button = nil,
        window = nil,
        timer_window = nil,
        zone_window = nil,
        controls = {},
        rows = {},
        zone_rows = {}
    }
}

local logger = Log.Create(addon.name)
local events = Events.Create({
    logger = logger
})

local refreshUi
local applyRouteTimingToRow
local updateTimerWidgetVisibility
local ensureZoneState
local resolveLiveCatalogForOrigin
local callStore
local collectZoneEntries
local dedupeEntries
local destinationNamesMatch
local reloadZoneStateModule
local buildZoneWatchRowsFallback
local refreshZoneWatchRows
local updateZoneWindowVisibility
local saveSettings
local toggleZoneWindow

local function trim(value)
    return (tostring(value or ""):gsub("^%s*(.-)%s*$", "%1"))
end

local function normalizeKey(value)
    local text = trim(value):lower()
    text = text:gsub("&", " and ")
    text = text:gsub("[^%w%s]", " ")
    text = text:gsub("%s+", " ")
    return trim(text)
end

local function buildZoneNameCandidates(value)
    local raw = trim(value)
    local candidates = {}
    local seen = {}

    local function add(name)
        local normalized = normalizeKey(name)
        if normalized ~= "" and not seen[normalized] then
            seen[normalized] = true
            table.insert(candidates, normalized)
        end
    end

    add(raw)

    local stripped = raw:match("%-%s*(.+)$")
    if stripped ~= nil then
        add(stripped)
    end

    for token in tostring(raw):gmatch("[^%-/]+") do
        add(token)
    end

    return candidates
end

local function round1(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    return math.floor(number * 10 + 0.5) / 10
end

local function round2(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    return math.floor(number * 100 + 0.5) / 100
end

local function formatGold(value)
    local number = tonumber(value)
    if number == nil then
        return "-"
    end
    local totalCopper = math.floor((number * 10000) + 0.5)
    local gold = math.floor(totalCopper / 10000)
    local silver = math.floor((totalCopper % 10000) / 100)
    local copper = totalCopper % 100
    return string.format("%dg %02ds %02dc", gold, silver, copper)
end

local function getUiNowMs()
    local now = nil
    pcall(function()
        if api.Time ~= nil and api.Time.GetUiMsec ~= nil then
            now = api.Time:GetUiMsec()
        end
    end)
    now = tonumber(now)
    if now ~= nil then
        return math.max(0, now)
    end
    if os ~= nil and os.clock ~= nil then
        return math.floor(os.clock() * 1000)
    end
    return 0
end

local function formatRouteDuration(seconds)
    local totalSeconds = tonumber(seconds)
    if totalSeconds == nil or totalSeconds < 0 then
        return "-"
    end
    totalSeconds = math.floor(totalSeconds + 0.5)
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local secs = totalSeconds % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, secs)
    end
    return string.format("%02d:%02d", minutes, secs)
end

local function getVehicleTypeIndex(vehicleType)
    local normalized = normalizeKey(vehicleType)
    for index, name in ipairs(VEHICLE_TYPES) do
        if normalizeKey(name) == normalized then
            return index
        end
    end
    return 1
end

local function getVehicleStorageKey(vehicleType)
    local index = getVehicleTypeIndex(vehicleType)
    return normalizeKey(VEHICLE_TYPES[index])
end

local function getSelectedVehicleType()
    return VEHICLE_TYPES[App.selected_vehicle_index] or VEHICLE_TYPES[1]
end

local function clampLauncherButtonSize(value)
    local size = math.floor((tonumber(value) or DEFAULT_SETTINGS.button_size or 44) + 0.5)
    if size < LAUNCHER_BUTTON_MIN_SIZE then
        size = LAUNCHER_BUTTON_MIN_SIZE
    elseif size > LAUNCHER_BUTTON_MAX_SIZE then
        size = LAUNCHER_BUTTON_MAX_SIZE
    end
    return size
end

local function getLauncherButtonSize()
    if type(App.settings) ~= "table" then
        return clampLauncherButtonSize(DEFAULT_SETTINGS.button_size)
    end
    return clampLauncherButtonSize(App.settings.button_size)
end

local function normalizeSettingsValue(settings)
    if type(settings) ~= "table" then
        return false
    end

    local changed = false

    local function ensureDefault(key, value)
        if settings[key] == nil then
            settings[key] = value
            changed = true
        end
    end

    for key, value in pairs(DEFAULT_SETTINGS) do
        ensureDefault(key, value)
    end

    local percentText = trim(settings.manual_percent_text)
    if percentText == "" then
        percentText = DEFAULT_SETTINGS.manual_percent_text
    end
    if settings.manual_percent_text ~= percentText then
        settings.manual_percent_text = percentText
        changed = true
    end

    local vehicleType = VEHICLE_TYPES[getVehicleTypeIndex(settings.vehicle_type)]
    if settings.vehicle_type ~= vehicleType then
        settings.vehicle_type = vehicleType
        changed = true
    end

    local buttonSize = clampLauncherButtonSize(settings.button_size)
    if settings.button_size ~= buttonSize then
        settings.button_size = buttonSize
        changed = true
    end

    return changed
end

local settingsStore = Settings.CreateStore({
    addon_id = SETTINGS_ID,
    legacy_addon_ids = {
        "nuzi-trade"
    },
    settings_file_path = SETTINGS_FILE_PATH,
    legacy_settings_file_path = LEGACY_SETTINGS_FILE_PATH,
    defaults = DEFAULT_SETTINGS,
    read_mode = "serialized_then_flat",
    write_mode = "serialized_then_flat",
    read_raw_text_fallback = true,
    write_mirror_paths = {
        LEGACY_SETTINGS_FILE_PATH
    },
    log_name = addon.name,
    normalize = function(settings)
        return normalizeSettingsValue(settings)
    end
})

local routeTimeStore = Settings.CreateStore({
    settings_file_path = ROUTE_TIMES_FILE_PATH,
    legacy_settings_file_path = LEGACY_ROUTE_TIMES_FILE_PATH,
    defaults = {},
    read_mode = "serialized_then_flat",
    write_mode = "serialized_then_flat",
    read_raw_text_fallback = true,
    write_mirror_paths = {
        LEGACY_ROUTE_TIMES_FILE_PATH
    },
    use_api_settings = false,
    save_global_settings = false,
    log_name = addon.name .. " Route Times"
})

local function buildRouteTimeSettingKey(routeKey, vehicleType)
    local routePart = normalizeKey(routeKey):gsub("%s+", "_")
    local vehiclePart = getVehicleStorageKey(vehicleType):gsub("%s+", "_")
    return string.format("route_time_%s_%s", routePart, vehiclePart)
end

local function buildRouteTimerKey(originName, destinationName, packName)
    local originKey = normalizeKey(originName)
    local destinationKey = normalizeKey(destinationName)
    local packKey = normalizeKey(packName)
    if originKey == "" or destinationKey == "" or packKey == "" then
        return nil
    end
    return table.concat({ originKey, destinationKey, packKey }, "|")
end

local function startsWith(text, prefix)
    return text:sub(1, #prefix) == prefix
end

local function tableHasEntries(value)
    if type(value) ~= "table" then
        return false
    end
    for _ in pairs(value) do
        return true
    end
    return false
end

local function showWidgetRaw(widget, show)
    if widget ~= nil and widget.Show ~= nil then
        pcall(function()
            widget:Show(show and true or false)
        end)
    end
end

local function safeShow(widget, show)
    if type(widget) == "table" and widget.__nuzi_primary ~= nil then
        for _, outline in ipairs(widget.__nuzi_outline or {}) do
            showWidgetRaw(outline, show)
        end
        showWidgetRaw(widget.__nuzi_primary, show)
        return
    end
    showWidgetRaw(widget, show)
end

local function setWidgetTextRaw(widget, text)
    if widget ~= nil and widget.SetText ~= nil then
        pcall(function()
            widget:SetText(tostring(text or ""))
        end)
    end
end

local function safeSetText(widget, text)
    if type(widget) == "table" and widget.__nuzi_primary ~= nil then
        for _, outline in ipairs(widget.__nuzi_outline or {}) do
            setWidgetTextRaw(outline, text)
        end
        setWidgetTextRaw(widget.__nuzi_primary, text)
        return
    end
    setWidgetTextRaw(widget, text)
end

local function safeSetExtent(widget, width, height)
    if type(widget) == "table" and widget.__nuzi_primary ~= nil then
        widget = widget.__nuzi_primary
    end
    if widget ~= nil and widget.SetExtent ~= nil then
        pcall(function()
            widget:SetExtent(width, height)
        end)
    end
end

local function isWidgetVisible(widget)
    if type(widget) == "table" and widget.__nuzi_primary ~= nil then
        widget = widget.__nuzi_primary
    end
    if widget == nil then
        return false
    end

    local visible = nil
    pcall(function()
        if widget.IsVisible ~= nil then
            visible = widget:IsVisible()
            return
        end
        if widget.GetVisible ~= nil then
            visible = widget:GetVisible()
            return
        end
        if widget.IsShown ~= nil then
            visible = widget:IsShown()
        end
    end)

    return visible == true
end

local function applyLabelColorRaw(label, rgba)
    if label == nil or label.style == nil or label.style.SetColor == nil then
        return
    end
    local color = rgba or { 255, 255, 255, 255 }
    pcall(function()
        label.style:SetColor(
            (tonumber(color[1]) or 255) / 255,
            (tonumber(color[2]) or 255) / 255,
            (tonumber(color[3]) or 255) / 255,
            (tonumber(color[4]) or 255) / 255
        )
    end)
end

local function setLabelColor(label, rgba)
    if type(label) == "table" and label.__nuzi_primary ~= nil then
        for _, outline in ipairs(label.__nuzi_outline or {}) do
            applyLabelColorRaw(outline, LABEL_OUTLINE_COLOR)
        end
        applyLabelColorRaw(label.__nuzi_primary, rgba)
        return
    end
    applyLabelColorRaw(label, rgba)
end

local function setLabelShadow(label, enabled)
    if label == nil or label.style == nil or label.style.SetShadow == nil then
        return
    end
    pcall(function()
        label.style:SetShadow(enabled and true or false)
    end)
end

local function createLabel(id, parent, text, x, y, width, height, fontSize)
    if api.Interface == nil or api.Interface.CreateWidget == nil then
        return nil
    end
    local label = api.Interface:CreateWidget("label", id, parent)
    if label == nil then
        return nil
    end
    label:AddAnchor("TOPLEFT", x, y)
    label:SetExtent(width or 100, height or 18)
    label:SetText(text or "")
    if label.style ~= nil then
        if label.style.SetFontSize ~= nil then
            label.style:SetFontSize(fontSize or 12)
        end
        if label.style.SetAlign ~= nil then
            label.style:SetAlign(ALIGN.LEFT)
        end
        setLabelShadow(label, true)
    end
    return label
end

local function createOutlinedLabel(id, parent, text, x, y, width, height, fontSize)
    local outlineOffsets = {
        { -1, 0 },
        { 1, 0 },
        { 0, -1 },
        { 0, 1 }
    }
    local outlines = {}
    for index, offset in ipairs(outlineOffsets) do
        local outline = createLabel(
            string.format("%sOutline%d", id, index),
            parent,
            text,
            x + offset[1],
            y + offset[2],
            width,
            height,
            fontSize
        )
        if outline ~= nil then
            setLabelShadow(outline, false)
            applyLabelColorRaw(outline, LABEL_OUTLINE_COLOR)
            table.insert(outlines, outline)
        end
    end

    local primary = createLabel(id, parent, text, x, y, width, height, fontSize)
    if primary == nil then
        return nil
    end

    return {
        __nuzi_primary = primary,
        __nuzi_outline = outlines
    }
end

local function createColorBlock(parent, x, y, width, height, r, g, b, a, layer)
    if parent == nil or parent.CreateColorDrawable == nil then
        return nil
    end
    local drawable = nil
    pcall(function()
        drawable = parent:CreateColorDrawable(r, g, b, a, layer or "background")
    end)
    if drawable == nil then
        return nil
    end
    pcall(function()
        drawable:AddAnchor("TOPLEFT", parent, x or 0, y or 0)
        if drawable.SetExtent ~= nil then
            drawable:SetExtent(width or 100, height or 100)
        else
            if drawable.SetWidth ~= nil then
                drawable:SetWidth(width or 100)
            end
            if drawable.SetHeight ~= nil then
                drawable:SetHeight(height or 100)
            end
        end
    end)
    return drawable
end

local function createSectionPanel(parent, title, x, y, width, height)
    createColorBlock(parent, x, y, width, height, 0.08, 0.07, 0.05, 0.84, "background")
    createColorBlock(parent, x, y, width, 38, 0.94, 0.80, 0.48, 0.10, "overlay")
    createColorBlock(parent, x + 14, y + 38, width - 28, 1, 0.88, 0.76, 0.46, 0.16, "overlay")
    local label = createLabel(
        "nuziTradeSection" .. tostring(title or ""):gsub("%W", ""),
        parent,
        tostring(title or ""),
        x + 16,
        y + 12,
        width - 32,
        18,
        15
    )
    setLabelColor(label, { 245, 224, 178, 255 })
    return label
end

local function createButton(id, parent, text, x, y, width, height)
    if api.Interface == nil or api.Interface.CreateWidget == nil then
        return nil
    end
    local button = api.Interface:CreateWidget("button", id, parent)
    if button == nil then
        return nil
    end
    button:AddAnchor("TOPLEFT", x, y)
    button:SetExtent(width or 80, height or 26)
    button:SetText(text or "")
    if api.Interface ~= nil and api.Interface.ApplyButtonSkin ~= nil then
        pcall(function()
            api.Interface:ApplyButtonSkin(button, BUTTON_BASIC.DEFAULT)
        end)
    end
    return button
end

local function createLauncherButton(id, x, y, size)
    local button = nil
    pcall(function()
        if api.Interface ~= nil and api.Interface.CreateEmptyWindow ~= nil then
            button = api.Interface:CreateEmptyWindow(id, "UIParent")
        elseif api.Interface ~= nil and api.Interface.CreateWidget ~= nil then
            button = api.Interface:CreateWidget("button", id, api.rootWindow)
        end
    end)
    if button == nil then
        return nil
    end

    pcall(function()
        if button.AddAnchor ~= nil then
            button:AddAnchor("TOPLEFT", x, y)
        end
        if button.SetExtent ~= nil then
            button:SetExtent(size or 44, size or 44)
        end
        if button.SetText ~= nil then
            button:SetText("")
        end
        if button.SetUILayer ~= nil then
            button:SetUILayer("game")
        end
        if button.Show ~= nil then
            button:Show(true)
        end
    end)

    return button
end

local function createComboBox(parent, x, y, width, items)
    local dropdown = nil
    pcall(function()
        if W_CTRL ~= nil and W_CTRL.CreateComboBox ~= nil then
            dropdown = W_CTRL.CreateComboBox(parent)
        elseif api.Interface ~= nil and api.Interface.CreateComboBox ~= nil then
            dropdown = api.Interface:CreateComboBox(parent)
        end
    end)
    if dropdown == nil then
        return nil
    end

    pcall(function()
        dropdown:AddAnchor("TOPLEFT", parent, x, y)
    end)
    if dropdown.SetExtent ~= nil then
        pcall(function()
            dropdown:SetExtent(width or 220, 24)
        end)
    end
    dropdown.__nuzi_items = items or {}
    if dropdown.AddItem ~= nil and type(dropdown.__nuzi_items) == "table" then
        pcall(function()
            for _, item in ipairs(dropdown.__nuzi_items) do
                dropdown:AddItem(tostring(item))
            end
        end)
    else
        dropdown.dropdownItem = dropdown.__nuzi_items
    end
    safeShow(dropdown, true)
    return dropdown
end

local function createEdit(id, parent, text, x, y, width, maxLength)
    local field = nil
    pcall(function()
        if W_CTRL ~= nil and W_CTRL.CreateEdit ~= nil then
            field = W_CTRL.CreateEdit(id, parent)
        elseif api.Interface ~= nil and api.Interface.CreateWidget ~= nil then
            field = api.Interface:CreateWidget("edit", id, parent)
        end
    end)
    if field == nil then
        return nil
    end

    pcall(function()
        field:AddAnchor("TOPLEFT", x, y)
    end)
    if field.SetExtent ~= nil then
        pcall(function()
            field:SetExtent(width or 88, 24)
        end)
    end
    if field.SetText ~= nil then
        pcall(function()
            field:SetText(tostring(text or ""))
        end)
    end
    if field.SetInitVal ~= nil then
        local initValue = tonumber(text)
        if initValue ~= nil then
            pcall(function()
                field:SetInitVal(initValue)
            end)
        end
    end
    if field.SetMaxTextLength ~= nil and maxLength ~= nil then
        pcall(function()
            field:SetMaxTextLength(maxLength)
        end)
    end
    if field.style ~= nil and field.style.SetAlign ~= nil then
        pcall(function()
            field.style:SetAlign(ALIGN.LEFT)
        end)
    end
    return field
end

local function createSlider(id, parent, x, y, width, minValue, maxValue, step)
    local slider = nil
    if CreateNuziSlider ~= nil then
        local ok, result = pcall(function()
            return CreateNuziSlider(id, parent)
        end)
        if ok then
            slider = result
        end
    end
    if slider == nil and api._Library ~= nil and api._Library.UI ~= nil and api._Library.UI.CreateSlider ~= nil then
        local ok, result = pcall(function()
            return api._Library.UI.CreateSlider(id, parent)
        end)
        if ok then
            slider = result
        end
    end
    if slider ~= nil then
        pcall(function()
            slider:AddAnchor("TOPLEFT", x, y)
            slider:SetExtent(width or 160, 26)
            slider:SetMinMaxValues(minValue, maxValue)
            if slider.SetStep ~= nil then
                slider:SetStep(step or 1)
            elseif slider.SetValueStep ~= nil then
                slider:SetValueStep(step or 1)
            end
        end)
    end
    return slider
end

local function setSliderValue(slider, value)
    if slider == nil then
        return
    end
    pcall(function()
        if slider.SetValue ~= nil then
            slider:SetValue(value, false)
        elseif slider.SetInitialValue ~= nil then
            slider:SetInitialValue(value)
        end
    end)
end

local function ensureLauncherButtonIcon(button)
    if button == nil then
        return nil
    end
    if button.__nuzi_icon ~= nil then
        return button.__nuzi_icon
    end
    if button.CreateImageDrawable == nil then
        return nil
    end

    local icon = nil
    pcall(function()
        icon = button:CreateImageDrawable("nuziTradeToggleButtonIcon", "artwork")
    end)
    if icon == nil then
        return nil
    end

    pcall(function()
        if icon.SetTexture ~= nil then
            icon:SetTexture(resolveAssetPath("nuzi-trade/icon.png"))
        end
        if icon.AddAnchor ~= nil then
            icon:AddAnchor("TOPLEFT", button, 0, 0)
        end
        if icon.Show ~= nil then
            icon:Show(true)
        end
    end)

    button.__nuzi_icon = icon
    return icon
end

local function applyLauncherButtonAppearance()
    local button = App.ui.button
    if button == nil then
        return
    end

    local size = getLauncherButtonSize()
    safeSetExtent(button, size, size)

    local icon = ensureLauncherButtonIcon(button)
    if icon ~= nil then
        if button.SetText ~= nil then
            pcall(function()
                button:SetText("")
            end)
        end
        if icon.SetExtent ~= nil then
            pcall(function()
                icon:SetExtent(size, size)
            end)
        end
        if icon.Show ~= nil then
            pcall(function()
                icon:Show(true)
            end)
        end
    elseif button.SetText ~= nil then
        pcall(function()
            button:SetText("NT")
        end)
    end

    safeSetText(App.ui.controls.launcher_size_value, tostring(size))
end

local function setLauncherButtonSize(value, saveNow)
    if type(App.settings) ~= "table" then
        return
    end
    local size = clampLauncherButtonSize(value)
    App.settings.button_size = size
    applyLauncherButtonAppearance()
    if App.ui.controls.launcher_size_slider ~= nil and not App.syncing_launcher_slider then
        App.syncing_launcher_slider = true
        setSliderValue(App.ui.controls.launcher_size_slider, size)
        App.syncing_launcher_slider = false
    end
    if saveNow then
        saveSettings()
    end
end

local function setComboItems(ctrl, items)
    if ctrl == nil then
        return
    end
    ctrl.__nuzi_items = items or {}
    if ctrl.AddItem ~= nil then
        pcall(function()
            if ctrl.Clear ~= nil then
                ctrl:Clear()
            elseif ctrl.RemoveAllItems ~= nil then
                ctrl:RemoveAllItems()
            end
            for _, item in ipairs(ctrl.__nuzi_items) do
                ctrl:AddItem(tostring(item))
            end
        end)
        return
    end
    ctrl.dropdownItem = ctrl.__nuzi_items
end

local function getComboIndexRaw(ctrl)
    if ctrl == nil then
        return nil
    end

    local raw = nil
    pcall(function()
        if ctrl.GetSelectedIndex ~= nil then
            raw = ctrl:GetSelectedIndex()
        elseif ctrl.GetSelIndex ~= nil then
            raw = ctrl:GetSelIndex()
        end
    end)

    return tonumber(raw)
end

local function getComboIndex1Based(ctrl, maxCount)
    local raw = getComboIndexRaw(ctrl)
    if raw == nil then
        return nil
    end

    local base = ctrl.__nuzi_index_base
    if base == nil then
        if raw == 0 then
            base = 0
        elseif maxCount ~= nil and raw == maxCount then
            base = 1
        elseif maxCount ~= nil and raw == (maxCount - 1) then
            base = 0
        else
            base = 1
        end
        ctrl.__nuzi_index_base = base
    end

    if base == 0 then
        return raw + 1
    end
    return raw
end

local function setComboIndex1Based(ctrl, idx)
    if ctrl == nil or idx == nil then
        return
    end
    idx = tonumber(idx)
    if idx == nil then
        return
    end

    local function updateBaseFromRaw(raw)
        raw = tonumber(raw)
        if raw == nil then
            return
        end
        if raw == idx then
            ctrl.__nuzi_index_base = 1
        elseif raw == (idx - 1) then
            ctrl.__nuzi_index_base = 0
        end
    end

    if ctrl.Select ~= nil then
        local selVal = idx
        if ctrl.GetSelectedIndex ~= nil then
            ctrl.__nuzi_index_base = 1
            selVal = idx
        elseif ctrl.GetSelIndex ~= nil then
            ctrl.__nuzi_index_base = 0
            selVal = idx - 1
        end
        pcall(function()
            ctrl:Select(selVal)
        end)
        updateBaseFromRaw(getComboIndexRaw(ctrl))
        return
    end

    local function trySetter(setter, val)
        local ok = pcall(function()
            setter(ctrl, val)
        end)
        if not ok then
            return nil
        end
        return getComboIndexRaw(ctrl)
    end

    if ctrl.SetSelectedIndex ~= nil then
        ctrl.__nuzi_index_base = nil
        local raw = trySetter(ctrl.SetSelectedIndex, idx)
        updateBaseFromRaw(raw)
        if ctrl.__nuzi_index_base == nil then
            raw = trySetter(ctrl.SetSelectedIndex, idx - 1)
            updateBaseFromRaw(raw)
        end
        return
    end

    if ctrl.SetSelIndex ~= nil then
        ctrl.__nuzi_index_base = 0
        local raw = trySetter(ctrl.SetSelIndex, idx - 1)
        updateBaseFromRaw(raw)
    end
end

local function getComboSelectedText(ctrl, values)
    if ctrl == nil or type(values) ~= "table" then
        return ""
    end

    local idx = getComboIndex1Based(ctrl, #values)
    if idx ~= nil and values[idx] ~= nil then
        return tostring(values[idx])
    end

    local raw = getComboIndexRaw(ctrl)
    if raw ~= nil then
        if values[raw] ~= nil then
            return tostring(values[raw])
        end
        if values[raw + 1] ~= nil then
            return tostring(values[raw + 1])
        end
    end

    local text = nil
    pcall(function()
        if ctrl.GetText ~= nil then
            text = ctrl:GetText()
        end
    end)
    return trim(text)
end

local function getEditText(ctrl)
    if ctrl == nil then
        return ""
    end

    local text = nil
    pcall(function()
        if ctrl.GetText ~= nil then
            text = ctrl:GetText()
        end
    end)

    return trim(text)
end

local function logInfo(message)
    logger:Info(tostring(message))
end

reloadZoneStateModule = function()
    if type(package) == "table" and type(package.loaded) == "table" then
        package.loaded["nuzi-trade/zone_state"] = nil
        package.loaded["nuzi-trade.zone_state"] = nil
    end

    local module, _, errors = Require.Try({
        "nuzi-trade/zone_state",
        "nuzi-trade.zone_state"
    })
    if module ~= nil then
        ZoneStateModule = module
        App.zone_state_manager = nil
        return module
    end

    if type(errors) == "table" and #errors > 0 then
        logInfo("Unable to reload zone_state module: " .. Require.DescribeErrors(errors))
    end
    return ZoneStateModule
end

local function loadPriceRows()
    if App.price_rows ~= nil then
        return App.price_rows
    end

    local rows = nil
    local ok, result = pcall(function()
        return api.File:Read("nuzi-trade/trade_pack_prices_data.txt")
    end)
    if ok and type(result) == "table" and #result > 0 then
        rows = result
    end

    if rows == nil then
        rows = Require.Try({
            "nuzi-trade/trade_pack_prices",
            "nuzi-trade.trade_pack_prices",
            "trade_pack_prices"
        })
    end

    if type(rows) ~= "table" then
        rows = {}
    end

    App.price_rows = rows
    App.price_data_loaded = #rows > 0
    if not App.price_data_loaded then
        logInfo("Trade pack data did not load. Static browsing will be unavailable until the data file is readable.")
    end
    return App.price_rows
end

local function shouldIncludeTradeRow(destination, currency)
    local normalizedDestination = normalizeKey(destination)
    local normalizedCurrency = normalizeKey(currency)

    if normalizedDestination == "diamond shores" and (
        normalizedCurrency == "charcoal stabilizer" or
        normalizedCurrency == "dragon stabilizer" or
        normalizedCurrency == "gilda star"
    ) then
        return false
    end

    return true
end

saveSettings = function()
    if App.settings == nil then
        return
    end
    settingsStore.settings = App.settings
    settingsStore:Save()
end

local function saveRouteTimeStore()
    if type(App.route_time_store) ~= "table" then
        App.route_time_store = {}
    end
    routeTimeStore.settings = App.route_time_store
    routeTimeStore:Save()
end

local function loadRouteTimeStore()
    local routeTimes, meta = routeTimeStore:Load()
    if type(routeTimes) ~= "table" then
        routeTimes = {}
    end

    local migrated = type(meta) == "table" and meta.migrated == true
    if type(App.settings) == "table" then
        for key, value in pairs(App.settings) do
            local keyText = tostring(key or "")
            if startsWith(keyText, "route_time_") then
                local seconds = tonumber(value)
                if seconds ~= nil and seconds >= 0 and routeTimes[keyText] == nil then
                    routeTimes[keyText] = math.floor(seconds + 0.5)
                end
            end
        end

        local nested = App.settings.route_times
        if type(nested) == "table" then
            for routeKey, entry in pairs(nested) do
                if type(routeKey) == "string" then
                    if type(entry) == "table" then
                        for _, vehicleType in ipairs(VEHICLE_TYPES) do
                            local vehicleKey = getVehicleStorageKey(vehicleType)
                            local seconds = tonumber(entry[vehicleKey])
                            if seconds == nil and vehicleKey == "hauler" then
                                seconds = tonumber(entry.default or entry.seconds or entry.time_seconds or entry.value)
                            end
                            if seconds ~= nil and seconds >= 0 then
                                local flatKey = buildRouteTimeSettingKey(routeKey, vehicleType)
                                if routeTimes[flatKey] == nil then
                                    routeTimes[flatKey] = math.floor(seconds + 0.5)
                                end
                            end
                        end
                    else
                        local seconds = tonumber(entry)
                        if seconds ~= nil and seconds >= 0 then
                            local flatKey = buildRouteTimeSettingKey(routeKey, VEHICLE_TYPES[1])
                            if routeTimes[flatKey] == nil then
                                routeTimes[flatKey] = math.floor(seconds + 0.5)
                            end
                        end
                    end
                end
            end
        end
    end

    App.route_time_store = routeTimes
    routeTimeStore.settings = routeTimes
    if migrated then
        saveRouteTimeStore()
    end
end

local function getSavedRouteTimeSeconds(routeKey, vehicleType)
    if App.settings == nil or routeKey == nil then
        return nil
    end

    local vehicleKey = getVehicleStorageKey(vehicleType)
    local flatKey = buildRouteTimeSettingKey(routeKey, vehicleType)
    local legacyFlatKey = "route_time_" .. normalizeKey(routeKey):gsub("%s+", "_")
    local stored = nil
    if type(App.route_time_store) == "table" then
        stored = App.route_time_store[flatKey]
        if stored == nil then
            stored = App.route_time_store[legacyFlatKey]
        end
    end
    if stored == nil then
        stored = App.settings[flatKey]
    end
    if stored == nil then
        stored = App.settings[legacyFlatKey]
    end
    if stored == nil then
        local nested = App.settings.route_times
        if type(nested) == "table" then
            local nestedValue = nested[routeKey]
            if type(nestedValue) == "table" then
                stored = nestedValue[vehicleKey]
                if stored == nil then
                    stored = nestedValue.default or nestedValue.seconds or nestedValue.time_seconds or nestedValue.value
                end
            else
                stored = nestedValue
            end
        end
    end
    stored = tonumber(stored)
    if stored == nil or stored < 0 then
        return nil
    end
    return stored
end

local function setSavedRouteTimeSeconds(routeKey, vehicleType, seconds)
    if App.settings == nil or routeKey == nil then
        return false
    end
    local roundedSeconds = tonumber(seconds)
    if roundedSeconds == nil or roundedSeconds < 0 then
        return false
    end
    local flatKey = buildRouteTimeSettingKey(routeKey, vehicleType)
    local normalizedSeconds = math.floor(roundedSeconds + 0.5)
    if type(App.route_time_store) ~= "table" then
        App.route_time_store = {}
    end
    App.route_time_store[flatKey] = normalizedSeconds
    App.settings[flatKey] = normalizedSeconds
    saveRouteTimeStore()
    saveSettings()
    return true
end

local function saveWidgetPosition(widget, xKey, yKey)
    if widget == nil or App.settings == nil then
        return
    end

    local x = nil
    local y = nil
    pcall(function()
        if widget.GetOffset ~= nil then
            x, y = widget:GetOffset()
            return
        end
        if widget.GetEffectiveOffset ~= nil then
            x, y = widget:GetEffectiveOffset()
        end
    end)

    x = tonumber(x)
    y = tonumber(y)
    if x == nil or y == nil then
        return
    end

    App.settings[xKey] = x
    App.settings[yKey] = y
    saveSettings()
end

local function saveButtonPosition(button)
    saveWidgetPosition(button, "button_x", "button_y")
end

local function saveMainWindowPosition(window)
    saveWidgetPosition(window, "trade_window_x", "trade_window_y")
end

local function enableDrag(widget, onStop)
    if widget == nil then
        return
    end
    if widget.RegisterForDrag ~= nil then
        widget:RegisterForDrag("LeftButton")
    end
    if widget.EnableDrag ~= nil then
        widget:EnableDrag(true)
    end
    if widget.SetHandler ~= nil then
        widget:SetHandler("OnDragStart", function(self)
            if self.StartMoving ~= nil then
                self:StartMoving()
            end
        end)
        widget:SetHandler("OnDragStop", function(self)
            if self.StopMovingOrSizing ~= nil then
                self:StopMovingOrSizing()
            end
            if onStop ~= nil then
                onStop(self)
            end
        end)
    end
end

local function loadSettings()
    local settings = settingsStore:Load()
    App.settings = settings
    settingsStore.settings = settings
    loadRouteTimeStore()
    App.selected_vehicle_index = getVehicleTypeIndex(settings.vehicle_type)
    App.route_timer.vehicle_type = settings.vehicle_type
    App.timer_window_visible = false
end

local function ensurePriceIndex()
    if App.price_index ~= nil then
        return
    end

    local priceRows = loadPriceRows()
    local priceIndex = {}
    local staticDestinations = {}
    local seen = {}

    for _, row in ipairs(priceRows or {}) do
        if type(row) == "table" then
            local packName = trim(row.pack_name or row.pack or row.name)
            local destination = trim(row.destination or row.dest)
            local currency = trim(row.currency)
            local price = tonumber(row.price)
            if packName ~= "" and destination ~= "" and price ~= nil and shouldIncludeTradeRow(destination, currency) then
                local dedupeKey = table.concat({
                    normalizeKey(packName),
                    normalizeKey(destination),
                    normalizeKey(currency),
                    tostring(price)
                }, "|")
                if not seen[dedupeKey] then
                    seen[dedupeKey] = true
                    if priceIndex[destination] == nil then
                        priceIndex[destination] = {}
                    end
                    table.insert(priceIndex[destination], {
                        pack_name = packName,
                        currency = currency,
                        max_price = price,
                        max_price_text = trim(row.price_text or "")
                    })
                end
            end
        end
    end

    for destination, rows in pairs(priceIndex) do
        table.sort(rows, function(a, b)
            if a.pack_name == b.pack_name then
                if a.currency == b.currency then
                    return (tonumber(a.max_price) or 0) < (tonumber(b.max_price) or 0)
                end
                return tostring(a.currency or "") < tostring(b.currency or "")
            end
            return tostring(a.pack_name or "") < tostring(b.pack_name or "")
        end)
        staticDestinations[normalizeKey(destination)] = destination
    end

    App.price_index = priceIndex
    App.static_destinations = staticDestinations
end

local function findStaticDestinationName(name)
    ensurePriceIndex()
    for _, normalized in ipairs(buildZoneNameCandidates(name)) do
        local exact = App.static_destinations[normalized]
        if exact ~= nil then
            return exact
        end

        for key, canonical in pairs(App.static_destinations) do
            if startsWith(key, normalized .. " ") or startsWith(normalized, key .. " ") then
                return canonical
            end
        end
    end

    return nil
end

ensureZoneState = function()
    if ZoneStateModule == nil or type(ZoneStateModule.Create) ~= "function" then
        reloadZoneStateModule()
    end
    if ZoneStateModule == nil or type(ZoneStateModule.Create) ~= "function" then
        return nil
    end
    if App.zone_state_manager ~= nil and type(App.zone_state_manager.BuildWatchRows) ~= "function" then
        App.zone_state_manager = nil
        reloadZoneStateModule()
    end
    if App.zone_state_manager == nil then
        App.zone_state_manager = ZoneStateModule.Create({
            app = App,
            colors = ZONE_STATE_COLORS,
            refresh_interval_ms = ZONE_STATE_REFRESH_INTERVAL_MS,
            trim = trim,
            normalize_key = normalizeKey,
            get_ui_now_ms = getUiNowMs,
            call_store = callStore,
            collect_zone_entries = collectZoneEntries,
            dedupe_entries = dedupeEntries,
            names_match = destinationNamesMatch,
            catalog_refresh_interval_ms = ZONE_WATCH_CATALOG_REFRESH_INTERVAL_MS,
            find_static_destination_name = findStaticDestinationName,
            is_all_destinations_entry = isAllDestinationsEntry
        })
    end
    return App.zone_state_manager
end

refreshZoneWatchRows = function(force)
    local manager = ensureZoneState()
    local rowsByKey = {}
    local rows = nil
    local refreshedAtMs = getUiNowMs()

    if manager ~= nil and type(manager.BuildWatchRows) == "function" then
        local ok, result = pcall(function()
            return manager:BuildWatchRows(ZONE_WATCH_ZONES, force)
        end)
        if ok and type(result) == "table" then
            rows = result
            App.zone_watch_fallback_logged = false
        elseif not App.zone_watch_fallback_logged then
            logInfo("Zone watch compatibility fallback enabled: " .. tostring(result))
            App.zone_watch_fallback_logged = true
        end
    end

    if type(rows) ~= "table" then
        rows = buildZoneWatchRowsFallback(force)
    end

    for _, row in ipairs(rows or {}) do
        if type(row) == "table" and trim(row.name) ~= "" then
            rowsByKey[normalizeKey(row.name)] = row
        end
    end
    App.zone_watch_rows = rowsByKey
    App.zone_watch_last_refresh_ms = refreshedAtMs
    App.zone_watch_countdown_started_ms = refreshedAtMs
    App.zone_watch_last_render_second = math.floor(refreshedAtMs / 1000)
end

local function buildOriginPatterns(name)
    local normalized = normalizeKey(name)
    local patterns = {}
    local seen = {}

    local function add(value)
        local pattern = normalizeKey(value)
        if pattern ~= "" and not seen[pattern] then
            seen[pattern] = true
            table.insert(patterns, pattern)
        end
    end

    add(normalized)

    local override = ORIGIN_ALIAS_OVERRIDES[normalized]
    if type(override) == "table" then
        for _, value in ipairs(override) do
            add(value)
        end
    end

    local words = {}
    for word in normalized:gmatch("%S+") do
        table.insert(words, word)
    end

    if #words > 1 and STRIP_SUFFIXES[words[#words]] then
        add(table.concat(words, " ", 1, #words - 1))
    end

    if #words > 2 and STRIP_SUFFIXES[words[#words]] and STRIP_SUFFIXES[words[#words - 1]] then
        add(table.concat(words, " ", 1, #words - 2))
    end

    return patterns
end

local function packMatchesOrigin(packName, patterns)
    local normalizedPack = normalizeKey(packName)
    for _, pattern in ipairs(patterns or {}) do
        if normalizedPack == pattern then
            return true
        end
        if startsWith(normalizedPack, pattern .. " ") then
            return true
        end
        if startsWith(normalizedPack, "original " .. pattern .. " ") then
            return true
        end
        if normalizedPack == "original " .. pattern then
            return true
        end
    end
    return false
end

local function originHasStaticRows(name)
    ensurePriceIndex()
    local patterns = buildOriginPatterns(name)
    for _, rows in pairs(App.price_index or {}) do
        for _, row in ipairs(rows or {}) do
            if packMatchesOrigin(row.pack_name, patterns) then
                return true
            end
        end
    end
    return false
end

local function buildRouteRows(originName, destinationName, percent)
    ensurePriceIndex()
    local canonicalDestination = findStaticDestinationName(destinationName)
    if canonicalDestination == nil then
        return {}
    end

    local sourceRows = App.price_index[canonicalDestination] or {}
    local patterns = buildOriginPatterns(originName)
    local routeRows = {}

    for _, row in ipairs(sourceRows) do
        if packMatchesOrigin(row.pack_name, patterns) then
            local currentValue = nil
            if percent ~= nil then
                currentValue = (tonumber(row.max_price) or 0) * percent / MAX_ROUTE_PERCENT
            end
            table.insert(routeRows, applyRouteTimingToRow({
                pack_name = row.pack_name,
                currency = row.currency,
                max_price = row.max_price,
                max_price_text = row.max_price_text,
                current_price = currentValue
            }, originName, canonicalDestination))
        end
    end

    table.sort(routeRows, function(a, b)
        if a.pack_name == b.pack_name then
            if a.currency == b.currency then
                return (tonumber(a.max_price) or 0) < (tonumber(b.max_price) or 0)
            end
            return tostring(a.currency or "") < tostring(b.currency or "")
        end
        return tostring(a.pack_name or "") < tostring(b.pack_name or "")
    end)

    return routeRows
end

callStore = function(method, ...)
    if api.Store == nil or api.Store[method] == nil then
        return nil
    end
    local ok, result = pcall(function(...)
        return api.Store[method](api.Store, ...)
    end, ...)
    if ok then
        return result
    end
    return nil
end

local function extractNumericField(entry)
    if type(entry) ~= "table" then
        return nil
    end
    for _, key in ipairs(ID_KEYS) do
        local value = entry[key]
        if tonumber(value) ~= nil then
            return tonumber(value)
        end
    end
    for key, value in pairs(entry) do
        if type(key) == "string" and key:lower():find("id") and tonumber(value) ~= nil then
            return tonumber(value)
        end
    end
    return nil
end

local function extractStringField(entry)
    if type(entry) ~= "table" then
        return nil
    end
    for _, key in ipairs(NAME_KEYS) do
        local value = entry[key]
        if type(value) == "string" and trim(value) ~= "" then
            return trim(value)
        end
    end
    for key, value in pairs(entry) do
        if type(key) == "string" and key:lower():find("name") and type(value) == "string" and trim(value) ~= "" then
            return trim(value)
        end
    end
    return nil
end

collectZoneEntries = function(node, results, visited)
    if type(node) ~= "table" or visited[node] then
        return
    end
    visited[node] = true

    local id = extractNumericField(node)
    local name = extractStringField(node)
    if id ~= nil and name ~= nil then
        table.insert(results, {
            id = id,
            name = name
        })
    end

    for _, value in pairs(node) do
        if type(value) == "table" then
            collectZoneEntries(value, results, visited)
        end
    end
end

dedupeEntries = function(entries)
    local seen = {}
    local deduped = {}
    for _, entry in ipairs(entries or {}) do
        local name = trim(entry.name)
        local id = tonumber(entry.id)
        if name ~= "" and id ~= nil then
            local key = normalizeKey(name) .. "|" .. tostring(id)
            if not seen[key] then
                seen[key] = true
                table.insert(deduped, {
                    id = id,
                    name = name
                })
            end
        end
    end
    table.sort(deduped, function(a, b)
        return normalizeKey(a.name) < normalizeKey(b.name)
    end)
    return deduped
end

local function normalizeRoutePercent(value)
    local percent = tonumber(value)
    if percent == nil then
        return nil
    end
    if percent <= 2 then
        percent = percent * 100
    end
    percent = math.max(0, math.min(MAX_ROUTE_PERCENT, percent))
    return round1(percent)
end

local function buildFallbackOriginEntries()
    local entries = {}
    for index, name in ipairs(FALLBACK_ORIGINS) do
        if originHasStaticRows(name) then
            table.insert(entries, {
                id = -1000 - index,
                name = name,
                fallback = true
            })
        end
    end
    return entries
end

local function namesMatchLoose(left, right)
    local leftKey = normalizeKey(left)
    local rightKey = normalizeKey(right)
    if leftKey == "" or rightKey == "" then
        return false
    end
    if leftKey == rightKey then
        return true
    end
    if startsWith(leftKey, rightKey .. " ") or startsWith(rightKey, leftKey .. " ") then
        return true
    end
    return false
end

local function originNamesMatch(liveName, staticName)
    local liveCandidates = buildZoneNameCandidates(liveName)
    for _, liveKey in ipairs(liveCandidates) do
        for _, pattern in ipairs(buildOriginPatterns(staticName)) do
            if liveKey == pattern then
                return true
            end
            if startsWith(liveKey, pattern .. " ") or startsWith(pattern, liveKey .. " ") then
                return true
            end
        end
    end
    return false
end

destinationNamesMatch = function(left, right)
    local leftCandidates = buildZoneNameCandidates(left)
    local rightCandidates = buildZoneNameCandidates(right)
    for _, leftKey in ipairs(leftCandidates) do
        for _, rightKey in ipairs(rightCandidates) do
            if leftKey == rightKey then
                return true
            end
            if startsWith(leftKey, rightKey .. " ") or startsWith(rightKey, leftKey .. " ") then
                return true
            end
        end
    end
    return false
end

buildZoneWatchRowsFallback = function(force)
    local now = getUiNowMs()

    local function getStateColor(key)
        return ZONE_STATE_COLORS[tostring(key or "unknown")] or ZONE_STATE_COLORS.unknown
    end

    local function inferStateKey(text)
        local normalized = normalizeKey(text)
        if normalized == "" then
            return nil
        end
        if normalized:find("war", 1, true) ~= nil or normalized:find("siege", 1, true) ~= nil then
            return "war"
        end
        if normalized:find("conflict", 1, true) ~= nil
            or normalized:find("contested", 1, true) ~= nil
            or normalized:find("combat", 1, true) ~= nil then
            return "conflict"
        end
        if normalized:find("peace", 1, true) ~= nil or normalized:find("safe", 1, true) ~= nil then
            return "peace"
        end
        return nil
    end

    local function getStateConstant(name, fallback)
        local value = _G ~= nil and _G[name] or nil
        value = tonumber(value)
        if value == nil then
            return tonumber(fallback)
        end
        return value
    end

    local function normalizeRemainTime(value)
        local remainTime = tonumber(value)
        if remainTime == nil then
            return nil
        end
        if remainTime < 0 then
            remainTime = 0
        end
        if remainTime > (86400 * 30) then
            remainTime = remainTime / 1000
        end
        return math.floor(remainTime + 0.5)
    end

    local function formatZoneWatchTime(value)
        local totalSeconds = normalizeRemainTime(value)
        if totalSeconds == nil then
            return "-"
        end

        local days = math.floor(totalSeconds / 86400)
        local hours = math.floor((totalSeconds % 86400) / 3600)
        local minutes = math.floor((totalSeconds % 3600) / 60)
        local seconds = totalSeconds % 60

        if days > 0 then
            return string.format("%dd %02d:%02d", days, hours, minutes)
        end
        if hours > 0 then
            return string.format("%d:%02d:%02d", hours, minutes, seconds)
        end
        return string.format("%02d:%02d", minutes, seconds)
    end

    local function findNumericField(node, fieldName, visited, depth)
        depth = tonumber(depth) or 0
        if depth > 2 then
            return nil
        end
        if type(node) ~= "table" or visited[node] then
            return nil
        end
        visited[node] = true

        local direct = tonumber(node[fieldName])
        if direct ~= nil then
            return direct
        end

        for _, value in pairs(node) do
            if type(value) == "table" then
                local nested = findNumericField(value, fieldName, visited, depth + 1)
                if nested ~= nil then
                    return nested
                end
            end
        end

        return nil
    end

    local function findStringField(node, fieldName, visited, depth)
        depth = tonumber(depth) or 0
        if depth > 2 then
            return nil
        end
        if type(node) ~= "table" or visited[node] then
            return nil
        end
        visited[node] = true

        local direct = node[fieldName]
        if type(direct) == "string" and trim(direct) ~= "" then
            return trim(direct)
        end

        for _, value in pairs(node) do
            if type(value) == "table" then
                local nested = findStringField(value, fieldName, visited, depth + 1)
                if nested ~= nil then
                    return nested
                end
            end
        end

        return nil
    end

    local function findBooleanField(node, fieldName, visited, depth)
        depth = tonumber(depth) or 0
        if depth > 2 then
            return nil
        end
        if type(node) ~= "table" or visited[node] then
            return nil
        end
        visited[node] = true

        local direct = node[fieldName]
        if type(direct) == "boolean" then
            return direct
        end

        for _, value in pairs(node) do
            if type(value) == "table" then
                local nested = findBooleanField(value, fieldName, visited, depth + 1)
                if nested ~= nil then
                    return nested
                end
            end
        end

        return nil
    end

    local function collectTexts(node, results, visited, depth)
        depth = tonumber(depth) or 0
        if depth > 2 then
            return
        end

        if type(node) == "string" then
            local text = trim(node)
            if text ~= "" then
                results[#results + 1] = text
            end
            return
        end
        if type(node) ~= "table" or visited[node] then
            return
        end
        visited[node] = true

        for key, value in pairs(node) do
            if type(key) == "string" and value == true then
                local keyHint = inferStateKey(key)
                if keyHint ~= nil then
                    results[#results + 1] = keyHint
                end
            end
            if type(value) == "table" then
                collectTexts(value, results, visited, depth + 1)
            elseif type(value) == "string" then
                local text = trim(value)
                if text ~= "" then
                    results[#results + 1] = text
                end
            end
        end
    end

    local function callZoneStateMethod(zoneId)
        for _, library in ipairs({ api.Zone, api.Map }) do
            if type(library) == "table" and type(library.GetZoneStateInfoByZoneId) == "function" then
                local ok, result = pcall(function()
                    return library:GetZoneStateInfoByZoneId(zoneId)
                end)
                if ok then
                    return result
                end

                ok, result = pcall(function()
                    return library.GetZoneStateInfoByZoneId(library, zoneId)
                end)
                if ok then
                    return result
                end
            end
        end
        return nil
    end

    local function buildStateRecord(zoneId, key, text, rawInfo)
        local remainTime = nil
        local remainText = ""
        if type(rawInfo) == "table" then
            remainTime = normalizeRemainTime(findNumericField(rawInfo, "remainTime", {}, 0))
            remainText = trim(findStringField(rawInfo, "strRemainTime", {}, 0))
        end
        if remainText == "" then
            remainText = formatZoneWatchTime(remainTime)
        end

        return {
            zone_id = tonumber(zoneId),
            key = tostring(key or "unknown"),
            status_text = tostring(text or "Unknown"),
            status_color = getStateColor(key),
            time_text = remainText ~= "" and remainText or "-",
            time_color = getStateColor(key),
            remain_time = remainTime
        }
    end

    local function getZoneStateRecord(zoneId)
        local numericZoneId = tonumber(zoneId)
        if numericZoneId == nil then
            return buildStateRecord(nil, "unknown", "Unavailable", nil)
        end

        if type(App.zone_watch_state_cache) ~= "table" then
            App.zone_watch_state_cache = {}
        end

        local cached = App.zone_watch_state_cache[numericZoneId]
        if cached ~= nil and not force and (now - (tonumber(cached.refreshed_at_ms) or 0)) < ZONE_STATE_REFRESH_INTERVAL_MS then
            return cached
        end

        local rawInfo = callZoneStateMethod(numericZoneId)
        local key = nil
        local text = nil

        if type(rawInfo) == "table" then
            local conflictState = findNumericField(rawInfo, "conflictState", {}, 0)
            if conflictState ~= nil then
                local battleState = getStateConstant("HPWS_BATTLE", 5)
                local warState = getStateConstant("HPWS_WAR", 6)
                local peaceState = getStateConstant("HPWS_PEACE", 7)
                if conflictState < battleState then
                    key = "conflict"
                    text = string.format("Conflict (Step %d)", math.max(1, math.floor(conflictState) + 1))
                elseif conflictState == battleState then
                    key = "conflict"
                    text = "Conflict"
                elseif conflictState == warState then
                    key = "war"
                    text = "War"
                elseif conflictState == peaceState then
                    key = "peace"
                    text = "Peace"
                end
            end

            if key == nil then
                if findBooleanField(rawInfo, "isSiegeZone", {}, 0) == true then
                    key = "war"
                    text = "War"
                elseif findBooleanField(rawInfo, "isConflictZone", {}, 0) == true then
                    key = "conflict"
                    text = "Conflict"
                elseif findBooleanField(rawInfo, "isPeaceZone", {}, 0) == true
                    or findBooleanField(rawInfo, "isNuiaProtectedZone", {}, 0) == true
                    or findBooleanField(rawInfo, "isHariharaProtectedZone", {}, 0) == true then
                    key = "peace"
                    text = "Peace"
                end
            end
        end

        if key == nil then
            local texts = {}
            if type(rawInfo) == "string" then
                texts[#texts + 1] = rawInfo
            elseif type(rawInfo) == "table" then
                collectTexts(rawInfo, texts, {}, 0)
            elseif rawInfo ~= nil then
                texts[#texts + 1] = tostring(rawInfo)
            end

            for _, candidate in ipairs(texts) do
                local matched = inferStateKey(candidate)
                if matched ~= nil then
                    key = matched
                    text = matched == "peace" and "Peace" or (matched == "war" and "War" or "Conflict")
                    break
                end
            end
        end

        if key == nil then
            key = "unknown"
            text = rawInfo ~= nil and "Unknown" or "Unavailable"
        end

        local state = buildStateRecord(numericZoneId, key, text, rawInfo)
        state.refreshed_at_ms = now
        App.zone_watch_state_cache[numericZoneId] = state
        return state
    end

    local resolvedCatalog = type(App.zone_watch_catalog) == "table" and App.zone_watch_catalog or {}
    if force or not tableHasEntries(resolvedCatalog) or (now - (tonumber(App.zone_watch_catalog_refreshed_at_ms) or 0)) >= ZONE_WATCH_CATALOG_REFRESH_INTERVAL_MS then
        resolvedCatalog = {}
        local unresolved = {}
        for _, zoneName in ipairs(ZONE_WATCH_ZONES) do
            unresolved[normalizeKey(zoneName)] = zoneName
        end

        local function rememberEntry(entry)
            local zoneId = type(entry) == "table" and tonumber(entry.id) or nil
            local zoneName = type(entry) == "table" and trim(entry.name) or ""
            if zoneId == nil or zoneName == "" then
                return
            end

            for zoneKey, wantedName in pairs(unresolved) do
                if resolvedCatalog[zoneKey] == nil and destinationNamesMatch(zoneName, wantedName) then
                    resolvedCatalog[zoneKey] = {
                        id = zoneId,
                        name = zoneName
                    }
                    unresolved[zoneKey] = nil
                    break
                end
            end
        end

        local origins = {}
        collectZoneEntries(callStore("GetProductionZoneGroups"), origins, {})
        origins = dedupeEntries(origins)
        for _, origin in ipairs(origins) do
            rememberEntry(origin)

            local destinations = {}
            collectZoneEntries(callStore("GetSellableZoneGroups", origin.id), destinations, {})
            destinations = dedupeEntries(destinations)
            for _, destination in ipairs(destinations) do
                rememberEntry(destination)
            end
        end

        App.zone_watch_catalog = resolvedCatalog
        App.zone_watch_catalog_refreshed_at_ms = now
    end

    local rows = {}
    for _, zoneName in ipairs(ZONE_WATCH_ZONES) do
        local resolved = resolvedCatalog[normalizeKey(zoneName)]
        local state = type(resolved) == "table"
            and getZoneStateRecord(resolved.id)
            or buildStateRecord(nil, "unknown", "Unavailable", nil)

        rows[#rows + 1] = {
            name = zoneName,
            live_name = type(resolved) == "table" and resolved.name or nil,
            zone_id = type(resolved) == "table" and tonumber(resolved.id) or nil,
            status_text = state.status_text,
            status_color = state.status_color,
            time_text = state.time_text,
            time_color = state.time_color,
            key = state.key,
            remain_time = state.remain_time
        }
    end

    return rows
end

local function findIndexByName(entries, name)
    local wantedCandidates = buildZoneNameCandidates(name)
    if #wantedCandidates == 0 then
        return nil
    end
    for index, entry in ipairs(entries or {}) do
        if destinationNamesMatch(entry.name, name) or destinationNamesMatch(entry.static_name, name) then
            return index
        end
    end
    return nil
end

local function isAllDestinationsEntry(entry)
    if type(entry) ~= "table" then
        return false
    end
    if entry.all == true then
        return true
    end
    return normalizeKey(entry.static_name or entry.name) == normalizeKey(ALL_DESTINATIONS_LABEL)
end

local function isAllOriginName(name)
    return normalizeKey(name) == normalizeKey(ALL_ORIGINS_LABEL)
end

local function isAllOriginsEntry(entry)
    if type(entry) ~= "table" then
        return false
    end
    if entry.all_origins == true then
        return true
    end
    return isAllOriginName(entry.name)
end

local function getSelectedOriginName()
    local entry = App.origins[App.selected_origin_index]
    if entry == nil then
        return ""
    end
    return tostring(entry.name or "")
end

local function getSelectedDestinationName()
    local entry = App.destinations[App.selected_destination_index]
    if entry == nil then
        return ""
    end
    return tostring(entry.static_name or entry.name or "")
end

local function getSelectedPackName()
    local entry = App.packs[App.selected_pack_index]
    if entry == nil then
        return ""
    end
    return tostring(entry.name or "")
end

local function getSelectedPackFilter()
    local packName = getSelectedPackName()
    if normalizeKey(packName) == normalizeKey(ALL_PACKS_LABEL) then
        return ""
    end
    return packName
end

local function getCurrentConcreteRouteInfo()
    local origin = App.origins[App.selected_origin_index]
    local destination = App.destinations[App.selected_destination_index]
    local packName = getSelectedPackFilter()
    local vehicleType = getSelectedVehicleType()
    if origin == nil or destination == nil or packName == "" or isAllOriginsEntry(origin) or isAllDestinationsEntry(destination) then
        return nil
    end

    local destinationName = tostring(destination.static_name or destination.name or "")
    local originName = tostring(origin.name or "")
    local routeKey = buildRouteTimerKey(originName, destinationName, packName)
    if routeKey == nil then
        return nil
    end

    return {
        origin_name = originName,
        destination_name = destinationName,
        pack_name = packName,
        vehicle_type = vehicleType,
        route_key = routeKey,
        route_label = string.format("%s -> %s | %s [%s]", originName, destinationName, packName, vehicleType)
    }
end

local function getRouteTimerElapsedMs()
    local elapsedMs = tonumber(App.route_timer.elapsed_ms) or 0
    if App.route_timer.running and (tonumber(App.route_timer.started_at_ms) or 0) > 0 then
        elapsedMs = elapsedMs + math.max(0, getUiNowMs() - (tonumber(App.route_timer.started_at_ms) or 0))
    end
    return math.max(0, elapsedMs)
end

local function setRouteTimerStatus(text)
    App.route_timer.status_text = tostring(text or "")
end

local function clearRouteTimerState()
    App.route_timer.running = false
    App.route_timer.started_at_ms = 0
    App.route_timer.elapsed_ms = 0
    App.route_timer.pending_save = false
    App.route_timer.route_key = nil
    App.route_timer.route_label = ""
    App.route_timer.last_render_second = nil
end

local function startRouteTimer()
    local routeInfo = getCurrentConcreteRouteInfo()
    if routeInfo == nil then
        setRouteTimerStatus("Select one origin, one destination, and one pack to start a route timer.")
        refreshUi()
        return
    end

    App.route_timer.running = true
    App.route_timer.started_at_ms = getUiNowMs()
    App.route_timer.elapsed_ms = 0
    App.route_timer.pending_save = false
    App.route_timer.route_key = routeInfo.route_key
    App.route_timer.route_label = routeInfo.route_label
    App.route_timer.vehicle_type = routeInfo.vehicle_type
    App.route_timer.last_render_second = nil
    setRouteTimerStatus("Timer running.")
    refreshUi()
end

local function stopRouteTimer()
    if not App.route_timer.running then
        if App.route_timer.route_key == nil then
            setRouteTimerStatus("Start a timer before stopping it.")
        elseif App.route_timer.pending_save then
            setRouteTimerStatus("Timer paused. Save to store this route time.")
        else
            setRouteTimerStatus("Timer stopped.")
        end
        refreshUi()
        return
    end

    App.route_timer.elapsed_ms = getRouteTimerElapsedMs()
    App.route_timer.running = false
    App.route_timer.started_at_ms = 0
    App.route_timer.pending_save = (tonumber(App.route_timer.elapsed_ms) or 0) > 0
    App.route_timer.last_render_second = nil
    setRouteTimerStatus("Timer paused. Save to store this route time.")
    refreshUi()
end

local function saveRouteTimer()
    if App.route_timer.running then
        stopRouteTimer()
    end

    if App.route_timer.route_key == nil then
        setRouteTimerStatus("Start a timer before saving it.")
        refreshUi()
        return
    end

    local elapsedMs = getRouteTimerElapsedMs()
    if elapsedMs <= 0 then
        setRouteTimerStatus("Timer has no elapsed time to save.")
        refreshUi()
        return
    end

    local elapsedSeconds = elapsedMs / 1000
    local vehicleType = App.route_timer.vehicle_type or getSelectedVehicleType()
    if setSavedRouteTimeSeconds(App.route_timer.route_key, vehicleType, elapsedSeconds) then
        setRouteTimerStatus("Saved route time for " .. tostring(App.route_timer.route_label))
        clearRouteTimerState()
        if App.visible then
            refreshSelectedRoute()
        end
    else
        setRouteTimerStatus("Unable to save route time.")
    end
    refreshUi()
end

applyRouteTimingToRow = function(row, originName, destinationName)
    if type(row) ~= "table" then
        return row
    end
    local vehicleType = getSelectedVehicleType()
    local routeKey = buildRouteTimerKey(originName, destinationName, row.pack_name)
    row.route_time_key = routeKey
    row.route_time_vehicle = vehicleType
    row.route_time_seconds = getSavedRouteTimeSeconds(routeKey, vehicleType)
    row.route_time_text = formatRouteDuration(row.route_time_seconds)
    return row
end

local function syncOriginSelectionFromControl()
    local values = (App.ui.controls.origin_combo ~= nil and type(App.ui.controls.origin_combo.dropdownItem) == "table")
        and App.ui.controls.origin_combo.dropdownItem
        or {}
    if #values == 0 and App.ui.controls.origin_combo ~= nil and type(App.ui.controls.origin_combo.__nuzi_items) == "table" then
        values = App.ui.controls.origin_combo.__nuzi_items
    end
    if #values == 0 then
        for _, entry in ipairs(App.origins or {}) do
            table.insert(values, tostring(entry.name))
        end
    end

    local selectedName = getComboSelectedText(App.ui.controls.origin_combo, values)
    local idx = findIndexByName(App.origins, selectedName)
    if idx == nil then
        idx = getComboIndex1Based(App.ui.controls.origin_combo, #App.origins)
    end
    if idx ~= nil and idx >= 1 and idx <= #App.origins then
        App.selected_origin_index = idx
    end
end

local function syncDestinationSelectionFromControl()
    local values = (App.ui.controls.destination_combo ~= nil and type(App.ui.controls.destination_combo.dropdownItem) == "table")
        and App.ui.controls.destination_combo.dropdownItem
        or {}
    if #values == 0 and App.ui.controls.destination_combo ~= nil and type(App.ui.controls.destination_combo.__nuzi_items) == "table" then
        values = App.ui.controls.destination_combo.__nuzi_items
    end
    if #values == 0 then
        for _, entry in ipairs(App.destinations or {}) do
            table.insert(values, tostring(entry.static_name or entry.name))
        end
    end

    local selectedName = getComboSelectedText(App.ui.controls.destination_combo, values)
    local idx = findIndexByName(App.destinations, selectedName)
    if idx == nil then
        idx = getComboIndex1Based(App.ui.controls.destination_combo, #App.destinations)
    end
    if idx ~= nil and idx >= 1 and idx <= #App.destinations then
        App.selected_destination_index = idx
    end
end

local function syncPackSelectionFromControl()
    local values = (App.ui.controls.pack_combo ~= nil and type(App.ui.controls.pack_combo.dropdownItem) == "table")
        and App.ui.controls.pack_combo.dropdownItem
        or {}
    if #values == 0 and App.ui.controls.pack_combo ~= nil and type(App.ui.controls.pack_combo.__nuzi_items) == "table" then
        values = App.ui.controls.pack_combo.__nuzi_items
    end
    if #values == 0 then
        for _, entry in ipairs(App.packs or {}) do
            table.insert(values, tostring(entry.name))
        end
    end

    local selectedName = getComboSelectedText(App.ui.controls.pack_combo, values)
    local idx = findIndexByName(App.packs, selectedName)
    if idx == nil then
        idx = getComboIndex1Based(App.ui.controls.pack_combo, #App.packs)
    end
    if idx ~= nil and idx >= 1 and idx <= #App.packs then
        App.selected_pack_index = idx
    end
end

local function resetLiveCatalog()
    App.live_origin_name = nil
    App.live_origin_id = nil
    App.live_destinations = {}
end

local function clearDisplayedRoute()
    App.route_rows = {}
    App.current_percent = nil
    App.route_page_index = 1
end

local function refreshOriginCatalog(preferredName)
    ensurePriceIndex()
    local filtered = buildFallbackOriginEntries()
    if #filtered > 0 then
        table.insert(filtered, 1, {
            id = nil,
            name = ALL_ORIGINS_LABEL,
            all_origins = true
        })
    end

    App.origins = filtered

    local preferred = trim(preferredName)
    if preferred == "" then
        preferred = trim(getSelectedOriginName())
    end
    if preferred == "" then
        preferred = trim(App.settings.origin_name)
    end

    local restored = findIndexByName(App.origins, preferred)
    if restored ~= nil then
        App.selected_origin_index = restored
    else
        App.selected_origin_index = math.max(1, math.min(App.selected_origin_index or 1, #App.origins))
    end

    if #App.origins == 0 then
        App.selected_origin_index = 1
    end
end

local function buildPackEntries(originName)
    ensurePriceIndex()
    local allOrigins = isAllOriginName(originName)
    local patterns = allOrigins and nil or buildOriginPatterns(originName)
    local seen = {}
    local packs = {
        {
            name = ALL_PACKS_LABEL,
            all = true
        }
    }

    for _, rows in pairs(App.price_index or {}) do
        for _, row in ipairs(rows or {}) do
            if allOrigins or packMatchesOrigin(row.pack_name, patterns) then
                local key = normalizeKey(row.pack_name)
                if key ~= "" and not seen[key] then
                    seen[key] = true
                    table.insert(packs, {
                        name = tostring(row.pack_name)
                    })
                end
            end
        end
    end

    table.sort(packs, function(a, b)
        if a.all then
            return true
        end
        if b.all then
            return false
        end
        return normalizeKey(a.name) < normalizeKey(b.name)
    end)

    return packs
end

local function refreshPacksForSelectedOrigin(preferredName)
    local origin = App.origins[App.selected_origin_index]
    App.packs = {}
    App.selected_pack_index = 1

    if origin == nil then
        return
    end

    App.packs = buildPackEntries(origin.name)

    local preferred = trim(preferredName)
    if preferred == "" then
        preferred = trim(getSelectedPackName())
    end
    if preferred == "" then
        preferred = trim(App.settings.pack_name)
    end
    if preferred == "" then
        preferred = ALL_PACKS_LABEL
    end

    local restored = findIndexByName(App.packs, preferred)
    if restored ~= nil then
        App.selected_pack_index = restored
    else
        App.selected_pack_index = 1
    end
end

local buildOriginMatcherList
local resolveOriginNameForPack

local function buildStaticDestinationEntries(originName)
    ensurePriceIndex()
    local destinations = {}
    local seen = {}
    local totalRowCount = 0
    local allOrigins = isAllOriginName(originName)
    local originMatchers = allOrigins and buildOriginMatcherList() or nil

    for _, canonicalName in pairs(App.static_destinations or {}) do
        if not seen[canonicalName] then
            seen[canonicalName] = true
            local rowCount = 0
            if allOrigins then
                for _, row in ipairs(App.price_index[canonicalName] or {}) do
                    if resolveOriginNameForPack(row.pack_name, originMatchers) ~= nil then
                        rowCount = rowCount + 1
                    end
                end
            else
                local rows = buildRouteRows(originName, canonicalName, nil)
                rowCount = #rows
            end
            if rowCount > 0 then
                totalRowCount = totalRowCount + rowCount
                table.insert(destinations, {
                    id = nil,
                    name = canonicalName,
                    static_name = canonicalName,
                    percent = nil,
                    row_count = rowCount
                })
            end
        end
    end

    table.sort(destinations, function(a, b)
        return normalizeKey(a.static_name or a.name) < normalizeKey(b.static_name or b.name)
    end)

    if #destinations > 0 and not allOrigins then
        table.insert(destinations, 1, {
            id = nil,
            name = ALL_DESTINATIONS_LABEL,
            static_name = ALL_DESTINATIONS_LABEL,
            percent = nil,
            row_count = totalRowCount,
            all = true
        })
    end

    return destinations
end

resolveLiveCatalogForOrigin = function(originName)
    App.live_origin_name = nil
    App.live_origin_id = nil
    App.live_destinations = {}

    local rawOrigins = callStore("GetProductionZoneGroups")
    local collectedOrigins = {}
    collectZoneEntries(rawOrigins, collectedOrigins, {})
    collectedOrigins = dedupeEntries(collectedOrigins)

    local liveOrigin = nil
    for _, entry in ipairs(collectedOrigins) do
        if originNamesMatch(entry.name, originName) then
            liveOrigin = entry
            break
        end
    end

    if liveOrigin == nil then
        return
    end

    App.live_origin_name = tostring(liveOrigin.name or originName)
    App.live_origin_id = liveOrigin.id

    local rawDestinations = callStore("GetSellableZoneGroups", liveOrigin.id)
    local collectedDestinations = {}
    collectZoneEntries(rawDestinations, collectedDestinations, {})
    collectedDestinations = dedupeEntries(collectedDestinations)

    for _, entry in ipairs(collectedDestinations) do
        local staticName = findStaticDestinationName(entry.name)
        if staticName ~= nil then
            App.live_destinations[normalizeKey(staticName)] = {
                id = entry.id,
                name = entry.name,
                static_name = staticName
            }
        end
    end

end

local function refreshDestinationsForSelectedOrigin(preferredName)
    ensurePriceIndex()
    App.destinations = {}
    App.current_percent = nil

    local origin = App.origins[App.selected_origin_index]
    if origin == nil then
        return
    end

    local destinations = buildStaticDestinationEntries(origin.name)
    App.destinations = destinations

    local preferred = trim(preferredName)
    if preferred == "" then
        preferred = trim(getSelectedDestinationName())
    end
    if preferred == "" then
        preferred = trim(App.settings.destination_name)
    end

    local restored = findIndexByName(App.destinations, preferred)
    if restored ~= nil then
        App.selected_destination_index = restored
    else
        App.selected_destination_index = math.max(1, math.min(App.selected_destination_index or 1, #App.destinations))
    end

end

local function parseManualPercent(text)
    local normalized = trim(text)
    if normalized == "" then
        return nil
    end
    normalized = normalized:gsub("%%", "")
    return normalizeRoutePercent(normalized)
end

local function filterRouteRowsByPack(rows, packName)
    if trim(packName) == "" then
        return rows or {}
    end

    local filteredRows = {}
    local wanted = normalizeKey(packName)
    for _, row in ipairs(rows or {}) do
        if normalizeKey(row.pack_name) == wanted then
            table.insert(filteredRows, row)
        end
    end
    return filteredRows
end

buildOriginMatcherList = function()
    local matchers = {}
    for _, originName in ipairs(FALLBACK_ORIGINS) do
        table.insert(matchers, {
            name = originName,
            patterns = buildOriginPatterns(originName)
        })
    end
    return matchers
end

resolveOriginNameForPack = function(packName, matchers)
    for _, matcher in ipairs(matchers or {}) do
        if packMatchesOrigin(packName, matcher.patterns) then
            return matcher.name
        end
    end
    return nil
end

local function buildAllOriginRouteRows(destinationName, percent, packName)
    ensurePriceIndex()
    local canonicalDestination = findStaticDestinationName(destinationName)
    if canonicalDestination == nil then
        return {}
    end

    local selectedPack = trim(packName)
    local wantedPack = normalizeKey(selectedPack)
    local matchers = buildOriginMatcherList()
    local routeRows = {}

    for _, row in ipairs(App.price_index[canonicalDestination] or {}) do
        if selectedPack == "" or normalizeKey(row.pack_name) == wantedPack then
            local originName = resolveOriginNameForPack(row.pack_name, matchers)
            if originName ~= nil then
                local currentValue = nil
                if percent ~= nil then
                    currentValue = (tonumber(row.max_price) or 0) * percent / MAX_ROUTE_PERCENT
                end
                table.insert(routeRows, applyRouteTimingToRow({
                    origin_name = originName,
                    destination_name = canonicalDestination,
                    pack_name = row.pack_name,
                    currency = row.currency,
                    max_price = row.max_price,
                    max_price_text = row.max_price_text,
                    current_price = currentValue
                }, originName, canonicalDestination))
            end
        end
    end

    table.sort(routeRows, function(a, b)
        local leftOrigin = tostring(a.origin_name or "")
        local rightOrigin = tostring(b.origin_name or "")
        if leftOrigin == rightOrigin then
            if tostring(a.pack_name or "") == tostring(b.pack_name or "") then
                if tostring(a.currency or "") == tostring(b.currency or "") then
                    return (tonumber(a.max_price) or 0) < (tonumber(b.max_price) or 0)
                end
                return tostring(a.currency or "") < tostring(b.currency or "")
            end
            return tostring(a.pack_name or "") < tostring(b.pack_name or "")
        end
        return leftOrigin < rightOrigin
    end)

    return routeRows
end

local function buildAllDestinationRouteRows(originName, percent, packName)
    local routeRows = {}
    local selectedPack = trim(packName)

    for _, destination in ipairs(App.destinations or {}) do
        if not isAllDestinationsEntry(destination) then
            local destinationName = destination.static_name or destination.name
            local rows = buildRouteRows(originName, destinationName, percent)
            rows = filterRouteRowsByPack(rows, selectedPack)

            for _, row in ipairs(rows) do
                table.insert(routeRows, applyRouteTimingToRow({
                    destination_name = destinationName,
                    pack_name = row.pack_name,
                    currency = row.currency,
                    max_price = row.max_price,
                    max_price_text = row.max_price_text,
                    current_price = row.current_price
                }, originName, destinationName))
            end
        end
    end

    table.sort(routeRows, function(a, b)
        local leftDestination = tostring(a.destination_name or "")
        local rightDestination = tostring(b.destination_name or "")
        if leftDestination == rightDestination then
            if tostring(a.pack_name or "") == tostring(b.pack_name or "") then
                if tostring(a.currency or "") == tostring(b.currency or "") then
                    return (tonumber(a.max_price) or 0) < (tonumber(b.max_price) or 0)
                end
                return tostring(a.currency or "") < tostring(b.currency or "")
            end
            return tostring(a.pack_name or "") < tostring(b.pack_name or "")
        end
        return leftDestination < rightDestination
    end)

    return routeRows
end

local function refreshSelectedRoute()
    local origin = App.origins[App.selected_origin_index]
    local destination = App.destinations[App.selected_destination_index]
    if origin == nil or destination == nil then
        App.route_rows = {}
        App.current_percent = nil
        return
    end

    local manualPercent = parseManualPercent(App.settings.manual_percent_text)
    local selectedPack = getSelectedPackFilter()
    local rows = {}

    if isAllOriginsEntry(origin) then
        rows = buildAllOriginRouteRows(destination.static_name or destination.name, manualPercent, selectedPack)
    elseif isAllDestinationsEntry(destination) then
        rows = buildAllDestinationRouteRows(origin.name, manualPercent, selectedPack)
    else
        rows = buildRouteRows(origin.name, destination.static_name or destination.name, manualPercent)
        rows = filterRouteRowsByPack(rows, selectedPack)
    end

    App.current_percent = manualPercent
    App.route_rows = rows
    local pageCount = math.max(1, math.ceil(#App.route_rows / ROWS_PER_PAGE))
    App.route_page_index = math.max(1, math.min(App.route_page_index or 1, pageCount))
    App.settings.origin_name = origin.name
    App.settings.destination_name = destination.static_name or destination.name
    App.settings.pack_name = getSelectedPackFilter()
    saveSettings()
end

local function onOriginSelected()
    if App.syncing_combo then
        return
    end
    local idx = getComboIndex1Based(App.ui.controls.origin_combo, #App.origins)
    if idx == nil or idx < 1 or idx > #App.origins then
        return
    end
    if idx == App.selected_origin_index then
        return
    end
    App.selected_origin_index = idx
    App.selected_pack_index = 1
    App.selected_destination_index = 1
    App.route_page_index = 1
    App.settings.origin_name = getSelectedOriginName()
    App.settings.pack_name = ""
    App.settings.destination_name = ""
    saveSettings()
    refreshPacksForSelectedOrigin("")
    refreshDestinationsForSelectedOrigin("")
    refreshSelectedRoute()
    App.needs_refresh = false
    refreshUi()
end

local function onPackSelected()
    if App.syncing_combo then
        return
    end
    local idx = getComboIndex1Based(App.ui.controls.pack_combo, #App.packs)
    if idx == nil or idx < 1 or idx > #App.packs then
        return
    end
    if idx == App.selected_pack_index then
        return
    end
    App.selected_pack_index = idx
    App.route_page_index = 1
    App.settings.pack_name = getSelectedPackFilter()
    saveSettings()
    refreshSelectedRoute()
    App.needs_refresh = false
    refreshUi()
end

local function onDestinationSelected()
    if App.syncing_combo then
        return
    end
    local idx = getComboIndex1Based(App.ui.controls.destination_combo, #App.destinations)
    if idx == nil or idx < 1 or idx > #App.destinations then
        return
    end
    if idx == App.selected_destination_index then
        return
    end
    App.selected_destination_index = idx
    App.route_page_index = 1
    App.settings.destination_name = getSelectedDestinationName()
    saveSettings()
    refreshSelectedRoute()
    App.needs_refresh = false
    refreshUi()
end

local function onVehicleSelected(vehicleType)
    local idx = getVehicleTypeIndex(vehicleType)
    if idx == nil or idx < 1 or idx > #VEHICLE_TYPES then
        return
    end
    if idx == App.selected_vehicle_index then
        return
    end
    App.selected_vehicle_index = idx
    App.settings.vehicle_type = getSelectedVehicleType()
    saveSettings()
    refreshSelectedRoute()
    refreshUi()
end

local function refreshAll(force)
    if not force and not App.visible then
        return
    end

    local originValues = {}
    for _, entry in ipairs(App.origins or {}) do
        table.insert(originValues, tostring(entry.name))
    end
    local destinationValues = {}
    for _, entry in ipairs(App.destinations or {}) do
        table.insert(destinationValues, tostring(entry.static_name or entry.name))
    end
    local packValues = {}
    for _, entry in ipairs(App.packs or {}) do
        table.insert(packValues, tostring(entry.name))
    end

    local preferredOrigin = getComboSelectedText(App.ui.controls.origin_combo, originValues)
    if preferredOrigin == "" then
        preferredOrigin = getSelectedOriginName()
    end

    local preferredDestination = getComboSelectedText(App.ui.controls.destination_combo, destinationValues)
    if preferredDestination == "" then
        preferredDestination = getSelectedDestinationName()
    end

    local preferredPack = getComboSelectedText(App.ui.controls.pack_combo, packValues)
    if preferredPack == "" then
        preferredPack = getSelectedPackName()
    end

    App.settings.manual_percent_text = getEditText(App.ui.controls.percent_input)

    refreshOriginCatalog(preferredOrigin)
    refreshPacksForSelectedOrigin(preferredPack)
    App.settings.origin_name = getSelectedOriginName()
    refreshDestinationsForSelectedOrigin(preferredDestination)
    refreshSelectedRoute()
    saveSettings()
    App.needs_refresh = false
end

local function cyclePage(delta)
    local pageCount = math.max(1, math.ceil(#App.route_rows / ROWS_PER_PAGE))
    App.route_page_index = App.route_page_index + delta
    if App.route_page_index < 1 then
        App.route_page_index = pageCount
    elseif App.route_page_index > pageCount then
        App.route_page_index = 1
    end
end

local function refreshZoneWindowUi()
    if App.ui.zone_window == nil then
        return
    end

    local shouldShow = App.zone_window_visible
    safeShow(App.ui.zone_window, shouldShow)
    if not shouldShow then
        return
    end

    local nowMs = getUiNowMs()
    local countdownStartedMs = tonumber(App.zone_watch_countdown_started_ms) or 0

    local function resolveZoneTimeText(row)
        if type(row) ~= "table" then
            return "-"
        end

        local remainSeconds = tonumber(row.remain_time)
        if remainSeconds == nil or countdownStartedMs <= 0 then
            return tostring(row.time_text or "-")
        end

        local elapsedSeconds = math.max(0, math.floor((nowMs - countdownStartedMs) / 1000))
        return formatRouteDuration(math.max(0, remainSeconds - elapsedSeconds))
    end

    for _, widgets in ipairs(App.ui.zone_rows or {}) do
        if widgets.kind == "section" then
            setLabelColor(widgets.label, ZONE_WINDOW_SECTION_COLOR)
        elseif widgets.kind == "zone" then
            local row = App.zone_watch_rows[normalizeKey(widgets.zone_name)] or {}
            safeSetText(widgets.name, widgets.zone_name)
            safeSetText(widgets.status, tostring(row.status_text or "Unavailable"))
            safeSetText(widgets.time, resolveZoneTimeText(row))
            setLabelColor(widgets.name, ZONE_WINDOW_NAME_COLOR)
            setLabelColor(widgets.status, row.status_color or ZONE_STATE_COLORS.unknown)
            setLabelColor(widgets.time, row.time_color or ZONE_STATE_COLORS.unknown)
        end
    end
end

updateZoneWindowVisibility = function()
    if App.ui.zone_window ~= nil then
        safeShow(App.ui.zone_window, App.zone_window_visible)
    end
end

toggleZoneWindow = function()
    App.zone_window_visible = not App.zone_window_visible
    if App.zone_window_visible then
        refreshZoneWatchRows(true)
    end
    refreshUi()
end

local function setTimerWindowVisible(show)
    App.timer_window_visible = show and true or false
    updateTimerWidgetVisibility()
    refreshUi()
end

local function toggleTimerWindow()
    setTimerWindowVisible(not App.timer_window_visible)
end

refreshUi = function()
    if App.ui.window == nil and App.ui.timer_window == nil then
        return
    end

    local selectedVehicleType = getSelectedVehicleType()
    local concreteRoute = getCurrentConcreteRouteInfo()
    local timerValueText = formatRouteDuration(getRouteTimerElapsedMs() / 1000)
    local timerRouteText = ""
    local timerStatusText = tostring(App.route_timer.status_text or "")

    if App.route_timer.route_key ~= nil then
        timerRouteText = tostring(App.route_timer.route_label or "")
    elseif concreteRoute ~= nil then
        timerRouteText = concreteRoute.route_label
        local savedSeconds = getSavedRouteTimeSeconds(concreteRoute.route_key, selectedVehicleType)
        if savedSeconds ~= nil then
            timerStatusText = string.format("Saved %s route time: %s", selectedVehicleType, formatRouteDuration(savedSeconds))
            timerValueText = formatRouteDuration(savedSeconds)
        elseif timerStatusText == "" then
            timerStatusText = string.format("No saved %s route time for the selected route.", selectedVehicleType)
        end
    else
        timerRouteText = "Choose one origin, one destination, and one pack to enable route timing."
    end

    if type(App.ui.controls.vehicle_buttons) == "table" then
        for index, button in ipairs(App.ui.controls.vehicle_buttons) do
            local label = VEHICLE_TYPES[index] or ""
            if index == App.selected_vehicle_index then
                label = "[" .. label .. "]"
            end
            safeSetText(button, label)
        end
    end
    safeSetText(App.ui.controls.timer_value, timerValueText)
    safeSetText(App.ui.controls.timer_route, timerRouteText)
    safeSetText(App.ui.controls.timer_status, timerStatusText)
    safeSetText(App.ui.controls.timer_toggle_button, App.timer_window_visible and "Hide Timer" or "Show Timer")
    updateTimerWidgetVisibility()

    if not App.visible or App.ui.window == nil then
        refreshZoneWindowUi()
        return
    end

    local originTotal = #App.origins
    local packTotal = #App.packs
    local destinationTotal = #App.destinations
    local originIndexText = originTotal > 0 and tostring(App.selected_origin_index) or "0"
    local packIndexText = packTotal > 0 and tostring(App.selected_pack_index) or "0"
    local destinationIndexText = destinationTotal > 0 and tostring(App.selected_destination_index) or "0"
    local pageCount = math.max(1, math.ceil(#App.route_rows / ROWS_PER_PAGE))
    local rowStart = ((App.route_page_index - 1) * ROWS_PER_PAGE) + 1
    local selectedOrigin = App.origins[App.selected_origin_index]
    local selectedDestination = App.destinations[App.selected_destination_index]
    local allOriginsMode = isAllOriginsEntry(selectedOrigin)
    local allDestinationsMode = isAllDestinationsEntry(selectedDestination)
    local selectedPack = getSelectedPackFilter()

    local originItems = {}
    for _, entry in ipairs(App.origins or {}) do
        table.insert(originItems, tostring(entry.name))
    end
    if #originItems == 0 then
        originItems = { "Unavailable" }
    end
    App.syncing_combo = true
    if App.ui.controls.origin_combo ~= nil then
        setComboItems(App.ui.controls.origin_combo, originItems)
        setComboIndex1Based(App.ui.controls.origin_combo, math.min(App.selected_origin_index, #originItems))
    end

    local packItems = {}
    for _, entry in ipairs(App.packs or {}) do
        table.insert(packItems, tostring(entry.name))
    end
    if #packItems == 0 then
        packItems = { ALL_PACKS_LABEL }
    end
    if App.ui.controls.pack_combo ~= nil then
        setComboItems(App.ui.controls.pack_combo, packItems)
        setComboIndex1Based(App.ui.controls.pack_combo, math.min(App.selected_pack_index, #packItems))
    end

    local destinationItems = {}
    for _, entry in ipairs(App.destinations or {}) do
        table.insert(destinationItems, tostring(entry.static_name or entry.name))
    end
    if #destinationItems == 0 then
        destinationItems = { "Unavailable" }
    end
    if App.ui.controls.destination_combo ~= nil then
        setComboItems(App.ui.controls.destination_combo, destinationItems)
        setComboIndex1Based(App.ui.controls.destination_combo, math.min(App.selected_destination_index, #destinationItems))
    end
    App.syncing_combo = false

    safeSetText(App.ui.controls.origin_meta, string.format("%s / %d", originIndexText, originTotal))
    safeSetText(App.ui.controls.pack_meta, string.format("%s / %d", packIndexText, packTotal))
    safeSetText(App.ui.controls.destination_meta, string.format("%s / %d", destinationIndexText, destinationTotal))
    safeSetText(App.ui.controls.launcher_size_value, tostring(getLauncherButtonSize()))
    safeSetText(App.ui.controls.page_value, string.format("Page %d / %d", App.route_page_index, pageCount))
    local routeNameHeader = "Pack"
    if allOriginsMode then
        routeNameHeader = selectedPack ~= "" and "Origin" or "Origin / Pack"
    elseif allDestinationsMode then
        routeNameHeader = selectedPack ~= "" and "Destination" or "Destination / Pack"
    end
    safeSetText(App.ui.controls.pack_header, routeNameHeader)
    safeSetText(App.ui.controls.currency_header, "Currency")
    safeSetText(App.ui.controls.cap_header, string.format("%s%%", tostring(App.current_percent or MAX_ROUTE_PERCENT)))
    safeSetText(App.ui.controls.live_header, "Live")
    safeSetText(App.ui.controls.route_time_header, string.format("%s Time", selectedVehicleType))

    for index = 1, ROWS_PER_PAGE do
        local widgets = App.ui.rows[index]
        local row = App.route_rows[rowStart + index - 1]
        if widgets ~= nil then
            if row ~= nil then
                local packText = tostring(row.pack_name or "")
                if allOriginsMode then
                    local originName = tostring(row.origin_name or "")
                    if selectedPack ~= "" then
                        packText = originName
                    else
                        packText = string.format("%s - %s", originName, tostring(row.pack_name or ""))
                    end
                elseif allDestinationsMode then
                    local destinationName = tostring(row.destination_name or "")
                    if selectedPack ~= "" then
                        packText = destinationName
                    else
                        packText = string.format("%s - %s", destinationName, tostring(row.pack_name or ""))
                    end
                end
                safeSetText(widgets.pack, packText)
                safeSetText(widgets.currency, tostring(row.currency or ""))
                if tostring(row.currency or "") == "Gold" then
                    safeSetText(widgets.cap, row.max_price_text ~= nil and tostring(row.max_price_text) or formatGold(row.max_price))
                else
                    safeSetText(widgets.cap, tostring(row.max_price or ""))
                end
                if row.current_price ~= nil then
                    if tostring(row.currency or "") == "Gold" then
                        safeSetText(widgets.live, formatGold(row.current_price))
                    else
                        safeSetText(widgets.live, tostring(round2(row.current_price)))
                    end
                    setLabelColor(widgets.live, { 140, 255, 170, 255 })
                else
                    safeSetText(widgets.live, "-")
                    setLabelColor(widgets.live, { 180, 180, 180, 255 })
                end
                safeSetText(widgets.route_time, tostring(row.route_time_text or "-"))
                safeShow(widgets.pack, true)
                safeShow(widgets.currency, true)
                safeShow(widgets.cap, true)
                safeShow(widgets.live, true)
                safeShow(widgets.route_time, true)
            else
                safeSetText(widgets.pack, "")
                safeSetText(widgets.currency, "")
                safeSetText(widgets.cap, "")
                safeSetText(widgets.live, "")
                safeSetText(widgets.route_time, "")
                safeShow(widgets.pack, false)
                safeShow(widgets.currency, false)
                safeShow(widgets.cap, false)
                safeShow(widgets.live, false)
                safeShow(widgets.route_time, false)
            end
        end
    end

    refreshZoneWindowUi()
end

updateTimerWidgetVisibility = function()
    local shouldShow = App.timer_window_visible == true
    if App.ui.timer_window ~= nil then
        safeShow(App.ui.timer_window, shouldShow)
    end
end

local function closeWindow()
    if App.closing_window then
        return
    end
    App.closing_window = true
    App.visible = false
    if App.ui.window ~= nil then
        saveMainWindowPosition(App.ui.window)
    end
    if App.ui.window ~= nil then
        safeShow(App.ui.window, false)
    end
    updateZoneWindowVisibility()
    updateTimerWidgetVisibility()
    App.closing_window = false
end

local function openWindow()
    App.visible = true
    App.needs_refresh = true
    if App.ui.window ~= nil then
        safeShow(App.ui.window, true)
    end
    refreshOriginCatalog(App.settings.origin_name)
    refreshPacksForSelectedOrigin(App.settings.pack_name)
    refreshDestinationsForSelectedOrigin(App.settings.destination_name)
    refreshSelectedRoute()
    if App.zone_window_visible then
        refreshZoneWatchRows(true)
    end
    safeSetText(App.ui.controls.percent_input, App.settings.manual_percent_text or "130")
    refreshUi()
end

local function toggleWindow()
    if App.visible then
        closeWindow()
    else
        openWindow()
    end
end

local function createUi()
    if App.ui.button == nil then
        local launcherSize = getLauncherButtonSize()
        local button = createLauncherButton("nuziTradeToggleButton", App.settings.button_x, App.settings.button_y, launcherSize)
        if button ~= nil and button.SetHandler ~= nil then
            button:SetHandler("OnClick", function()
                toggleWindow()
            end)
            enableDrag(button, function(self)
                saveButtonPosition(self)
            end)
        end
        App.ui.button = button
        applyLauncherButtonAppearance()
    end

    if App.ui.window ~= nil then
        return
    end

    if api.Interface == nil or api.Interface.CreateWindow == nil then
        return
    end

    local window = api.Interface:CreateWindow("nuziTradeWindow", "Nuzi Trade", 920, 500)
    if window == nil then
        return
    end
    window:AddAnchor("TOPLEFT", "UIParent", App.settings.trade_window_x, App.settings.trade_window_y)
    enableDrag(window, function(self)
        saveMainWindowPosition(self)
    end)
    pcall(function()
        window:SetHandler("OnCloseByEsc", closeWindow)
    end)
    pcall(function()
        window:SetHandler("OnHide", closeWindow)
    end)
    pcall(function()
        window:SetHandler("OnClose", closeWindow)
    end)

    App.ui.window = window

    createSectionPanel(window, "Route", 14, 34, 526, 126)
    createSectionPanel(window, "Tools", 554, 34, 352, 126)
    createSectionPanel(window, "Results", 14, 172, 892, 296)

    createLabel("nuziTradeOriginLabel", window, "Origin", 32, 72, 70, 18, 13)
    App.ui.controls.origin_combo = createComboBox(window, 118, 66, 336, { "Loading..." })
    App.ui.controls.origin_meta = createLabel("nuziTradeOriginMeta", window, "", 462, 72, 56, 18, 12)
    if App.ui.controls.origin_combo ~= nil then
        pcall(function()
            App.ui.controls.origin_combo:SetHandler("OnSelChanged", onOriginSelected)
        end)
    end

    createLabel("nuziTradePackLabel", window, "Pack", 32, 104, 70, 18, 13)
    App.ui.controls.pack_combo = createComboBox(window, 118, 98, 336, { ALL_PACKS_LABEL })
    App.ui.controls.pack_meta = createLabel("nuziTradePackMeta", window, "", 462, 104, 56, 18, 12)
    if App.ui.controls.pack_combo ~= nil then
        pcall(function()
            App.ui.controls.pack_combo:SetHandler("OnSelChanged", onPackSelected)
        end)
    end

    createLabel("nuziTradeDestinationLabel", window, "Destination", 32, 136, 76, 18, 13)
    App.ui.controls.destination_combo = createComboBox(window, 118, 130, 336, { "Loading..." })
    App.ui.controls.destination_meta = createLabel("nuziTradeDestinationMeta", window, "", 462, 136, 56, 18, 12)
    if App.ui.controls.destination_combo ~= nil then
        pcall(function()
            App.ui.controls.destination_combo:SetHandler("OnSelChanged", onDestinationSelected)
        end)
    end

    createLabel("nuziTradeManualPercentLabel", window, "Live %", 572, 72, 64, 18, 13)
    App.ui.controls.percent_input = createEdit("nuziTradeManualPercent", window, App.settings.manual_percent_text or "130", 650, 66, 76, 8)

    createLabel("nuziTradeLauncherSizeLabel", window, "Launcher", 572, 104, 68, 18, 13)
    App.ui.controls.launcher_size_slider = createSlider(
        "nuziTradeLauncherSize",
        window,
        650,
        100,
        132,
        LAUNCHER_BUTTON_MIN_SIZE,
        LAUNCHER_BUTTON_MAX_SIZE,
        1
    )
    App.ui.controls.launcher_size_value = createLabel("nuziTradeLauncherSizeValue", window, "", 790, 104, 28, 18, 12)
    if App.ui.controls.launcher_size_slider ~= nil and App.ui.controls.launcher_size_slider.SetHandler ~= nil then
        App.ui.controls.launcher_size_slider:SetHandler("OnSliderChanged", function(_, raw)
            if App.syncing_launcher_slider then
                return
            end
            setLauncherButtonSize(raw, true)
        end)
    end

    App.ui.controls.timer_toggle_button = createButton("nuziTradeTimerToggle", window, "Show Timer", 572, 128, 104, 26)
    if App.ui.controls.timer_toggle_button ~= nil and App.ui.controls.timer_toggle_button.SetHandler ~= nil then
        App.ui.controls.timer_toggle_button:SetHandler("OnClick", function()
            toggleTimerWindow()
        end)
    end

    local zonesButton = createButton("nuziTradeZones", window, "Zones", 684, 128, 92, 26)
    if zonesButton ~= nil and zonesButton.SetHandler ~= nil then
        zonesButton:SetHandler("OnClick", function()
            toggleZoneWindow()
        end)
    end

    local refreshButton = createButton("nuziTradeRefresh", window, "Refresh", 784, 128, 92, 26)
    if refreshButton ~= nil and refreshButton.SetHandler ~= nil then
        refreshButton:SetHandler("OnClick", function()
            refreshAll(true)
            refreshUi()
        end)
    end

    App.ui.controls.page_value = createLabel("nuziTradePageValue", window, "", 32, 206, 180, 18, 12)
    setLauncherButtonSize(getLauncherButtonSize(), false)

    local prevButton = createButton("nuziTradePrevPage", window, "Prev Page", 686, 202, 88, 24)
    if prevButton ~= nil and prevButton.SetHandler ~= nil then
        prevButton:SetHandler("OnClick", function()
            cyclePage(-1)
            refreshUi()
        end)
    end
    local nextButton = createButton("nuziTradeNextPage", window, "Next Page", 784, 202, 88, 24)
    if nextButton ~= nil and nextButton.SetHandler ~= nil then
        nextButton:SetHandler("OnClick", function()
            cyclePage(1)
            refreshUi()
        end)
    end

    App.ui.controls.pack_header = createLabel("nuziTradePackHeader", window, "Pack", 32, 238, 344, 18, 12)
    App.ui.controls.currency_header = createLabel("nuziTradeCurrencyHeader", window, "Currency", 392, 238, 96, 18, 12)
    App.ui.controls.cap_header = createLabel("nuziTradeCapHeader", window, "130%", 506, 238, 72, 18, 12)
    App.ui.controls.live_header = createLabel("nuziTradeLiveHeader", window, "Live", 592, 238, 72, 18, 12)
    App.ui.controls.route_time_header = createLabel("nuziTradeRouteTimeHeader", window, "Route Time", 684, 238, 140, 18, 12)

    for index = 1, ROWS_PER_PAGE do
        local y = 262 + ((index - 1) * 18)
        App.ui.rows[index] = {
            pack = createLabel("nuziTradePackRow" .. tostring(index), window, "", 32, y, 348, 18, 12),
            currency = createLabel("nuziTradeCurrencyRow" .. tostring(index), window, "", 392, y, 96, 18, 12),
            cap = createLabel("nuziTradeCapRow" .. tostring(index), window, "", 506, y, 72, 18, 12),
            live = createLabel("nuziTradeLiveRow" .. tostring(index), window, "", 592, y, 72, 18, 12),
            route_time = createLabel("nuziTradeRouteTimeRow" .. tostring(index), window, "", 684, y, 140, 18, 12)
        }
        setLabelColor(App.ui.rows[index].cap, { 255, 226, 180, 255 })
    end

    local timerWindow = api.Interface:CreateWindow("nuziTradeTimerWindow", "Nuzi Trade Timer", 396, 148)
    if timerWindow ~= nil then
        timerWindow:AddAnchor("TOPLEFT", "UIParent", App.settings.timer_window_x, App.settings.timer_window_y)
        enableDrag(timerWindow, function(self)
            saveWidgetPosition(self, "timer_window_x", "timer_window_y")
        end)

        createLabel("nuziTradeTimerLabel", timerWindow, "Route Timer", 16, 40, 78, 18, 13)
        App.ui.controls.timer_value = createLabel("nuziTradeTimerValue", timerWindow, "00:00", 98, 40, 74, 18, 13)
        App.ui.controls.vehicle_buttons = {}
        for index, vehicleType in ipairs(VEHICLE_TYPES) do
            local x = 176 + ((index - 1) * 68)
            local button = createButton("nuziTradeVehicle" .. tostring(index), timerWindow, vehicleType, x, 34, 64, 24)
            if button ~= nil and button.SetHandler ~= nil then
                button:SetHandler("OnClick", function()
                    onVehicleSelected(vehicleType)
                end)
            end
            App.ui.controls.vehicle_buttons[index] = button
        end

        local startTimerButton = createButton("nuziTradeTimerStart", timerWindow, "Start", 16, 72, 68, 24)
        if startTimerButton ~= nil and startTimerButton.SetHandler ~= nil then
            startTimerButton:SetHandler("OnClick", startRouteTimer)
        end
        local stopTimerButton = createButton("nuziTradeTimerStop", timerWindow, "Stop", 92, 72, 68, 24)
        if stopTimerButton ~= nil and stopTimerButton.SetHandler ~= nil then
            stopTimerButton:SetHandler("OnClick", stopRouteTimer)
        end
        local saveTimerButton = createButton("nuziTradeTimerSave", timerWindow, "Save", 168, 72, 68, 24)
        if saveTimerButton ~= nil and saveTimerButton.SetHandler ~= nil then
            saveTimerButton:SetHandler("OnClick", saveRouteTimer)
        end

        App.ui.controls.timer_route = createLabel("nuziTradeTimerRoute", timerWindow, "", 16, 104, 360, 18, 12)
        App.ui.controls.timer_status = createLabel("nuziTradeTimerStatus", timerWindow, "", 16, 122, 360, 18, 12)
        App.ui.timer_window = timerWindow

        local function onTimerWindowClosed()
            if App.timer_window_visible then
                setTimerWindowVisible(false)
            end
        end

        pcall(function()
            timerWindow:SetHandler("OnCloseByEsc", onTimerWindowClosed)
        end)
        pcall(function()
            timerWindow:SetHandler("OnHide", onTimerWindowClosed)
        end)
        pcall(function()
            timerWindow:SetHandler("OnClose", onTimerWindowClosed)
        end)

        safeShow(timerWindow, App.timer_window_visible)
    end

    local zoneWindow = api.Interface:CreateWindow("nuziTradeZoneWindow", "Nuzi Trade Zone Status", 520, 344)
    if zoneWindow ~= nil then
        zoneWindow:AddAnchor("TOPLEFT", "UIParent", App.settings.zone_window_x, App.settings.zone_window_y)
        enableDrag(zoneWindow, function(self)
            saveWidgetPosition(self, "zone_window_x", "zone_window_y")
        end)

        local function onZoneWindowClosed()
            App.zone_window_visible = false
            refreshUi()
        end

        pcall(function()
            zoneWindow:SetHandler("OnCloseByEsc", onZoneWindowClosed)
        end)
        pcall(function()
            zoneWindow:SetHandler("OnHide", onZoneWindowClosed)
        end)
        pcall(function()
            zoneWindow:SetHandler("OnClose", onZoneWindowClosed)
        end)

        createOutlinedLabel("nuziTradeZoneSummary", zoneWindow, "Status and timer for the current contested-zone rotation.", 16, 40, 340, 18, 12)

        local zoneRefreshButton = createButton("nuziTradeZoneRefresh", zoneWindow, "Refresh", 400, 34, 96, 24)
        if zoneRefreshButton ~= nil and zoneRefreshButton.SetHandler ~= nil then
            zoneRefreshButton:SetHandler("OnClick", function()
                refreshZoneWatchRows(true)
                refreshUi()
            end)
        end

        createOutlinedLabel("nuziTradeZoneHeaderName", zoneWindow, "Zone", 18, 72, 170, 18, 12)
        createOutlinedLabel("nuziTradeZoneHeaderState", zoneWindow, "Status", 220, 72, 148, 18, 12)
        createOutlinedLabel("nuziTradeZoneHeaderTime", zoneWindow, "Time Left", 394, 72, 96, 18, 12)

        local y = 96
        App.ui.zone_rows = {}
        for _, entry in ipairs(ZONE_WATCH_LAYOUT) do
            if entry.kind == "section" then
                App.ui.zone_rows[#App.ui.zone_rows + 1] = {
                    kind = "section",
                    label = createOutlinedLabel("nuziTradeZoneSection" .. tostring(#App.ui.zone_rows + 1), zoneWindow, entry.title, 18, y, 180, 18, 13)
                }
                y = y + 22
            else
                App.ui.zone_rows[#App.ui.zone_rows + 1] = {
                    kind = "zone",
                    zone_name = entry.name,
                    name = createOutlinedLabel("nuziTradeZoneName" .. tostring(#App.ui.zone_rows + 1), zoneWindow, entry.name, 18, y, 182, 18, 12),
                    status = createOutlinedLabel("nuziTradeZoneState" .. tostring(#App.ui.zone_rows + 1), zoneWindow, "Unavailable", 220, y, 160, 18, 12),
                    time = createOutlinedLabel("nuziTradeZoneTime" .. tostring(#App.ui.zone_rows + 1), zoneWindow, "-", 394, y, 96, 18, 12)
                }
                y = y + 18
            end
        end

        App.ui.zone_window = zoneWindow
        safeShow(zoneWindow, false)
    end

    safeShow(window, false)
end

local function unloadUi()
    if api.Interface ~= nil and api.Interface.Free ~= nil then
        if App.ui.button ~= nil then
            pcall(function()
                api.Interface:Free(App.ui.button)
            end)
        end
        if App.ui.window ~= nil then
            pcall(function()
                api.Interface:Free(App.ui.window)
            end)
        end
        if App.ui.timer_window ~= nil then
            pcall(function()
                api.Interface:Free(App.ui.timer_window)
            end)
        end
        if App.ui.zone_window ~= nil then
            pcall(function()
                api.Interface:Free(App.ui.zone_window)
            end)
        end
    end
    App.ui.button = nil
    App.ui.window = nil
    App.ui.timer_window = nil
    App.ui.zone_window = nil
    App.ui.controls = {}
    App.ui.rows = {}
    App.ui.zone_rows = {}
end

local function onUpdate(dt)
    if not App.loaded then
        return
    end

    if not App.visible and not App.zone_window_visible and not App.route_timer.running then
        return
    end

    if App.visible and App.ui.window ~= nil and not isWidgetVisible(App.ui.window) then
        closeWindow()
        return
    end

    if App.zone_window_visible then
        if App.ui.zone_window ~= nil and not isWidgetVisible(App.ui.zone_window) then
            App.zone_window_visible = false
            refreshUi()
            return
        end
        local now = getUiNowMs()
        local renderSecond = math.floor(now / 1000)
        if renderSecond ~= App.zone_watch_last_render_second then
            App.zone_watch_last_render_second = renderSecond
            refreshUi()
        end
        if (now - (tonumber(App.zone_watch_last_refresh_ms) or 0)) >= ZONE_STATE_REFRESH_INTERVAL_MS then
            refreshZoneWatchRows(false)
            refreshUi()
        end
    end

    if App.route_timer.running then
        local elapsedSeconds = math.floor(getRouteTimerElapsedMs() / 1000)
        if elapsedSeconds ~= App.route_timer.last_render_second then
            App.route_timer.last_render_second = elapsedSeconds
            refreshUi()
        end
    end
end

local function onUiReloaded()
    App.zone_state_manager = nil
    App.timer_window_visible = false
    unloadUi()
    createUi()
    if App.visible then
        openWindow()
    else
        closeWindow()
    end
end

function addon.OnLoad()
    loadSettings()
    createUi()
    App.loaded = true
    App.visible = false
    closeWindow()
    events:OnSafe("UPDATE", "UPDATE", onUpdate)
    events:OnSafe("UI_RELOADED", "UI_RELOADED", onUiReloaded)
    logInfo("Loaded v" .. tostring(addon.version))
end

function addon.OnUnload()
    App.loaded = false
    App.visible = false
    App.zone_state_manager = nil
    unloadUi()
    events:ClearAll()
end

addon.OnSettingToggle = function()
    toggleWindow()
    refreshUi()
end

return addon
