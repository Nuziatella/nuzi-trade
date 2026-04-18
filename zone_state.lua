local api = require("api")

local ZoneState = {}

local DEFAULT_UNKNOWN_COLOR = { 186, 186, 186, 255 }
local DEFAULT_HPWS_BATTLE = 5
local DEFAULT_HPWS_WAR = 6
local DEFAULT_HPWS_PEACE = 7

function ZoneState.Create(options)
    options = type(options) == "table" and options or {}

    local app = type(options.app) == "table" and options.app or {}
    local colors = type(options.colors) == "table" and options.colors or {}
    local refreshIntervalMs = tonumber(options.refresh_interval_ms) or 5000
    local trim = type(options.trim) == "function"
        and options.trim
        or function(value)
            return (tostring(value or ""):gsub("^%s*(.-)%s*$", "%1"))
        end
    local normalizeKey = type(options.normalize_key) == "function"
        and options.normalize_key
        or function(value)
            return string.lower(trim(value))
        end
    local getUiNowMs = type(options.get_ui_now_ms) == "function"
        and options.get_ui_now_ms
        or function()
            return 0
        end
    local findStaticDestinationName = type(options.find_static_destination_name) == "function"
        and options.find_static_destination_name
        or function(value)
            return trim(value)
        end
    local isAllDestinationsEntry = type(options.is_all_destinations_entry) == "function"
        and options.is_all_destinations_entry
        or function(entry)
            return type(entry) == "table" and entry.all == true
        end
    local callStore = type(options.call_store) == "function"
        and options.call_store
        or function()
            return nil
        end
    local collectZoneEntries = type(options.collect_zone_entries) == "function"
        and options.collect_zone_entries
        or function()
        end
    local dedupeEntries = type(options.dedupe_entries) == "function"
        and options.dedupe_entries
        or function(entries)
            return type(entries) == "table" and entries or {}
        end
    local namesMatch = type(options.names_match) == "function"
        and options.names_match
        or function(left, right)
            return normalizeKey(left) == normalizeKey(right)
        end
    local catalogRefreshIntervalMs = tonumber(options.catalog_refresh_interval_ms) or 60000

    local function getColor(key)
        return colors[tostring(key or "unknown")] or colors.unknown or DEFAULT_UNKNOWN_COLOR
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

    local function titleCaseText(text)
        local words = {}
        local normalized = normalizeKey(text)
        for word in normalized:gmatch("%S+") do
            words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2)
        end
        if #words == 0 then
            return trim(text)
        end
        return table.concat(words, " ")
    end

    local function inferZoneStateKeyFromText(text)
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

    local function getHonorPointWarStateValue(name, fallback)
        local value = _G ~= nil and _G[name] or nil
        value = tonumber(value)
        if value == nil then
            return tonumber(fallback)
        end
        return value
    end

    local function clamp(value, minimum, maximum)
        if value < minimum then
            return minimum
        end
        if value > maximum then
            return maximum
        end
        return value
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

    local function collectZoneStateTexts(node, results, visited, depth)
        depth = tonumber(depth) or 0
        if depth > 2 then
            return
        end

        local nodeType = type(node)
        if nodeType == "string" then
            local text = trim(node)
            if text ~= "" then
                results[#results + 1] = text
            end
            return
        end
        if nodeType ~= "table" or visited[node] then
            return
        end
        visited[node] = true

        for key, value in pairs(node) do
            if type(key) == "string" and value == true then
                local keyHint = inferZoneStateKeyFromText(key)
                if keyHint ~= nil then
                    results[#results + 1] = keyHint
                end
            end
            if type(value) == "table" then
                collectZoneStateTexts(value, results, visited, depth + 1)
            elseif type(value) == "string" then
                local text = trim(value)
                if text ~= "" then
                    results[#results + 1] = text
                end
            end
        end
    end

    local function buildZoneStateRecord(zoneId, key, label, available)
        local normalizedKey = tostring(key or "unknown")
        local displayText = trim(label)
        if displayText == "" then
            if normalizedKey == "peace" then
                displayText = "Peace"
            elseif normalizedKey == "conflict" then
                displayText = "Conflict"
            elseif normalizedKey == "war" then
                displayText = "War"
            elseif normalizedKey == "static" then
                displayText = "Static Only"
            else
                displayText = "Unknown"
            end
        end

        local shortText = displayText
        if normalizedKey == "static" then
            shortText = "Static"
        elseif normalizedKey == "unknown" and displayText == "Unsupported" then
            shortText = "-"
        elseif #shortText > 12 then
            shortText = shortText:sub(1, 12)
        end

        return {
            zone_id = tonumber(zoneId),
            key = normalizedKey,
            text = displayText,
            short_text = shortText,
            remain_time = nil,
            remain_time_text = "-",
            color = getColor(normalizedKey),
            available = available == true,
            risky = normalizedKey == "war" or normalizedKey == "conflict"
        }
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

    local function formatRemainTime(value)
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

    local function applyRemainTime(record, rawInfo)
        if type(record) ~= "table" then
            return record
        end

        local remainTime = nil
        local remainText = nil
        if type(rawInfo) == "table" then
            remainTime = normalizeRemainTime(findNumericField(rawInfo, "remainTime", {}, 0))
            remainText = trim(findStringField(rawInfo, "strRemainTime", {}, 0))
        end

        if remainText == "" then
            remainText = formatRemainTime(remainTime)
        end

        record.remain_time = remainTime
        record.remain_time_text = remainText ~= "" and remainText or "-"
        return record
    end

    local function buildConflictStateRecord(zoneId, conflictState)
        conflictState = tonumber(conflictState)
        if conflictState == nil then
            return nil
        end

        local battleState = getHonorPointWarStateValue("HPWS_BATTLE", DEFAULT_HPWS_BATTLE)
        local warState = getHonorPointWarStateValue("HPWS_WAR", DEFAULT_HPWS_WAR)
        local peaceState = getHonorPointWarStateValue("HPWS_PEACE", DEFAULT_HPWS_PEACE)
        local maxDangerStep = math.max(1, math.floor(battleState))

        if conflictState < battleState then
            local step = clamp(math.floor(conflictState) + 1, 1, maxDangerStep)
            local record = buildZoneStateRecord(
                zoneId,
                "conflict",
                string.format("Conflict (Step %d)", step),
                true
            )
            record.danger_step = step
            record.danger_steps_max = maxDangerStep
            record.conflict_state = conflictState
            return record
        end

        if conflictState == battleState then
            local record = buildZoneStateRecord(zoneId, "conflict", "Conflict", true)
            record.conflict_state = conflictState
            return record
        end

        if conflictState == warState then
            local record = buildZoneStateRecord(zoneId, "war", "War", true)
            record.conflict_state = conflictState
            return record
        end

        if conflictState == peaceState then
            local record = buildZoneStateRecord(zoneId, "peace", "Peace", true)
            record.conflict_state = conflictState
            return record
        end

        return nil
    end

    local function callZoneStateMethod(zoneId)
        local libraries = {
            api.Zone,
            api.Map
        }

        for _, library in ipairs(libraries) do
            if type(library) == "table" and type(library.GetZoneStateInfoByZoneId) == "function" then
                local ok, result = pcall(function()
                    return library:GetZoneStateInfoByZoneId(zoneId)
                end)
                if ok then
                    return result, "api"
                end

                ok, result = pcall(function()
                    return library.GetZoneStateInfoByZoneId(library, zoneId)
                end)
                if ok then
                    return result, "api"
                end

                return nil, "api"
            end
        end

        return nil, "unsupported"
    end

    local function parseZoneStateInfo(zoneId, rawInfo, source)
        if tonumber(zoneId) == nil then
            return buildZoneStateRecord(nil, "static", "Static Only", false)
        end

        if type(rawInfo) == "table" then
            local conflictState = findNumericField(rawInfo, "conflictState", {}, 0)
            local conflictRecord = buildConflictStateRecord(zoneId, conflictState)
            if conflictRecord ~= nil then
                return applyRemainTime(conflictRecord, rawInfo)
            end

            if findBooleanField(rawInfo, "isSiegeZone", {}, 0) == true then
                return applyRemainTime(buildZoneStateRecord(zoneId, "war", "War", true), rawInfo)
            end
            if findBooleanField(rawInfo, "isConflictZone", {}, 0) == true then
                return applyRemainTime(buildZoneStateRecord(zoneId, "conflict", "Conflict", true), rawInfo)
            end
            if findBooleanField(rawInfo, "isPeaceZone", {}, 0) == true
                or findBooleanField(rawInfo, "isNuiaProtectedZone", {}, 0) == true
                or findBooleanField(rawInfo, "isHariharaProtectedZone", {}, 0) == true then
                return applyRemainTime(buildZoneStateRecord(zoneId, "peace", "Peace", true), rawInfo)
            end
        end

        local texts = {}
        if type(rawInfo) == "string" then
            texts[#texts + 1] = rawInfo
        elseif type(rawInfo) == "table" then
            collectZoneStateTexts(rawInfo, texts, {}, 0)
        elseif rawInfo ~= nil then
            texts[#texts + 1] = tostring(rawInfo)
        end

        local matchedKey = nil
        local displayText = nil
        for _, text in ipairs(texts) do
            local cleaned = trim(text)
            if cleaned ~= "" then
                if displayText == nil then
                    displayText = cleaned
                end
                local candidate = inferZoneStateKeyFromText(cleaned)
                if candidate ~= nil then
                    matchedKey = candidate
                    if candidate == "peace" then
                        displayText = "Peace"
                    elseif candidate == "conflict" then
                        displayText = "Conflict"
                    elseif candidate == "war" then
                        displayText = "War"
                    end
                    break
                end
            end
        end

        if matchedKey ~= nil then
            return applyRemainTime(buildZoneStateRecord(zoneId, matchedKey, displayText, true), rawInfo)
        end
        if displayText ~= nil then
            return applyRemainTime(buildZoneStateRecord(zoneId, "unknown", titleCaseText(displayText), true), rawInfo)
        end
        if source == "unsupported" then
            return buildZoneStateRecord(zoneId, "unknown", "Unsupported", false)
        end
        return applyRemainTime(buildZoneStateRecord(zoneId, "unknown", "Unknown", rawInfo ~= nil), rawInfo)
    end

    local function getZoneStateInfo(zoneId, force)
        local numericZoneId = tonumber(zoneId)
        if numericZoneId == nil then
            return buildZoneStateRecord(nil, "static", "Static Only", false)
        end

        if type(app.zone_state_cache) ~= "table" then
            app.zone_state_cache = {}
        end

        local now = getUiNowMs()
        local cached = app.zone_state_cache[numericZoneId]
        if cached ~= nil and not force and (now - (tonumber(cached.refreshed_at_ms) or 0)) < refreshIntervalMs then
            return cached
        end

        local rawInfo, source = callZoneStateMethod(numericZoneId)
        local parsed = parseZoneStateInfo(numericZoneId, rawInfo, source)
        parsed.refreshed_at_ms = now
        app.zone_state_cache[numericZoneId] = parsed
        return parsed
    end

    local function getLiveDestinationMetadata(destinationName)
        local canonicalName = findStaticDestinationName(destinationName) or trim(destinationName)
        if canonicalName == "" then
            return nil
        end
        if type(app.live_destinations) ~= "table" then
            return nil
        end
        return app.live_destinations[normalizeKey(canonicalName)]
    end

    local function resolveWatchCatalog(watchZones, force)
        if type(app.zone_watch_catalog) ~= "table" then
            app.zone_watch_catalog = {}
        end

        local now = getUiNowMs()
        if not force
            and tableHasEntries(app.zone_watch_catalog)
            and (now - (tonumber(app.zone_watch_catalog_refreshed_at_ms) or 0)) < catalogRefreshIntervalMs then
            return app.zone_watch_catalog
        end

        local wantedByKey = {}
        local unresolved = 0
        for _, entry in ipairs(watchZones or {}) do
            local zoneName = type(entry) == "table"
                and trim(entry.name or entry.zone_name or "")
                or trim(entry)
            local key = normalizeKey(zoneName)
            if key ~= "" and wantedByKey[key] == nil then
                wantedByKey[key] = zoneName
                unresolved = unresolved + 1
            end
        end

        local catalog = {}
        local function rememberZone(entry)
            local zoneId = type(entry) == "table" and tonumber(entry.id) or nil
            local zoneName = type(entry) == "table" and trim(entry.name) or ""
            if zoneId == nil or zoneName == "" or unresolved <= 0 then
                return
            end

            for key, wantedName in pairs(wantedByKey) do
                if catalog[key] == nil and namesMatch(zoneName, wantedName) then
                    catalog[key] = {
                        id = zoneId,
                        name = zoneName
                    }
                    unresolved = unresolved - 1
                    break
                end
            end
        end

        local origins = {}
        collectZoneEntries(callStore("GetProductionZoneGroups"), origins, {})
        origins = dedupeEntries(origins)

        for _, origin in ipairs(origins) do
            rememberZone(origin)
            if unresolved <= 0 then
                break
            end

            local destinations = {}
            collectZoneEntries(callStore("GetSellableZoneGroups", origin.id), destinations, {})
            destinations = dedupeEntries(destinations)
            for _, destination in ipairs(destinations) do
                rememberZone(destination)
                if unresolved <= 0 then
                    break
                end
            end
        end

        app.zone_watch_catalog = catalog
        app.zone_watch_catalog_refreshed_at_ms = now
        return catalog
    end

    local manager = {}

    function manager:GetInfo(zoneId, force)
        return getZoneStateInfo(zoneId, force)
    end

    function manager:GetLiveDestinationMetadata(destinationName)
        return getLiveDestinationMetadata(destinationName)
    end

    function manager:ApplyDestinationState(entry, force)
        if type(entry) ~= "table" then
            return entry
        end

        if isAllDestinationsEntry(entry) then
            entry.zone_state = buildZoneStateRecord(nil, "unknown", "Mixed", false)
            entry.zone_state_text = entry.zone_state.text
            entry.zone_state_short_text = entry.zone_state.short_text
            entry.zone_state_color = entry.zone_state.color
            entry.zone_state_key = entry.zone_state.key
            entry.zone_state_risky = false
            return entry
        end

        local liveEntry = getLiveDestinationMetadata(entry.static_name or entry.name)
        if type(liveEntry) == "table" then
            entry.id = tonumber(liveEntry.id)
            entry.live_name = tostring(liveEntry.name or "")
        else
            entry.id = nil
            entry.live_name = nil
        end

        local state = getZoneStateInfo(entry.id, force)
        entry.zone_state = state
        entry.zone_state_text = state.text
        entry.zone_state_short_text = state.short_text
        entry.zone_state_color = state.color
        entry.zone_state_key = state.key
        entry.zone_state_risky = state.risky
        return entry
    end

    function manager:BuildOriginSummary(origin, liveOriginId, liveOriginName)
        if origin == nil then
            return "", getColor("unknown")
        end

        local originName = type(origin) == "table"
            and trim(origin.name or "")
            or trim(origin)
        local zoneId = tonumber(liveOriginId)
        if zoneId == nil then
            if originName == "" then
                return "", getColor("unknown")
            end
            return "Zone: unavailable", getColor("unknown")
        end

        local state = getZoneStateInfo(zoneId, false)
        local stateText = trim(state.text or "Unknown")
        local liveName = trim(liveOriginName)
        if liveName ~= "" and normalizeKey(liveName) ~= normalizeKey(originName) then
            stateText = string.format("%s (%s)", stateText, liveName)
        end
        return "Zone: " .. stateText, state.color or getColor("unknown")
    end

    function manager:BuildDestinationSummary(destination)
        if destination == nil then
            return "", getColor("unknown")
        end

        if isAllDestinationsEntry(destination) then
            local counts = {
                peace = 0,
                conflict = 0,
                war = 0,
                static = 0,
                unknown = 0
            }
            local total = 0
            for _, entry in ipairs(app.destinations or {}) do
                if not isAllDestinationsEntry(entry) then
                    local key = tostring(entry.zone_state_key or "unknown")
                    if counts[key] == nil then
                        key = "unknown"
                    end
                    counts[key] = counts[key] + 1
                    total = total + 1
                end
            end

            if total == 0 then
                return "Zones: unavailable", getColor("unknown")
            end

            local parts = {}
            if counts.war > 0 then
                parts[#parts + 1] = string.format("W%d", counts.war)
            end
            if counts.conflict > 0 then
                parts[#parts + 1] = string.format("C%d", counts.conflict)
            end
            if counts.peace > 0 then
                parts[#parts + 1] = string.format("P%d", counts.peace)
            end
            if counts.static > 0 then
                parts[#parts + 1] = string.format("S%d", counts.static)
            end
            if counts.unknown > 0 then
                parts[#parts + 1] = string.format("?%d", counts.unknown)
            end

            local color = getColor("unknown")
            if counts.war > 0 then
                color = getColor("war")
            elseif counts.conflict > 0 then
                color = getColor("conflict")
            elseif counts.peace > 0 and counts.peace == total then
                color = getColor("peace")
            elseif counts.static > 0 and counts.static == total then
                color = getColor("static")
            end

            return "Zones: " .. table.concat(parts, " | "), color
        end

        local state = destination.zone_state or getZoneStateInfo(destination.id, false)
        return "Zone: " .. tostring(state.text or "Unknown"), state.color or getColor("unknown")
    end

    function manager:BuildWatchRows(watchZones, force)
        local resolvedCatalog = resolveWatchCatalog(watchZones, force)
        local rows = {}

        for _, entry in ipairs(watchZones or {}) do
            local zoneName = type(entry) == "table"
                and trim(entry.name or entry.zone_name or "")
                or trim(entry)
            if zoneName ~= "" then
                local resolved = resolvedCatalog[normalizeKey(zoneName)]
                local state = nil
                if type(resolved) == "table" and tonumber(resolved.id) ~= nil then
                    state = getZoneStateInfo(resolved.id, force)
                else
                    state = buildZoneStateRecord(nil, "unknown", "Unavailable", false)
                end

                rows[#rows + 1] = {
                    name = zoneName,
                    live_name = type(resolved) == "table" and resolved.name or nil,
                    zone_id = type(resolved) == "table" and tonumber(resolved.id) or nil,
                    status_text = tostring(state.text or "Unknown"),
                    status_color = state.color or getColor("unknown"),
                    time_text = tostring(state.remain_time_text or "-"),
                    time_color = state.color or getColor("unknown"),
                    key = tostring(state.key or "unknown"),
                    remain_time = state.remain_time
                }
            end
        end

        return rows
    end

    return manager
end

return ZoneState
