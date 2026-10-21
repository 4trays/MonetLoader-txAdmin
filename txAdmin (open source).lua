script_name("txAdmin Open Source")
script_author("4trays LazyCat Studios")
script_version("4.6.0-webview")

require('lib.moonloader')
require('encoding').default = 'CP1251'
local u8 = require('encoding').UTF8
local ev = require('samp.events')
local inicfg = require('inicfg')
local lib = require('webviews')

if MONET_DPI_SCALE == nil then MONET_DPI_SCALE = 1.0 end
local sizeX, sizeY = nil, nil


-- CONFIG
local configIni = inicfg.load({
    window = { posX = 20, posY = 100, locked = false }
}, 'txAdmin_webview')

local BROWSER_ID = 2 
local browser_ready = false
local browser_created = false
local appVisible = false
local isLoggedIn = false
local positionLocked = configIni.window.locked or false

local function savePos(x, y)
    configIni.window.posX = math.floor(x)
    configIni.window.posY = math.floor(y)
    inicfg.save(configIni, 'txAdmin_webview')
end
local function saveLock()
    configIni.window.locked = positionLocked
    inicfg.save(configIni, 'txAdmin_webview')
end

local isDutyOn = false
local selectedPlayer = nil

local worldFeatures = {
    names = false,
    nameSize = 14,
    line = false,
    lineColor = { 1.0, 1.0, 1.0 },
    lineThickness = 2.0
}

local playersList = {}
local SORT_BY = { id = "id", name = "name", distance = "distance", ping = "ping" }
local currentSort = "id"
local sortAscending = true

local logsData = {}
local logsSearchTerm = ""
local maxLogs = 1000
local LOG_CATEGORY_MAP = { [0] = nil, [1] = "ADMIN", [2] = "PLAYER", [3] = "SERVER", [4] = "SYSTEM" }
local currentLogCategory = 0

local logStats = { totalLogs = 0, banCount = 0, kickCount = 0, warnCount = 0, muteCount = 0, jailCount = 0 }

local importantKeywords = {
    "destroy", "vehicle", "cheat", "hack", "death", "kill", "spawn",
    "weapon", "ban", "kick", "mute", "jail", "warn", "admin", "teleport",
    "explode", "explosion", "money", "cash", "withdraw", "deposit", "bot:"
}
local serverBlacklist = { "city", "uptime", "server uptime", "current city", "time", "weather" }
local logColorKeywords = {
    ban = {"ban", "banned"}, kick = {"kick", "kicked"}, warn = {"warn", "warned", "warning"},
    mute = {"mute", "muted"}, jail = {"jail", "jailed"}, kill = {"kill", "killed", "death", "died"},
    money = {"money", "cash", "withdraw", "deposit", "paid"}, weapon = {"weapon", "gun", "armour"},
    teleport = {"teleport", "teleported", "tp"}, spawn = {"spawn", "spawned"}, bot = {"bot:"}
}

local fontCache = {}


-- LOGIC

function isImportantMessage(text)
    local lowerText = text:lower()
    if text:find("%[Server%]:") then
        for _, blackword in ipairs(serverBlacklist) do
            if lowerText:find(blackword, 1, true) then return false end
        end
    end
    if lowerText:find("bot:", 1, true) then return true end
    for _, keyword in ipairs(importantKeywords) do
        if lowerText:find(keyword, 1, true) then return true end
    end
    if lowerText:find("has been") or lowerText:find("was") or
       lowerText:find("banned") or lowerText:find("kicked") or
       lowerText:find("warned") or lowerText:find("muted") or
       lowerText:find("jailed") or lowerText:find("spawned") then
        return true
    end
    return false
end

function getLogType(text)
    local lowerText = text:lower()
    for logType, keywords in pairs(logColorKeywords) do
        for _, keyword in ipairs(keywords) do
            if lowerText:find(keyword, 1, true) then return logType end
        end
    end
    return "other"
end

function addLogEntry(message, category)
    local timestamp = os.date("[%H:%M:%S]")
    local logType = getLogType(message)

    table.insert(logsData, {
        time = timestamp, message = message, category = category or "SYSTEM",
        type = logType, fullText = timestamp .. " " .. message
    })

    logStats.totalLogs = logStats.totalLogs + 1
    if logType == "ban" then logStats.banCount = logStats.banCount + 1
    elseif logType == "kick" then logStats.kickCount = logStats.kickCount + 1
    elseif logType == "warn" then logStats.warnCount = logStats.warnCount + 1
    elseif logType == "mute" then logStats.muteCount = logStats.muteCount + 1
    elseif logType == "jail" then logStats.jailCount = logStats.jailCount + 1
    end

    if #logsData > maxLogs then table.remove(logsData, 1) end
    pushLogs()
end

function shouldShowLog(logEntry)
    if currentLogCategory ~= 0 then
        if logEntry.category ~= LOG_CATEGORY_MAP[currentLogCategory] then return false end
    end
    if logsSearchTerm ~= "" then
        if not logEntry.fullText:lower():find(logsSearchTerm, 1, true) then return false end
    end
    return true
end

function getAllConnectedPlayers()
    local players = {}
    local result, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if not result then return players end
    for i = 0, sampGetMaxPlayerId(false) do
        if sampIsPlayerConnected(i) and i ~= myId then
            table.insert(players, i)
        end
    end
    return players
end

function joinArgb(a, r, g, b)
    return bit.bor(bit.lshift(a, 24), bit.lshift(r, 16), bit.lshift(g, 8), b)
end

function getOrCreateFont(size)
    if not fontCache[size] then
        fontCache[size] = renderCreateFont("Arial", size, 5)
    end
    return fontCache[size]
end

function renderPlayerNames()
    local fontSize = worldFeatures.nameSize
    local font = getOrCreateFont(fontSize)
    for _, playerId in pairs(getAllConnectedPlayers()) do
        local result, handle = sampGetCharHandleBySampPlayerId(playerId)
        if result and doesCharExist(handle) and isCharOnScreen(handle) then
            local playerName = sampGetPlayerNickname(playerId)
            local x, y, z = getCharCoordinates(handle)
            z = z + 1.0
            local screenX, screenY = convert3DCoordsToScreen(x, y, z)
            if screenX and screenY and screenX > 0 and screenY > 0 and screenX < sizeX and screenY < sizeY then
                local displayText = playerName .. " [" .. playerId .. "]"
                local textLength = renderGetFontDrawTextLength(font, displayText)
                renderDrawBox(screenX - textLength / 2 - 3, screenY - 1, textLength + 6, fontSize + 6, 0x80000000)
                renderFontDrawText(font, displayText, screenX - textLength / 2, screenY, 0xFFFFFFFF)
            end
        end
    end
end

function renderPlayerLines()
    local result, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if not result then return end
    local myX, myY, myZ = getCharCoordinates(PLAYER_PED)
    local myScreenX, myScreenY = convert3DCoordsToScreen(myX, myY, myZ)
    if not myScreenX or not myScreenY then return end
    for _, playerId in pairs(getAllConnectedPlayers()) do
        local result, handle = sampGetCharHandleBySampPlayerId(playerId)
        if result and doesCharExist(handle) then
            local targetX, targetY, targetZ = getCharCoordinates(handle)
            local targetScreenX, targetScreenY = convert3DCoordsToScreen(targetX, targetY, targetZ)
            if targetScreenX and targetScreenY then
                local r = math.floor(worldFeatures.lineColor[1] * 255)
                local g = math.floor(worldFeatures.lineColor[2] * 255)
                local b = math.floor(worldFeatures.lineColor[3] * 255)
                local color = joinArgb(255, r, g, b)
                renderDrawLine(myScreenX, myScreenY, targetScreenX, targetScreenY, worldFeatures.lineThickness, color)
            end
        end
    end
end

function getPlayerPing(playerId)
    if sampIsPlayerConnected(playerId) then return sampGetPlayerPing(playerId) end
    return 0
end
function getPlayerHealth(playerId)
    local result, handle = sampGetCharHandleBySampPlayerId(playerId)
    if result and doesCharExist(handle) then return getCharHealth(handle) end
    return 0
end
function getPlayerArmour(playerId)
    local result, handle = sampGetCharHandleBySampPlayerId(playerId)
    if result and doesCharExist(handle) then return getCharArmour(handle) end
    return 0
end
function getPlayerDistance(playerId)
    local result, myPed = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if not result then return 9999 end
    local myX, myY, myZ = getCharCoordinates(PLAYER_PED)
    local result2, handle = sampGetCharHandleBySampPlayerId(playerId)
    if result2 and doesCharExist(handle) then
        local x, y, z = getCharCoordinates(handle)
        return math.floor(getDistanceBetweenCoords3d(myX, myY, myZ, x, y, z))
    end
    return 9999
end

function loadAllPlayers()
    playersList = {}
    local result, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    for i = 0, sampGetMaxPlayerId(false) do
        if sampIsPlayerConnected(i) then
            local nick = sampGetPlayerNickname(i)
            if nick and nick ~= "" then
                local isSelf = (result and i == myId)
                table.insert(playersList, {
                    id = i, name = nick, ping = getPlayerPing(i) or 0,
                    distance = isSelf and 0 or (getPlayerDistance(i) or 9999),
                    health = isSelf and getCharHealth(PLAYER_PED) or (getPlayerHealth(i) or 0),
                    armour = isSelf and getCharArmour(PLAYER_PED) or (getPlayerArmour(i) or 0),
                    isSelf = isSelf
                })
            end
        end
    end
    sortPlayersList()
end

function searchPlayersByTerm(searchTerm)
    playersList = {}
    for i = 0, sampGetMaxPlayerId(false) do
        if sampIsPlayerConnected(i) then
            local nick = sampGetPlayerNickname(i)
            if nick and nick ~= "" then
                if searchTerm == "" then
                    table.insert(playersList, { id = i, name = nick, ping = getPlayerPing(i), distance = getPlayerDistance(i), health = getPlayerHealth(i), armour = getPlayerArmour(i) })
                else
                    local idMatch = tostring(i):find(searchTerm, 1, true)
                    local nameMatch = nick:lower():find(searchTerm:lower(), 1, true)
                    if idMatch or nameMatch then
                        table.insert(playersList, { id = i, name = nick, ping = getPlayerPing(i), distance = getPlayerDistance(i), health = getPlayerHealth(i), armour = getPlayerArmour(i) })
                    end
                end
            end
        end
    end
    sortPlayersList()
end

