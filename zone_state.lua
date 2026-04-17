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

    local function getColor(key)
        return colors[tostring(key or "unknown")] or colors.unknown or DEFAULT_UNKNOWN_COLOR
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
            color = getColor(normalizedKey),
            available = available == true,
            risky = normalizedKey == "war" or normalizedKey == "conflict"
        }
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
                return conflictRecord
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
            return buildZoneStateRecord(zoneId, matchedKey, displayText, true)
        end
        if displayText ~= nil then
            return buildZoneStateRecord(zoneId, "unknown", titleCaseText(displayText), true)
        end
        if source == "unsupported" then
            return buildZoneStateRecord(zoneId, "unknown", "Unsupported", false)
        end
        return buildZoneStateRecord(zoneId, "unknown", "Unknown", rawInfo ~= nil)
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

    return manager
end

return ZoneState
