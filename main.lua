local api = require("api")

local function loadModule(candidates)
    for _, name in ipairs(candidates or {}) do
        local ok, mod = pcall(require, name)
        if ok and type(mod) == "table" then
            return mod
        end
    end
    return nil
end

local addon = {
    name = "Nuzi Trade",
    author = "Nuzi",
    version = "0.2.2",
    desc = "Trade pack values"
}

local SETTINGS_ID = "nuzi_trade"
local MAX_ROUTE_PERCENT = 130
local ROWS_PER_PAGE = 10
local ALL_PACKS_LABEL = "All Packs"
local ALL_DESTINATIONS_LABEL = "All Destinations"

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
    route_page_index = 1,
    current_percent = nil,
    needs_refresh = true,
    closing_window = false,
    syncing_combo = false,
    ui = {
        button = nil,
        window = nil,
        controls = {},
        rows = {}
    }
}

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

local function startsWith(text, prefix)
    return text:sub(1, #prefix) == prefix
end

local function safeShow(widget, show)
    if widget ~= nil and widget.Show ~= nil then
        pcall(function()
            widget:Show(show and true or false)
        end)
    end
end

local function safeSetText(widget, text)
    if widget ~= nil and widget.SetText ~= nil then
        pcall(function()
            widget:SetText(tostring(text or ""))
        end)
    end
end

local function isWidgetVisible(widget)
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

local function setLabelColor(label, rgba)
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
        if label.style.SetShadow ~= nil then
            label.style:SetShadow(true)
        end
    end
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
    pcall(function()
        api.Log:Info("[Nuzi Trade] " .. tostring(message))
    end)
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
        rows = loadModule({
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

local function saveSettings()
    if App.settings == nil then
        return
    end
    pcall(function()
        api.SaveSettings()
    end)
end

local function loadSettings()
    local settings = api.GetSettings(SETTINGS_ID)
    if type(settings) ~= "table" then
        settings = api.GetSettings("nuzi-trade")
    end
    if type(settings) ~= "table" then
        settings = {}
    end
    if settings.button_x == nil then
        settings.button_x = 16
    end
    if settings.button_y == nil then
        settings.button_y = 240
    end
    if settings.origin_name == nil then
        settings.origin_name = ""
    end
    if settings.destination_name == nil then
        settings.destination_name = ""
    end
    if settings.pack_name == nil then
        settings.pack_name = ""
    end
    if settings.manual_percent_text == nil then
        settings.manual_percent_text = "130"
    end
    if trim(settings.manual_percent_text) == "" then
        settings.manual_percent_text = "130"
    end
    App.settings = settings
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
            if packName ~= "" and destination ~= "" and price ~= nil then
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
            table.insert(routeRows, {
                pack_name = row.pack_name,
                currency = row.currency,
                max_price = row.max_price,
                max_price_text = row.max_price_text,
                current_price = currentValue
            })
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

local function callStore(method, ...)
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

local function collectZoneEntries(node, results, visited)
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

local function dedupeEntries(entries)
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

local function destinationNamesMatch(left, right)
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

local function isAllDestinationsEntry(entry)
    if type(entry) ~= "table" then
        return false
    end
    if entry.all == true then
        return true
    end
    return normalizeKey(entry.static_name or entry.name) == normalizeKey(ALL_DESTINATIONS_LABEL)
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
    local patterns = buildOriginPatterns(originName)
    local seen = {}
    local packs = {
        {
            name = ALL_PACKS_LABEL,
            all = true
        }
    }

    for _, rows in pairs(App.price_index or {}) do
        for _, row in ipairs(rows or {}) do
            if packMatchesOrigin(row.pack_name, patterns) then
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

local function buildStaticDestinationEntries(originName)
    ensurePriceIndex()
    local destinations = {}
    local seen = {}
    local totalRowCount = 0

    for _, canonicalName in pairs(App.static_destinations or {}) do
        if not seen[canonicalName] then
            seen[canonicalName] = true
            local rows = buildRouteRows(originName, canonicalName, nil)
            if #rows > 0 then
                totalRowCount = totalRowCount + #rows
                table.insert(destinations, {
                    id = nil,
                    name = canonicalName,
                    static_name = canonicalName,
                    percent = nil,
                    row_count = #rows
                })
            end
        end
    end

    table.sort(destinations, function(a, b)
        return normalizeKey(a.static_name or a.name) < normalizeKey(b.static_name or b.name)
    end)

    if #destinations > 0 then
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

local function resolveLiveCatalogForOrigin(originName)
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

    App.live_origin_name = originName
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

local function buildAllDestinationRouteRows(originName, percent, packName)
    local routeRows = {}
    local selectedPack = trim(packName)

    for _, destination in ipairs(App.destinations or {}) do
        if not isAllDestinationsEntry(destination) then
            local destinationName = destination.static_name or destination.name
            local rows = buildRouteRows(originName, destinationName, percent)
            rows = filterRouteRowsByPack(rows, selectedPack)

            for _, row in ipairs(rows) do
                table.insert(routeRows, {
                    destination_name = destinationName,
                    pack_name = row.pack_name,
                    currency = row.currency,
                    max_price = row.max_price,
                    max_price_text = row.max_price_text,
                    current_price = row.current_price
                })
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

    if isAllDestinationsEntry(destination) then
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
    clearDisplayedRoute()
    App.needs_refresh = true
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
    clearDisplayedRoute()
    App.needs_refresh = true
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
    clearDisplayedRoute()
    App.needs_refresh = true
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

local function refreshUi()
    if App.ui.window == nil then
        return
    end

    if not App.visible then
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
    local selectedDestination = App.destinations[App.selected_destination_index]
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
    safeSetText(App.ui.controls.page_value, string.format("Page %d / %d", App.route_page_index, pageCount))
    safeSetText(App.ui.controls.pack_header, allDestinationsMode and (selectedPack ~= "" and "Destination" or "Destination / Pack") or "Pack")
    safeSetText(App.ui.controls.currency_header, "Currency")
    safeSetText(App.ui.controls.cap_header, string.format("%s%%", tostring(App.current_percent or MAX_ROUTE_PERCENT)))
    safeSetText(App.ui.controls.live_header, "Live")

    for index = 1, ROWS_PER_PAGE do
        local widgets = App.ui.rows[index]
        local row = App.route_rows[rowStart + index - 1]
        if widgets ~= nil then
            if row ~= nil then
                local packText = tostring(row.pack_name or "")
                if allDestinationsMode then
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
                safeShow(widgets.pack, true)
                safeShow(widgets.currency, true)
                safeShow(widgets.cap, true)
                safeShow(widgets.live, true)
            else
                safeSetText(widgets.pack, "")
                safeSetText(widgets.currency, "")
                safeSetText(widgets.cap, "")
                safeSetText(widgets.live, "")
                safeShow(widgets.pack, false)
                safeShow(widgets.currency, false)
                safeShow(widgets.cap, false)
                safeShow(widgets.live, false)
            end
        end
    end
end

local function closeWindow()
    if App.closing_window then
        return
    end
    App.closing_window = true
    App.visible = false
    if App.ui.window ~= nil then
        safeShow(App.ui.window, false)
    end
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
    clearDisplayedRoute()
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
        local parent = api.rootWindow
        local button = createButton("nuziTradeToggleButton", parent, "NT", App.settings.button_x, App.settings.button_y, 44, 28)
        if button ~= nil and button.SetHandler ~= nil then
            button:SetHandler("OnClick", function()
                toggleWindow()
            end)
        end
        App.ui.button = button
    end

    if App.ui.window ~= nil then
        return
    end

    if api.Interface == nil or api.Interface.CreateWindow == nil then
        return
    end

    local window = api.Interface:CreateWindow("nuziTradeWindow", "Nuzi Trade", 640, 430)
    if window == nil then
        return
    end
    window:AddAnchor("CENTER", "UIParent", 0, 0)
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

    createLabel("nuziTradeOriginLabel", window, "Origin", 18, 42, 54, 18, 13)
    App.ui.controls.origin_combo = createComboBox(window, 84, 36, 340, { "Loading..." })
    App.ui.controls.origin_meta = createLabel("nuziTradeOriginMeta", window, "", 432, 42, 56, 18, 12)
    if App.ui.controls.origin_combo ~= nil then
        pcall(function()
            App.ui.controls.origin_combo:SetHandler("OnSelChanged", onOriginSelected)
        end)
    end

    createLabel("nuziTradePackLabel", window, "Pack", 18, 74, 54, 18, 13)
    App.ui.controls.pack_combo = createComboBox(window, 84, 68, 340, { ALL_PACKS_LABEL })
    App.ui.controls.pack_meta = createLabel("nuziTradePackMeta", window, "", 432, 74, 56, 18, 12)
    if App.ui.controls.pack_combo ~= nil then
        pcall(function()
            App.ui.controls.pack_combo:SetHandler("OnSelChanged", onPackSelected)
        end)
    end

    createLabel("nuziTradeDestinationLabel", window, "Destination", 18, 106, 70, 18, 13)
    App.ui.controls.destination_combo = createComboBox(window, 84, 100, 340, { "Loading..." })
    App.ui.controls.destination_meta = createLabel("nuziTradeDestinationMeta", window, "", 432, 106, 56, 18, 12)
    if App.ui.controls.destination_combo ~= nil then
        pcall(function()
            App.ui.controls.destination_combo:SetHandler("OnSelChanged", onDestinationSelected)
        end)
    end

    createLabel("nuziTradeManualPercentLabel", window, "Live %", 18, 138, 54, 18, 13)
    App.ui.controls.percent_input = createEdit("nuziTradeManualPercent", window, App.settings.manual_percent_text or "130", 84, 132, 96, 8)

    local refreshButton = createButton("nuziTradeRefresh", window, "Refresh", 506, 84, 116, 40)
    if refreshButton ~= nil and refreshButton.SetHandler ~= nil then
        refreshButton:SetHandler("OnClick", function()
            refreshAll(true)
            refreshUi()
        end)
    end

    App.ui.controls.page_value = createLabel("nuziTradePageValue", window, "", 18, 170, 180, 18, 12)

    local prevButton = createButton("nuziTradePrevPage", window, "Prev Page", 438, 164, 88, 24)
    if prevButton ~= nil and prevButton.SetHandler ~= nil then
        prevButton:SetHandler("OnClick", function()
            cyclePage(-1)
            refreshUi()
        end)
    end
    local nextButton = createButton("nuziTradeNextPage", window, "Next Page", 534, 164, 88, 24)
    if nextButton ~= nil and nextButton.SetHandler ~= nil then
        nextButton:SetHandler("OnClick", function()
            cyclePage(1)
            refreshUi()
        end)
    end

    App.ui.controls.pack_header = createLabel("nuziTradePackHeader", window, "Pack", 18, 200, 290, 18, 12)
    App.ui.controls.currency_header = createLabel("nuziTradeCurrencyHeader", window, "Currency", 330, 200, 120, 18, 12)
    App.ui.controls.cap_header = createLabel("nuziTradeCapHeader", window, "130%", 470, 200, 50, 18, 12)
    App.ui.controls.live_header = createLabel("nuziTradeLiveHeader", window, "Live", 544, 200, 60, 18, 12)

    for index = 1, ROWS_PER_PAGE do
        local y = 224 + ((index - 1) * 18)
        App.ui.rows[index] = {
            pack = createLabel("nuziTradePackRow" .. tostring(index), window, "", 18, y, 300, 18, 12),
            currency = createLabel("nuziTradeCurrencyRow" .. tostring(index), window, "", 330, y, 120, 18, 12),
            cap = createLabel("nuziTradeCapRow" .. tostring(index), window, "", 470, y, 50, 18, 12),
            live = createLabel("nuziTradeLiveRow" .. tostring(index), window, "", 544, y, 72, 18, 12)
        }
        setLabelColor(App.ui.rows[index].cap, { 255, 226, 180, 255 })
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
    end
    App.ui.button = nil
    App.ui.window = nil
    App.ui.controls = {}
    App.ui.rows = {}
end

local function onUpdate(dt)
    if not App.loaded then
        return
    end

    if not App.visible then
        return
    end

    if App.ui.window ~= nil and not isWidgetVisible(App.ui.window) then
        closeWindow()
        return
    end
end

local function onUiReloaded()
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
    api.On("UPDATE", onUpdate)
    api.On("UI_RELOADED", onUiReloaded)
    logInfo("Loaded v" .. tostring(addon.version))
end

function addon.OnUnload()
    App.loaded = false
    App.visible = false
    unloadUi()
    api.On("UPDATE", function()
    end)
    api.On("UI_RELOADED", function()
    end)
end

addon.OnSettingToggle = function()
    toggleWindow()
    refreshUi()
end

return addon