function scanPlayersInRadius(radius)
    playersList = {}
    if not radius or radius <= 0 then
        sampAddChatMessage("[txAdmin] {FF6666}Invalid radius value!", 0xFF6666)
        return
    end
    local result, myPed = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if not result then return end
    local myX, myY, myZ = getCharCoordinates(PLAYER_PED)
    for i = 0, sampGetMaxPlayerId(false) do
        if sampIsPlayerConnected(i) and i ~= myPed then
            local result2, handle = sampGetCharHandleBySampPlayerId(i)
            if result2 and doesCharExist(handle) then
                local x, y, z = getCharCoordinates(handle)
                local distance = getDistanceBetweenCoords3d(myX, myY, myZ, x, y, z)
                if distance <= radius then
                    local nick = sampGetPlayerNickname(i)
                    if nick and nick ~= "" then
                        table.insert(playersList, { id = i, name = nick, distance = math.floor(distance), ping = getPlayerPing(i), health = getPlayerHealth(i), armour = getPlayerArmour(i) })
                    end
                end
            end
        end
    end
    sortPlayersList()
    if #playersList == 0 then
        sampAddChatMessage(string.format("[txAdmin] {FF6666}No players within %dm!", radius), 0xFF6666)
    else
        sampAddChatMessage(string.format("[txAdmin] {FFFFFF}Found {20CCCC}%d{FFFFFF} player(s) within %dm", #playersList, radius), 0x20CCCC)
    end
end

function sortPlayersList()
    table.sort(playersList, function(a, b)
        local valA, valB
        if currentSort == "id" then valA, valB = a.id, b.id
        elseif currentSort == "name" then valA, valB = a.name:lower(), b.name:lower()
        elseif currentSort == "distance" then valA, valB = a.distance or 9999, b.distance or 9999
        elseif currentSort == "ping" then valA, valB = a.ping or 0, b.ping or 0
        else valA, valB = a.id, b.id end
        if sortAscending then return valA < valB else return valA > valB end
    end)
end


-- WEBVIEW UI

local TXADMIN_HTML_B64 = "PCFET0NUWVBFIGh0bWw+CjxodG1sPgo8aGVhZD4KPG1ldGEgY2hhcnNldD0iVVRGLTgiPgo8bGluayByZWw9InN0eWxlc2hlZXQiIGhyZWY9Imh0dHBzOi8vY2RuanMuY2xvdWRmbGFyZS5jb20vYWpheC9saWJzL2ZvbnQtYXdlc29tZS82LjUuMS9jc3MvYWxsLm1pbi5jc3MiPgo8c3R5bGU+CiAgOnJvb3QgewogICAgLS1iZzogcmdiYSgyOCwyOCwzMywwLjk3KTsKICAgIC0tYmctc29saWQ6ICMxYzFjMjE7CiAgICAtLXRpdGxlYmc6ICMxNDE0MWE7CiAgICAtLWJ0bjogIzJlMmUzMzsKICAgIC0tYnRuLWhvdmVyOiAjMzgzODNkOwogICAgLS1idG4tYWN0aXZlOiAjNDI0MjQ3OwogICAgLS10ZXh0OiAjZDlkOWQ5OwogICAgLS10ZXh0LW11dGVkOiAjODA4MDgwOwogICAgLS1jeWFuOiAjMzNjY2NjOwogICAgLS1jeWFuLWhvdmVyOiAjNGRlNmU2OwogICAgLS1jeWFuLWRhcms6ICMyNjk5OTk7CiAgICAtLWJvcmRlcjogcmdiYSg1MSwyMDQsMjA0LDAuMjApOwogICAgLS1zdWNjZXNzOiAjMzNjYzMzOwogICAgLS1kYW5nZXI6ICNjYzMzMzM7CiAgICAtLXdhcm5pbmc6ICNlNWIyMzM7CiAgICAtLWNoaWxkLWJnOiAjMGYwZjEyOwogIH0KICAqIHsgYm94LXNpemluZzogYm9yZGVyLWJveDsgbWFyZ2luOiAwOyBwYWRkaW5nOiAwOyAtd2Via2l0LXVzZXItc2VsZWN0OiBub25lOyB1c2VyLXNlbGVjdDogbm9uZTsgLXdlYmtpdC10YXAtaGlnaGxpZ2h0LWNvbG9yOiB0cmFuc3BhcmVudDsgfQogIGh0bWwsIGJvZHkgeyBiYWNrZ3JvdW5kOiB0cmFuc3BhcmVudDsgd2lkdGg6IDEwMCU7IGhlaWdodDogMTAwJTsgb3ZlcmZsb3c6IGhpZGRlbjsgZm9udC1mYW1pbHk6IC1hcHBsZS1zeXN0ZW0sIFJvYm90bywgc2Fucy1zZXJpZjsgZm9udC1zaXplOiAxM3B4OyBjb2xvcjogdmFyKC0tdGV4dCk7IH0KICBpbnB1dCB7IHVzZXItc2VsZWN0OiB0ZXh0OyAtd2Via2l0LXVzZXItc2VsZWN0OiB0ZXh0OyB9CgogICNhcHAgewogICAgcG9zaXRpb246IGFic29sdXRlOwogICAgbGVmdDogMjBweDsgdG9wOiAxMDBweDsKICAgIHdpZHRoOiAzMzBweDsKICAgIG1heC1oZWlnaHQ6IDUyMHB4OwogICAgYmFja2dyb3VuZDogdmFyKC0tYmcpOwogICAgYm9yZGVyOiAxcHggc29saWQgdmFyKC0tYm9yZGVyKTsKICAgIGJvcmRlci1yYWRpdXM6IDEwcHg7CiAgICBib3gtc2hhZG93OiAwIDhweCAzMHB4IHJnYmEoMCwwLDAsMC41KTsKICAgIG92ZXJmbG93OiBoaWRkZW47CiAgICBkaXNwbGF5OiBub25lOwogICAgdHJhbnNmb3JtOiBzY2FsZSgwLjcyKTsKICAgIHRyYW5zZm9ybS1vcmlnaW46IHRvcCBsZWZ0OwogIH0KICAjYXBwLnNob3cgeyBkaXNwbGF5OiBmbGV4OyBmbGV4LWRpcmVjdGlvbjogY29sdW1uOyB9CgogIDo6LXdlYmtpdC1zY3JvbGxiYXIgeyB3aWR0aDogNXB4OyB9CiAgOjotd2Via2l0LXNjcm9sbGJhci10aHVtYiB7IGJhY2tncm91bmQ6IHZhcigtLWN5YW4tZGFyayk7IGJvcmRlci1yYWRpdXM6IDNweDsgfQogIDo6LXdlYmtpdC1zY3JvbGxiYXItdHJhY2sgeyBiYWNrZ3JvdW5kOiB0cmFuc3BhcmVudDsgfQoKICAvKiA9PT09PSBkcmFnIGhhbmRsZSAoZGlwYWthaSBkaSB0aXRsZSBiYXIgbG9naW4gJiBtYWluKSA9PT09PSAqLwogIC5kcmFnLWhhbmRsZSB7IHRvdWNoLWFjdGlvbjogbm9uZTsgY3Vyc29yOiBncmFiOyB9CgogIC8qID09PT09IExPR0lOID09PT09ICovCiAgI2xvZ2luU2NyZWVuIHsgcGFkZGluZzogMjBweCAxOHB4IDE2cHg7IHRleHQtYWxpZ246IGNlbnRlcjsgcG9zaXRpb246IHJlbGF0aXZlOyB9CiAgLmxvZ2luLXJ1bGUgeyBjb2xvcjogdmFyKC0tY3lhbik7IGxldHRlci1zcGFjaW5nOiAycHg7IGZvbnQtc2l6ZTogMTFweDsgb3BhY2l0eTogMC42OyB9CiAgLmxvZ2luLXNoaWVsZCB7IGZvbnQtc2l6ZTogMjZweDsgY29sb3I6IHZhcigtLWN5YW4pOyBtYXJnaW46IDEwcHggMCA2cHg7IH0KICAubG9naW4tdGl0bGUgeyBmb250LXNpemU6IDE3cHg7IGNvbG9yOiAjZmZmOyBmb250LXdlaWdodDogNjAwOyB9CiAgLmxvZ2luLXN1YnRpdGxlIHsgZm9udC1zaXplOiAxMXB4OyBjb2xvcjogdmFyKC0tdGV4dC1tdXRlZCk7IG1hcmdpbi1ib3R0b206IDE0cHg7IH0KICAuZmllbGQtZ3JvdXAgeyB0ZXh0LWFsaWduOiBsZWZ0OyBtYXJnaW4tYm90dG9tOiAxMHB4OyB9CiAgLmZpZWxkLWxhYmVsIHsgZm9udC1zaXplOiAxMXB4OyBjb2xvcjogdmFyKC0tY3lhbik7IG1hcmdpbi1ib3R0b206IDRweDsgZGlzcGxheTogZmxleDsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA1cHg7IH0KICAuZmllbGQtaW5wdXQgewogICAgd2lkdGg6IDEwMCU7IGJhY2tncm91bmQ6ICMxYTFhMWY7IGJvcmRlcjogMXB4IHNvbGlkIHZhcigtLWJvcmRlcik7CiAgICBib3JkZXItcmFkaXVzOiA1cHg7IGNvbG9yOiB2YXIoLS10ZXh0KTsgZm9udC1zaXplOiAxMnB4OyBwYWRkaW5nOiA4cHggMTBweDsKICAgIG91dGxpbmU6IG5vbmU7IHRyYW5zaXRpb246IGJvcmRlci1jb2xvciAwLjE1czsKICB9CiAgLmZpZWxkLWlucHV0OmZvY3VzIHsgYm9yZGVyLWNvbG9yOiB2YXIoLS1jeWFuKTsgfQogIC5yZW1lbWJlci1yb3cgeyBkaXNwbGF5OiBmbGV4OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDZweDsgZm9udC1zaXplOiAxMXB4OyBjb2xvcjogdmFyKC0tdGV4dC1tdXRlZCk7IG1hcmdpbjogNnB4IDAgMTBweDsgfQogIC5sb2dpbi1lcnJvciB7CiAgICBmb250LXNpemU6IDExcHg7IGNvbG9yOiB2YXIoLS1kYW5nZXIpOyB0ZXh0LWFsaWduOiBjZW50ZXI7IG1hcmdpbi1ib3R0b206IDhweDsKICAgIGRpc3BsYXk6IG5vbmU7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGp1c3RpZnktY29udGVudDogY2VudGVyOyBnYXA6IDVweDsKICB9CiAgLmxvZ2luLWVycm9yLnNob3cgeyBkaXNwbGF5OiBmbGV4OyB9CiAgI2xvZ2luU2NyZWVuLnNoYWtlIHsgYW5pbWF0aW9uOiBzaGFrZSAwLjRzOyB9CiAgQGtleWZyYW1lcyBzaGFrZSB7CiAgICAwJSwxMDAlIHsgdHJhbnNmb3JtOiB0cmFuc2xhdGVYKDApOyB9CiAgICAyMCUsNjAlIHsgdHJhbnNmb3JtOiB0cmFuc2xhdGVYKC02cHgpOyB9CiAgICA0MCUsODAlIHsgdHJhbnNmb3JtOiB0cmFuc2xhdGVYKDZweCk7IH0KICB9CiAgLmxvZ2luLWJ0biB7CiAgICB3aWR0aDogMTAwJTsgYmFja2dyb3VuZDogdmFyKC0tY3lhbik7IGNvbG9yOiAjMDgxODFhOyBib3JkZXI6IG5vbmU7IGJvcmRlci1yYWRpdXM6IDZweDsKICAgIGZvbnQtc2l6ZTogMTNweDsgZm9udC13ZWlnaHQ6IDYwMDsgcGFkZGluZzogMTBweDsgZGlzcGxheTogZmxleDsgYWxpZ24taXRlbXM6IGNlbnRlcjsKICAgIGp1c3RpZnktY29udGVudDogY2VudGVyOyBnYXA6IDZweDsgdHJhbnNpdGlvbjogYmFja2dyb3VuZCAwLjE1czsKICB9CiAgLmxvZ2luLWJ0bjphY3RpdmUgeyBiYWNrZ3JvdW5kOiB2YXIoLS1jeWFuLWRhcmspOyB9CiAgLmxvZ2luLWZvb3RlciB7IGZvbnQtc2l6ZTogMTBweDsgY29sb3I6ICM0ZDRkNGQ7IG1hcmdpbi10b3A6IDEycHg7IH0KICAuYXBwLWNsb3NlLWJ0biB7CiAgICBwb3NpdGlvbjogYWJzb2x1dGU7IHJpZ2h0OiA4cHg7IHRvcDogOHB4OwogICAgYmFja2dyb3VuZDogcmdiYSgxMDAsNDAsNDAsMC45KTsgY29sb3I6ICNmZmY7IGJvcmRlcjogbm9uZTsgYm9yZGVyLXJhZGl1czogNXB4OwogICAgd2lkdGg6IDIycHg7IGhlaWdodDogMjJweDsgZm9udC1zaXplOiAxMXB4OyB6LWluZGV4OiA1OwogIH0KICAuZmEtc3BpbiB7IGFuaW1hdGlvbjogZmEtc3BpbiAwLjlzIGxpbmVhciBpbmZpbml0ZTsgfQogIEBrZXlmcmFtZXMgZmEtc3BpbiB7IGZyb20geyB0cmFuc2Zvcm06IHJvdGF0ZSgwKTsgfSB0byB7IHRyYW5zZm9ybTogcm90YXRlKDM2MGRlZyk7IH0gfQoKICAvKiA9PT09PSBMT0FESU5HIChhYmlzIGxvZ2luKSA9PT09PSAqLwogICNsb2FkaW5nU2NyZWVuIHsKICAgIGRpc3BsYXk6IG5vbmU7IGZsZXgtZGlyZWN0aW9uOiBjb2x1bW47IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGp1c3RpZnktY29udGVudDogY2VudGVyOwogICAgcGFkZGluZzogNTBweCAyMHB4OyBnYXA6IDE0cHg7CiAgfQogICNsb2FkaW5nU2NyZWVuLnNob3cgeyBkaXNwbGF5OiBmbGV4OyB9CiAgLmxvYWRpbmctaWNvbiB7IGZvbnQtc2l6ZTogMzBweDsgY29sb3I6IHZhcigtLWN5YW4pOyB9CiAgLmxvYWRpbmctdGV4dCB7IGZvbnQtc2l6ZTogMTJweDsgY29sb3I6IHZhcigtLXRleHQtbXV0ZWQpOyB9CiAgLmxvYWRpbmctYmFyLXRyYWNrIHsgd2lkdGg6IDIyMHB4OyBoZWlnaHQ6IDRweDsgYmFja2dyb3VuZDogIzFhMWExZjsgYm9yZGVyLXJhZGl1czogM3B4OyBvdmVyZmxvdzogaGlkZGVuOyB9CiAgLmxvYWRpbmctYmFyLWZpbGwgeyBoZWlnaHQ6IDEwMCU7IHdpZHRoOiAwJTsgYmFja2dyb3VuZDogdmFyKC0tY3lhbik7IGJvcmRlci1yYWRpdXM6IDNweDsgdHJhbnNpdGlvbjogd2lkdGggMC4yNXMgbGluZWFyOyB9CgogIC8qID09PT09IE1BSU4gUEFORUwgPT09PT0gKi8KICAjbWFpblNjcmVlbiB7IGRpc3BsYXk6IG5vbmU7IGZsZXgtZGlyZWN0aW9uOiBjb2x1bW47IG1heC1oZWlnaHQ6IDUyMHB4OyB9CiAgI21haW5TY3JlZW4uc2hvdyB7IGRpc3BsYXk6IGZsZXg7IH0KCiAgLm1haW4taGVhZGVyIHsgcGFkZGluZzogMTBweCAxNHB4IDhweDsgdGV4dC1hbGlnbjogY2VudGVyOyBwb3NpdGlvbjogcmVsYXRpdmU7IH0KICAubWFpbi1oZWFkZXItdGl0bGUgeyBjb2xvcjogdmFyKC0tY3lhbik7IGZvbnQtc2l6ZTogMTNweDsgZm9udC13ZWlnaHQ6IDYwMDsgZGlzcGxheTogZmxleDsgYWxpZ24taXRlbXM6IGNlbnRlcjsganVzdGlmeS1jb250ZW50OiBjZW50ZXI7IGdhcDogNnB4OyB9CiAgLm1haW4taGVhZGVyLXZlcnNpb24geyBmb250LXNpemU6IDEwcHg7IGNvbG9yOiAjNjY2OyBtYXJnaW4tdG9wOiAxcHg7IH0KICAubG9jay1iYWRnZSB7IHBvc2l0aW9uOiBhYnNvbHV0ZTsgcmlnaHQ6IDEycHg7IHRvcDogMTBweDsgY29sb3I6IHZhcigtLXdhcm5pbmcpOyBmb250LXNpemU6IDEycHg7IH0KICAuaGVhZGVyLWRpdmlkZXIgeyBoZWlnaHQ6IDFweDsgYmFja2dyb3VuZDogdmFyKC0tYm9yZGVyKTsgbWFyZ2luOiA4cHggMCAwOyB9CgogIC50YWJzIHsgZGlzcGxheTogZmxleDsgZ2FwOiA0cHg7IHBhZGRpbmc6IDhweCAxMHB4IDA7IH0KICAudGFiLWJ0biB7CiAgICBmbGV4OiAxOyBiYWNrZ3JvdW5kOiAjMjYyNjJiOyBjb2xvcjogdmFyKC0tdGV4dCk7IGJvcmRlcjogbm9uZTsgYm9yZGVyLXJhZGl1czogNXB4OwogICAgZm9udC1zaXplOiAxMXB4OyBwYWRkaW5nOiA3cHggMnB4OyBkaXNwbGF5OiBmbGV4OyBhbGlnbi1pdGVtczogY2VudGVyOyBqdXN0aWZ5LWNvbnRlbnQ6IGNlbnRlcjsKICAgIGdhcDogNHB4OyB0cmFuc2l0aW9uOiBiYWNrZ3JvdW5kIDAuMTVzLCBjb2xvciAwLjE1czsKICB9CiAgLnRhYi1idG4uYWN0aXZlIHsgYmFja2dyb3VuZDogcmdiYSg1MSwyMDQsMjA0LDAuMjUpOyBjb2xvcjogdmFyKC0tY3lhbik7IH0KCiAgLnRhYi1jb250ZW50IHsgcGFkZGluZzogMTBweCAxMnB4IDEycHg7IG92ZXJmbG93LXk6IGF1dG87IGZsZXg6IDE7IH0KICAudGFiLXBhbmUgeyBkaXNwbGF5OiBub25lOyB9CiAgLnRhYi1wYW5lLmFjdGl2ZSB7IGRpc3BsYXk6IGJsb2NrOyB9CgogIC8qID09PT09IFNlY3Rpb24gKE1haW4gdGFiKSA9PT09PSAqLwogIC5zZWN0aW9uIHsgbWFyZ2luLWJvdHRvbTogNHB4OyB9CiAgLnNlY3Rpb24taGVhZCB7CiAgICBkaXNwbGF5OiBmbGV4OyBhbGlnbi1pdGVtczogY2VudGVyOyBnYXA6IDZweDsgcGFkZGluZzogOHB4IDRweDsgY3Vyc29yOiBwb2ludGVyOwogICAgYm9yZGVyLXJhZGl1czogNXB4OyB0cmFuc2l0aW9uOiBiYWNrZ3JvdW5kIDAuMTVzOwogIH0KICAuc2VjdGlvbi1oZWFkOmFjdGl2ZSB7IGJhY2tncm91bmQ6ICMyNjI2MmI7IH0KICAuc2VjdGlvbi10aXRsZSB7IGZsZXg6IDE7IGZvbnQtc2l6ZTogMTJweDsgfQogIC5zZWN0aW9uLWJhZGdlIHsgZm9udC1zaXplOiAxMHB4OyBjb2xvcjogIzgwODA4MDsgfQogIC5zZWN0aW9uLWJhZGdlLm9uIHsgY29sb3I6IHZhcigtLXN1Y2Nlc3MpOyB9CiAgLnNlY3Rpb24tYmFkZ2Uub2ZmIHsgY29sb3I6IHZhcigtLWRhbmdlcik7IH0KICAuc2VjdGlvbi1jaGV2cm9uIHsgY29sb3I6IHZhcigtLWN5YW4pOyBmb250LXNpemU6IDEwcHg7IHRyYW5zaXRpb246IHRyYW5zZm9ybSAwLjJzOyB3aWR0aDogMTJweDsgdGV4dC1hbGlnbjogY2VudGVyOyB9CiAgLnNlY3Rpb24tYm9keSB7CiAgICBtYXgtaGVpZ2h0OiAwOyBvdmVyZmxvdzogaGlkZGVuOyB0cmFuc2l0aW9uOiBtYXgtaGVpZ2h0IDAuMjJzIGVhc2U7CiAgICBwYWRkaW5nOiAwIDRweDsKICB9CiAgLnNlY3Rpb24tYm9keS5vcGVuIHsgbWF4LWhlaWdodDogMzAwcHg7IHBhZGRpbmc6IDRweCA0cHggMTBweDsgfQoKICAucm93IHsgZGlzcGxheTogZmxleDsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA2cHg7IG1hcmdpbi1ib3R0b206IDhweDsgZmxleC13cmFwOiB3cmFwOyB9CiAgLmJ0biB7CiAgICBiYWNrZ3JvdW5kOiB2YXIoLS1idG4pOyBjb2xvcjogdmFyKC0tdGV4dCk7IGJvcmRlcjogbm9uZTsgYm9yZGVyLXJhZGl1czogNXB4OwogICAgZm9udC1zaXplOiAxMXB4OyBwYWRkaW5nOiA3cHggMTBweDsgZGlzcGxheTogaW5saW5lLWZsZXg7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogNXB4OwogICAgdHJhbnNpdGlvbjogYmFja2dyb3VuZCAwLjEycywgdHJhbnNmb3JtIDAuMDhzOwogIH0KICAuYnRuOmFjdGl2ZSB7IGJhY2tncm91bmQ6IHZhcigtLWJ0bi1hY3RpdmUpOyB0cmFuc2Zvcm06IHNjYWxlKDAuOTcpOyB9CiAgLmJ0bi1ibG9jayB7IHdpZHRoOiAxMDAlOyBqdXN0aWZ5LWNvbnRlbnQ6IGNlbnRlcjsgfQogIC5idG4tY3lhbiB7IGJhY2tncm91bmQ6IHZhcigtLWN5YW4pOyBjb2xvcjogIzA4MTgxYTsgfQogIC5idG4tc3VjY2VzcyB7IGJhY2tncm91bmQ6IHZhcigtLXN1Y2Nlc3MpOyBjb2xvcjogIzA2MjEwYTsgfQogIC5idG4tZGFuZ2VyIHsgYmFja2dyb3VuZDogdmFyKC0tZGFuZ2VyKTsgY29sb3I6ICNmZmY7IH0KICAuaW5wdXQtc20gewogICAgYmFja2dyb3VuZDogIzFhMWExZjsgYm9yZGVyOiAxcHggc29saWQgdmFyKC0tYm9yZGVyKTsgYm9yZGVyLXJhZGl1czogNXB4OwogICAgY29sb3I6IHZhcigtLXRleHQpOyBmb250LXNpemU6IDExcHg7IHBhZGRpbmc6IDZweCA4cHg7IG91dGxpbmU6IG5vbmU7IG1pbi13aWR0aDogMDsKICB9CiAgLmlucHV0LXNtOmZvY3VzIHsgYm9yZGVyLWNvbG9yOiB2YXIoLS1jeWFuKTsgfQogIC5sYmwtaW5saW5lIHsgZm9udC1zaXplOiAxMXB4OyBjb2xvcjogdmFyKC0tdGV4dC1tdXRlZCk7IHdoaXRlLXNwYWNlOiBub3dyYXA7IH0KICAuY2hlY2tib3gtcm93IHsgZGlzcGxheTogZmxleDsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA2cHg7IGZvbnQtc2l6ZTogMTFweDsgbWFyZ2luLWJvdHRvbTogNnB4OyB9CiAgaW5wdXRbdHlwZT1jaGVja2JveF0geyBhY2NlbnQtY29sb3I6IHZhcigtLWN5YW4pOyB3aWR0aDogMTRweDsgaGVpZ2h0OiAxNHB4OyB9CiAgaW5wdXRbdHlwZT1yYW5nZV0geyBhY2NlbnQtY29sb3I6IHZhcigtLWN5YW4pOyB9CiAgaW5wdXRbdHlwZT1jb2xvcl0geyB3aWR0aDogMjhweDsgaGVpZ2h0OiAyMHB4OyBib3JkZXI6IG5vbmU7IGJvcmRlci1yYWRpdXM6IDRweDsgYmFja2dyb3VuZDogbm9uZTsgcGFkZGluZzogMDsgfQoKICAvKiA9PT09PSBQbGF5ZXJzIHRhYiA9PT09PSAqLwogIC5wbGF5ZXJzLXRvcCB7IGRpc3BsYXk6IGZsZXg7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGp1c3RpZnktY29udGVudDogc3BhY2UtYmV0d2VlbjsgbWFyZ2luLWJvdHRvbTogNnB4OyB9CiAgLnBsYXllcnMtY291bnQgeyBjb2xvcjogdmFyKC0tc3VjY2Vzcyk7IGZvbnQtc2l6ZTogMTFweDsgZGlzcGxheTogZmxleDsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA0cHg7IH0KICAuc2VhcmNoLXJvdyB7IGRpc3BsYXk6IGZsZXg7IGdhcDogNXB4OyBtYXJnaW4tYm90dG9tOiA4cHg7IH0KICAuc2VhcmNoLXJvdyAuaW5wdXQtc20geyBmbGV4OiAxOyB9CiAgLnNvcnQtcm93IHsgZGlzcGxheTogZmxleDsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiA0cHg7IG1hcmdpbi1ib3R0b206IDhweDsgfQogIC5zb3J0LWJ0biB7IGZvbnQtc2l6ZTogMTBweDsgcGFkZGluZzogNHB4IDhweDsgfQogIC5zb3J0LWJ0bi5hY3RpdmUgeyBjb2xvcjogdmFyKC0tY3lhbik7IH0KCiAgLnBsYXllci10YWJsZS1oZWFkIHsKICAgIGRpc3BsYXk6IGdyaWQ7IGdyaWQtdGVtcGxhdGUtY29sdW1uczogMjZweCAxZnIgNDBweCA0MHB4IDM0cHggNDBweDsKICAgIGZvbnQtc2l6ZTogMTBweDsgY29sb3I6IHZhcigtLWN5YW4pOyBiYWNrZ3JvdW5kOiB2YXIoLS1jaGlsZC1iZyk7IGJvcmRlci1yYWRpdXM6IDVweDsKICAgIHBhZGRpbmc6IDVweCA2cHg7IG1hcmdpbi1ib3R0b206IDRweDsKICB9CiAgI3BsYXllckxpc3QgeyBtYXgtaGVpZ2h0OiAxOTBweDsgb3ZlcmZsb3cteTogYXV0bzsgYmFja2dyb3VuZDogdmFyKC0tY2hpbGQtYmcpOyBib3JkZXItcmFkaXVzOiA1cHg7IHBhZGRpbmc6IDJweDsgfQogIC5wbGF5ZXItcm93IHsKICAgIGRpc3BsYXk6IGdyaWQ7IGdyaWQtdGVtcGxhdGUtY29sdW1uczogMjZweCAxZnIgNDBweCA0MHB4IDM0cHggNDBweDsgYWxpZ24taXRlbXM6IGNlbnRlcjsKICAgIGZvbnQtc2l6ZTogMTFweDsgcGFkZGluZzogNXB4IDZweDsgYm9yZGVyLXJhZGl1czogNHB4OyB0cmFuc2l0aW9uOiBiYWNrZ3JvdW5kIDAuMXM7CiAgfQogIC5wbGF5ZXItcm93OmFjdGl2ZSB7IGJhY2tncm91bmQ6ICMxZTFlMjQ7IH0KICAucGxheWVyLXJvdyAucGlkIHsgY29sb3I6IHZhcigtLWN5YW4pOyB9CiAgLnBsYXllci1yb3cgLnBuYW1lLnNlbGYgeyBjb2xvcjogdmFyKC0tc3VjY2Vzcyk7IH0KICAucGluZy1nIHsgY29sb3I6IHZhcigtLXN1Y2Nlc3MpOyB9IC5waW5nLXkgeyBjb2xvcjogdmFyKC0td2FybmluZyk7IH0gLnBpbmctciB7IGNvbG9yOiB2YXIoLS1kYW5nZXIpOyB9CiAgLnZpZXctYnRuIHsgYmFja2dyb3VuZDogdmFyKC0tY3lhbik7IGNvbG9yOiAjMDgxODFhOyBib3JkZXI6IG5vbmU7IGJvcmRlci1yYWRpdXM6IDRweDsgZm9udC1zaXplOiAxMHB4OyBwYWRkaW5nOiAzcHggMDsgd2lkdGg6IDI4cHg7IH0KICAuZW1wdHktaGludCB7IHRleHQtYWxpZ246IGNlbnRlcjsgY29sb3I6ICM2NjY7IGZvbnQtc2l6ZTogMTFweDsgcGFkZGluZzogMTZweCAwOyB9CgogIC8qID09PT09IExvZ3MgdGFiID09PT09ICovCiAgLmxvZ3MtdG9wIHsgZGlzcGxheTogZmxleDsgYWxpZ24taXRlbXM6IGNlbnRlcjsganVzdGlmeS1jb250ZW50OiBzcGFjZS1iZXR3ZWVuOyBtYXJnaW4tYm90dG9tOiA2cHg7IH0KICAuY2F0LXJvdyB7IGRpc3BsYXk6IGZsZXg7IGdhcDogM3B4OyBtYXJnaW4tYm90dG9tOiA4cHg7IH0KICAuY2F0LWJ0biB7IGZsZXg6IDE7IGZvbnQtc2l6ZTogMTBweDsgcGFkZGluZzogNXB4IDJweDsgYmFja2dyb3VuZDogIzI2MjYyYjsgYm9yZGVyLXJhZGl1czogNHB4OyB0ZXh0LWFsaWduOiBjZW50ZXI7IH0KICAuY2F0LWJ0bi5hY3RpdmUtYWxsIHsgYmFja2dyb3VuZDogcmdiYSg1MSwyMDQsMjA0LDAuMyk7IGNvbG9yOiB2YXIoLS1jeWFuKTsgfQogIC5jYXQtYnRuLmFjdGl2ZS1hZG1pbiB7IGJhY2tncm91bmQ6IHJnYmEoMjMwLDEwMiwxMDIsMC4zKTsgY29sb3I6ICNlNjY2NjY7IH0KICAuY2F0LWJ0bi5hY3RpdmUtcGxheWVyIHsgYmFja2dyb3VuZDogcmdiYSgxMDIsMTc5LDIzMCwwLjMpOyBjb2xvcjogIzY2YjNlNjsgfQogIC5jYXQtYnRuLmFjdGl2ZS1zZXJ2ZXIgeyBiYWNrZ3JvdW5kOiByZ2JhKDIzMCwxNzksNzcsMC4zKTsgY29sb3I6ICNlNmIzNGQ7IH0KICAuY2F0LWJ0bi5hY3RpdmUtc3lzdGVtIHsgYmFja2dyb3VuZDogcmdiYSgxNTMsMTUzLDIwNCwwLjMpOyBjb2xvcjogIzk5OTljYzsgfQogIC5zdGF0cy1iYXIgeyBkaXNwbGF5OiBmbGV4OyBnYXA6IDhweDsgYmFja2dyb3VuZDogdmFyKC0tY2hpbGQtYmcpOyBib3JkZXItcmFkaXVzOiA1cHg7IHBhZGRpbmc6IDVweCA4cHg7IGZvbnQtc2l6ZTogMTBweDsgbWFyZ2luLWJvdHRvbTogNnB4OyB9CiAgLnN0YXRzLWJhciBzcGFuOmxhc3QtY2hpbGQgeyBtYXJnaW4tbGVmdDogYXV0bzsgY29sb3I6IHZhcigtLWN5YW4pOyB9CiAgI2xvZ3NMaXN0IHsgbWF4LWhlaWdodDogMjEwcHg7IG92ZXJmbG93LXk6IGF1dG87IGJhY2tncm91bmQ6ICMwZDBkMGY7IGJvcmRlci1yYWRpdXM6IDVweDsgcGFkZGluZzogNXB4OyB9CiAgLmxvZy1saW5lIHsgZm9udC1zaXplOiAxMC41cHg7IGxpbmUtaGVpZ2h0OiAxLjU7IHdvcmQtYnJlYWs6IGJyZWFrLXdvcmQ7IG1hcmdpbi1ib3R0b206IDFweDsgfQogIC5sb2ctdGltZSB7IGNvbG9yOiAjNGQ0ZDRkOyB9CiAgLmxvZy1jYXQgeyBtYXJnaW46IDAgM3B4OyB9CgogIC8qID09PT09IFBsYXllciBQb3B1cCA9PT09PSAqLwogICNwb3B1cE92ZXJsYXkgewogICAgZGlzcGxheTogbm9uZTsgcG9zaXRpb246IGFic29sdXRlOyBsZWZ0OiAwOyB0b3A6IDA7IHdpZHRoOiAxMDAlOyBoZWlnaHQ6IDEwMCU7CiAgICBiYWNrZ3JvdW5kOiByZ2JhKDAsMCwwLDAuNTUpOyBhbGlnbi1pdGVtczogY2VudGVyOyBqdXN0aWZ5LWNvbnRlbnQ6IGNlbnRlcjsgei1pbmRleDogNTA7CiAgfQogICNwb3B1cE92ZXJsYXkuc2hvdyB7IGRpc3BsYXk6IGZsZXg7IH0KICAjcG9wdXBDYXJkIHsKICAgIHdpZHRoOiAzMDBweDsgbWF4LWhlaWdodDogNDIwcHg7IGJhY2tncm91bmQ6ICMxNzE3MWI7IGJvcmRlcjogMXB4IHNvbGlkIHJnYmEoNTEsMjA0LDIwNCwwLjM1KTsKICAgIGJvcmRlci1yYWRpdXM6IDEwcHg7IHBhZGRpbmc6IDEycHg7IG92ZXJmbG93LXk6IGF1dG87CiAgfQogIC5wb3B1cC1jbG9zZS1yb3cgeyBkaXNwbGF5OiBmbGV4OyBqdXN0aWZ5LWNvbnRlbnQ6IGZsZXgtZW5kOyBtYXJnaW4tYm90dG9tOiA0cHg7IH0KICAucG9wdXAtY2xvc2UtYnRuIHsgYmFja2dyb3VuZDogIzY2MWYxZjsgY29sb3I6ICNmZmY7IGJvcmRlcjogbm9uZTsgYm9yZGVyLXJhZGl1czogNXB4OyB3aWR0aDogMjRweDsgaGVpZ2h0OiAyNHB4OyBmb250LXNpemU6IDExcHg7IH0KICAucG9wdXAtaW5mbyB7IGJhY2tncm91bmQ6ICMxZTFlMjM7IGJvcmRlci1yYWRpdXM6IDZweDsgcGFkZGluZzogOHB4IDEwcHg7IG1hcmdpbi1ib3R0b206IDEwcHg7IH0KICAucG9wdXAtaW5mby10b3AgeyBkaXNwbGF5OiBmbGV4OyBqdXN0aWZ5LWNvbnRlbnQ6IHNwYWNlLWJldHdlZW47IGFsaWduLWl0ZW1zOiBjZW50ZXI7IG1hcmdpbi1ib3R0b206IDRweDsgfQogIC5wb3B1cC1pbmZvLW5hbWUgeyBjb2xvcjogI2ZmZjsgZm9udC1zaXplOiAxM3B4OyBmb250LXdlaWdodDogNjAwOyB9CiAgLnBvcHVwLWluZm8tb25saW5lIHsgY29sb3I6IHZhcigtLXN1Y2Nlc3MpOyBmb250LXNpemU6IDEwcHg7IGRpc3BsYXk6IGZsZXg7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogM3B4OyB9CiAgLnBvcHVwLWluZm8tc3RhdHMgeyBkaXNwbGF5OiBmbGV4OyBnYXA6IDEwcHg7IGZvbnQtc2l6ZTogMTFweDsgfQogIC5wb3B1cC1zZWN0aW9uLWxhYmVsIHsgY29sb3I6ICM4ODg7IGZvbnQtc2l6ZTogMTFweDsgbWFyZ2luOiA2cHggMCA1cHg7IGRpc3BsYXk6IGZsZXg7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogNXB4OyB9CiAgLnB1bmlzaC1yb3csIC5hY3Rpb24tZ3JpZCB7IGRpc3BsYXk6IGdyaWQ7IGdyaWQtdGVtcGxhdGUtY29sdW1uczogcmVwZWF0KDMsIDFmcik7IGdhcDogNXB4OyBtYXJnaW4tYm90dG9tOiA4cHg7IH0KICAucHVuaXNoLXJvdyAuYnRuLCAuYWN0aW9uLWdyaWQgLmJ0biB7IGZvbnQtc2l6ZTogMTBweDsgcGFkZGluZzogN3B4IDJweDsganVzdGlmeS1jb250ZW50OiBjZW50ZXI7IH0KICAjcG9wdXBGb3JtIHsgYm9yZGVyLXRvcDogMXB4IHNvbGlkIHZhcigtLWJvcmRlcik7IHBhZGRpbmctdG9wOiA4cHg7IG1hcmdpbi10b3A6IDRweDsgfQogIC5mb3JtLXJvdyB7IGRpc3BsYXk6IGZsZXg7IGFsaWduLWl0ZW1zOiBjZW50ZXI7IGdhcDogNnB4OyBtYXJnaW4tYm90dG9tOiA2cHg7IGZsZXgtd3JhcDogd3JhcDsgfQogIC5mb3JtLXJvdyAuaW5wdXQtc20geyBmbGV4OiAxOyBtaW4td2lkdGg6IDYwcHg7IH0KICAuZW1wdHktc2VsZWN0IHsgdGV4dC1hbGlnbjogY2VudGVyOyBjb2xvcjogIzU1NTsgZm9udC1zaXplOiAxMXB4OyBwYWRkaW5nOiAxMHB4IDA7IH0KPC9zdHlsZT4KPC9oZWFkPgo8Ym9keT4KCjxkaXYgaWQ9ImFwcCI+CgogIDwhLS0gPT09PT09PT09PT09IExPR0lOID09PT09PT09PT09PSAtLT4KICA8ZGl2IGlkPSJsb2dpblNjcmVlbiI+CiAgICA8YnV0dG9uIGNsYXNzPSJhcHAtY2xvc2UtYnRuIiBvbmNsaWNrPSJhY3QoJ2Nsb3NlQXBwJykiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS14bWFyayI+PC9pPjwvYnV0dG9uPgogICAgPGRpdiBjbGFzcz0ibG9naW4tcnVsZSI+LS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tPC9kaXY+CiAgICA8ZGl2IGNsYXNzPSJsb2dpbi1zaGllbGQgZHJhZy1oYW5kbGUiIGlkPSJsb2dpbkRyYWdIYW5kbGUiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1zaGllbGQtaGFsdmVkIj48L2k+PC9kaXY+CiAgICA8ZGl2IGNsYXNzPSJsb2dpbi10aXRsZSI+dHhBZG1pbiBQYW5lbDwvZGl2PgogICAgPGRpdiBjbGFzcz0ibG9naW4tc3VidGl0bGUiPlNlcnZlciBBZG1pbmlzdHJhdGlvbjwvZGl2PgoKICAgIDxkaXYgY2xhc3M9ImZpZWxkLWdyb3VwIj4KICAgICAgPGRpdiBjbGFzcz0iZmllbGQtbGFiZWwiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS11c2VyIj48L2k+IFVDUCBVc2VybmFtZTwvZGl2PgogICAgICA8aW5wdXQgY2xhc3M9ImZpZWxkLWlucHV0IiBpZD0ibG9naW5Vc2VyIiBwbGFjZWhvbGRlcj0iRW50ZXIgeW91ciBVQ1AgbmFtZSI+CiAgICA8L2Rpdj4KICAgIDxkaXYgY2xhc3M9ImZpZWxkLWdyb3VwIj4KICAgICAgPGRpdiBjbGFzcz0iZmllbGQtbGFiZWwiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1sb2NrIj48L2k+IFBhc3N3b3JkPC9kaXY+CiAgICAgIDxpbnB1dCBjbGFzcz0iZmllbGQtaW5wdXQiIGlkPSJsb2dpblBhc3MiIHR5cGU9InBhc3N3b3JkIiBwbGFjZWhvbGRlcj0iRW50ZXIgeW91ciBwYXNzd29yZCI+CiAgICA8L2Rpdj4KICAgIDxkaXYgY2xhc3M9InJlbWVtYmVyLXJvdyI+PGlucHV0IHR5cGU9ImNoZWNrYm94IiBpZD0icmVtZW1iZXJNZSI+IFJlbWVtYmVyIG1lPC9kaXY+CgogICAgPGRpdiBjbGFzcz0ibG9naW4tZXJyb3IiIGlkPSJsb2dpbkVycm9yIj48aSBjbGFzcz0iZmEtc29saWQgZmEtY2lyY2xlLWV4Y2xhbWF0aW9uIj48L2k+IDxzcGFuIGlkPSJsb2dpbkVycm9yVGV4dCI+PC9zcGFuPjwvZGl2PgoKICAgIDxidXR0b24gY2xhc3M9ImxvZ2luLWJ0biIgaWQ9ImxvZ2luQnRuIiBvbmNsaWNrPSJkb0xvZ2luKCkiPgogICAgICA8aSBjbGFzcz0iZmEtc29saWQgZmEtcmlnaHQtdG8tYnJhY2tldCI+PC9pPiBMT0dJTgogICAgPC9idXR0b24+CgogICAgPGRpdiBjbGFzcz0ibG9naW4tZm9vdGVyIj48aSBjbGFzcz0iZmEtc29saWQgZmEtY29kZSI+PC9pPiA0dHJheXMuVGVhbSB2NC41LjI8L2Rpdj4KICAgIDxkaXYgY2xhc3M9ImxvZ2luLXJ1bGUiPi0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLTwvZGl2PgogIDwvZGl2PgoKICA8IS0tID09PT09PT09PT09PSBMT0FESU5HID09PT09PT09PT09PSAtLT4KICA8ZGl2IGlkPSJsb2FkaW5nU2NyZWVuIj4KICAgIDxkaXYgY2xhc3M9ImxvYWRpbmctaWNvbiI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLXNoaWVsZC1oYWx2ZWQiPjwvaT48L2Rpdj4KICAgIDxkaXYgY2xhc3M9ImxvYWRpbmctdGV4dCIgaWQ9ImxvYWRpbmdUZXh0Ij5BdXRoZW50aWNhdGluZy4uLjwvZGl2PgogICAgPGRpdiBjbGFzcz0ibG9hZGluZy1iYXItdHJhY2siPjxkaXYgY2xhc3M9ImxvYWRpbmctYmFyLWZpbGwiIGlkPSJsb2FkaW5nQmFyIj48L2Rpdj48L2Rpdj4KICA8L2Rpdj4KCiAgPCEtLSA9PT09PT09PT09PT0gTUFJTiA9PT09PT09PT09PT0gLS0+CiAgPGRpdiBpZD0ibWFpblNjcmVlbiI+CiAgICA8ZGl2IGNsYXNzPSJtYWluLWhlYWRlciBkcmFnLWhhbmRsZSIgaWQ9Im1haW5EcmFnSGFuZGxlIj4KICAgICAgPGJ1dHRvbiBjbGFzcz0iYXBwLWNsb3NlLWJ0biIgb25jbGljaz0iYWN0KCdjbG9zZUFwcCcpIiBzdHlsZT0icmlnaHQ6OHB4OyB0b3A6OHB4OyI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLXhtYXJrIj48L2k+PC9idXR0b24+CiAgICAgIDxkaXYgY2xhc3M9Im1haW4taGVhZGVyLXRpdGxlIj48aSBjbGFzcz0iZmEtc29saWQgZmEtc2NyZXdkcml2ZXItd3JlbmNoIj48L2k+IHR4QWRtaW48L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0ibWFpbi1oZWFkZXItdmVyc2lvbiI+djQuNS4yPC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9ImxvY2stYmFkZ2UiIGlkPSJsb2NrQmFkZ2UiIHN0eWxlPSJkaXNwbGF5Om5vbmU7IHJpZ2h0OjM2cHg7Ij48aSBjbGFzcz0iZmEtc29saWQgZmEtbG9jayI+PC9pPjwvZGl2PgogICAgPC9kaXY+CiAgICA8ZGl2IGNsYXNzPSJoZWFkZXItZGl2aWRlciI+PC9kaXY+CgogICAgPGRpdiBjbGFzcz0idGFicyI+CiAgICAgIDxidXR0b24gY2xhc3M9InRhYi1idG4gYWN0aXZlIiBpZD0idGFiQnRuMSIgb25jbGljaz0ic3dpdGNoVGFiKDEpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtaG91c2UiPjwvaT4gTUFJTjwvYnV0dG9uPgogICAgICA8YnV0dG9uIGNsYXNzPSJ0YWItYnRuIiBpZD0idGFiQnRuMiIgb25jbGljaz0ic3dpdGNoVGFiKDIpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtdXNlcnMiPjwvaT4gUExBWUVSUzwvYnV0dG9uPgogICAgICA8YnV0dG9uIGNsYXNzPSJ0YWItYnRuIiBpZD0idGFiQnRuMyIgb25jbGljaz0ic3dpdGNoVGFiKDMpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtbGlzdC11bCI+PC9pPiBMT0dTPC9idXR0b24+CiAgICA8L2Rpdj4KCiAgICA8ZGl2IGNsYXNzPSJ0YWItY29udGVudCI+CgogICAgICA8IS0tID09PT09IFRBQiAxOiBNQUlOID09PT09IC0tPgogICAgICA8ZGl2IGNsYXNzPSJ0YWItcGFuZSBhY3RpdmUiIGlkPSJwYW5lMSI+CgogICAgICAgIDxkaXYgY2xhc3M9InNlY3Rpb24iPgogICAgICAgICAgPGRpdiBjbGFzcz0ic2VjdGlvbi1oZWFkIiBvbmNsaWNrPSJ0b2dnbGVTZWN0aW9uKCdwbGF5ZXJNb2RlJykiPgogICAgICAgICAgICA8aSBjbGFzcz0iZmEtc29saWQgZmEtZ2VhciI+PC9pPgogICAgICAgICAgICA8c3BhbiBjbGFzcz0ic2VjdGlvbi10aXRsZSI+UGxheWVyIE1vZGU8L3NwYW4+CiAgICAgICAgICAgIDxzcGFuIGNsYXNzPSJzZWN0aW9uLWJhZGdlIG9mZiIgaWQ9ImR1dHlCYWRnZSI+T2ZmIER1dHk8L3NwYW4+CiAgICAgICAgICAgIDxzcGFuIGNsYXNzPSJzZWN0aW9uLWNoZXZyb24iIGlkPSJjaGV2LXBsYXllck1vZGUiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1jaGV2cm9uLXJpZ2h0Ij48L2k+PC9zcGFuPgogICAgICAgICAgPC9kaXY+CiAgICAgICAgICA8ZGl2IGNsYXNzPSJzZWN0aW9uLWJvZHkiIGlkPSJib2R5LXBsYXllck1vZGUiPgogICAgICAgICAgICA8ZGl2IGNsYXNzPSJyb3ciPgogICAgICAgICAgICAgIDxidXR0b24gY2xhc3M9ImJ0biBidG4tZGFuZ2VyIiBpZD0iZHV0eUJ0biIgb25jbGljaz0iYWN0KCdkdXR5VG9nZ2xlJykiIHN0eWxlPSJmbGV4OjE7Ij5HbyBPbiBEdXR5PC9idXR0b24+CiAgICAgICAgICAgIDwvZGl2PgogICAgICAgICAgICA8ZGl2IGNsYXNzPSJyb3ciPgogICAgICAgICAgICAgIDxidXR0b24gY2xhc3M9ImJ0biIgc3R5bGU9ImZsZXg6MTsiIG9uY2xpY2s9ImFjdCgnc3RhZmZPbmxpbmUnKSI+U3RhZmYgT25saW5lPC9idXR0b24+CiAgICAgICAgICAgICAgPGJ1dHRvbiBjbGFzcz0iYnRuIiBzdHlsZT0iZmxleDoxOyIgb25jbGljaz0iYWN0KCduZXdQbGF5ZXInKSI+TmV3IFBsYXllcjwvYnV0dG9uPgogICAgICAgICAgICA8L2Rpdj4KICAgICAgICAgIDwvZGl2PgogICAgICAgIDwvZGl2PgoKICAgICAgICA8ZGl2IGNsYXNzPSJzZWN0aW9uIj4KICAgICAgICAgIDxkaXYgY2xhc3M9InNlY3Rpb24taGVhZCIgb25jbGljaz0idG9nZ2xlU2VjdGlvbigndGVsZXBvcnQnKSI+CiAgICAgICAgICAgIDxpIGNsYXNzPSJmYS1zb2xpZCBmYS1sb2NhdGlvbi1kb3QiPjwvaT4KICAgICAgICAgICAgPHNwYW4gY2xhc3M9InNlY3Rpb24tdGl0bGUiPlRlbGVwb3J0PC9zcGFuPgogICAgICAgICAgICA8c3BhbiBjbGFzcz0ic2VjdGlvbi1iYWRnZSI+V2F5cG9pbnQ8L3NwYW4+CiAgICAgICAgICAgIDxzcGFuIGNsYXNzPSJzZWN0aW9uLWNoZXZyb24iIGlkPSJjaGV2LXRlbGVwb3J0Ij48aSBjbGFzcz0iZmEtc29saWQgZmEtY2hldnJvbi1yaWdodCI+PC9pPjwvc3Bhbj4KICAgICAgICAgIDwvZGl2PgogICAgICAgICAgPGRpdiBjbGFzcz0ic2VjdGlvbi1ib2R5IiBpZD0iYm9keS10ZWxlcG9ydCI+CiAgICAgICAgICAgIDxkaXYgY2xhc3M9ImZvcm0tcm93Ij4KICAgICAgICAgICAgICA8c3BhbiBjbGFzcz0ibGJsLWlubGluZSI+SUQ6PC9zcGFuPgogICAgICAgICAgICAgIDxpbnB1dCBjbGFzcz0iaW5wdXQtc20iIGlkPSJ0cElkIiBzdHlsZT0id2lkdGg6NDRweDsiIHBsYWNlaG9sZGVyPSJJRCI+CiAgICAgICAgICAgICAgPHNwYW4gY2xhc3M9ImxibC1pbmxpbmUiPkRlc3Q6PC9zcGFuPgogICAgICAgICAgICAgIDxpbnB1dCBjbGFzcz0iaW5wdXQtc20iIGlkPSJ0cERlc3QiIHBsYWNlaG9sZGVyPSJMb2NhdGlvbiI+CiAgICAgICAgICAgICAgPGJ1dHRvbiBjbGFzcz0iYnRuIGJ0bi1jeWFuIiBvbmNsaWNrPSJ0ZWxlcG9ydEdvKCkiPlRQPC9idXR0b24+CiAgICAgICAgICAgIDwvZGl2PgogICAgICAgICAgPC9kaXY+CiAgICAgICAgPC9kaXY+CgogICAgICAgIDxkaXYgY2xhc3M9InNlY3Rpb24iPgogICAgICAgICAgPGRpdiBjbGFzcz0ic2VjdGlvbi1oZWFkIiBvbmNsaWNrPSJ0b2dnbGVTZWN0aW9uKCd2ZWhpY2xlJykiPgogICAgICAgICAgICA8aSBjbGFzcz0iZmEtc29saWQgZmEtY2FyIj48L2k+CiAgICAgICAgICAgIDxzcGFuIGNsYXNzPSJzZWN0aW9uLXRpdGxlIj5WZWhpY2xlPC9zcGFuPgogICAgICAgICAgICA8c3BhbiBjbGFzcz0ic2VjdGlvbi1iYWRnZSI+U3Bhd248L3NwYW4+CiAgICAgICAgICAgIDxzcGFuIGNsYXNzPSJzZWN0aW9uLWNoZXZyb24iIGlkPSJjaGV2LXZlaGljbGUiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1jaGV2cm9uLXJpZ2h0Ij48L2k+PC9zcGFuPgogICAgICAgICAgPC9kaXY+CiAgICAgICAgICA8ZGl2IGNsYXNzPSJzZWN0aW9uLWJvZHkiIGlkPSJib2R5LXZlaGljbGUiPgogICAgICAgICAgICA8ZGl2IGNsYXNzPSJmb3JtLXJvdyI+CiAgICAgICAgICAgICAgPHNwYW4gY2xhc3M9ImxibC1pbmxpbmUiPk1vZGVsOjwvc3Bhbj4KICAgICAgICAgICAgICA8aW5wdXQgY2xhc3M9ImlucHV0LXNtIiBpZD0idmVoTW9kZWwiIHBsYWNlaG9sZGVyPSJWZWhpY2xlIG5hbWUgb3IgSUQiPgogICAgICAgICAgICAgIDxidXR0b24gY2xhc3M9ImJ0biBidG4tY3lhbiIgb25jbGljaz0idmVoaWNsZUdvKCkiPlNwYXduPC9idXR0b24+CiAgICAgICAgICAgIDwvZGl2PgogICAgICAgICAgPC9kaXY+CiAgICAgICAgPC9kaXY+CgogICAgICAgIDxkaXYgY2xhc3M9InNlY3Rpb24iPgogICAgICAgICAgPGRpdiBjbGFzcz0ic2VjdGlvbi1oZWFkIiBvbmNsaWNrPSJ0b2dnbGVTZWN0aW9uKCdoZWFsJykiPgogICAgICAgICAgICA8aSBjbGFzcz0iZmEtc29saWQgZmEtaGVhcnQiPjwvaT4KICAgICAgICAgICAgPHNwYW4gY2xhc3M9InNlY3Rpb24tdGl0bGUiPkhlYWw8L3NwYW4+CiAgICAgICAgICAgIDxzcGFuIGNsYXNzPSJzZWN0aW9uLWJhZGdlIj5IUCBDb250cm9sPC9zcGFuPgogICAgICAgICAgICA8c3BhbiBjbGFzcz0ic2VjdGlvbi1jaGV2cm9uIiBpZD0iY2hldi1oZWFsIj48aSBjbGFzcz0iZmEtc29saWQgZmEtY2hldnJvbi1yaWdodCI+PC9pPjwvc3Bhbj4KICAgICAgICAgIDwvZGl2PgogICAgICAgICAgPGRpdiBjbGFzcz0ic2VjdGlvbi1ib2R5IiBpZD0iYm9keS1oZWFsIj4KICAgICAgICAgICAgPGRpdiBjbGFzcz0iZm9ybS1yb3ciPgogICAgICAgICAgICAgIDxzcGFuIGNsYXNzPSJsYmwtaW5saW5lIj5JRDo8L3NwYW4+CiAgICAgICAgICAgICAgPGlucHV0IGNsYXNzPSJpbnB1dC1zbSIgaWQ9ImhlYWxJZCIgc3R5bGU9IndpZHRoOjQ0cHg7IiBwbGFjZWhvbGRlcj0iSUQiPgogICAgICAgICAgICAgIDxzcGFuIGNsYXNzPSJsYmwtaW5saW5lIj5IUDo8L3NwYW4+CiAgICAgICAgICAgICAgPGlucHV0IGNsYXNzPSJpbnB1dC1zbSIgaWQ9ImhlYWxBbXQiIHN0eWxlPSJ3aWR0aDo2MHB4OyIgcGxhY2Vob2xkZXI9IjEtMTAwIj4KICAgICAgICAgICAgICA8YnV0dG9uIGNsYXNzPSJidG4gYnRuLWN5YW4iIG9uY2xpY2s9ImhlYWxHbygpIj5TZXQ8L2J1dHRvbj4KICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICA8L2Rpdj4KICAgICAgICA8L2Rpdj4KCiAgICAgICAgPGRpdiBjbGFzcz0ic2VjdGlvbiI+CiAgICAgICAgICA8ZGl2IGNsYXNzPSJzZWN0aW9uLWhlYWQiIG9uY2xpY2s9InRvZ2dsZVNlY3Rpb24oJ3dvcmxkJykiPgogICAgICAgICAgICA8aSBjbGFzcz0iZmEtc29saWQgZmEtZ2xvYmUiPjwvaT4KICAgICAgICAgICAgPHNwYW4gY2xhc3M9InNlY3Rpb24tdGl0bGUiPldvcmxkPC9zcGFuPgogICAgICAgICAgICA8c3BhbiBjbGFzcz0ic2VjdGlvbi1iYWRnZSI+RVNQICZhbXA7IFZpc3VhbDwvc3Bhbj4KICAgICAgICAgICAgPHNwYW4gY2xhc3M9InNlY3Rpb24tY2hldnJvbiIgaWQ9ImNoZXYtd29ybGQiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1jaGV2cm9uLXJpZ2h0Ij48L2k+PC9zcGFuPgogICAgICAgICAgPC9kaXY+CiAgICAgICAgICA8ZGl2IGNsYXNzPSJzZWN0aW9uLWJvZHkiIGlkPSJib2R5LXdvcmxkIj4KICAgICAgICAgICAgPGRpdiBjbGFzcz0icG9wdXAtc2VjdGlvbi1sYWJlbCI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLXVzZXItdGFnIj48L2k+IFBsYXllciBOYW1lczwvZGl2PgogICAgICAgICAgICA8ZGl2IGNsYXNzPSJjaGVja2JveC1yb3ciPjxpbnB1dCB0eXBlPSJjaGVja2JveCIgaWQ9Im5hbWVzT24iIG9uY2hhbmdlPSJ3b3JsZE5hbWVzVG9nZ2xlKCkiPiBTaG93PC9kaXY+CiAgICAgICAgICAgIDxkaXYgY2xhc3M9InJvdyIgaWQ9Im5hbWVTaXplUm93IiBzdHlsZT0iZGlzcGxheTpub25lOyI+CiAgICAgICAgICAgICAgPHNwYW4gY2xhc3M9ImxibC1pbmxpbmUiPlNpemU6PC9zcGFuPgogICAgICAgICAgICAgIDxpbnB1dCB0eXBlPSJyYW5nZSIgaWQ9Im5hbWVTaXplIiBtaW49IjYiIG1heD0iMTYiIHZhbHVlPSIxNCIgb25pbnB1dD0id29ybGROYW1lU2l6ZSgpIiBzdHlsZT0iZmxleDoxOyI+CiAgICAgICAgICAgICAgPHNwYW4gY2xhc3M9ImxibC1pbmxpbmUiIGlkPSJuYW1lU2l6ZVZhbCI+MTQ8L3NwYW4+CiAgICAgICAgICAgIDwvZGl2PgoKICAgICAgICAgICAgPGRpdiBjbGFzcz0icG9wdXAtc2VjdGlvbi1sYWJlbCI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLXRpbWVsaW5lIj48L2k+IFBsYXllciBMaW5lczwvZGl2PgogICAgICAgICAgICA8ZGl2IGNsYXNzPSJjaGVja2JveC1yb3ciPjxpbnB1dCB0eXBlPSJjaGVja2JveCIgaWQ9ImxpbmVzT24iIG9uY2hhbmdlPSJ3b3JsZExpbmVzVG9nZ2xlKCkiPiBTaG93PC9kaXY+CiAgICAgICAgICAgIDxkaXYgY2xhc3M9InJvdyIgaWQ9ImxpbmVPcHRSb3ciIHN0eWxlPSJkaXNwbGF5Om5vbmU7Ij4KICAgICAgICAgICAgICA8c3BhbiBjbGFzcz0ibGJsLWlubGluZSI+Q29sb3I6PC9zcGFuPgogICAgICAgICAgICAgIDxpbnB1dCB0eXBlPSJjb2xvciIgaWQ9ImxpbmVDb2xvciIgdmFsdWU9IiNmZmZmZmYiIG9uaW5wdXQ9IndvcmxkTGluZUNvbG9yKCkiPgogICAgICAgICAgICAgIDxzcGFuIGNsYXNzPSJsYmwtaW5saW5lIj5XaWR0aDo8L3NwYW4+CiAgICAgICAgICAgICAgPGlucHV0IHR5cGU9InJhbmdlIiBpZD0ibGluZVdpZHRoIiBtaW49IjEiIG1heD0iNSIgc3RlcD0iMC41IiB2YWx1ZT0iMiIgb25pbnB1dD0id29ybGRMaW5lVGhpY2tuZXNzKCkiIHN0eWxlPSJmbGV4OjE7Ij4KICAgICAgICAgICAgPC9kaXY+CiAgICAgICAgICA8L2Rpdj4KICAgICAgICA8L2Rpdj4KCiAgICAgIDwvZGl2PgoKICAgICAgPCEtLSA9PT09PSBUQUIgMjogUExBWUVSUyA9PT09PSAtLT4KICAgICAgPGRpdiBjbGFzcz0idGFiLXBhbmUiIGlkPSJwYW5lMiI+CiAgICAgICAgPGRpdiBjbGFzcz0icGxheWVycy10b3AiPgogICAgICAgICAgPHNwYW4gc3R5bGU9ImNvbG9yOnZhcigtLWN5YW4pOyI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLXVzZXJzIj48L2k+IE9ubGluZSBQbGF5ZXJzPC9zcGFuPgogICAgICAgICAgPHNwYW4gY2xhc3M9InBsYXllcnMtY291bnQiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1jaXJjbGUiIHN0eWxlPSJmb250LXNpemU6N3B4OyI+PC9pPiA8c3BhbiBpZD0icGxheWVyQ291bnRUeHQiPjA8L3NwYW4+IHBsYXllcnM8L3NwYW4+CiAgICAgICAgPC9kaXY+CiAgICAgICAgPGRpdiBjbGFzcz0ic2VhcmNoLXJvdyI+CiAgICAgICAgICA8aW5wdXQgY2xhc3M9ImlucHV0LXNtIiBpZD0icGxheWVyU2VhcmNoIiBwbGFjZWhvbGRlcj0iU2VhcmNoLi4uIiBvbmtleWRvd249ImlmKGV2ZW50LmtleT09PSdFbnRlcicpcGxheWVyc1NlYXJjaCgpIj4KICAgICAgICAgIDxidXR0b24gY2xhc3M9ImJ0biIgb25jbGljaz0icGxheWVyc1NlYXJjaCgpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtbWFnbmlmeWluZy1nbGFzcyI+PC9pPjwvYnV0dG9uPgogICAgICAgICAgPGJ1dHRvbiBjbGFzcz0iYnRuIiBvbmNsaWNrPSJhY3QoJ3BsYXllcnNSZWZyZXNoJykiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1yb3RhdGUiPjwvaT48L2J1dHRvbj4KICAgICAgICA8L2Rpdj4KICAgICAgICA8ZGl2IGNsYXNzPSJzZWFyY2gtcm93Ij4KICAgICAgICAgIDxzcGFuIGNsYXNzPSJsYmwtaW5saW5lIj5SYWRpdXM6PC9zcGFuPgogICAgICAgICAgPGlucHV0IGNsYXNzPSJpbnB1dC1zbSIgaWQ9InNjYW5SYWRpdXMiIHN0eWxlPSJ3aWR0aDo1MHB4OyIgdmFsdWU9IjUwIj4KICAgICAgICAgIDxidXR0b24gY2xhc3M9ImJ0biIgb25jbGljaz0icGxheWVyc1NjYW4oKSI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLWxvY2F0aW9uLWNyb3NzaGFpcnMiPjwvaT4gU2NhbjwvYnV0dG9uPgogICAgICAgICAgPHNwYW4gY2xhc3M9ImxibC1pbmxpbmUiIHN0eWxlPSJtYXJnaW4tbGVmdDphdXRvOyI+U29ydDo8L3NwYW4+CiAgICAgICAgICA8YnV0dG9uIGNsYXNzPSJidG4gc29ydC1idG4gYWN0aXZlIiBpZD0ic29ydElkIiBvbmNsaWNrPSJwbGF5ZXJzU29ydCgnaWQnKSI+SUQ8L2J1dHRvbj4KICAgICAgICAgIDxidXR0b24gY2xhc3M9ImJ0biBzb3J0LWJ0biIgaWQ9InNvcnREaXN0IiBvbmNsaWNrPSJwbGF5ZXJzU29ydCgnZGlzdGFuY2UnKSI+RGlzdDwvYnV0dG9uPgogICAgICAgICAgPGJ1dHRvbiBjbGFzcz0iYnRuIHNvcnQtYnRuIiBpZD0ic29ydFBpbmciIG9uY2xpY2s9InBsYXllcnNTb3J0KCdwaW5nJykiPlBpbmc8L2J1dHRvbj4KICAgICAgICA8L2Rpdj4KCiAgICAgICAgPGRpdiBjbGFzcz0icGxheWVyLXRhYmxlLWhlYWQiPgogICAgICAgICAgPHNwYW4+SUQ8L3NwYW4+PHNwYW4+TmFtZTwvc3Bhbj48c3Bhbj5QaW5nPC9zcGFuPjxzcGFuPkRpc3Q8L3NwYW4+PHNwYW4+SFA8L3NwYW4+PHNwYW4+PC9zcGFuPgogICAgICAgIDwvZGl2PgogICAgICAgIDxkaXYgaWQ9InBsYXllckxpc3QiPjxkaXYgY2xhc3M9ImVtcHR5LWhpbnQiPk5vIHBsYXllcnMgZm91bmQuIENsaWNrIHJlZnJlc2ggdG8gbG9hZC48L2Rpdj48L2Rpdj4KICAgICAgPC9kaXY+CgogICAgICA8IS0tID09PT09IFRBQiAzOiBMT0dTID09PT09IC0tPgogICAgICA8ZGl2IGNsYXNzPSJ0YWItcGFuZSIgaWQ9InBhbmUzIj4KICAgICAgICA8ZGl2IGNsYXNzPSJsb2dzLXRvcCI+CiAgICAgICAgICA8c3BhbiBzdHlsZT0iY29sb3I6dmFyKC0tY3lhbik7Ij48aSBjbGFzcz0iZmEtc29saWQgZmEtbGlzdC11bCI+PC9pPiBMaXZlIENvbnNvbGU8L3NwYW4+CiAgICAgICAgICA8c3BhbiBzdHlsZT0iY29sb3I6IzgwODA4MDtmb250LXNpemU6MTFweDsiPlRvdGFsOiA8c3BhbiBpZD0ibG9nc1RvdGFsVHh0Ij4wPC9zcGFuPjwvc3Bhbj4KICAgICAgICA8L2Rpdj4KICAgICAgICA8ZGl2IGNsYXNzPSJjYXQtcm93IiBpZD0iY2F0Um93Ij4KICAgICAgICAgIDxidXR0b24gY2xhc3M9ImNhdC1idG4gYWN0aXZlLWFsbCIgb25jbGljaz0ibG9nc0NhdGVnb3J5KDAsdGhpcykiPkFsbDwvYnV0dG9uPgogICAgICAgICAgPGJ1dHRvbiBjbGFzcz0iY2F0LWJ0biIgb25jbGljaz0ibG9nc0NhdGVnb3J5KDEsdGhpcykiPkFkbWluPC9idXR0b24+CiAgICAgICAgICA8YnV0dG9uIGNsYXNzPSJjYXQtYnRuIiBvbmNsaWNrPSJsb2dzQ2F0ZWdvcnkoMix0aGlzKSI+UGxheWVyPC9idXR0b24+CiAgICAgICAgICA8YnV0dG9uIGNsYXNzPSJjYXQtYnRuIiBvbmNsaWNrPSJsb2dzQ2F0ZWdvcnkoMyx0aGlzKSI+U2VydmVyPC9idXR0b24+CiAgICAgICAgICA8YnV0dG9uIGNsYXNzPSJjYXQtYnRuIiBvbmNsaWNrPSJsb2dzQ2F0ZWdvcnkoNCx0aGlzKSI+U3lzdGVtPC9idXR0b24+CiAgICAgICAgPC9kaXY+CiAgICAgICAgPGRpdiBjbGFzcz0ic2VhcmNoLXJvdyI+CiAgICAgICAgICA8aW5wdXQgY2xhc3M9ImlucHV0LXNtIiBpZD0ibG9nc1NlYXJjaCIgcGxhY2Vob2xkZXI9IlNlYXJjaC4uLiIgb25pbnB1dD0ibG9nc1NlYXJjaCgpIj4KICAgICAgICAgIDxidXR0b24gY2xhc3M9ImJ0biIgb25jbGljaz0iYWN0KCdsb2dzQ2xlYXInKSI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLXhtYXJrIj48L2k+PC9idXR0b24+CiAgICAgICAgICA8YnV0dG9uIGNsYXNzPSJidG4iIG9uY2xpY2s9ImFjdCgnbG9nc1Njcm9sbEJvdHRvbScpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtYXJyb3ctZG93biI+PC9pPjwvYnV0dG9uPgogICAgICAgIDwvZGl2PgogICAgICAgIDxkaXYgY2xhc3M9InN0YXRzLWJhciI+CiAgICAgICAgICA8c3BhbiBzdHlsZT0iY29sb3I6I2U2NGQ0ZDsiPkI6PHNwYW4gaWQ9InN0YXRCIj4wPC9zcGFuPjwvc3Bhbj4KICAgICAgICAgIDxzcGFuIHN0eWxlPSJjb2xvcjojZTY4YTRkOyI+Szo8c3BhbiBpZD0ic3RhdEsiPjA8L3NwYW4+PC9zcGFuPgogICAgICAgICAgPHNwYW4gc3R5bGU9ImNvbG9yOnZhcigtLXdhcm5pbmcpOyI+Vzo8c3BhbiBpZD0ic3RhdFciPjA8L3NwYW4+PC9zcGFuPgogICAgICAgICAgPHNwYW4gc3R5bGU9ImNvbG9yOiNiMzY2ZTY7Ij5NOjxzcGFuIGlkPSJzdGF0TSI+MDwvc3Bhbj48L3NwYW4+CiAgICAgICAgICA8c3BhbiBzdHlsZT0iY29sb3I6IzgwODA4MDsiPko6PHNwYW4gaWQ9InN0YXRKIj4wPC9zcGFuPjwvc3Bhbj4KICAgICAgICAgIDxzcGFuIGlkPSJjbG9ja1R4dCI+LS06LS06LS08L3NwYW4+CiAgICAgICAgPC9kaXY+CiAgICAgICAgPGRpdiBpZD0ibG9nc0xpc3QiPjxkaXYgY2xhc3M9ImVtcHR5LWhpbnQiPk5vIGxvZ3M8L2Rpdj48L2Rpdj4KICAgICAgPC9kaXY+CgogICAgPC9kaXY+CiAgPC9kaXY+CgogIDwhLS0gPT09PT09PT09PT09IFBMQVlFUiBQT1BVUCA9PT09PT09PT09PT0gLS0+CiAgPGRpdiBpZD0icG9wdXBPdmVybGF5Ij4KICAgIDxkaXYgaWQ9InBvcHVwQ2FyZCI+CiAgICAgIDxkaXYgY2xhc3M9InBvcHVwLWNsb3NlLXJvdyI+CiAgICAgICAgPGJ1dHRvbiBjbGFzcz0icG9wdXAtY2xvc2UtYnRuIiBvbmNsaWNrPSJhY3QoJ3BvcHVwQ2xvc2UnKSI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLXhtYXJrIj48L2k+PC9idXR0b24+CiAgICAgIDwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJwb3B1cC1pbmZvIj4KICAgICAgICA8ZGl2IGNsYXNzPSJwb3B1cC1pbmZvLXRvcCI+CiAgICAgICAgICA8c3BhbiBjbGFzcz0icG9wdXAtaW5mby1uYW1lIiBpZD0icG9wTmFtZSI+LTwvc3Bhbj4KICAgICAgICAgIDxzcGFuIGNsYXNzPSJwb3B1cC1pbmZvLW9ubGluZSI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLWNpcmNsZSIgc3R5bGU9ImZvbnQtc2l6ZTo3cHg7Ij48L2k+IE9ubGluZTwvc3Bhbj4KICAgICAgICA8L2Rpdj4KICAgICAgICA8ZGl2IGNsYXNzPSJwb3B1cC1pbmZvLXN0YXRzIj4KICAgICAgICAgIDxzcGFuIHN0eWxlPSJjb2xvcjp2YXIoLS1jeWFuKTsiPklEOiA8c3BhbiBpZD0icG9wSWQiPi08L3NwYW4+PC9zcGFuPgogICAgICAgICAgPHNwYW4gc3R5bGU9ImNvbG9yOnZhcigtLXN1Y2Nlc3MpOyI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLWhlYXJ0Ij48L2k+IDxzcGFuIGlkPSJwb3BIcCI+LTwvc3Bhbj48L3NwYW4+CiAgICAgICAgICA8c3BhbiBzdHlsZT0iY29sb3I6Izk5NjZlNjsiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1zaGllbGQiPjwvaT4gPHNwYW4gaWQ9InBvcEFybW91ciI+LTwvc3Bhbj48L3NwYW4+CiAgICAgICAgICA8c3BhbiBzdHlsZT0iY29sb3I6dmFyKC0td2FybmluZyk7Ij48aSBjbGFzcz0iZmEtc29saWQgZmEtc2lnbmFsIj48L2k+IDxzcGFuIGlkPSJwb3BQaW5nIj4tPC9zcGFuPm1zPC9zcGFuPgogICAgICAgIDwvZGl2PgogICAgICA8L2Rpdj4KCiAgICAgIDxkaXYgY2xhc3M9InBvcHVwLXNlY3Rpb24tbGFiZWwiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1nYXZlbCI+PC9pPiBQdW5pc2g8L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0icHVuaXNoLXJvdyI+CiAgICAgICAgPGJ1dHRvbiBjbGFzcz0iYnRuIiBzdHlsZT0iYmFja2dyb3VuZDp2YXIoLS13YXJuaW5nKTtjb2xvcjojMjQxYzA0OyIgb25jbGljaz0icG9wdXBGb3JtKCd3YXJuJykiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS10cmlhbmdsZS1leGNsYW1hdGlvbiI+PC9pPiBXYXJuPC9idXR0b24+CiAgICAgICAgPGJ1dHRvbiBjbGFzcz0iYnRuIiBzdHlsZT0iYmFja2dyb3VuZDojZTY4YTRkO2NvbG9yOiMyNDFjMDQ7IiBvbmNsaWNrPSJwb3B1cEZvcm0oJ2tpY2snKSI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLWNpcmNsZS14bWFyayI+PC9pPiBLaWNrPC9idXR0b24+CiAgICAgICAgPGJ1dHRvbiBjbGFzcz0iYnRuIGJ0bi1kYW5nZXIiIG9uY2xpY2s9InBvcHVwRm9ybSgnYmFuJykiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1iYW4iPjwvaT4gQmFuPC9idXR0b24+CiAgICAgIDwvZGl2PgoKICAgICAgPGRpdiBjbGFzcz0icG9wdXAtc2VjdGlvbi1sYWJlbCI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLWJvbHQiPjwvaT4gQWN0aW9uczwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJhY3Rpb24tZ3JpZCI+CiAgICAgICAgPGJ1dHRvbiBjbGFzcz0iYnRuIiBzdHlsZT0iYmFja2dyb3VuZDojNjY5OWNjOyIgb25jbGljaz0icG9wdXBGb3JtKCdkbScpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtZW52ZWxvcGUiPjwvaT4gRE08L2J1dHRvbj4KICAgICAgICA8YnV0dG9uIGNsYXNzPSJidG4iIHN0eWxlPSJiYWNrZ3JvdW5kOiM0ZGNjODU7Y29sb3I6IzA0MjEwZjsiIG9uY2xpY2s9ImFjdCgncG9wdXBIZWFsJykiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1oZWFydCI+PC9pPiBIZWFsPC9idXR0b24+CiAgICAgICAgPGJ1dHRvbiBjbGFzcz0iYnRuIiBzdHlsZT0iYmFja2dyb3VuZDojNGQ5OWNjOyIgb25jbGljaz0iYWN0KCdwb3B1cEdvdG8nKSI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLWxvY2F0aW9uLWRvdCI+PC9pPiBHbyB0bzwvYnV0dG9uPgogICAgICAgIDxidXR0b24gY2xhc3M9ImJ0biIgc3R5bGU9ImJhY2tncm91bmQ6IzgwODBjYzsiIG9uY2xpY2s9ImFjdCgncG9wdXBCcmluZycpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtbG9jYXRpb24tYXJyb3ciPjwvaT4gQnJpbmc8L2J1dHRvbj4KICAgICAgICA8YnV0dG9uIGNsYXNzPSJidG4iIHN0eWxlPSJiYWNrZ3JvdW5kOiM5OTY2Y2M7IiBvbmNsaWNrPSJhY3QoJ3BvcHVwU3BlYycpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtZXllIj48L2k+IFNwZWN0YXRlPC9idXR0b24+CiAgICAgICAgPGJ1dHRvbiBjbGFzcz0iYnRuIiBzdHlsZT0iYmFja2dyb3VuZDojNjZiM2U2OyIgb25jbGljaz0iYWN0KCdwb3B1cEZyZWV6ZScpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtc25vd2ZsYWtlIj48L2k+IEZyZWV6ZTwvYnV0dG9uPgogICAgICAgIDxidXR0b24gY2xhc3M9ImJ0biIgc3R5bGU9ImJhY2tncm91bmQ6I2IzNjZlNjsiIG9uY2xpY2s9InBvcHVwRm9ybSgnbXV0ZScpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtY29tbWVudC1zbGFzaCI+PC9pPiBNdXRlPC9idXR0b24+CiAgICAgICAgPGJ1dHRvbiBjbGFzcz0iYnRuIiBzdHlsZT0iYmFja2dyb3VuZDojODA4MDk5OyIgb25jbGljaz0icG9wdXBGb3JtKCdqYWlsJykiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1sb2NrIj48L2k+IEphaWw8L2J1dHRvbj4KICAgICAgICA8YnV0dG9uIGNsYXNzPSJidG4iIHN0eWxlPSJiYWNrZ3JvdW5kOiM4MDY2NTI7IiBvbmNsaWNrPSJhY3QoJ3BvcHVwU2xhcCcpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtaGFuZCI+PC9pPiBTbGFwPC9idXR0b24+CiAgICAgIDwvZGl2PgoKICAgICAgPGRpdiBpZD0icG9wdXBGb3JtIj4KICAgICAgICA8ZGl2IGNsYXNzPSJlbXB0eS1zZWxlY3QiIGlkPSJwb3B1cEZvcm1FbXB0eSI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLWhhbmQtcG9pbnRlciI+PC9pPiBTZWxlY3QgYW4gYWN0aW9uIGFib3ZlPC9kaXY+CiAgICAgICAgPGRpdiBpZD0icG9wdXBGb3JtQWN0aXZlIiBzdHlsZT0iZGlzcGxheTpub25lOyI+PC9kaXY+CiAgICAgIDwvZGl2PgogICAgPC9kaXY+CiAgPC9kaXY+Cgo8L2Rpdj4KCjxzY3JpcHQ+CiAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09CiAgLy8gU1RBVEUKICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0KICB2YXIgY3VycmVudFBvcHVwQWN0aW9uID0gIm5vbmUiOwogIHZhciBjdXJyZW50UGxheWVyID0gbnVsbDsKCiAgZnVuY3Rpb24gYWN0KGNtZCkgeyBjb25zb2xlLmxvZygiYWN0aW9uOiIgKyBjbWQpOyB9CiAgZnVuY3Rpb24gYWN0QXJnKGNtZCwgYXJncykgeyBjb25zb2xlLmxvZygiYWN0aW9uOiIgKyBjbWQgKyAifCIgKyBhcmdzLmpvaW4oInwiKSk7IH0KCiAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09CiAgLy8gRFJBRyAoZHVhIGhhbmRsZTogbG9naW4gc2NyZWVuIGljb24gJiBtYWluIGhlYWRlcikg4oCUIG11cm5pIENTUy9KUwogIC8vID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQogIChmdW5jdGlvbiAoKSB7CiAgICB2YXIgYXBwRWwgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnYXBwJyk7CiAgICB2YXIgaGFuZGxlcyA9IFtkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbG9naW5EcmFnSGFuZGxlJyksIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdtYWluRHJhZ0hhbmRsZScpXTsKICAgIHZhciBkcmFnRW5hYmxlZCA9IHRydWU7CiAgICB2YXIgZHJhZ2dpbmcgPSBmYWxzZSwgb2ZmWCA9IDAsIG9mZlkgPSAwOwoKICAgIHdpbmRvdy5zZXRMb2NrZWQgPSBmdW5jdGlvbiAobG9ja2VkKSB7IGRyYWdFbmFibGVkID0gIWxvY2tlZDsgfTsKICAgIHdpbmRvdy5zZXRQb3NpdGlvbiA9IGZ1bmN0aW9uICh4LCB5KSB7IGFwcEVsLnN0eWxlLmxlZnQgPSB4ICsgInB4IjsgYXBwRWwuc3R5bGUudG9wID0geSArICJweCI7IH07CgogICAgaGFuZGxlcy5mb3JFYWNoKGZ1bmN0aW9uIChoKSB7CiAgICAgIGguYWRkRXZlbnRMaXN0ZW5lcigncG9pbnRlcmRvd24nLCBmdW5jdGlvbiAoZSkgewogICAgICAgIGlmICghZHJhZ0VuYWJsZWQpIHJldHVybjsKICAgICAgICBkcmFnZ2luZyA9IHRydWU7CiAgICAgICAgb2ZmWCA9IGUuY2xpZW50WCAtIGFwcEVsLm9mZnNldExlZnQ7CiAgICAgICAgb2ZmWSA9IGUuY2xpZW50WSAtIGFwcEVsLm9mZnNldFRvcDsKICAgICAgICBoLnNldFBvaW50ZXJDYXB0dXJlKGUucG9pbnRlcklkKTsKICAgICAgfSk7CiAgICAgIGguYWRkRXZlbnRMaXN0ZW5lcigncG9pbnRlcm1vdmUnLCBmdW5jdGlvbiAoZSkgewogICAgICAgIGlmICghZHJhZ2dpbmcpIHJldHVybjsKICAgICAgICB2YXIgeCA9IE1hdGgubWF4KDAsIE1hdGgubWluKGUuY2xpZW50WCAtIG9mZlgsIHdpbmRvdy5pbm5lcldpZHRoIC0gYXBwRWwub2Zmc2V0V2lkdGgpKTsKICAgICAgICB2YXIgeSA9IE1hdGgubWF4KDAsIE1hdGgubWluKGUuY2xpZW50WSAtIG9mZlksIHdpbmRvdy5pbm5lckhlaWdodCAtIGFwcEVsLm9mZnNldEhlaWdodCkpOwogICAgICAgIGFwcEVsLnN0eWxlLmxlZnQgPSB4ICsgInB4IjsgYXBwRWwuc3R5bGUudG9wID0geSArICJweCI7CiAgICAgIH0pOwogICAgICBoLmFkZEV2ZW50TGlzdGVuZXIoJ3BvaW50ZXJ1cCcsIGZ1bmN0aW9uICgpIHsKICAgICAgICBpZiAoZHJhZ2dpbmcpIHsgZHJhZ2dpbmcgPSBmYWxzZTsgY29uc29sZS5sb2coImFjdGlvbjpwb3NTYXZlfCIgKyBhcHBFbC5vZmZzZXRMZWZ0ICsgInwiICsgYXBwRWwub2Zmc2V0VG9wKTsgfQogICAgICB9KTsKICAgICAgaC5hZGRFdmVudExpc3RlbmVyKCdwb2ludGVyY2FuY2VsJywgZnVuY3Rpb24gKCkgeyBkcmFnZ2luZyA9IGZhbHNlOyB9KTsKICAgIH0pOwogIH0pKCk7CgogIGZ1bmN0aW9uIHNob3dBcHAodikgeyBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnYXBwJykuY2xhc3NOYW1lID0gdiA/ICdzaG93JyA6ICcnOyB9CgogIC8vID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQogIC8vIExPR0lOCiAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09CiAgZnVuY3Rpb24gZG9Mb2dpbigpIHsKICAgIHZhciB1ID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xvZ2luVXNlcicpLnZhbHVlLnRyaW0oKTsKICAgIHZhciBwID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xvZ2luUGFzcycpLnZhbHVlLnRyaW0oKTsKICAgIGFjdEFyZygnbG9naW4nLCBbdSwgcF0pOwogIH0KCiAgZnVuY3Rpb24gbG9naW5TaG93RXJyb3IobXNnKSB7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbG9naW5FcnJvclRleHQnKS50ZXh0Q29udGVudCA9IG1zZzsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdsb2dpbkVycm9yJykuY2xhc3NOYW1lID0gJ2xvZ2luLWVycm9yIHNob3cnOwogICAgdmFyIHNjciA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdsb2dpblNjcmVlbicpOwogICAgc2NyLmNsYXNzTGlzdC5yZW1vdmUoJ3NoYWtlJyk7IHZvaWQgc2NyLm9mZnNldFdpZHRoOyBzY3IuY2xhc3NMaXN0LmFkZCgnc2hha2UnKTsKICB9CgogIGZ1bmN0aW9uIGxvZ2luU2V0TG9hZGluZyh2KSB7CiAgICB2YXIgYnRuID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xvZ2luQnRuJyk7CiAgICBidG4uaW5uZXJIVE1MID0gdgogICAgICA/ICc8aSBjbGFzcz0iZmEtc29saWQgZmEtc3Bpbm5lciBmYS1zcGluIj48L2k+IExPR0dJTkcgSU4uLi4nCiAgICAgIDogJzxpIGNsYXNzPSJmYS1zb2xpZCBmYS1yaWdodC10by1icmFja2V0Ij48L2k+IExPR0lOJzsKICB9CgogIC8vIGRpcGFuZ2dpbCBMdWEgYmVnaXR1IGxvZ2luIGRpdGVyaW1hIC0+IHRhbXBpbGluIGxvYWRpbmcgc2NyZWVuIGxhbHUgbWFpbgogIGZ1bmN0aW9uIGxvZ2luU3VjY2VzcygpIHsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdsb2dpblNjcmVlbicpLnN0eWxlLmRpc3BsYXkgPSAnbm9uZSc7CiAgICB2YXIgbGQgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbG9hZGluZ1NjcmVlbicpOwogICAgbGQuY2xhc3NOYW1lID0gJ3Nob3cnOwogICAgdmFyIGJhciA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdsb2FkaW5nQmFyJyk7CiAgICB2YXIgdHh0ID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xvYWRpbmdUZXh0Jyk7CiAgICB2YXIgc3RlcHMgPSBbCiAgICAgIFsxNSwgIkF1dGhlbnRpY2F0aW5nLi4uIl0sCiAgICAgIFs0NSwgIkxvYWRpbmcgYWRtaW4gZGF0YS4uLiJdLAogICAgICBbNzUsICJTeW5jaW5nIHBsYXllciBsaXN0Li4uIl0sCiAgICAgIFsxMDAsICJSZWFkeSJdCiAgICBdOwogICAgdmFyIGkgPSAwOwogICAgZnVuY3Rpb24gbmV4dCgpIHsKICAgICAgaWYgKGkgPj0gc3RlcHMubGVuZ3RoKSB7CiAgICAgICAgc2V0VGltZW91dChmdW5jdGlvbiAoKSB7CiAgICAgICAgICBsZC5jbGFzc05hbWUgPSAnJzsKICAgICAgICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdtYWluU2NyZWVuJykuY2xhc3NOYW1lID0gJ3Nob3cnOwogICAgICAgIH0sIDIwMCk7CiAgICAgICAgcmV0dXJuOwogICAgICB9CiAgICAgIGJhci5zdHlsZS53aWR0aCA9IHN0ZXBzW2ldWzBdICsgIiUiOwogICAgICB0eHQudGV4dENvbnRlbnQgPSBzdGVwc1tpXVsxXTsKICAgICAgaSsrOwogICAgICBzZXRUaW1lb3V0KG5leHQsIDIyMCk7CiAgICB9CiAgICBuZXh0KCk7CiAgfQoKICBmdW5jdGlvbiBkb0xvZ291dCgpIHsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdtYWluU2NyZWVuJykuY2xhc3NOYW1lID0gJyc7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbG9naW5TY3JlZW4nKS5zdHlsZS5kaXNwbGF5ID0gJyc7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbG9naW5Vc2VyJykudmFsdWUgPSAnJzsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdsb2dpblBhc3MnKS52YWx1ZSA9ICcnOwogICAgbG9naW5TZXRMb2FkaW5nKGZhbHNlKTsKICB9CgogIC8vID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQogIC8vIFRBQlMKICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0KICBmdW5jdGlvbiBzd2l0Y2hUYWIobikgewogICAgZm9yICh2YXIgaSA9IDE7IGkgPD0gMzsgaSsrKSB7CiAgICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCd0YWJCdG4nICsgaSkuY2xhc3NOYW1lID0gJ3RhYi1idG4nICsgKGkgPT09IG4gPyAnIGFjdGl2ZScgOiAnJyk7CiAgICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdwYW5lJyArIGkpLmNsYXNzTmFtZSA9ICd0YWItcGFuZScgKyAoaSA9PT0gbiA/ICcgYWN0aXZlJyA6ICcnKTsKICAgIH0KICAgIGFjdCgndGFiU3dpdGNofCcgKyBuKTsKICB9CgogIC8vID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQogIC8vIFNFQ1RJT05TIChtYWluIHRhYikKICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0KICB2YXIgb3BlblNlY3Rpb24gPSBudWxsOwogIGZ1bmN0aW9uIHRvZ2dsZVNlY3Rpb24obmFtZSkgewogICAgdmFyIG5ld09wZW4gPSAob3BlblNlY3Rpb24gPT09IG5hbWUpID8gbnVsbCA6IG5hbWU7CiAgICBbJ3BsYXllck1vZGUnLCAndGVsZXBvcnQnLCAndmVoaWNsZScsICdoZWFsJywgJ3dvcmxkJ10uZm9yRWFjaChmdW5jdGlvbiAocykgewogICAgICB2YXIgYm9keSA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdib2R5LScgKyBzKTsKICAgICAgdmFyIGNoZXYgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnY2hldi0nICsgcykuZmlyc3RFbGVtZW50Q2hpbGQ7CiAgICAgIHZhciBpc09wZW4gPSAocyA9PT0gbmV3T3Blbik7CiAgICAgIGJvZHkuY2xhc3NOYW1lID0gJ3NlY3Rpb24tYm9keScgKyAoaXNPcGVuID8gJyBvcGVuJyA6ICcnKTsKICAgICAgY2hldi5jbGFzc05hbWUgPSAnZmEtc29saWQgJyArIChpc09wZW4gPyAnZmEtY2hldnJvbi1kb3duJyA6ICdmYS1jaGV2cm9uLXJpZ2h0Jyk7CiAgICB9KTsKICAgIG9wZW5TZWN0aW9uID0gbmV3T3BlbjsKICB9CgogIGZ1bmN0aW9uIHNldER1dHlTdGF0ZShvbikgewogICAgdmFyIGJhZGdlID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2R1dHlCYWRnZScpOwogICAgYmFkZ2UudGV4dENvbnRlbnQgPSBvbiA/ICdPbiBEdXR5JyA6ICdPZmYgRHV0eSc7CiAgICBiYWRnZS5jbGFzc05hbWUgPSAnc2VjdGlvbi1iYWRnZSAnICsgKG9uID8gJ29uJyA6ICdvZmYnKTsKICAgIHZhciBidG4gPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnZHV0eUJ0bicpOwogICAgYnRuLnRleHRDb250ZW50ID0gb24gPyAnR28gT2ZmIER1dHknIDogJ0dvIE9uIER1dHknOwogICAgYnRuLmNsYXNzTmFtZSA9ICdidG4gJyArIChvbiA/ICdidG4tc3VjY2VzcycgOiAnYnRuLWRhbmdlcicpOwogIH0KCiAgZnVuY3Rpb24gdGVsZXBvcnRHbygpIHsKICAgIHZhciBpZCA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCd0cElkJykudmFsdWUudHJpbSgpOwogICAgdmFyIGRlc3QgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgndHBEZXN0JykudmFsdWUudHJpbSgpOwogICAgaWYgKGlkICYmIGRlc3QpIGFjdEFyZygndGVsZXBvcnQnLCBbaWQsIGRlc3RdKTsKICB9CiAgZnVuY3Rpb24gdmVoaWNsZUdvKCkgewogICAgdmFyIG0gPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgndmVoTW9kZWwnKS52YWx1ZS50cmltKCk7CiAgICBpZiAobSkgYWN0QXJnKCd2ZWhpY2xlU3Bhd24nLCBbbV0pOwogIH0KICBmdW5jdGlvbiBoZWFsR28oKSB7CiAgICB2YXIgaWQgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnaGVhbElkJykudmFsdWUudHJpbSgpOwogICAgdmFyIGFtdCA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdoZWFsQW10JykudmFsdWUudHJpbSgpOwogICAgaWYgKGlkICYmIGFtdCkgYWN0QXJnKCdoZWFsU2V0JywgW2lkLCBhbXRdKTsKICB9CgogIGZ1bmN0aW9uIHdvcmxkTmFtZXNUb2dnbGUoKSB7CiAgICB2YXIgb24gPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbmFtZXNPbicpLmNoZWNrZWQ7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbmFtZVNpemVSb3cnKS5zdHlsZS5kaXNwbGF5ID0gb24gPyAnZmxleCcgOiAnbm9uZSc7CiAgICBhY3RBcmcoJ3dvcmxkTmFtZXNUb2dnbGUnLCBbb25dKTsKICB9CiAgZnVuY3Rpb24gd29ybGROYW1lU2l6ZSgpIHsKICAgIHZhciB2ID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ25hbWVTaXplJykudmFsdWU7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbmFtZVNpemVWYWwnKS50ZXh0Q29udGVudCA9IHY7CiAgICBhY3RBcmcoJ3dvcmxkTmFtZVNpemUnLCBbdl0pOwogIH0KICBmdW5jdGlvbiB3b3JsZExpbmVzVG9nZ2xlKCkgewogICAgdmFyIG9uID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xpbmVzT24nKS5jaGVja2VkOwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xpbmVPcHRSb3cnKS5zdHlsZS5kaXNwbGF5ID0gb24gPyAnZmxleCcgOiAnbm9uZSc7CiAgICBhY3RBcmcoJ3dvcmxkTGluZXNUb2dnbGUnLCBbb25dKTsKICB9CiAgZnVuY3Rpb24gd29ybGRMaW5lQ29sb3IoKSB7CiAgICB2YXIgaGV4ID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xpbmVDb2xvcicpLnZhbHVlOwogICAgdmFyIHIgPSBwYXJzZUludChoZXguc3Vic3RyKDEsMiksMTYpLCBnID0gcGFyc2VJbnQoaGV4LnN1YnN0cigzLDIpLDE2KSwgYiA9IHBhcnNlSW50KGhleC5zdWJzdHIoNSwyKSwxNik7CiAgICBhY3RBcmcoJ3dvcmxkTGluZUNvbG9yJywgW3IsIGcsIGJdKTsKICB9CiAgZnVuY3Rpb24gd29ybGRMaW5lVGhpY2tuZXNzKCkgewogICAgYWN0QXJnKCd3b3JsZExpbmVUaGlja25lc3MnLCBbZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xpbmVXaWR0aCcpLnZhbHVlXSk7CiAgfQoKICAvLyBkaXBhbmdnaWwgZGFyaSBMdWEgYnVhdCBzaW5rcm9uaW4gdWxhbmcgc3RhdGUgd29ybGQgKG1pc2FsIGFiaXMgcmVsb2FkKQogIGZ1bmN0aW9uIHNldFdvcmxkU3RhdGUobmFtZXNPbiwgbmFtZVNpemUsIGxpbmVzT24sIGxpbmVDb2xvckhleCwgbGluZVdpZHRoKSB7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbmFtZXNPbicpLmNoZWNrZWQgPSBuYW1lc09uOwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ25hbWVTaXplUm93Jykuc3R5bGUuZGlzcGxheSA9IG5hbWVzT24gPyAnZmxleCcgOiAnbm9uZSc7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbmFtZVNpemUnKS52YWx1ZSA9IG5hbWVTaXplOwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ25hbWVTaXplVmFsJykudGV4dENvbnRlbnQgPSBuYW1lU2l6ZTsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdsaW5lc09uJykuY2hlY2tlZCA9IGxpbmVzT247CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbGluZU9wdFJvdycpLnN0eWxlLmRpc3BsYXkgPSBsaW5lc09uID8gJ2ZsZXgnIDogJ25vbmUnOwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xpbmVDb2xvcicpLnZhbHVlID0gbGluZUNvbG9ySGV4OwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xpbmVXaWR0aCcpLnZhbHVlID0gbGluZVdpZHRoOwogIH0KCiAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09CiAgLy8gUExBWUVSUyBUQUIKICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0KICB2YXIgY3VycmVudFNvcnRUeXBlID0gJ2lkJzsKICBmdW5jdGlvbiBwbGF5ZXJzU2VhcmNoKCkgeyBhY3RBcmcoJ3BsYXllcnNTZWFyY2gnLCBbZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3BsYXllclNlYXJjaCcpLnZhbHVlLnRyaW0oKV0pOyB9CiAgZnVuY3Rpb24gcGxheWVyc1NjYW4oKSB7IGFjdEFyZygncGxheWVyc1NjYW4nLCBbZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3NjYW5SYWRpdXMnKS52YWx1ZS50cmltKCldKTsgfQogIGZ1bmN0aW9uIHBsYXllcnNTb3J0KHR5cGUpIHsKICAgIGN1cnJlbnRTb3J0VHlwZSA9IHR5cGU7CiAgICBbJ0lkJywnRGlzdCcsJ1BpbmcnXS5mb3JFYWNoKGZ1bmN0aW9uKHMpeyBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnc29ydCcrcykuY2xhc3NOYW1lID0gJ2J0biBzb3J0LWJ0bic7IH0pOwogICAgdmFyIG1hcCA9IHtpZDonc29ydElkJywgZGlzdGFuY2U6J3NvcnREaXN0JywgcGluZzonc29ydFBpbmcnfTsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKG1hcFt0eXBlXSkuY2xhc3NOYW1lID0gJ2J0biBzb3J0LWJ0biBhY3RpdmUnOwogICAgYWN0QXJnKCdwbGF5ZXJzU29ydCcsIFt0eXBlXSk7CiAgfQoKICBmdW5jdGlvbiBwaW5nQ2xhc3MocCkgeyByZXR1cm4gcCA8PSAxMDAgPyAncGluZy1nJyA6IChwIDw9IDIwMCA/ICdwaW5nLXknIDogJ3BpbmctcicpOyB9CgogIC8vIGRpcGFuZ2dpbCBMdWEgdGlhcCBhZGEgdXBkYXRlIGxpc3QgcGxheWVyOiB1cGRhdGVQbGF5ZXJzKFt7aWQsbmFtZSxwaW5nLGRpc3RhbmNlLGhlYWx0aCxhcm1vdXIsaXNTZWxmfSwgLi4uXSkKICBmdW5jdGlvbiB1cGRhdGVQbGF5ZXJzKGxpc3QpIHsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdwbGF5ZXJDb3VudFR4dCcpLnRleHRDb250ZW50ID0gbGlzdC5sZW5ndGg7CiAgICB2YXIgZWwgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgncGxheWVyTGlzdCcpOwogICAgaWYgKGxpc3QubGVuZ3RoID09PSAwKSB7CiAgICAgIGVsLmlubmVySFRNTCA9ICc8ZGl2IGNsYXNzPSJlbXB0eS1oaW50Ij5ObyBwbGF5ZXJzIGZvdW5kLiBDbGljayByZWZyZXNoIHRvIGxvYWQuPC9kaXY+JzsKICAgICAgcmV0dXJuOwogICAgfQogICAgdmFyIGh0bWwgPSAnJzsKICAgIGZvciAodmFyIGkgPSAwOyBpIDwgbGlzdC5sZW5ndGg7IGkrKykgewogICAgICB2YXIgcCA9IGxpc3RbaV07CiAgICAgIHZhciBkaXN0ID0gKHAuZGlzdGFuY2UgIT0gbnVsbCAmJiBwLmRpc3RhbmNlIDwgOTk5OSkgPyBwLmRpc3RhbmNlIDogJy0nOwogICAgICBodG1sICs9ICc8ZGl2IGNsYXNzPSJwbGF5ZXItcm93Ij4nCiAgICAgICAgKyAnPHNwYW4gY2xhc3M9InBpZCI+JyArIHAuaWQgKyAnPC9zcGFuPicKICAgICAgICArICc8c3BhbiBjbGFzcz0icG5hbWUnICsgKHAuaXNTZWxmID8gJyBzZWxmJyA6ICcnKSArICciPicgKyBlc2NhcGVIdG1sKHAubmFtZSkgKyAocC5pc1NlbGYgPyAnIChZb3UpJyA6ICcnKSArICc8L3NwYW4+JwogICAgICAgICsgJzxzcGFuIGNsYXNzPSInICsgcGluZ0NsYXNzKHAucGluZyB8fCAwKSArICciPicgKyAocC5waW5nIHx8IDApICsgJzwvc3Bhbj4nCiAgICAgICAgKyAnPHNwYW4+JyArIGRpc3QgKyAnPC9zcGFuPicKICAgICAgICArICc8c3Bhbj4nICsgKHAuaGVhbHRoIHx8IDApICsgJzwvc3Bhbj4nCiAgICAgICAgKyAnPHNwYW4+PGJ1dHRvbiBjbGFzcz0idmlldy1idG4iIG9uY2xpY2s9XCd2aWV3UGxheWVyKCcgKyBwLmlkICsgJylcJz48aSBjbGFzcz0iZmEtc29saWQgZmEtZXllIj48L2k+PC9idXR0b24+PC9zcGFuPicKICAgICAgICArICc8L2Rpdj4nOwogICAgfQogICAgZWwuaW5uZXJIVE1MID0gaHRtbDsKICB9CgogIGZ1bmN0aW9uIHZpZXdQbGF5ZXIoaWQpIHsgYWN0KCdwbGF5ZXJWaWV3fCcgKyBpZCk7IH0KICBmdW5jdGlvbiBlc2NhcGVIdG1sKHMpIHsgcmV0dXJuIFN0cmluZyhzKS5yZXBsYWNlKC9bJjw+IiddL2csIGZ1bmN0aW9uKGMpeyByZXR1cm4geycmJzonJmFtcDsnLCc8JzonJmx0OycsJz4nOicmZ3Q7JywnIic6JyZxdW90OycsIiciOicmIzM5Oyd9W2NdOyB9KTsgfQoKICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0KICAvLyBQTEFZRVIgUE9QVVAKICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0KICBmdW5jdGlvbiBvcGVuUGxheWVyUG9wdXAocCkgewogICAgY3VycmVudFBsYXllciA9IHA7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgncG9wTmFtZScpLnRleHRDb250ZW50ID0gcC5uYW1lOwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3BvcElkJykudGV4dENvbnRlbnQgPSBwLmlkOwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3BvcEhwJykudGV4dENvbnRlbnQgPSBwLmhlYWx0aCB8fCAwOwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3BvcEFybW91cicpLnRleHRDb250ZW50ID0gcC5hcm1vdXIgfHwgMDsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdwb3BQaW5nJykudGV4dENvbnRlbnQgPSBwLnBpbmcgfHwgMDsKICAgIHBvcHVwRm9ybSgnbm9uZScpOwogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3BvcHVwT3ZlcmxheScpLmNsYXNzTmFtZSA9ICdzaG93JzsKICB9CiAgZnVuY3Rpb24gY2xvc2VQbGF5ZXJQb3B1cCgpIHsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdwb3B1cE92ZXJsYXknKS5jbGFzc05hbWUgPSAnJzsKICAgIGN1cnJlbnRQbGF5ZXIgPSBudWxsOwogIH0KCiAgZnVuY3Rpb24gcG9wdXBGb3JtKHR5cGUpIHsKICAgIGN1cnJlbnRQb3B1cEFjdGlvbiA9IHR5cGU7CiAgICB2YXIgZW1wdHkgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgncG9wdXBGb3JtRW1wdHknKTsKICAgIHZhciBhY3RpdmUgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgncG9wdXBGb3JtQWN0aXZlJyk7CiAgICBpZiAodHlwZSA9PT0gJ25vbmUnKSB7IGVtcHR5LnN0eWxlLmRpc3BsYXkgPSAnYmxvY2snOyBhY3RpdmUuc3R5bGUuZGlzcGxheSA9ICdub25lJzsgcmV0dXJuOyB9CiAgICBlbXB0eS5zdHlsZS5kaXNwbGF5ID0gJ25vbmUnOyBhY3RpdmUuc3R5bGUuZGlzcGxheSA9ICdibG9jayc7CgogICAgdmFyIGZvcm1zID0gewogICAgICBiYW46ICc8ZGl2IGNsYXNzPSJwb3B1cC1zZWN0aW9uLWxhYmVsIiBzdHlsZT0iY29sb3I6dmFyKC0tZGFuZ2VyKTsiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1iYW4iPjwvaT4gQmFuIFBsYXllcjwvZGl2PicKICAgICAgICArICc8ZGl2IGNsYXNzPSJmb3JtLXJvdyI+PHNwYW4gY2xhc3M9ImxibC1pbmxpbmUiPkRheXM6PC9zcGFuPjxpbnB1dCBjbGFzcz0iaW5wdXQtc20iIGlkPSJmRGF5cyIgc3R5bGU9IndpZHRoOjUwcHg7IiBwbGFjZWhvbGRlcj0iMC0zMCI+JwogICAgICAgICsgJzxzcGFuIGNsYXNzPSJsYmwtaW5saW5lIj5SZWFzb246PC9zcGFuPjxpbnB1dCBjbGFzcz0iaW5wdXQtc20iIGlkPSJmUmVhc29uIj48L2Rpdj4nCiAgICAgICAgKyAnPGJ1dHRvbiBjbGFzcz0iYnRuIGJ0bi1kYW5nZXIiIG9uY2xpY2s9InBvcHVwQ29uZmlybUJhbigpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtY2hlY2siPjwvaT4gQ29uZmlybTwvYnV0dG9uPicsCiAgICAgIGtpY2s6ICc8ZGl2IGNsYXNzPSJwb3B1cC1zZWN0aW9uLWxhYmVsIiBzdHlsZT0iY29sb3I6I2U2OGE0ZDsiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1jaXJjbGUteG1hcmsiPjwvaT4gS2ljayBQbGF5ZXI8L2Rpdj4nCiAgICAgICAgKyAnPGRpdiBjbGFzcz0iZm9ybS1yb3ciPjxzcGFuIGNsYXNzPSJsYmwtaW5saW5lIj5SZWFzb246PC9zcGFuPjxpbnB1dCBjbGFzcz0iaW5wdXQtc20iIGlkPSJmUmVhc29uIj48L2Rpdj4nCiAgICAgICAgKyAnPGJ1dHRvbiBjbGFzcz0iYnRuIiBzdHlsZT0iYmFja2dyb3VuZDojZTY4YTRkO2NvbG9yOiMyNDFjMDQ7IiBvbmNsaWNrPSJwb3B1cENvbmZpcm1LaWNrKCkiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1jaGVjayI+PC9pPiBDb25maXJtPC9idXR0b24+JywKICAgICAgd2FybjogJzxkaXYgY2xhc3M9InBvcHVwLXNlY3Rpb24tbGFiZWwiIHN0eWxlPSJjb2xvcjp2YXIoLS13YXJuaW5nKTsiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS10cmlhbmdsZS1leGNsYW1hdGlvbiI+PC9pPiBXYXJuIFBsYXllcjwvZGl2PicKICAgICAgICArICc8ZGl2IGNsYXNzPSJmb3JtLXJvdyI+PHNwYW4gY2xhc3M9ImxibC1pbmxpbmUiPlJlYXNvbjo8L3NwYW4+PGlucHV0IGNsYXNzPSJpbnB1dC1zbSIgaWQ9ImZSZWFzb24iPjwvZGl2PicKICAgICAgICArICc8YnV0dG9uIGNsYXNzPSJidG4iIHN0eWxlPSJiYWNrZ3JvdW5kOnZhcigtLXdhcm5pbmcpO2NvbG9yOiMyNDFjMDQ7IiBvbmNsaWNrPSJwb3B1cENvbmZpcm1XYXJuKCkiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1jaGVjayI+PC9pPiBDb25maXJtPC9idXR0b24+JywKICAgICAgbXV0ZTogJzxkaXYgY2xhc3M9InBvcHVwLXNlY3Rpb24tbGFiZWwiIHN0eWxlPSJjb2xvcjojYjM2NmU2OyI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLWNvbW1lbnQtc2xhc2giPjwvaT4gTXV0ZSBQbGF5ZXI8L2Rpdj4nCiAgICAgICAgKyAnPGRpdiBjbGFzcz0iZm9ybS1yb3ciPjxzcGFuIGNsYXNzPSJsYmwtaW5saW5lIj5UaW1lOjwvc3Bhbj48aW5wdXQgY2xhc3M9ImlucHV0LXNtIiBpZD0iZlRpbWUiIHN0eWxlPSJ3aWR0aDo0NHB4OyIgcGxhY2Vob2xkZXI9Im1pbiI+JwogICAgICAgICsgJzxzcGFuIGNsYXNzPSJsYmwtaW5saW5lIj5SZWFzb246PC9zcGFuPjxpbnB1dCBjbGFzcz0iaW5wdXQtc20iIGlkPSJmUmVhc29uIj48L2Rpdj4nCiAgICAgICAgKyAnPGJ1dHRvbiBjbGFzcz0iYnRuIiBzdHlsZT0iYmFja2dyb3VuZDojYjM2NmU2OyIgb25jbGljaz0icG9wdXBDb25maXJtTXV0ZSgpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtY2hlY2siPjwvaT4gQ29uZmlybTwvYnV0dG9uPicsCiAgICAgIGphaWw6ICc8ZGl2IGNsYXNzPSJwb3B1cC1zZWN0aW9uLWxhYmVsIiBzdHlsZT0iY29sb3I6IzgwODA5OTsiPjxpIGNsYXNzPSJmYS1zb2xpZCBmYS1sb2NrIj48L2k+IEphaWwgUGxheWVyPC9kaXY+JwogICAgICAgICsgJzxkaXYgY2xhc3M9ImZvcm0tcm93Ij48c3BhbiBjbGFzcz0ibGJsLWlubGluZSI+VGltZTo8L3NwYW4+PGlucHV0IGNsYXNzPSJpbnB1dC1zbSIgaWQ9ImZUaW1lIiBzdHlsZT0id2lkdGg6NDRweDsiIHBsYWNlaG9sZGVyPSJtaW4iPicKICAgICAgICArICc8c3BhbiBjbGFzcz0ibGJsLWlubGluZSI+UmVhc29uOjwvc3Bhbj48aW5wdXQgY2xhc3M9ImlucHV0LXNtIiBpZD0iZlJlYXNvbiI+PC9kaXY+JwogICAgICAgICsgJzxidXR0b24gY2xhc3M9ImJ0biIgc3R5bGU9ImJhY2tncm91bmQ6IzgwODA5OTsiIG9uY2xpY2s9InBvcHVwQ29uZmlybUphaWwoKSI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLWNoZWNrIj48L2k+IENvbmZpcm08L2J1dHRvbj4nLAogICAgICBkbTogJzxkaXYgY2xhc3M9InBvcHVwLXNlY3Rpb24tbGFiZWwiIHN0eWxlPSJjb2xvcjojNjY5OWNjOyI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLWVudmVsb3BlIj48L2k+IERpcmVjdCBNZXNzYWdlPC9kaXY+JwogICAgICAgICsgJzxkaXYgY2xhc3M9ImZvcm0tcm93Ij48c3BhbiBjbGFzcz0ibGJsLWlubGluZSI+TWVzc2FnZTo8L3NwYW4+PGlucHV0IGNsYXNzPSJpbnB1dC1zbSIgaWQ9ImZSZWFzb24iIHBsYWNlaG9sZGVyPSJZb3VyIG1lc3NhZ2UuLi4iPjwvZGl2PicKICAgICAgICArICc8YnV0dG9uIGNsYXNzPSJidG4iIHN0eWxlPSJiYWNrZ3JvdW5kOiM2Njk5Y2M7IiBvbmNsaWNrPSJwb3B1cENvbmZpcm1EbSgpIj48aSBjbGFzcz0iZmEtc29saWQgZmEtcGFwZXItcGxhbmUiPjwvaT4gU2VuZDwvYnV0dG9uPicKICAgIH07CiAgICBhY3RpdmUuaW5uZXJIVE1MID0gKGZvcm1zW3R5cGVdIHx8ICcnKSArICcgPGJ1dHRvbiBjbGFzcz0iYnRuIiBvbmNsaWNrPSJwb3B1cEZvcm0oXCdub25lXCcpIiBzdHlsZT0ibWFyZ2luLWxlZnQ6NXB4OyI+PGkgY2xhc3M9ImZhLXNvbGlkIGZhLXhtYXJrIj48L2k+IENhbmNlbDwvYnV0dG9uPic7CiAgfQoKICBmdW5jdGlvbiBwb3B1cENvbmZpcm1CYW4oKSB7CiAgICB2YXIgZCA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdmRGF5cycpLnZhbHVlLnRyaW0oKSwgciA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdmUmVhc29uJykudmFsdWUudHJpbSgpOwogICAgaWYgKGQgJiYgcikgYWN0QXJnKCdwb3B1cENvbmZpcm0nLCBbJ2JhbicsIGQsIHJdKTsKICB9CiAgZnVuY3Rpb24gcG9wdXBDb25maXJtS2ljaygpIHsKICAgIHZhciByID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2ZSZWFzb24nKS52YWx1ZS50cmltKCk7CiAgICBpZiAocikgYWN0QXJnKCdwb3B1cENvbmZpcm0nLCBbJ2tpY2snLCByXSk7CiAgfQogIGZ1bmN0aW9uIHBvcHVwQ29uZmlybVdhcm4oKSB7CiAgICB2YXIgciA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdmUmVhc29uJykudmFsdWUudHJpbSgpOwogICAgaWYgKHIpIGFjdEFyZygncG9wdXBDb25maXJtJywgWyd3YXJuJywgcl0pOwogIH0KICBmdW5jdGlvbiBwb3B1cENvbmZpcm1NdXRlKCkgewogICAgdmFyIHQgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnZlRpbWUnKS52YWx1ZS50cmltKCksIHIgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnZlJlYXNvbicpLnZhbHVlLnRyaW0oKTsKICAgIGlmICh0ICYmIHIpIGFjdEFyZygncG9wdXBDb25maXJtJywgWydtdXRlJywgdCwgcl0pOwogIH0KICBmdW5jdGlvbiBwb3B1cENvbmZpcm1KYWlsKCkgewogICAgdmFyIHQgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnZlRpbWUnKS52YWx1ZS50cmltKCksIHIgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnZlJlYXNvbicpLnZhbHVlLnRyaW0oKTsKICAgIGlmICh0ICYmIHIpIGFjdEFyZygncG9wdXBDb25maXJtJywgWydqYWlsJywgdCwgcl0pOwogIH0KICBmdW5jdGlvbiBwb3B1cENvbmZpcm1EbSgpIHsKICAgIHZhciBtID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2ZSZWFzb24nKS52YWx1ZS50cmltKCk7CiAgICBpZiAobSkgYWN0QXJnKCdwb3B1cENvbmZpcm0nLCBbJ2RtJywgbV0pOwogIH0KCiAgLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09CiAgLy8gTE9HUyBUQUIKICAvLyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0KICBmdW5jdGlvbiBsb2dzU2VhcmNoKCkgeyBhY3RBcmcoJ2xvZ3NTZWFyY2gnLCBbZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xvZ3NTZWFyY2gnKS52YWx1ZS50cmltKCldKTsgfQogIGZ1bmN0aW9uIGxvZ3NDYXRlZ29yeShuLCBidG4pIHsKICAgIGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJyNjYXRSb3cgLmNhdC1idG4nKS5mb3JFYWNoKGZ1bmN0aW9uKGIpeyBiLmNsYXNzTmFtZSA9ICdjYXQtYnRuJzsgfSk7CiAgICB2YXIgY2xhc3NlcyA9IFsnYWN0aXZlLWFsbCcsJ2FjdGl2ZS1hZG1pbicsJ2FjdGl2ZS1wbGF5ZXInLCdhY3RpdmUtc2VydmVyJywnYWN0aXZlLXN5c3RlbSddOwogICAgYnRuLmNsYXNzTmFtZSA9ICdjYXQtYnRuICcgKyBjbGFzc2VzW25dOwogICAgYWN0QXJnKCdsb2dzQ2F0ZWdvcnknLCBbbl0pOwogIH0KCiAgdmFyIENBVF9DT0xPUiA9IHsgQURNSU46ICcjZTY2NjY2JywgUExBWUVSOiAnIzY2YjNlNicsIFNFUlZFUjogJyNlNmIzNGQnLCBTWVNURU06ICcjOTk5OWNjJyB9OwogIHZhciBUWVBFX0NPTE9SID0gewogICAgYmFuOiAnI2U2MzMzMycsIGtpY2s6ICcjZTY4MDRkJywgd2FybjogJyNlNmIzMzMnLCBtdXRlOiAnI2IzNjZlNicsIGphaWw6ICcjODA4MDgwJywKICAgIGtpbGw6ICcjY2M0ZDRkJywgbW9uZXk6ICcjMzNjYzMzJywgd2VhcG9uOiAnIzk5OTljYycsIHRlbGVwb3J0OiAnIzRkYjNlNicsIHNwYXduOiAnIzY2Y2M5OScsIGJvdDogJyM2NmNjNjYnLCBvdGhlcjogJyNiZmJmYmYnCiAgfTsKICB2YXIgVFlQRV9JQ09OID0gewogICAgYmFuOiAnW0JBTl0nLCBraWNrOiAnW0tJQ0tdJywgd2FybjogJ1tXQVJOXScsIG11dGU6ICdbTVVURV0nLCBqYWlsOiAnW0pBSUxdJywga2lsbDogJ1tLSUxMXScsCiAgICBtb25leTogJ1skXScsIHdlYXBvbjogJ1tXUE5dJywgdGVsZXBvcnQ6ICdbVFBdJywgc3Bhd246ICdbU1BBV05dJywgYm90OiAnW0JPVF0nLCBvdGhlcjogJ1s+XScKICB9OwoKICAvLyBkaXBhbmdnaWwgTHVhOiB1cGRhdGVMb2dzKFt7dGltZSxjYXRlZ29yeSx0eXBlLG1lc3NhZ2V9LCAuLi5dKSDigJQgYmlhc2FueWEgY3VrdXAga2lyaW0gTiB0ZXJha2hpcgogIGZ1bmN0aW9uIHVwZGF0ZUxvZ3MobGlzdCkgewogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2xvZ3NUb3RhbFR4dCcpLnRleHRDb250ZW50ID0gbGlzdC5sZW5ndGg7CiAgICB2YXIgZWwgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbG9nc0xpc3QnKTsKICAgIGlmIChsaXN0Lmxlbmd0aCA9PT0gMCkgeyBlbC5pbm5lckhUTUwgPSAnPGRpdiBjbGFzcz0iZW1wdHktaGludCI+Tm8gbG9nczwvZGl2Pic7IHJldHVybjsgfQogICAgdmFyIGh0bWwgPSAnJzsKICAgIGZvciAodmFyIGkgPSAwOyBpIDwgbGlzdC5sZW5ndGg7IGkrKykgewogICAgICB2YXIgbCA9IGxpc3RbaV07CiAgICAgIGh0bWwgKz0gJzxkaXYgY2xhc3M9ImxvZy1saW5lIj4nCiAgICAgICAgKyAnPHNwYW4gY2xhc3M9ImxvZy10aW1lIj4nICsgbC50aW1lICsgJzwvc3Bhbj4nCiAgICAgICAgKyAnPHNwYW4gY2xhc3M9ImxvZy1jYXQiIHN0eWxlPSJjb2xvcjonICsgKENBVF9DT0xPUltsLmNhdGVnb3J5XSB8fCAnIzk5OTljYycpICsgJzsiPlsnICsgbC5jYXRlZ29yeS5zdWJzdHIoMCwzKSArICddPC9zcGFuPicKICAgICAgICArICc8c3BhbiBzdHlsZT0iY29sb3I6JyArIChUWVBFX0NPTE9SW2wudHlwZV0gfHwgJyNiZmJmYmYnKSArICc7Ij4nICsgKFRZUEVfSUNPTltsLnR5cGVdIHx8ICdbPl0nKSArICcgJyArIGVzY2FwZUh0bWwobC5tZXNzYWdlKSArICc8L3NwYW4+JwogICAgICAgICsgJzwvZGl2Pic7CiAgICB9CiAgICBlbC5pbm5lckhUTUwgPSBodG1sOwogICAgZWwuc2Nyb2xsVG9wID0gZWwuc2Nyb2xsSGVpZ2h0OwogIH0KCiAgZnVuY3Rpb24gdXBkYXRlTG9nU3RhdHModG90YWwsIGJhbiwga2ljaywgd2FybiwgbXV0ZSwgamFpbCkgewogICAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3N0YXRCJykudGV4dENvbnRlbnQgPSBiYW47CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnc3RhdEsnKS50ZXh0Q29udGVudCA9IGtpY2s7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnc3RhdFcnKS50ZXh0Q29udGVudCA9IHdhcm47CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnc3RhdE0nKS50ZXh0Q29udGVudCA9IG11dGU7CiAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnc3RhdEonKS50ZXh0Q29udGVudCA9IGphaWw7CiAgfQoKICBmdW5jdGlvbiB1cGRhdGVDbG9jayh0KSB7IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdjbG9ja1R4dCcpLnRleHRDb250ZW50ID0gdDsgfQoKICBjb25zb2xlLmxvZygiYWN0aW9uOmNvbnRlbnRSZWFkeSIpOwo8L3NjcmlwdD4KPC9ib2R5Pgo8L2h0bWw+Cg=="

local CHUNK_SIZE = 4000
local content_sent = false

local B64CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function b64encode(data)
    return ((data:gsub('.', function(x)
        local r, byte = '', x:byte()
        for i = 8, 1, -1 do r = r .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
        return B64CHARS:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function pushChunkedJSON(jsFuncName, jsonStr)
    if not browser_ready then return end
    local b64 = b64encode(jsonStr)
    if #b64 <= CHUNK_SIZE then
        lib.executeJS(BROWSER_ID, jsFuncName .. "(JSON.parse(atob('" .. b64 .. "')))")
        return
    end
    lib.executeJS(BROWSER_ID, "window.__p=[];")
    local i = 1
    while i <= #b64 do
        local part = b64:sub(i, i + CHUNK_SIZE - 1)
        lib.executeJS(BROWSER_ID, "window.__p.push('" .. part .. "');")
        i = i + CHUNK_SIZE
    end
    lib.executeJS(BROWSER_ID, jsFuncName .. "(JSON.parse(atob(window.__p.join(''))))")
end

local function createGUI()
    lib.createBrowser(BROWSER_ID, "about:blank")
end

local function sendHtmlChunks()
    lib.executeJS(BROWSER_ID, "window.__c=[];")
    local len = #TXADMIN_HTML_B64
    local i = 1
    while i <= len do
        local part = TXADMIN_HTML_B64:sub(i, i + CHUNK_SIZE - 1)
        lib.executeJS(BROWSER_ID, "window.__c.push('" .. part .. "');")
        i = i + CHUNK_SIZE
    end
    lib.executeJS(BROWSER_ID, "(function(){var h=atob(window.__c.join(''));document.open();document.write(h);document.close();})();")
end

function pushPlayers()
    if not browser_ready then return end
    local ok, json = pcall(encodeJson, playersList)
    if ok then pushChunkedJSON("updatePlayers", json) end
end

function pushLogs()
    if not browser_ready then return end
    local filtered = {}
    for _, log in ipairs(logsData) do
        if shouldShowLog(log) then table.insert(filtered, log) end
    end
  
    local sendList = {}
    local startIdx = math.max(1, #filtered - 99)
    for i = startIdx, #filtered do table.insert(sendList, filtered[i]) end

    local ok, json = pcall(encodeJson, sendList)
    if ok then pushChunkedJSON("updateLogs", json) end
    lib.executeJS(BROWSER_ID, string.format("updateLogStats(%d,%d,%d,%d,%d,%d)",
        logStats.totalLogs, logStats.banCount, logStats.kickCount, logStats.warnCount, logStats.muteCount, logStats.jailCount))
end

local function jsStr(s)
    s = tostring(s or "")
    return "'" .. s:gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n") .. "'"
end

local function splitPipe(s)
    local parts = {}
    for part in (s .. "|"):gmatch("(.-)|") do
        table.insert(parts, part)
    end
    return parts
end

initializeChatLogging = function()
    addLogEntry("[txAdmin] Chat logging initialized", "SYSTEM")
    ev.onServerMessage = function(color, text)
        local cleanText = text:gsub("{%x+}", "")
        if isImportantMessage(cleanText) then
            addLogEntry("[Server]: " .. cleanText, "SERVER")
        end
    end
    ev.onChatMessage = function(playerId, text)
        local playerName = sampGetPlayerNickname(playerId)
        if isImportantMessage(text) then
            addLogEntry(playerName .. ": " .. text, "PLAYER")
        end
    end
end

local function doLogin(username, password)
    if username == "" or password == "" then
        lib.executeJS(BROWSER_ID, "loginShowError(" .. jsStr("Please fill in all fields!") .. ")")
        return
    end
    if #username < 3 or #password < 3 then
        lib.executeJS(BROWSER_ID, "loginShowError(" .. jsStr("Min 3 characters required!") .. ")")
        return
    end

    isLoggedIn = true
    sampAddChatMessage(string.format("[txAdmin] {FFFFFF}Welcome back, {20CCCC}%s{FFFFFF}!", username), 0x20CCCC)
    addLogEntry("[txAdmin] Admin " .. username .. " logged in", "ADMIN")

    lib.executeJS(BROWSER_ID, "loginSuccess()")
    lib.executeJS(BROWSER_ID, string.format("setWorldState(%s,%d,%s,'#%02x%02x%02x',%.1f)",
        tostring(worldFeatures.names), worldFeatures.nameSize, tostring(worldFeatures.line),
        math.floor(worldFeatures.lineColor[1]*255), math.floor(worldFeatures.lineColor[2]*255), math.floor(worldFeatures.lineColor[3]*255),
        worldFeatures.lineThickness))
    lib.executeJS(BROWSER_ID, "setDutyState(" .. tostring(isDutyOn) .. ")")
    pushLogs()
end

local function handleAction(cmd, args)
    if cmd == "login" then
        doLogin(args[1] or "", args[2] or "")

    elseif cmd == "dutyToggle" then
        sampSendChat("/aod")
        isDutyOn = not isDutyOn
        lib.executeJS(BROWSER_ID, "setDutyState(" .. tostring(isDutyOn) .. ")")

    elseif cmd == "staffOnline" then
        sampSendChat("/admins")

    elseif cmd == "newPlayer" then
        sampSendChat("/lowlist")

    elseif cmd == "teleport" then
        local id, dest = args[1], args[2]
        if id and dest and id ~= "" and dest ~= "" then
            sampSendChat(string.format("/st %s %s", id, dest))
            addLogEntry("Teleported player ID " .. id .. " to " .. dest, "ADMIN")
        end

    elseif cmd == "vehicleSpawn" then
        local model = args[1]
        if model and model ~= "" then
            sampSendChat("/veh " .. model)
            addLogEntry("Spawned vehicle: " .. model, "ADMIN")
        end

    elseif cmd == "healSet" then
        local id, amount = args[1], args[2]
        if id and amount and id ~= "" and amount ~= "" then
            sampSendChat(string.format("/sethp %s %s", id, amount))
            addLogEntry("Set player ID " .. id .. " HP to " .. amount, "ADMIN")
        end

    elseif cmd == "worldNamesToggle" then
        worldFeatures.names = (args[1] == "true")
    elseif cmd == "worldNameSize" then
        worldFeatures.nameSize = tonumber(args[1]) or 14
    elseif cmd == "worldLinesToggle" then
        worldFeatures.line = (args[1] == "true")
    elseif cmd == "worldLineColor" then
        worldFeatures.lineColor = { (tonumber(args[1]) or 255)/255, (tonumber(args[2]) or 255)/255, (tonumber(args[3]) or 255)/255 }
    elseif cmd == "worldLineThickness" then
        worldFeatures.lineThickness = tonumber(args[1]) or 2.0

    elseif cmd == "tabSwitch" then
        if args[1] == "2" then
            if #playersList == 0 then loadAllPlayers() end
            pushPlayers()
        end

    elseif cmd == "playersSearch" then
        searchPlayersByTerm(args[1] or "")
        pushPlayers()
        if (args[1] or "") ~= "" then
            if #playersList == 0 then
                sampAddChatMessage("[txAdmin] {FF6666}No players found!", 0xFF6666)
            else
                sampAddChatMessage(string.format("[txAdmin] {FFFFFF}Found {20CCCC}%d{FFFFFF} player(s)", #playersList), 0x20CCCC)
            end
        end

    elseif cmd == "playersRefresh" then
        loadAllPlayers()
        pushPlayers()
        sampAddChatMessage("[txAdmin] {FFFFFF}Player list refreshed!", 0x20CCCC)

    elseif cmd == "playersScan" then
        scanPlayersInRadius(tonumber(args[1]))
        pushPlayers()

    elseif cmd == "playersSort" then
        local newSort = args[1]
        if currentSort == newSort then sortAscending = not sortAscending
        else currentSort = newSort; sortAscending = true end
        sortPlayersList()
        pushPlayers()

    elseif cmd == "playerView" then
        local id = tonumber(args[1])
        local found = nil
        for _, p in ipairs(playersList) do
            if p.id == id then found = p; break end
        end
        if not found and id then
            found = { id = id, name = sampGetPlayerNickname(id) or ("ID " .. id), ping = getPlayerPing(id), health = getPlayerHealth(id), armour = getPlayerArmour(id) }
        end
        if found then
            selectedPlayer = found
            local ok, json = pcall(encodeJson, found)
            if ok then pushChunkedJSON("openPlayerPopup", json) end
        end

    elseif cmd == "popupClose" then
        selectedPlayer = nil
        lib.executeJS(BROWSER_ID, "closePlayerPopup()")

    elseif cmd == "popupHeal" then
        if selectedPlayer then
            sampSendChat("/sethp " .. selectedPlayer.id .. " 100")
            sampAddChatMessage("[txAdmin] {FFFFFF}Player healed!", 0x20CCCC)
            addLogEntry("Healed " .. selectedPlayer.name, "ADMIN")
        end
    elseif cmd == "popupGoto" then
        if selectedPlayer then
            sampSendChat("/goto " .. selectedPlayer.id)
            sampAddChatMessage("[txAdmin] {FFFFFF}Teleporting...", 0x20CCCC)
            addLogEntry("Teleported to " .. selectedPlayer.name, "ADMIN")
        end
    elseif cmd == "popupBring" then
        if selectedPlayer then
            sampSendChat("/gethere " .. selectedPlayer.id)
            sampAddChatMessage("[txAdmin] {FFFFFF}Bringing player...", 0x20CCCC)
            addLogEntry("Brought " .. selectedPlayer.name, "ADMIN")
        end
    elseif cmd == "popupSpec" then
        if selectedPlayer then
            sampSendChat("/spec " .. selectedPlayer.id)
            sampAddChatMessage("[txAdmin] {FFFFFF}Spectating...", 0x20CCCC)
            addLogEntry("Spectating " .. selectedPlayer.name, "ADMIN")
        end
    elseif cmd == "popupFreeze" then
        if selectedPlayer then
            sampSendChat("/freeze " .. selectedPlayer.id)
            sampAddChatMessage("[txAdmin] {FFFFFF}Player frozen!", 0x20CCCC)
            addLogEntry("Froze " .. selectedPlayer.name, "ADMIN")
        end
    elseif cmd == "popupSlap" then
        if selectedPlayer then
            sampSendChat("/slap " .. selectedPlayer.id)
            sampAddChatMessage("[txAdmin] {FFFFFF}Player slapped!", 0x20CCCC)
            addLogEntry("Slapped " .. selectedPlayer.name, "ADMIN")
        end

    elseif cmd == "popupConfirm" then
        if not selectedPlayer then return end
        local kind = args[1]
        if kind == "ban" then
            local days, reason = args[2], args[3]
            if days and reason and days ~= "" and reason ~= "" then
                sampSendChat(string.format("/ban %d %s %s", selectedPlayer.id, days, reason))
                sampAddChatMessage("[txAdmin] {FFFFFF}Player banned!", 0x20CCCC)
                addLogEntry("Banned " .. selectedPlayer.name .. " for " .. days .. " days: " .. reason, "ADMIN")
                selectedPlayer = nil
                lib.executeJS(BROWSER_ID, "closePlayerPopup()")
            end
        elseif kind == "kick" then
            local reason = args[2]
            if reason and reason ~= "" then
                sampSendChat(string.format("/kick %d %s", selectedPlayer.id, reason))
                sampAddChatMessage("[txAdmin] {FFFFFF}Player kicked!", 0x20CCCC)
                addLogEntry("Kicked " .. selectedPlayer.name .. ": " .. reason, "ADMIN")
                selectedPlayer = nil
                lib.executeJS(BROWSER_ID, "closePlayerPopup()")
            end
        elseif kind == "warn" then
            local reason = args[2]
            if reason and reason ~= "" then
                sampSendChat(string.format("/warn %d %s", selectedPlayer.id, reason))
                sampAddChatMessage("[txAdmin] {FFFFFF}Player warned!", 0x20CCCC)
                addLogEntry("Warned " .. selectedPlayer.name .. ": " .. reason, "ADMIN")
                selectedPlayer = nil
                lib.executeJS(BROWSER_ID, "closePlayerPopup()")
            end
        elseif kind == "mute" then
            local time, reason = args[2], args[3]
            if time and reason and time ~= "" and reason ~= "" then
                sampSendChat(string.format("/mute %d %s %s", selectedPlayer.id, time, reason))
                sampAddChatMessage("[txAdmin] {FFFFFF}Player muted!", 0x20CCCC)
                addLogEntry("Muted " .. selectedPlayer.name .. " for " .. time .. " mins: " .. reason, "ADMIN")
                selectedPlayer = nil
                lib.executeJS(BROWSER_ID, "closePlayerPopup()")
            end
        elseif kind == "jail" then
            local time, reason = args[2], args[3]
            if time and reason and time ~= "" and reason ~= "" then
                sampSendChat(string.format("/jail %d %s %s", selectedPlayer.id, time, reason))
                sampAddChatMessage("[txAdmin] {FFFFFF}Player jailed!", 0x20CCCC)
                addLogEntry("Jailed " .. selectedPlayer.name .. " for " .. time .. " mins: " .. reason, "ADMIN")
                selectedPlayer = nil
                lib.executeJS(BROWSER_ID, "closePlayerPopup()")
            end
        elseif kind == "dm" then
            local message = args[2]
            if message and message ~= "" then
                sampSendChat(string.format("/pm %d %s", selectedPlayer.id, message))
                sampAddChatMessage("[txAdmin] {FFFFFF}Message sent!", 0x20CCCC)
                addLogEntry("Sent DM to " .. selectedPlayer.name .. ": " .. message, "ADMIN")
            end
        end

    elseif cmd == "logsSearch" then
        logsSearchTerm = (args[1] or ""):lower()
        pushLogs()
    elseif cmd == "logsCategory" then
        currentLogCategory = tonumber(args[1]) or 0
        pushLogs()
    elseif cmd == "logsClear" then
        logsData = {}
        logStats = { totalLogs = 0, banCount = 0, kickCount = 0, warnCount = 0, muteCount = 0, jailCount = 0 }
        pushLogs()
    elseif cmd == "logsScrollBottom" then
        pushLogs()

    elseif cmd == "posSave" then
        local x, y = tonumber(args[1]), tonumber(args[2])
        if x and y then savePos(x, y) end

    elseif cmd == "closeApp" then
        appVisible = false
        lib.setVisible(BROWSER_ID, false)
        lib.setClickable(BROWSER_ID, false)
        lib.executeJS(BROWSER_ID, "showApp(false)")
    end
end

function lib.onAction(data)
    if data.type == "PING" and data.msg == "STATUS_OK" then

    elseif data.type == "WV_LOADED" then
        if not content_sent then
            content_sent = true
            sendHtmlChunks()
        end

    elseif data.type == "WV_ANSWER" then
        local msg = data.msg
        if msg == "action:contentReady" then
            browser_ready = true
            do
                local px = math.max(0, math.min(configIni.window.posX, sizeX - 240))
                local py = math.max(0, math.min(configIni.window.posY, sizeY - 60))
                lib.executeJS(BROWSER_ID, "setPosition(" .. px .. "," .. py .. ")")
            end
            lib.executeJS(BROWSER_ID, "setLocked(" .. tostring(positionLocked) .. ")")
            lib.setVisible(BROWSER_ID, appVisible)
            lib.setClickable(BROWSER_ID, appVisible)
            lib.executeJS(BROWSER_ID, "showApp(" .. tostring(appVisible) .. ")")
            if isLoggedIn then
                lib.executeJS(BROWSER_ID, "loginSuccess()")
            end
        elseif msg:sub(1, 7) == "action:" then
            local parts = splitPipe(msg:sub(8))
            local cmd = table.remove(parts, 1)
            handleAction(cmd, parts)
        end

    elseif data.type == "WV_DIE" then
        browser_ready = false
        content_sent = false
        if browser_created then
            lib.deleteBrowser(BROWSER_ID)
            createGUI()
        end

    elseif data.type == "WV_CLOSE" then
        appVisible = false
        if browser_ready then lib.executeJS(BROWSER_ID, "showApp(false)") end

    elseif data.type == "WV_ERROR" then
        lib.addLog("txAdmin WebView error: " .. tostring(data.msg))
    end
end

local function toggleApp()
    appVisible = not appVisible
    if appVisible and not browser_created then
        browser_created = true
        createGUI()
    elseif browser_ready then
        lib.setVisible(BROWSER_ID, appVisible)
        lib.setClickable(BROWSER_ID, appVisible)
        lib.executeJS(BROWSER_ID, "showApp(" .. tostring(appVisible) .. ")")
    end
end

function onScriptTerminate(script, quit)
    if script == thisScript() then
        if browser_ready then lib.deleteBrowser(BROWSER_ID) end
    end
end


-- MAIN

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(0) end

    sizeX, sizeY = getScreenResolution()

    sampRegisterChatCommand("txadmin", function() toggleApp() end)
    sampRegisterChatCommand("tx", function() toggleApp() end)

    sampRegisterChatCommand("txlock", function()
        positionLocked = not positionLocked
        saveLock()
        if browser_ready then lib.executeJS(BROWSER_ID, "setLocked(" .. tostring(positionLocked) .. ")") end
        local status = positionLocked and "terkunci" or "tidak terkunci"
        sampAddChatMessage("[txAdmin] {FFFFFF}Posisi window " .. status, 0x20CCCC)
    end)

    sampRegisterChatCommand("txlogout", function()
        if isLoggedIn then
            isLoggedIn = false
            if browser_ready then lib.executeJS(BROWSER_ID, "doLogout()") end
            sampAddChatMessage("[txAdmin] {FFFFFF}Logged out successfully!", 0x20CCCC)
        else
            sampAddChatMessage("[txAdmin] {FF6666}You are not logged in!", 0xFF6666)
        end
    end)

    initializeChatLogging()
    sampAddChatMessage("[txAdmin] {FFFFFF}loaded! Use {20CCCC}/txadmin {FFFFFF}or {20CCCC}/tx {FFFFFF}to use it.", 0x20CCCC)
    sampAddChatMessage("[txAdmin] {FFFFFF}Use {20CCCC}/txlock {FFFFFF}to lock/unlock window position.", 0x20CCCC)

    local lastClock = 0
    while true do
        wait(0)

        if worldFeatures.names then renderPlayerNames() end
        if worldFeatures.line then renderPlayerLines() end

        if browser_ready and appVisible then
            local now = os.clock()
            if now - lastClock >= 1.0 then
                lastClock = now
                lib.executeJS(BROWSER_ID, "updateClock(" .. jsStr(os.date("%H:%M:%S")) .. ")")
            end
        end
    end
end
