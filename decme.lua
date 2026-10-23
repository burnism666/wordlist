
local display, shelf, mannq, pmaker, vault, gaia, ut = {}, {}, {}, {}, {}, {}, {}
local maglist = {}
local filterUID = ""
local checker_locks = {}

local h_typ = "nn"
local h_len = 1
local h_name = ""
local h_pos = "front"
local h_delay = 2000
local hunt_run = false
local visited = {}
local last_visit = ""
local hide_world = false
local visit_history = {}
local VISIT_MAX = 5

discordids = discordids or ""
discordname = discordname or ""

local IDS = {
    display = { 2946 },
    shelf = { 10552, 10190, 3794 },
    mannq = { 10078, 10076, 10074, 10072, 6214, 1420 },
    pmaker = { 1684, 4482 },
    vault = { 8878 },
    gaia = { 6946 },
    ut = { 6948 },
}

local LOCK_IDS = {202, 204, 206, 242, 1796, 2408, 4428, 4802, 4994, 5260, 5770, 5814, 5980, 7188, 8470, 9640, 10410, 11550, 11586, 11902, 12654, 13200, 13636, 14296, 14536, 14538}

local WORLD_LOCKS = {
    [242]=true, [1796]=true, [2408]=true, [4428]=true, [4802]=true,
    [5260]=true, [5770]=true, [5814]=true, [5980]=true, [7188]=true,
    [8470]=true, [9640]=true, [10410]=true, [11550]=true, [11586]=true,
    [11902]=true, [12654]=true, [13200]=true, [13636]=true, [14296]=true,
    [14536]=true, [14538]=true,
}

local AREA_LOCKS = {
    [202]=10, [204]=48, [206]=200, [4994]=200,
}

local filterPub = { shelf = false, mannq = false, pm = false, disp = false, gaia = false, ut = false }
local shelf_shown, mannq_shown, pmaker_shown = {}, {}, {}
local display_shown, gaia_shown, ut_shown = {}, {}, {}

-- ===== ESP Draw (new) =====
local esp_show = { pathmaker = false, display = false, shelf = false, mannq = false, gaia = false, ut = false, items = false }
local esp_item_ids = {}
local esp_pts = {}
local esp_only_public = true
local esp_hide_lock_area = false
local esp_world = nil
local esp_pending = false
local esp_last_scan = 0
local ESP_SCAN_INTERVAL = 2000
local vend_esp = nil
local ESP_COL = {
    pathmaker = 4294967040,
    display = 4278255360,
    shelf = 4294901760,
    mannq = 4278190335,
    gaia = 4278255555,
    ut = 4294967295,
    items = 4294967295,
}

local function ovlay(msg)
    sendVariant({ [0] = "OnTextOverlay", [1] = "`9[Burem] `7" .. msg }, -1, 0)
end

local function addVisit(world)
    if not world or world == "" then return end
    for i, w in ipairs(visit_history) do
        if w == world then
            table.remove(visit_history, i)
            break
        end
    end
    table.insert(visit_history, 1, world)
    while #visit_history > VISIT_MAX do
        table.remove(visit_history)
    end
    last_visit = world
end

local function isHiddenConsole(msg)
    if not msg or msg == "" then return false end
    if msg:find("Magically Warping") and msg:find("to home world") then return true end
    if msg:find(" entered%.") and msg:find("There are") then return true end
    if msg:find("World Locked") and msg:find("ACCESS GRANTED") then return true end
    if msg:find("World Locked") and msg:find("by ") then return true end
    return false
end

local function showVisitDlg()
    local dlg = {}
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "add_label_with_icon|big|`9Visited Worlds (Last 5)|left|3802|")
    table.insert(dlg, "add_spacer|small|")
    if #visit_history == 0 then
        table.insert(dlg, "add_label|`4No visited worlds yet.|")
    else
        for i, w in ipairs(visit_history) do
            table.insert(dlg, "add_button|visit_world_" .. i .. "|`2" .. w .. "|0|0|0|")
        end
    end
    table.insert(dlg, "end_dialog|visit_hist|Close||")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end


local BF_DEFAULT_LIST = {
    -- contoh: "namakamu", "namaorang", "privateid1",
}
local bf_ids = {}
for _, v in ipairs(BF_DEFAULT_LIST) do
    bf_ids[#bf_ids + 1] = v
end
local bf_running = false
local bf_found = false
local bf_stopped = false
local bf_index = 1        -- kursor progres: ID berikutnya yang dicoba
local bf_paused = false   -- true = paused, bisa di-resume
local bf_attempts = 0     -- total percobaan (cap 1000, global antar resume)
local bf_delay = 1200     -- ms per percobaan

local function bfParse(text)
    local out = {}
    for token in tostring(text or ""):gmatch("[^,%s]+") do
        out[#out + 1] = token
    end
    return out
end

local function bfAddList(tokens)
    local seen = {}
    for _, v in ipairs(bf_ids) do seen[v:lower()] = true end
    local added = 0
    for _, v in ipairs(tokens) do
        local key = v:lower()
        if not seen[key] then
            seen[key] = true
            bf_ids[#bf_ids + 1] = v
            added = added + 1
        end
    end
    return added
end

local function showBfDlg()
    local status = bf_running and "`2Running" or (bf_paused and "`4Paused" or (bf_found and "`2Found" or "`4Idle"))
    local dlg = {}
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "add_label_with_icon|big|`9Bruteforce ID|left|762|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label_with_icon|small|`9Wordlist: `2" .. #bf_ids .. " `7entries|left|2480|")
    table.insert(dlg, "add_label_with_icon|small|`9Status: `7" .. status .. "|left|10024|")
    table.insert(dlg, "add_label_with_icon|small|`9Progress: `2" .. (bf_index - 1) .. " `7/ `2" .. #bf_ids .. "|left|3802|")
    local preview = ""
    for i = 1, math.min(3, #bf_ids) do
        preview = preview .. (i > 1 and ", " or "") .. bf_ids[i]
    end
    if #bf_ids > 3 then preview = preview .. ", ..." end
    if preview ~= "" then
        table.insert(dlg, "add_label_with_icon|small|`9Preview: `7" .. preview .. "|left|32|")
    end
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_text_input|bf_delay|Delay (ms):|" .. bf_delay .. "|5|")
    table.insert(dlg, "add_button|bf_edit|`9Open Wordlist Editor (massal)|0|0|0|")
    table.insert(dlg, "add_button|bf_clearlist|`4Clear Wordlist|0|0|0|")
    table.insert(dlg, "add_spacer|small|")
    if bf_paused then
        table.insert(dlg, "add_button|bf_continue|`2Continue Bruteforce (from " .. bf_index .. ")|0|0|0|")
    end
    table.insert(dlg, "add_button|bf_start|`2Start Bruteforce|0|0|0|")
    table.insert(dlg, "add_button|bf_prog_reset|`4Reset Progress|0|0|0|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label|`7Open Friends menu to pause & save progress while running.|")
    table.insert(dlg, "end_dialog|bf_menu|Close||")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

local function bfStart()
    if bf_running then ovlay("BF already running.") return end
    if #bf_ids == 0 then ovlay("Wordlist kosong. Tambah lewat /bf.") return end
    if bf_index > #bf_ids then bf_index = #bf_ids end
    if not bf_paused then bf_index = 1 end
    bf_paused = false
    bf_running = true
    bf_found = false
    bf_stopped = false
    ovlay((bf_index > 1 and "BF continue from ID " .. bf_index .. " of " or "BF started. ") .. #bf_ids .. " IDs.")
    local startX, startY
    local me = getLocal()
    if me and me.pos then startX, startY = me.pos.x, me.pos.y end
    runThread(function()
        while bf_index <= #bf_ids do
            if bf_attempts >= 1000 then break end
            if not bf_running or bf_found or bf_stopped then break end
            local idw = bf_ids[bf_index]
            local wcur = getWorld()
            local wor = (wcur and wcur.name) or ""
            bf_index = bf_index + 1
            bf_attempts = bf_attempts + 1
            sendPacket(3, "action|join_request\nname|" .. wor .. "|" .. idw .. "\ninvitedWorld|0")
            ovlay("`9Trying ID : `5" .. idw)
            sleep(bf_delay)
            if not bf_running or bf_stopped then break end
            local p = getLocal()
            if p and p.pos and startX and startY then
                if p.pos.x ~= startX or p.pos.y ~= startY then
                    bf_found = true
                    bf_running = false
                    ovlay("`9Valid ID Found : `2" .. idw)
                    break
                end
            end
        end
        bf_running = false
        if not bf_found and not bf_stopped then
            ovlay("Success Trying All ID.")
        end
    end, "bfid")
end

local function showWordlistDlg()
    local dlg = {}
    table.insert(dlg, "set_default_color|`o")
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "add_label_with_icon|big|`9Wordlist Editor|left|1366|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label_with_icon|small|`9Total wordlist: `2" .. #bf_ids .. " `7entries|left|2480|")
    table.insert(dlg, "add_textbox|Paste the ID/name in the box below. Multiple entries are allowed comma|left|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_text_box_input|wl_input|||256|7|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_button|wl_add|`2Add to Wordlist|noflags|0|0|")
    table.insert(dlg, "add_button|wl_clear|`4Clear Wordlist|noflags|0|0|")
    table.insert(dlg, "add_button|wl_back|Cancel|noflags|0|0|")
    table.insert(dlg, "add_quick_exit|")
    table.insert(dlg, "end_dialog|wl_edit||")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

local function idleak()
    AddHook("OnVarlist", "Leaked", function(var)
        if var and var[0] == "OnSendToServer" then
            local info = tostring(var[4] or "")
            local iddoor = info:match("|([^|]+)|")
            if iddoor then
                local w = getWorld()
                local wname = (w and w.name) or "-"
                logToConsole("`b[Burem] `wID Door : " .. wname .. " | " .. iddoor)
                return 
            end
        end
    end)
end
idleak()

-- ===== Hide Console World (toggle) =====
AddHook("OnVarlist", "BuremHideConsoleWorld", function(var)
    if not var then return false end
    if var[0] ~= "OnConsoleMessage" then return false end
    local msg = tostring(var[1] or "")
    if msg:find(" entered%.") and msg:find("There are") then
        local wname = msg:match("World `w([^`]+)`") or msg:match("World ([^ ]+)")
        if wname then addVisit(wname) end
    end
    if not hide_world then return false end
    if isHiddenConsole(msg) then
        logToConsole("`9[Burem] `4World name has been hide.")
        return true
    end
    return false
end)

-- ===== World Lock Check (overlay on enter) =====
local wl_locked = false
local wl_gen = 0

local function wlAnnounce(text)
    ovlay(text)
end

AddHook("OnVarlist", "BuremWorldLockMsg", function(var)
    if not var or var[0] ~= "OnConsoleMessage" then return false end
    local msg = tostring(var[1] or "")
    if msg:find("World Locked") then
        if not wl_locked then
            wl_locked = true
            wlAnnounce("`4World Locked")
        end
        return false
    end
    if msg:find(" entered%.") and msg:find("There are") then
        wl_locked = false
        wl_gen = wl_gen + 1
        local my = wl_gen
        runThread(function()
            sleep(100)
            if my ~= wl_gen then return end
            if not wl_locked then
                wlAnnounce("`2World Public")
            end
        end, "buremwlockchk")
    end
    return false
end)
-- ===== end World Lock Check =====

local function isLockId(id)
    for _, v in ipairs(LOCK_IDS) do
        if v == id then return true end
    end
    return false
end

local function collectLocks()
    local locks = {}
    local tiles = getTile()
    if not tiles then return locks end
    for _, tile in pairs(tiles) do
        if tile and isLockId(tile.fg) then
            local extra = getExtraTile(tile.pos.x, tile.pos.y)
            if extra and extra.valid and extra.owner and extra.owner > 0 then
                if filterUID == "" or tostring(extra.owner) == filterUID then
                    local nm = "Lock"
                    local info = getItemByID(tile.fg)
                    if info and info.name and info.name ~= "" then nm = info.name end
                    table.insert(locks, {
                        id = tile.fg, name = nm,
                        x = tile.pos.x + 1, y = tile.pos.y + 1,
                        owner = tostring(extra.owner),
                        admins = extra.adminList or {},
                    })
                end
            end
        end
    end
    return locks
end

-- ===== Public resolve (from cekFlag) =====
local function readGetFlags(tile)
    local gf = tile.getFlags
    if type(gf) == "function" then
        local ok, r = pcall(gf, tile)
        if ok then return r end
        return nil
    end
    if type(gf) == "table" then return gf end
    return nil
end

local function getPublic(tile)
    local gf = readGetFlags(tile)
    if gf and gf.public ~= nil then return gf.public end
    local raw = tonumber(tile.flags) or 0
    if math.floor(raw / 128) % 2 == 1 then return true end
    if math.floor(raw / 256) % 2 == 1 then return true end
    return false
end

local function scanPublicLocks()
    local locks = {}
    local tiles = getTile()
    if not tiles then return locks end
    for _, t in pairs(tiles) do
        if t and t.pos and isLockId(t.fg) then
            local e = getExtraTile(t.pos.x, t.pos.y)
            if e and e.valid then
                local gf = readGetFlags(t)
                local raw = tonumber(t.flags) or 0
                local pub
                if gf and gf.public ~= nil then
                    pub = gf.public
                else
                    pub = (math.floor(raw / 128) % 2 == 1) or (math.floor(raw / 256) % 2 == 1)
                end
                local nm = "Lock"
                local info = getItemByID(t.fg)
                if info and info.name and info.name ~= "" then nm = info.name end
                table.insert(locks, {
                    x = t.pos.x, y = t.pos.y, fg = t.fg, name = nm,
                    isWorld = WORLD_LOCKS[t.fg] or false,
                    areaSize = AREA_LOCKS[t.fg],
                    owner = e.owner or 0,
                    public = pub,
                })
            end
        end
    end
    return locks
end

local function coversLock(L, tx, ty)
    if L.isWorld then return true end
    if L.areaSize then
        local side = math.ceil(math.sqrt(L.areaSize))
        local half = math.floor(side / 2)
        return math.abs(tx - L.x) <= half and math.abs(ty - L.y) <= half
    end
    return false
end

local function resolvePublic(locks, tile, tx, ty)
    if tile and getPublic(tile) then return true, nil end
    for _, L in ipairs(locks) do
        if coversLock(L, tx, ty) then
            if L.public then return true, L end
            return false, L
        end
    end
    return true, nil -- no lock covering = unlocked = public
end

local function attachPublicInfo(list)
    local locks = scanPublicLocks()
    for _, d in ipairs(list) do
        local tile = nil
        local okT, t = pcall(checkTile, d.x, d.y)
        if okT and t then tile = t end
        local isPub = select(1, resolvePublic(locks, tile, d.x, d.y))
        d.public = isPub
        if #locks > 0 then
            for _, L in ipairs(locks) do
                if coversLock(L, d.x, d.y) then
                    d.viaLock = L
                    break
                end
            end
        end
    end
    return list
end

local function onlyPublic(list)
    local out = {}
    for _, d in ipairs(list) do
        if d.public then out[#out + 1] = d end
    end
    return out
end
-- ===== end Public resolve =====

-- ===== ESP Draw helpers (new) =====
local function espAnyOn()
    for _, v in pairs(esp_show) do
        if v then return true end
    end
    return false
end

local function espInWorld()
    local w = getWorld()
    if not w or not w.name or w.name == "" or w.name:upper() == "EXIT" then return false end
    local ok, me = pcall(getLocal)
    if not ok or not me or not me.pos then return false end
    return true
end

local function espRescan()
    esp_pts = {}
    local w = getWorld()
    esp_world = (w and w.name) or ""
    esp_last_scan = getCurrentTimeInternal()
    if not espAnyOn() then
        esp_pending = false
        return
    end
    if not espInWorld() then
        esp_pending = false
        return
    end
    local want, colOf = {}, {}
    local function addIds(ids, col)
        for _, id in ipairs(ids) do
            want[id] = true
            colOf[id] = col
        end
    end
    if esp_show.pathmaker then addIds(IDS.pmaker, ESP_COL.pathmaker) end
    if esp_show.display then addIds(IDS.display, ESP_COL.display) end
    if esp_show.shelf then addIds(IDS.shelf, ESP_COL.shelf) end
    if esp_show.mannq then addIds(IDS.mannq, ESP_COL.mannq) end
    if esp_show.gaia then addIds(IDS.gaia, ESP_COL.gaia) end
    if esp_show.ut then addIds(IDS.ut, ESP_COL.ut) end
    if esp_show.items and #esp_item_ids > 0 then addIds(esp_item_ids, ESP_COL.items) end
    if not next(want) then
        esp_pending = false
        return
    end
    local found = {}
    local tiles = getTile()
    if not tiles or not next(tiles) then
        esp_pending = true
        return
    end
    esp_pending = false
    for _, t in pairs(tiles) do
        if t and t.pos and want[t.fg] then
            found[#found + 1] = { x = t.pos.x, y = t.pos.y, fg = t.fg }
        end
    end
    pcall(attachPublicInfo, found)
    for _, d in ipairs(found) do
        local pass = true
        if esp_only_public and not d.public then pass = false end
        if pass and esp_hide_lock_area and d.viaLock then pass = false end
        if pass then
            esp_pts[#esp_pts + 1] = { x = d.x, y = d.y, c = colOf[d.fg] or ESP_COL.items }
        end
    end
end

local function applyEspFromPkt(pkt)
    local function getCb(k)
        local v = pkt:match(k .. "|(%d)")
        if v == "1" then return true end
        if v == "0" then return false end
        return nil
    end
    local vals = {
        pathmaker = getCb("esp_path"),
        display = getCb("esp_disp"),
        shelf = getCb("esp_shelf"),
        mannq = getCb("esp_mannq"),
        gaia = getCb("esp_gaia"),
        ut = getCb("esp_ut"),
        items = getCb("esp_items"),
    }
    local idsStr = pkt:match("esp_ids|([^|\n]*)")
    local idsChanged = false
    if idsStr ~= nil then
        local newIds = {}
        for n in tostring(idsStr):gmatch("%d+") do
            newIds[#newIds + 1] = tonumber(n)
        end
        if #newIds ~= #esp_item_ids then
            idsChanged = true
        else
            for i = 1, #newIds do
                if newIds[i] ~= esp_item_ids[i] then idsChanged = true break end
            end
        end
        if idsChanged then esp_item_ids = newIds end
    end
    local changed = idsChanged
    for k, v in pairs(vals) do
        if v ~= nil and v ~= esp_show[k] then
            esp_show[k] = v
            changed = true
        end
    end
    if not changed then return end
    espRescan()
    local n = #esp_pts
    ovlay("ESP updated. Drawing " .. n .. " tile(s)." .. (esp_only_public and " (public)" or ""))
end

AddHook("OnRender", "BuremESPDraw", function()
    if not espAnyOn() then return end
    if not espInWorld() then
        if #esp_pts > 0 then esp_pts = {} end
        esp_world = nil
        esp_pending = false
        return
    end
    local w = getWorld()
    local wname = (w and w.name) or ""
    if wname ~= esp_world then
        espRescan()
    elseif esp_pending then
        local now = getCurrentTimeInternal()
        if now - esp_last_scan >= ESP_SCAN_INTERVAL then
            espRescan()
        end
    end
    if #esp_pts == 0 then return end
    local me = getLocal()
    if not me or not me.pos then return end
    local ok = pcall(function()
        local p_screen = worldToScreen(me.pos.x + 9, me.pos.y - 20)
        for i = 1, #esp_pts do
            local pt = esp_pts[i]
            local s = worldToScreen(pt.x * 32, pt.y * 32)
            local e = worldToScreen(pt.x * 32 + 32, pt.y * 32 + 32)
            ImGui.BG:AddRect(s, e, pt.c, 0.0, 1.5)
            ImGui.BG:AddLine(p_screen, s, pt.c, 1.5)
        end
    end)
    if not ok then
        esp_pts = {}
        esp_pending = true
    end
end)

AddHook("OnJoinWorld", "BuremESPJoin", function()
    esp_pts = {}
    esp_world = nil
    esp_pending = true
    esp_last_scan = 0
    vend_esp = nil
end)

AddHook("OnRender", "BuremVendESP", function()
    if not vend_esp then return end
    if not espInWorld() then
        vend_esp = nil
        return
    end
    local w = getWorld()
    local wname = (w and w.name) or ""
    if vend_esp.world and vend_esp.world ~= "" and wname:upper() ~= vend_esp.world:upper() then
        vend_esp = nil
        return
    end
    local me = getLocal()
    if not me or not me.pos then return end
    local ok = pcall(function()
        local p_screen = worldToScreen(me.pos.x + 9, me.pos.y - 20)
        local s = worldToScreen(vend_esp.x * 32, vend_esp.y * 32)
        local e = worldToScreen(vend_esp.x * 32 + 32, vend_esp.y * 32 + 32)
        ImGui.BG:AddRect(s, e, 4294967040, 0.0, 2.5)
        ImGui.BG:AddLine(p_screen, s, 4294967040, 2.0)
    end)
    if not ok then vend_esp = nil end
end)

local ENTRANCE_IDS = {}
for _, id in ipairs({6,12,30,60,224,544,546,552,598,686,762,858,886,972,976,1040,1162,1294,1326,1682,1910,2274,2810,3126,3284,3286,3798,4164,4190,4218,4240,4352,4466,4468,4520,4710,4718,4744,4834,4836,4838,5036,5054,5056,5058,5060,5354,5362,5748,5818,5820,6104,6178,6390,6548,6850,7066,7164,7184,7322,7708,7812,7850,7860,8260,8266,8320,8658,9358,9662,10060,10202,10654,10702,10734,10882,11136,11138,11336,11746,12006,12652,12954}) do
    ENTRANCE_IDS[id] = true
end
local ent_show = false
local ent_pts = {}
local ent_world = nil
local ent_pending = false
local ent_last_scan = 0
local ent_last_key = nil
local ent_scanned = {} -- [worldName] = true, sudah discan 1x di world ini
local ENT_SCAN_INTERVAL = 2000

local function entScan(verbose)
    ent_pts = {}
    local w = getWorld()
    local wname = (w and w.name) or ""
    if wname == "" or wname:upper() == "EXIT" then
        ent_world = nil
        ent_pending = false
        ent_last_scan = getCurrentTimeInternal()
        ent_scanned = {}
        ent_pts = {}
        ent_last_key = nil
        return
    end
    ent_world = wname
    local tiles = getTile()
    if not tiles or not next(tiles) then
        ent_pending = true
        ent_last_scan = getCurrentTimeInternal()
        return
    end
    ent_scanned[wname] = true
    ent_pending = false
    local pubN = 0
    for _, t in pairs(tiles) do
        if t and t.pos and ENTRANCE_IDS[t.fg] then
            local pub = getPublic(t)
            if pub then pubN = pubN + 1 end
            ent_pts[#ent_pts + 1] = { x = t.pos.x, y = t.pos.y, pub = pub }
            if verbose then
                --logToConsole("`9[Entrance] (" .. (t.pos.x + 1) .. "," .. (t.pos.y + 1) .. ") id=" .. t.fg .. " public=" .. (pub and "`2true" or "`4false"))
            end
        end
    end
    local key = #ent_pts .. ":" .. pubN
    if ent_last_key == nil or key ~= ent_last_key then
        ent_last_key = key
        logToConsole("Entrance: " .. #ent_pts .. " `2| Public: " .. pubN .. "`4 | Non-public: " .. (#ent_pts - pubN))
    end
    ent_last_scan = getCurrentTimeInternal()
end

local function entToggle()
    ent_show = not ent_show
    if ent_show then
        ent_world = nil
        ent_pending = false
        ent_last_key = nil
        ent_scanned = {}
        ovlay("Entrance Check: `2ON")
    else
        ent_pts = {}
        ent_world = nil
        ent_pending = false
        ovlay("Entrance Check: `4OFF")
    end
end

AddHook("OnRender", "BuremEntranceDraw", function()
    if not ent_show then return end
    if not espInWorld() then
        if #ent_pts > 0 then ent_pts = {} end
        return
    end
    local w = getWorld()
    local wname = (w and w.name) or ""
    if wname ~= "" and not ent_scanned[wname] then
        entScan(true)
    end
    if #ent_pts == 0 then return end
    local ok = pcall(function()
        for i = 1, #ent_pts do
            local d = ent_pts[i]
            local s = worldToScreen(d.x * 32, d.y * 32)
            local e = worldToScreen(d.x * 32 + 32, d.y * 32 + 32)
            ImGui.BG:AddRectFilled(s, e, d.pub and 1677786880 or 1677721855, 0.0, 0)
        end
    end)
    if not ok then
        ent_pts = {}
        ent_world = nil
        ent_pending = false
        ent_last_scan = getCurrentTimeInternal()
        ent_scanned = {}
    end
end)

AddHook("OnJoinWorld", "BuremEntJoin", function()
    ent_scanned = {}
    ent_pts = {}
    ent_world = nil
    ent_pending = false
    ent_last_key = nil
end)
-- ===== end Entrance Check =====

local function showChecker()
    local locks = collectLocks()
    checker_locks = locks
    local w = getWorld()
    local wname = (w and w.name) or "-"
    local dlg = {}
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "add_label_with_icon|big|`9World Checker|left|10024|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label_with_icon|small|World: `9" .. wname .. "|left|3802|")
    table.insert(dlg, "add_label_with_icon|small|Total Locks: `9" .. #locks .. "|left|2480|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_text_input|filteruidinput|Filter UID :|" .. filterUID .. "|32|")
    table.insert(dlg, "add_button|checker_apply|`2Apply Filter|0|0|0|")
    table.insert(dlg, "add_spacer|small|")
    if #locks == 0 then
        table.insert(dlg, "add_label|`4No Lock Found.|")
    else
        for i, l in ipairs(locks) do
            table.insert(dlg, "add_label_with_icon_button|small|`9" .. l.name .. " `7(" .. l.x .. "," .. l.y .. ") Owner:" .. l.owner .. " Admin:" .. #l.admins .. "|left|" .. l.id .. "|lock_" .. i .. "|")
        end
    end
    table.insert(dlg, "end_dialog|checkerw|Close||")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

local function showLockDetail(idx)
    local l = checker_locks[idx]
    if not l then ovlay("Lock not found.") return end
    local dlg = {}
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "add_label_with_icon|big|`9" .. l.name .. "|left|" .. l.id .. "|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label_with_icon|small|`7Pos: `9(" .. l.x .. "," .. l.y .. ") `7ItemID: `9" .. l.id .. "|left|" .. l.id .. "|")
    table.insert(dlg, "add_label_with_icon|small|`7Owner UID: `2" .. l.owner .. "|left|242|")
    table.insert(dlg, "add_label_with_icon|small|`7Total Admin: `9" .. #l.admins .. "|left|2480|")
    table.insert(dlg, "add_spacer|small|")
    if #l.admins == 0 then
        table.insert(dlg, "add_label|`4No Admins.|")
    else
        for _, uid in ipairs(l.admins) do
            table.insert(dlg, "add_label_with_icon|small|`9" .. tostring(uid) .. "|left|242|")
        end
    end
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_button|lock_back|`2Back to Checker|0|0|0|")
    table.insert(dlg, "end_dialog|lockdetail|Close||")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

local function scanTiles(ids)
    local out = {}
    local lookup = {}
    for _, id in ipairs(ids) do lookup[id] = true end
    local tiles = getTile()
    if not tiles then return out end
    for _, t in pairs(tiles) do
        if t and lookup[t.fg] then
            table.insert(out, { x = t.pos.x, y = t.pos.y, fg = t.fg })
        end
    end
    return out
end

local function display_scan()
    display = {}
    local lookup = {}
    for _, id in ipairs(IDS.display) do lookup[id] = true end
    local tiles = getTile()
    if not tiles then return end
    for _, t in pairs(tiles) do
        if t and lookup[t.fg] then
            local e = getExtraTile(t.pos.x, t.pos.y)
            table.insert(display, {
                x = t.pos.x, y = t.pos.y, fg = t.fg,
                owner = (e and e.valid) and e.owner or 0,
            })
        end
    end
end
local function shelf_scan() shelf = scanTiles(IDS.shelf) end
local function mannq_scan() mannq = scanTiles(IDS.mannq) end
local function pmaker_scan() pmaker = scanTiles(IDS.pmaker) end
local function vault_scan() vault = scanTiles(IDS.vault) end

local vault_itemid = 2 -- itemid yang dikirim ke storageboxxtreme (bisa diganti via picker)
local function gaia_scan() gaia = scanTiles(IDS.gaia) end
local function ut_scan() ut = scanTiles(IDS.ut) end

local mag_filter = {} -- [itemID] = true -> hide item ini dari list magnet
local magSearch = ""  -- filter cari nama/ID drop di dialog magnet

local function magnet()
    maglist = {}
    local objs = getWorldObject()
    if not objs then return maglist end
    for _, o in pairs(objs) do
        if o and o.id and o.id > 0 then
            table.insert(maglist, { oid = o.oid, id = o.id, amount = o.amount or 0 })
        end
    end
    return maglist
end

local function showList(dlgName, title, icon, data, prefix, emptyMsg, filterMode, extra)
    local dlg = {}
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "add_label_with_icon|big|" .. title .. "|left|" .. icon .. "|")
    table.insert(dlg, "add_label_with_icon|small|`9Creator: `5Cicippetani & Burnism|left|242|")
    table.insert(dlg, "add_label_with_icon|small|`9Discord Server: `2https://discord.gg/yMBDMA5grc|left|482|")
    table.insert(dlg, "add_spacer|small|")
    if extra then
        for _, ln in ipairs(extra) do table.insert(dlg, ln) end
        table.insert(dlg, "add_spacer|small|")
    end
    if filterMode == "toggle" then
        if filterPub[prefix:gsub("_$", "")] then
            table.insert(dlg, "add_button|" .. prefix .. "pub_off|`4Disable Filter Only Public|0|0|0|")
        else
            table.insert(dlg, "add_button|" .. prefix .. "pub_on|`2Filter Only Public|0|0|0|")
        end
        table.insert(dlg, "add_spacer|small|")
    elseif filterMode == "toggle_unl" then
        if filterPub[prefix:gsub("_$", "")] then
            table.insert(dlg, "add_button|" .. prefix .. "pub_off|`4Disable Only Unlocked|0|0|0|")
        else
            table.insert(dlg, "add_button|" .. prefix .. "pub_on|`2Show Only Unlocked|0|0|0|")
        end
        table.insert(dlg, "add_spacer|small|")
    end
    if #data > 0 then
        for i, d in ipairs(data) do
            local nm = tostring(d.fg)
            local info = getItemByID(d.fg)
            if info and info.name and info.name ~= "" then nm = info.name end

            if prefix == "disp_" then
                local itemd = "No Have Item"
                if d.owner and d.owner ~= 0 then
                    local hitms = getItemByID(d.owner)
                    if hitms and hitms.name and hitms.name ~= "" then
                        itemd = hitms.name
                    end
                end
                table.insert(dlg, "add_label_with_icon_button|small|`9" .. nm .. ": `0[" .. d.x .. "] `0[" .. d.y .. "] `4- `2"..itemd.."|left|" .. d.fg .. "|" .. prefix .. i .. "|")
            else
                table.insert(dlg, "add_label_with_icon_button|small|`9" .. nm .. ": `0[" .. d.x .. "] `0[" .. d.y .. "]|left|" .. d.fg .. "|" .. prefix .. i .. "|")
            end
        end
    else
        table.insert(dlg, "add_label|`4" .. emptyMsg .. "|")
    end

    table.insert(dlg, "end_dialog|" .. dlgName .. "|Close|OK|")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

local function showVaultList()
    showList("vault_hack", "Safe Vault Bypass", "8878", vault, "vault_",
        "No Safe Vault found.", nil, {
            "add_label_with_icon|small|`7Item to Bypass: `9" .. ((getItemByID(vault_itemid) or {}).name or tostring(vault_itemid)) .. "|left|8878|",
            "add_item_picker|selecttarget|`wChoose Targ et Item``|Choose the target item!|",
        })
end

local function showMagnetDlg()
    magnet()
    local dlg = {}
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "add_label_with_icon|big|Extract-O-Snap Exploit|left|6140|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_smalltext|Requires Extract-O-Snap, item must be in a public area.|")
    table.insert(dlg, "add_text_input|mag_search|Search drops :|" .. magSearch .. "|50|")
    table.insert(dlg, "add_button|mag_search_apply|`2Search / Refresh|0|0|0|")
    table.insert(dlg, "add_spacer|small|")
    local qraw = magSearch:gsub("^%s+", ""):gsub("%s+$", "")
    local q = qraw:lower()
    local qid = tonumber(qraw)
    local matched = 0
    local hiddenN = 0
    local list = {}
    if #maglist > 0 then
        for _, m in ipairs(maglist) do
            if mag_filter[m.id] then
                hiddenN = hiddenN + 1
            else
                local nm = tostring(m.id)
                local info = getItemByID(m.id)
                if info and info.name and info.name ~= "" then nm = info.name end
                if q == "" or nm:lower():find(q, 1, true) or (qid and m.id == qid) then
                    matched = matched + 1
                    list[#list + 1] = { m = m, nm = nm }
                end
            end
        end
    end
    local shown = 0
    local maxShow = 60
    for i = 1, math.min(#list, maxShow) do
        local e = list[i]
        shown = shown + 1
        table.insert(dlg, "add_label_with_icon_button|small|`9" .. e.nm .. " `7x" .. e.m.amount .. "|left|" .. e.m.id .. "|mag_" .. e.m.oid .. "|")
    end
    if #list > maxShow then
        table.insert(dlg, "add_label|small|`7... +" .. (#list - maxShow) .. " more, refine search.|")
    end
    if shown == 0 then
        if #maglist == 0 then
            table.insert(dlg, "add_label|`4No drops in this world.|")
        elseif q ~= "" and matched == 0 then
            table.insert(dlg, "add_label|`4No match for '" .. qraw .. "'.|")
        else
            table.insert(dlg, "add_label|`4All drops hidden by object filter.|")
        end
    end
    table.insert(dlg, "add_label|`9Drops: `2" .. shown .. " `7/ `2" .. #maglist .. " `7hidden: `4" .. hiddenN .. "|")
    table.insert(dlg, "end_dialog|mag_list|Close|OK|")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

local function magFilterCount()
    local n = 0
    for _ in pairs(mag_filter) do n = n + 1 end
    return n
end

local function showObjFilterDlg()
    magnet()
    local byId = {}
    for _, m in ipairs(maglist) do
        if m.id and m.id > 0 then
            local e = byId[m.id]
            if e then e.amount = e.amount + m.amount
            else byId[m.id] = { id = m.id, amount = m.amount } end
        end
    end
    for id in pairs(mag_filter) do
        if not byId[id] then byId[id] = { id = id, amount = 0 } end
    end
    local hidden, active = {}, {}
    for _, e in pairs(byId) do
        if mag_filter[e.id] then table.insert(hidden, e)
        else table.insert(active, e) end
    end
    local function byIdSort(a, b) return a.id < b.id end
    table.sort(hidden, byIdSort)
    table.sort(active, byIdSort)

    local dlg = {}
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "set_default_color|`9")
    table.insert(dlg, "add_label_with_icon|big|`wObject Filter (Magnet)|left|6140|")
    table.insert(dlg, "add_smalltext|`7Click item to hide/show it from magnet list.|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label|`4-- Hidden from Magnet (`w" .. #hidden .. "`4) --`|")
    if #hidden > 0 then
        for _, e in ipairs(hidden) do
            local nm = tostring(e.id)
            local info = getItemByID(e.id)
            if info and info.name and info.name ~= "" then nm = info.name end
            table.insert(dlg, "add_button_with_icon|mag_flt_unh_" .. e.id .. "|`4" .. nm .. "|frame|" .. e.id .. "|" .. e.amount .. "|")
        end
        table.insert(dlg, "add_button_with_icon||END_LIST|noflags|0||")
    else
        table.insert(dlg, "add_label|`7(none)|")
    end
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label|`2-- Visible in Magnet (`w" .. #active .. "`2) --`|")
    if #active > 0 then
        for _, e in ipairs(active) do
            local nm = tostring(e.id)
            local info = getItemByID(e.id)
            if info and info.name and info.name ~= "" then nm = info.name end
            table.insert(dlg, "add_button_with_icon|mag_flt_hid_" .. e.id .. "|`2" .. nm .. "|frame|" .. e.id .. "|" .. e.amount .. "|")
        end
        table.insert(dlg, "add_button_with_icon||END_LIST|noflags|0||")
    else
        table.insert(dlg, "add_label|`4no drops in this world|")
    end
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_button|mag_filter_clear|`4Reset Filter|noflags|0|0|")
    table.insert(dlg, "end_dialog|mag_filter_dlg|Close|Back|")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

local function getPlayerTilePos()
    local me = getLocal()
    if not me or not me.pos then return nil, nil end
    return math.floor(me.pos.x / 32), math.floor(me.pos.y / 32)
end

local function makeWorldName()
    local chars = (h_typ == "wn") and "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" or "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local nlen = #h_name
    if h_len < 1 or nlen > 24 then return nil end
    local function randChars(n)
        local s = ""
        for i = 1, n do
            local r = math.random(1, #chars)
            s = s .. chars:sub(r, r)
        end
        return s
    end
    local world = ""
    if h_pos == "mid" then
        if h_len <= nlen or h_len > 24 then return nil end
        local space = h_len - nlen
        local half = math.floor(space / 2)
        world = randChars(half) .. h_name .. randChars(space - half)
    elseif h_pos == "front" then
        if h_len + nlen > 24 or h_len + nlen < 1 then return nil end
        world = h_name .. randChars(h_len)
    else
        if h_len + nlen > 24 or h_len + nlen < 1 then return nil end
        world = randChars(h_len) .. h_name
    end
    return world
end

local function showFinderSetup()
    local dlg = "set_border_color|112,86,191,255\n"
        .. "set_bg_color|43,34,74,200\n"
        .. "set_default_color|`o\n"
        .. "add_label_with_icon|big|Finder Setup|left|11218|\n"
        .. "add_text_input|world_l|World Length|" .. h_len .. "|3|\n"
        .. "add_text_input|world_t|World Type (nn/wn)|" .. h_typ .. "|3|\n"
        .. "add_text_input|world_n|Set World|" .. h_name .. "|12|\n"
        .. "add_text_input|world_dly|Delay (ms)|" .. h_delay .. "|6|\n"
        .. "add_text_input|world_p|Position (front/mid/end)|" .. h_pos .. "|5|\n"
        .. "end_dialog|set_find_world|Cancel|OK|"
    sendVariant({ [0] = "OnDialogRequest", [1] = dlg }, -1, 0)
end

local function showHelpDlg()
    local dlg = {}
    table.insert(dlg, "set_border_color|112,86,191,255")
    table.insert(dlg, "set_bg_color|43,34,74,200")
    table.insert(dlg, "add_label_with_icon|big|`w[Burem] Premium Menu|left|9380|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label_with_icon|big|`wInformation CLient|left|1400|")
    table.insert(dlg, "add_label_with_icon|small|`9Discord ID: `4" .. tostring((discordids ~= "" and discordids) or discordid or "-") .. "|left|14358|")
    table.insert(dlg, "add_label_with_icon|small|`9Discord Username: `9" .. tostring(discordname ~= "" and discordname or "-") .. "|left|1280|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label_with_icon|big|`wInformation Script|left|9222|")
    table.insert(dlg, "add_label_with_icon|small|`9Creator: `5Cicippetani & Burnism|left|242|")
    table.insert(dlg, "add_label_with_icon|small|`9Discord Server: `2https://discord.gg/yMBDMA5grc|left|482|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label_with_icon|big|`wCommands|left|9436|")
    table.insert(dlg, "add_label_with_icon|small|`2/display `9- Display Block list|left|2946|")
    table.insert(dlg, "add_label_with_icon|small|`2/shelf `9- Display Shelf list|left|3794|")
    table.insert(dlg, "add_label_with_icon|small|`2/mannq `9- Mannequin list|left|1420|")
    table.insert(dlg, "add_label_with_icon|small|`2/pmaker `9- Path Marker list|left|1684|")
    table.insert(dlg, "add_label_with_icon|small|`2/vault `9- Safe Vault list|left|8878|")
    table.insert(dlg, "add_label_with_icon|small|`2/gaia `9- Gaia Beacon list|left|6946|")
    table.insert(dlg, "add_label_with_icon|small|`2/ut `9- Unstable Tesseract list|left|6948|")
    table.insert(dlg, "add_label_with_icon|small|`2/magnet `9- Magnet / Extract-O-Snap|left|6140|")
    table.insert(dlg, "add_label_with_icon|small|`2/check `9- World lock checker|left|7188|")
    table.insert(dlg, "add_label_with_icon|small|`2/set `9- Finder setup|left|11218|")
    table.insert(dlg, "add_label_with_icon|small|`2/manual `9- Join random world|left|3802|")
    table.insert(dlg, "add_label_with_icon|small|`2/start `9- Auto hunt random world|left|3802|")
    table.insert(dlg, "add_label_with_icon|small|`2/cekvend `9- Vending checker|left|9268|")
    table.insert(dlg, "add_label_with_icon|small|`2/vendfinder `9- Vend Finder (global search)|left|10024|")
    table.insert(dlg, "add_label_with_icon|small|`2/vdeals `9- Vend Deals (latest deals)|left|2978|")
    table.insert(dlg, "add_label_with_icon|small|`2/bf `9- Bruteforce ID|left|762|")
    table.insert(dlg, "add_label_with_icon|small|`2/wordlist `9- Wordlist Editor (tambah massal)|left|1366|")
    table.insert(dlg, "add_label_with_icon|small|`2/setsave `9- Set 3 world save (namaWorld:id)|left|3802|")
    table.insert(dlg, "add_label_with_icon|small|`2/save1-3 `9- Langsung join world save|left|3802|")
    table.insert(dlg, "add_label_with_icon|small|`2/menu `9- This help menu|left|2422|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "end_dialog|helpmenu|Close||")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

-- ===== Simple Vend (view only, no findPath) =====
local vendAll = {}
local vendFilter = ""
local vendShown = {}
local vendPage = 1
local CEK_PAGE_SIZE = 30

local function scanVends()
    local w = getWorld()
    if not w then return {} end
    local tiles = getTile()
    if not tiles then return {} end
    local buf = {}
    for _, t in pairs(tiles) do
        if t and (t.fg == 2978 or t.fg == 9268) then
            local e = getExtraTile(t.pos.x, t.pos.y)
            if e and e.valid then
                local itemid = tonumber(e.lastUpdate)
                if itemid and itemid > 0 then
                    local it = getItemByID(itemid)
                    if it then
                        local priceText
                        if e.owner < 0 then
                            priceText = tostring(-e.owner) .. "/WL"
                        else
                            priceText = tostring(e.owner) .. " WL Each"
                        end
                        buf[#buf + 1] = {
                            itemid = itemid,
                            x = t.pos.x, y = t.pos.y,
                            world = w.name,
                            name = it.name,
                            price = priceText,
                        }
                    end
                end
            end
        end
    end
    return buf
end

local function filterVends(list, keyword)
    if not keyword or keyword == "" then return list end
    keyword = keyword:lower()
    local out = {}
    for _, v in ipairs(list) do
        if v.name:lower():find(keyword, 1, true) then
            out[#out + 1] = v
        end
    end
    return out
end

local function showCekDialog()
    local w = getWorld()
    local wname = (w and w.name) or "-"
    local filtered = filterVends(vendAll, vendFilter)
    vendShown = filtered
    local tp = math.max(1, math.ceil(#filtered / CEK_PAGE_SIZE))
    if vendPage > tp then vendPage = tp end
    if vendPage < 1 then vendPage = 1 end
    local first = (vendPage - 1) * CEK_PAGE_SIZE + 1
    local last = math.min(vendPage * CEK_PAGE_SIZE, #filtered)
    local dlg = {}
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "add_label_with_icon|big|Vending Checker|left|9268|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label_with_icon|small|World: `9" .. wname .. "|left|3802|")
    table.insert(dlg, "add_label_with_icon|small|Total vend: `9" .. #vendAll .. "|left|2480|")
    table.insert(dlg, "add_label_with_icon|small|`7Page: `9" .. vendPage .. "`7/ `9" .. tp .. " `7(`9" .. first .. "`7-`9" .. last .. ")|left|2480|")
    table.insert(dlg, "add_text_input|cek_filter|Filter item :|" .. vendFilter .. "|64|")
    table.insert(dlg, "add_button|cek_apply|`2Search / Refresh|0|0|0|")
    table.insert(dlg, "add_spacer|small|")
    if #vendAll == 0 then
        table.insert(dlg, "add_label|`4No vend found in this world.|")
    elseif #filtered == 0 then
        table.insert(dlg, "add_label|`4No match for '" .. vendFilter .. "'.|")
    else
        for i = first, last do
            local v = filtered[i]
            table.insert(dlg, "add_label_with_icon_button|small|`0" .. v.name .. " `9" .. v.price .. " `7(" .. v.x .. "," .. v.y .. ")|left|" .. v.itemid .. "|cekvend_" .. i .. "|")
        end
        table.insert(dlg, "add_spacer|small|")
        if vendPage > 1 then
            table.insert(dlg, "add_button|cek_prev|`2<< Page " .. (vendPage - 1) .. "|0|0|0|")
        end
        if vendPage < tp then
            table.insert(dlg, "add_button|cek_next|`2Page " .. (vendPage + 1) .. " >>|0|0|0|")
        end
    end
    table.insert(dlg, "end_dialog|cek_vend|Close||")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

-- ===== Vend Finder (from vendfinder-new.lua) =====
local vfOpenDialog

local function vfInit()
local CFG = {
    API       = "https://vend.aping.cloud/vend/items",
    API_DEALS = "https://vend.aping.cloud/vend/deals",
    DISCORDID = "1327891399013699678",
    PASS      = "G6mKzXVCRkYtdMs0KEQLhGsN",
    TIMEOUT   = 90000,
    JOIN_LOCK = 900,
}

local THEME = "set_border_color|187,153,255,255\nset_bg_color|30,24,51,200\nset_default_color|`o"
local SPACER, EXIT = "add_spacer|small|", "add_quick_exit|"

local cache, keyword, err, lastJoin = {}, "", nil, 0
local sorting, accessible = 0, 2
local SORT_NAME = { "Low to High", "High to Low", "Recently Updated" }
local ACC_NAME  = { [0] = "Inaccessible", [1] = "Accessible", [2] = "Any" }
local frameList, frameKw = {}, ""
local deals, dealErr = {}, nil
local db, dbBusy = nil, false
local vfSerial = 0
local vfPage, VF_PAGE_SIZE = 1, 20

-- HELPERS
local function say(m) local ok = pcall(sendVariant, { [0] = "OnTextOverlay", [1] = "`9[VendFinder] `7" .. tostring(m) }) if not ok then print("[VendFinder] " .. tostring(m)) end end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function esc(s)  return (tostring(s or ""):gsub("[\r\n|]", " ")) end
local function enc(s)  return (tostring(s):gsub("[^%w%-%.%_%~]", function(c) return string.format("%%%02X", string.byte(c)) end)) end
local function dlg(l)
    local body = table.concat(l, "\n")
    local ok, e = pcall(sendVariant, { [0] = "OnDialogRequest", [1] = body }, -1, 0)
    if ok then return true end
    say("`4dlg: " .. tostring(e))
    local ok2, e2 = pcall(sendVariant, { [0] = "OnDialogRequest", [1] = body }, -1, 0)
    if not ok2 then say("`4dlg retry: " .. tostring(e2)) end
    return ok2
end
local function big(t)  return "add_label_with_icon|big|`w" .. t .. "|left|2978|" end
local function small(t) return "add_label_with_icon|small|" .. t .. "|left|2480|" end
local function note(t) return "add_smalltext|" .. t .. "|left|enable|" end
local function btn(id, t) return "add_button|" .. id .. "|" .. t .. "|noflags|0|0|" end
local function enddlg(name, ok) return "end_dialog|" .. name .. "|Close|" .. (ok or "") .. "|" end

local function price(mode, p)
    return tostring(p or 0) .. (tostring(mode):lower():find("each") and " each" or " /WL")
end

local function lockColor(l)
    l = tostring(l):lower()
    if l:find("worldlock") then return "`4" end
    if l:find("public") then return "`2" end
    return "`7"
end

local function fetch(url)
    local ok, res = pcall(makeRequest, url, "GET",
        { ["Content-Type"] = "application/json" }, "", CFG.TIMEOUT)

    if not ok then return {}, "error: " .. tostring(res) end
    if not res then return {}, "no response" end
    local fail = res.error or res.status_error or res.errorMessage
    if fail and tostring(fail) ~= "" then return {}, "http: " .. tostring(fail) end
    if not res.content or res.content == "" then return {}, "empty body" end

    local out, e, first = {}, nil, nil
    for line in tostring(res.content):gmatch("[^\r\n]+") do
        first = first or trim(line)
        e = e or line:match("^ERROR|(.*)$")
        local p = {}
        for f in line:gmatch("[^|]+") do p[#p + 1] = trim(f) end
        if #p >= 8 and tonumber(p[1]) then out[#out + 1] = p end
    end
    if #out == 0 and not e then e = "bad response: " .. tostring(first):sub(1, 120) end
    return out, e
end

local function api(path, extra)
    return fetch(path .. "?discordid=" .. CFG.DISCORDID .. "&pass=" .. CFG.PASS
        .. (extra or "") .. "&page=1")
end

local function matchName(kw)
    local words = {}
    for w in kw:gmatch("%S+") do words[#words + 1] = w:lower() end
    local out = {}
    for i = 1, #db, 2 do
        local nm = db[i + 1]:lower()
        local hit = true
        for _, w in ipairs(words) do
            if not nm:find(w, 1, true) then hit = false break end
        end
        if hit then
            out[#out + 1] = { db[i], db[i + 1] }
            if #out >= 300 then break end
        end
    end
    return out
end

local function buildDB()
    if db then return end
    dbBusy = true
    local t = {}
    for id = 0, 20000 do
        local ok, it = pcall(getItemByID, id)
        if ok and it and type(it.name) == "string" and it.name ~= "" then
            t[#t + 1] = id
            t[#t + 1] = it.name
        end
        if id % 500 == 0 then sleep(1) end
    end
    db = t
    dbBusy = false
end

local function pageRange(total)
    vfPage = 1
    return 1, total, 1
end

local function showFrame()
    local total = #frameList
    local first, last, pages = pageRange(total)

    local d = { THEME, big("Vend Finder") }
    table.insert(d, small("`9Keyword: `2" .. esc(frameKw) .. " `7- `9Found: `2" .. total
        .. " `7(page `9" .. vfPage .. "`7/`9" .. pages .. "`7)"))

    if total == 0 then
        table.insert(d, "add_label|`4No local item matches: " .. esc(frameKw) .. "|")
    else
        for i = first, last do
            local it = frameList[i]
            table.insert(d, string.format("add_button_with_icon|vfn_%d|`o%s|frame|%d|",
                i, esc(it[2]), it[1] ~= 0 and it[1] or 2978))
        end
        table.insert(d, "add_button_with_icon||END_LIST|noflags|0||")
    end

    table.insert(d, note("`7Click an item to send its name to the server"))
    table.insert(d, SPACER)
    if vfPage > 1 then table.insert(d, btn("vfn_prev", "`2<< Page " .. (vfPage - 1))) end
    if vfPage < pages then table.insert(d, btn("vfn_next", "`2Page " .. (vfPage + 1) .. " >>")) end
    table.insert(d, btn("vfback", "`7< Change keyword"))
    table.insert(d, enddlg("vendfinder_frame"))
    table.insert(d, EXIT)
    dlg(d)
end

local function showForm()
    dlg({ THEME, big("Vend Finder"), note("`7Search vending machines from the database"), SPACER,
        "add_text_input|vendsearch|Item / Item Name:|Dirt|32|",
        btn("vfsort_cycle", "`9Sorting: `2" .. SORT_NAME[sorting + 1]),
        btn("vfacc_cycle", "`9Accessible: `2" .. ACC_NAME[accessible]),
        SPACER,
        btn("vendsearch_btn", "`5Search"), SPACER,
        enddlg("vendfinder_search"), EXIT })
end

local function showList()
    local total = #cache
    local first, last, pages = pageRange(total)

    local d = { THEME, big("Vend Finder"),
        small("`9Keyword: `2" .. esc(keyword) .. " `7- `9Results: `2" .. total), SPACER }

    if err then table.insert(d, "add_label_with_icon|small|`c" .. esc(err) .. "|left|32|") end
    if total > 0 then
        table.insert(d, small("`7Page `9" .. vfPage .. "`7/`9" .. pages .. " `7(showing `9" .. first .. "`7-`9" .. last .. "`7)"))
    end
    table.insert(d, note("`7Click a row to join that world."))

    for i = first, last do
        local p = cache[i]
        table.insert(d, string.format(
            "add_label_with_icon_button|small|`0%s `2- `9%s `2%s `7(%s,%s) `6%s|left|%s|vf_%d|",
            esc(p[2]), price(p[7], p[6]), esc(p[3]),
            p[4] or -1, p[5] or -1, esc(p[9] or "-"), p[1], i))
    end

    table.insert(d, SPACER)
    if vfPage > 1 then table.insert(d, btn("vf_prev", "`2<< Page " .. (vfPage - 1))) end
    if vfPage < pages then table.insert(d, btn("vf_next", "`2Page " .. (vfPage + 1) .. " >>")) end
    table.insert(d, btn("vfback", "`7< Change keyword"))
    table.insert(d, enddlg("vendfinder_list"))
    table.insert(d, EXIT)
    dlg(d)
end

local function showDeals()
    local total = #deals
    local first, last, pages = pageRange(total)

    local d = { THEME, big("Vend Deals"), small("`7Deals: `9" .. total
        .. " `7(page `9" .. vfPage .. "`7/`9" .. pages .. "`7)"), SPACER }

    if dealErr then table.insert(d, "add_label_with_icon|small|`c" .. esc(dealErr) .. "|left|32|") end

    for i = first, last do
        local p = deals[i]
        table.insert(d, string.format(
            "add_label_with_icon_button|small|`0%s `2- `9%s `4[%s] `3%s %s `7%s|left|%s|vfdd_%d|",
            esc(p[2]), price(p[4], p[3]), esc(p[5]), esc(p[6]), p[7], esc(p[8]),
            p[1], i))
    end

    table.insert(d, SPACER)
    if vfPage > 1 then table.insert(d, btn("vd_prev", "`2<< Page " .. (vfPage - 1))) end
    if vfPage < pages then table.insert(d, btn("vd_next", "`2Page " .. (vfPage + 1) .. " >>")) end
    table.insert(d, btn("vdback", "`7< Back to Search"))
    table.insert(d, enddlg("venddeals_list"))
    table.insert(d, EXIT)
    dlg(d)
end

-- ACTIONS
function openFrame(kw)
    kw = trim(kw)
    if kw == "" then say("`4empty keyword") return showForm() end

    if not db then
        say("scanning item db .. (once)")
        local ok, e = pcall(buildDB)
        if not ok or not db then
            say("`4item db failed: " .. tostring(e))
            return showForm()
        end
        say("item db ready: " .. math.floor(#db / 2) .. " items")
    end

    frameKw, frameList = kw, matchName(kw)
    vfPage = 1
    say(#frameList == 0 and ("`4no local item: " .. kw) or ("`9" .. #frameList .. " local matches"))
    showFrame()
end

function doSearch(kw)
    kw = trim(kw)
    if kw == "" then say("`4empty keyword") return showForm() end

    cache, keyword, err = {}, kw, nil
    vfPage = 1
    say("search `2" .. kw .. "")
    cache, err = api(CFG.API, "&items=" .. enc(kw) .. "&sorting=" .. sorting .. "&accessible=" .. accessible)

    if #cache == 0 then
        err = err or ("no vending for: " .. kw)
        say("`4" .. err)
        return showList()
    end

    table.sort(cache, function(a, b)
        local pa, pb = tonumber(a[6]) or 0, tonumber(b[6]) or 0
        return pa == pb and tonumber(a[1]) < tonumber(b[1]) or pa < pb
    end)
    say("got " .. #cache .. " results")
    showList()
end

function showDealsList()
    deals, dealErr = {}, nil
    vfPage = 1
    say("fetching latest deals ..")
    deals, dealErr = api(CFG.API_DEALS)
    dealErr = dealErr or (#deals == 0 and "no deals" or nil)
    say(dealErr and ("`4" .. dealErr) or ("got " .. #deals .. " deals"))
    showDeals()
end

local function joinWorld(name)
    if not name or name == "" or name == "?" then return say("`4unknown world") end
    local now = getCurrentTimeInternal()
    if now - lastJoin < CFG.JOIN_LOCK then return say("`4cooldown, wait a bit") end
    lastJoin = now
    say("join `b" .. name .. "`")
    local target = name
    vfSerial = vfSerial + 1
    runThread(function()
        sleep(150)
        sendPacket(3, "action|join_request\nname|" .. target .. "\ninvitedWorld|0")
    end, "vfjoin" .. tostring(vfSerial))
end

local vq, vqBusy = {}, false

local function guarded(fn)
    if #vq >= 6 then
        say("`4too many queued, ignored")
        return
    end
    vq[#vq + 1] = fn
    if vqBusy then say("`7busy, queued ..") return end
    vqBusy = true
    vfSerial = vfSerial + 1
    runThread(function()
        local guard = 0
        while #vq > 0 and guard < 6 do
            guard = guard + 1
            local job = table.remove(vq, 1)
            local ok, e = pcall(job)
            if not ok then say("`4error: " .. tostring(e)) end
            sleep(20)
        end
        for i = #vq, 1, -1 do vq[i] = nil end
        vqBusy = false
    end, "vfwork" .. tostring(vfSerial))
end

-- HOOK
AddHook("OnTextPacket", "VendFinderCmd", function(_, p)
    if type(p) ~= "string" then return end
    local txt = p:match("action|input\n|text|(.*)")
    if not txt then return end

    local raw = trim(txt):lower()
    if raw:find("^/vdeals") then
        guarded(showDealsList)
        return true
    end
    if raw:find("^/vendfinder") then
        local kw = trim(txt:sub(#"/vendfinder" + 1))
        if kw ~= "" then guarded(function() openFrame(kw) end)
        else showForm() end
        return true
    end
end)

AddHook("OnTextPacket", "VendFinderAction", function(_, p)
    if type(p) ~= "string" or not p:find("action|dialog_return") then return end
    local function hit(id) return p:find("buttonClicked|" .. id) end

    if p:find("dialog_name|vendfinder_list") then
        if hit("vfback") then guarded(function() openFrame(keyword) end) return true end
        if hit("vf_prev") then if vfPage > 1 then vfPage = vfPage - 1 end showList() return true end
        if hit("vf_next") then vfPage = vfPage + 1 showList() return true end
        local i = tonumber(p:match("buttonClicked|vf_(%d+)"))
        if i then joinWorld(cache[i] and cache[i][3]) end
        return true
    end

    if p:find("dialog_name|venddeals_list") then
        if hit("vdback") then showForm() return true end
        if hit("vd_prev") then if vfPage > 1 then vfPage = vfPage - 1 end showDeals() return true end
        if hit("vd_next") then vfPage = vfPage + 1 showDeals() return true end
        local i = tonumber(p:match("buttonClicked|vfdd_(%d+)"))
        if i then joinWorld(deals[i] and deals[i][6]) end
        return true
    end

    if p:find("dialog_name|vendfinder_frame") then
        if hit("vfback") then showForm() return true end
        if hit("vfn_prev") then if vfPage > 1 then vfPage = vfPage - 1 end showFrame() return true end
        if hit("vfn_next") then vfPage = vfPage + 1 showFrame() return true end
        local i = tonumber(p:match("buttonClicked|vfn_(%d+)"))
        local it = i and frameList[i]
        if it then
            guarded(function() doSearch(it[2]) end)
        end
        return true
    end

    if p:find("dialog_name|vendfinder_search") then
        if hit("vfsort_cycle") then sorting = (sorting + 1) % 3 showForm() return true end
        if hit("vfacc_cycle") then accessible = (accessible + 2) % 3 showForm() return true end
    end

    if hit("vendsearch_btn") then
        local kw = trim(p:match("vendsearch|([^|\n]*)") or p:match("vendsearch%|'([^|]*)'") or "")
        if kw == "" then say("`4empty input") return showForm() end
        guarded(function() openFrame(kw) end)
        return true
    end
end)
vfOpenDialog = showForm
end

vfInit()

local function huntLoop()
    if hunt_run then
        ovlay("Hunting already running. Open Friends to stop.")
        return
    end
    hunt_run = true
    ovlay("Auto hunting started.")
    runThread(function()
        while hunt_run do
            local world = makeWorldName()
            if not world then
                ovlay("Invalid config. Check /set.")
                hunt_run = false
                break
            end
            local tries = 1
            while visited[world] and tries < 20 do
                world = makeWorldName()
                if not world then break end
                tries = tries + 1
            end
            if not world then
                ovlay("Invalid config. Check /set.")
                hunt_run = false
                break
            end
            visited[world] = true
            last_visit = world
            addVisit(world)
            sendPacket(3, "action|join_request\nname|" .. world .. "\ninvitedWorld|0")
            ovlay("Joining " .. world)
            sleep(h_delay > 0 and h_delay or 2000)
        end
    end, "hunting")
end

function sendBuremPortal()
    local hideLbl = hide_world and "`2ON" or "`4OFF"
    local friends = "set_border_color|187,153,255,255\n"
        .. "set_bg_color|30,24,51,200\n"
        .. "set_default_color|`9\n"
        .. "add_label_with_icon|big|`wBurem Leak Portal`|left|2422|\n"
        .. "add_spacer|small|\n"
        .. "add_button|Buremmenu|`wBurem Setting`|noflags|0|0|\n"
        .. "add_button|about|`wAbout script`|noflags|0|0|\n"
        .. "add_button|visit|`wVisited Worlds (`2" .. #visit_history .. "/5`w)|noflags|0|0|\n"
        .. "add_button|hide_world|`wHide World: " .. hideLbl .. "|noflags|0|0|\n"
        .. "add_button|ent_check|`wEnterance Check: " .. (ent_show and "`2ON" or "`4OFF") .. "|noflags|0|0|\n"
        .. "add_button|nick_setup|`wNickname Setup|noflags|0|0|\n"
        .. "add_spacer|small|\n"
        .. "add_label_with_icon|big|`wSocial Portal`|left|1366|\n"
        .. "add_spacer|small|\n"
        .. "add_button|showfriend|`wShow Friends`|noflags|0|0|\n"
        .. "add_button|communityhub|`wCommunity Hub`|noflags|0|0|\n"
        .. "add_button|show_apprentices|`wShow Apprentices`|noflags|0|0|\n"
        .. "add_button|showguild|`wCreate Guild`|noflags|0|0|\n"
        .. "add_button|trade_history|`wTrade History`|noflags|0|0|\n"
        .. "add_quick_exit|\n"
        .. "end_dialog|socialportal|Close|Back|"
    sendVariant({ [0] = "OnDialogRequest", [1] = friends }, -1, 0)
end

AddHook("OnVarlist", "my_social_portal_hook", function(variant)
    if variant and variant[0] == "OnDialogRequest" and type(variant[1]) == "string" then
        if variant[1]:find("Friends") or variant[1]:find("add_label_with_icon|big|Friends") then
            sendBuremPortal()
            return true
        end
    end
end)

-- ===== Label Checker (scan TileExtra.label) =====
local label_results = {}
local label_page = 1
local LABEL_PAGE_SIZE = 15
local label_esp = nil -- {x, y, label, world}

local function labelClean(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("[|\r\n]", " ")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function labelIconName(id)
    if not id or id == 0 then return "None" end
    local info = getItemByID(id)
    if info and info.name and info.name ~= "" then return info.name end
    return tostring(id)
end

local function labelScan()
    local out = {}
    local tiles = getTile()
    if not tiles then return out end
    for _, t in pairs(tiles) do
        if t and t.pos then
            local e = getExtraTile(t.pos.x, t.pos.y)
            if e and e.valid then
                local lb = labelClean(e.label)
                if lb ~= "" then
                    table.insert(out, {
                        x = t.pos.x, y = t.pos.y,
                        fg = t.fg or 0, bg = t.bg or 0,
                        label = lb,
                    })
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    return out
end

local function labelTotalPages()
    local n = math.ceil(#label_results / LABEL_PAGE_SIZE)
    if n < 1 then n = 1 end
    return n
end

local function labelRenderDlg()
    local w = getWorld()
    local tp = labelTotalPages()
    if label_page > tp then label_page = tp end
    if label_page < 1 then label_page = 1 end

    local dlg = {}
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "add_label_with_icon|big|`9Label Checker|left|6140|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_label_with_icon|small|`7World: `9" .. ((w and w.name) or "-") .. "|left|3802|")
    table.insert(dlg, "add_label_with_icon|small|`7Found: `9" .. #label_results .. " `7| Page `9" .. label_page .. "/" .. tp .. "|left|2480|")
    table.insert(dlg, "add_spacer|small|")

    if #label_results == 0 then
        table.insert(dlg, "add_label|`4No tile with label found in this world.|")
    else
        local first = (label_page - 1) * LABEL_PAGE_SIZE + 1
        local last = math.min(label_page * LABEL_PAGE_SIZE, #label_results)
        for i = first, last do
            local d = label_results[i]
            local icon = (d.fg > 0) and d.fg or ((d.bg > 0) and d.bg or 2480)
            table.insert(dlg, string.format(
                "add_label_with_icon_button|small|`7(%d,%d) `9%s`e: `7%s|left|%d|lb_%d|",
                d.x, d.y, labelIconName(icon), d.label, icon, i
            ))
        end
        table.insert(dlg, "add_spacer|small|")
        if label_page > 1 then
            table.insert(dlg, "add_button|lb_prev|`2<< Page " .. (label_page - 1) .. "|0|0|0|")
        end
        if label_page < tp then
            table.insert(dlg, "add_button|lb_next|`2Page " .. (label_page + 1) .. " >>|0|0|0|")
        end
    end

    table.insert(dlg, "end_dialog|label_list|Close||")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

local function showLabelDlg()
    label_results = labelScan()
    label_page = 1
    labelRenderDlg()
    if #label_results > 0 then
        ovlay(#label_results .. " label found.")
    else
        ovlay("No label in this world.")
    end
end

AddHook("OnTextPacket", "BuremLabelDlg", function(_, pkt)
    if type(pkt) ~= "string" then return false end
    if not pkt:find("dialog_name|label_list") then return false end

    if pkt:find("buttonClicked|lb_next") then
        label_page = label_page + 1
        labelRenderDlg()
        return true
    end
    if pkt:find("buttonClicked|lb_prev") then
        label_page = label_page - 1
        labelRenderDlg()
        return true
    end

    local idx = tonumber(pkt:match("buttonClicked|lb_(%d+)"))
    if not idx then return true end
    local d = label_results[idx]
    if not d then ovlay("Data not found.") return true end

    local w = getWorld()
    label_esp = { x = d.x, y = d.y, label = d.label, world = (w and w.name) or "" }
    ovlay("ESP -> (" .. d.x .. "," .. d.y .. ") " .. d.label)
    logToConsole("`b[Label] `w(" .. d.x .. "," .. d.y .. ") `e" .. d.label)
    return true
end)

AddHook("OnRender", "BuremLabelEsp", function()
    if not label_esp then return end
    local w = getWorld()
    local wname = (w and w.name) or ""
    if wname == "" or wname:upper() == "EXIT"
        or (label_esp.world ~= "" and wname:upper() ~= label_esp.world:upper()) then
        label_esp = nil
        return
    end
    local me = getLocal()
    if not me or not me.pos then return end
    local ok = pcall(function()
        local s = worldToScreen(label_esp.x * 32, label_esp.y * 32)
        local e = worldToScreen(label_esp.x * 32 + 32, label_esp.y * 32 + 32)
        ImGui.BG:AddRectFilled(s, e, 1677810493, 0.0, 0)
        ImGui.BG:AddRect(s, e, 4294950784, 0.0, 3.0)
        local p_screen = worldToScreen(me.pos.x + 9, me.pos.y - 20)
        ImGui.BG:AddLine(p_screen, s, 4294950784, 2.0)
    end)
    if not ok then label_esp = nil end
end)
-- ===== end Label Checker =====

-- ===== Nickname Setup (ported from name-var.lua) =====
local nv_on = false
local nv_hide = false
local nv_tile = false
local nv_name = ""
local nv_base = nil
local nv_last = ""
local nv_busy = false

local function nvStripCoord(s)
    s = tostring(s or "")
    s = s:gsub("%s*`9%[%-?%d+,%-?%d+%]", "")
    return s
end

local function nvGetBase()
    if nv_base and nv_base ~= "" then return nv_base end
    local ok, me = pcall(getLocal)
    if ok and me and me.name and me.name ~= "" then
        local n = nvStripCoord(me.name)
        if n ~= "" then
            nv_base = n
            return n
        end
    end
    return nil
end

local function nvBuildTag()
    if nv_hide then return "`bHidden" end
    local nm = nv_name
    if nm == nil or nm == "" then nm = nvGetBase() end
    if not nm or nm == "" then return "" end
    if nv_tile then
        local ok, me = pcall(getLocal)
        if ok and me and me.pos then
            local tx = math.floor(me.pos.x / 32)
            local ty = math.floor(me.pos.y / 32)
            return nm .. " `9[" .. tx .. "," .. ty .. "]``"
        end
    end
    return nm
end

local function nvApply(force)
    if nv_busy then return end
    if not nv_on then return end
    local tag = nvBuildTag()
    if not force and tag == nv_last then return end
    local ok, me = pcall(getLocal)
    if not ok or not me then return end
    nv_busy = true
    nv_last = tag
    local netid = tonumber(me.netid or me.netId) or -1
    sendVariant({ [0] = "OnNameChanged", [1] = tag }, netid)
    nv_busy = false
end

local function nvRestore()
    local ok, me = pcall(getLocal)
    if not ok or not me then return end
    local restored = nvGetBase() or ""
    nv_last = restored
    local netid = tonumber(me.netid or me.netId) or -1
    sendVariant({ [0] = "OnNameChanged", [1] = restored }, netid)
end

function showNickSetup()
    local dlg = {}
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "set_default_color|`9")
    table.insert(dlg, "add_label_with_icon|big|`wNickname Setup|left|242|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_checkbox|nv_on|`wEnabled|" .. (nv_on and "1" or "0") .. "|")
    table.insert(dlg, "add_checkbox|nv_hide|`wHide Nickname|" .. (nv_hide and "1" or "0") .. "|")
    table.insert(dlg, "add_checkbox|nv_tile|`wShow Tile In Nickname|" .. (nv_tile and "1" or "0") .. "|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_text_input|nv_name|Nickname :|" .. nv_name .. "|24|")
    table.insert(dlg, "add_spacer|small|")
    local base = nvGetBase() or "-"
    local cur
    if not nv_on then cur = "`4OFF"
    elseif nv_hide then cur = "`4HIDDEN"
    else cur = "`2" .. (nv_name ~= "" and nv_name or base) end
    table.insert(dlg, "add_label_with_icon|small|`7Base name: `9" .. base .. "|left|242|")
    table.insert(dlg, "add_label_with_icon|small|`7Current tag: " .. cur .. "|left|1280|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "end_dialog|nick_setup|Close|Save|")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

local save_slots = { "", "", "" }

local function saveParse(v)
    v = tostring(v or ""):gsub("[|\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if v == "" then return nil end
    local w, id = v:match("^([^:]+):(.+)$")
    if w then
        w = w:gsub("%s+$", "")
        id = id:gsub("^%s+", ""):gsub("%s+$", "")
    else
        w, id = v, nil
    end
    if w == "" then return nil end
    return w, id
end

local function saveJoin(n)
    local w, id = saveParse(save_slots[n])
    if not w then ovlay("Save " .. n .. " empty. Set first /setsave.") return end
    local pkt
    if id and id ~= "" then
        pkt = "action|join_request\nname|" .. w .. "|" .. id .. "\ninvitedWorld|0"
    else
        pkt = "action|join_request\nname|" .. w .. "\ninvitedWorld|0"
    end
    addVisit(w)
    sendPacket(3, pkt)
    ovlay("Entering World Save")
end

local function showSaveDialog()
    local dlg = {}
    table.insert(dlg, "set_border_color|187,153,255,255")
    table.insert(dlg, "set_bg_color|30,24,51,200")
    table.insert(dlg, "set_default_color|`9")
    table.insert(dlg, "add_label_with_icon|big|`wWorld Save|left|3802|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_smalltext|Format: worldName:id")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "add_text_input|save1|Save 1|" .. save_slots[1] .. "|64|")
    table.insert(dlg, "add_text_input|save2|Save 2|" .. save_slots[2] .. "|64|")
    table.insert(dlg, "add_text_input|save3|Save 3|" .. save_slots[3] .. "|64|")
    table.insert(dlg, "add_spacer|small|")
    table.insert(dlg, "end_dialog|save_setup|Close|Save|")
    sendVariant({ [0] = "OnDialogRequest", [1] = table.concat(dlg, "\n") }, -1, 0)
end

AddHook("OnJoinWorld", "BuremNameVarJoin", function()
    if not nv_on then return end
    nvApply(true)
    runThread(function()
        for _ = 1, 6 do
            sleep(350)
            if not nv_on then return end
            nvApply(true)
        end
    end, "buremnickjoin")
end)

AddHook("OnRender", "BuremNameVarTick", function()
    if not espInWorld() then return end
    nvApply()
end)

AddHook("OnVarlist", "BuremNameVarWatch", function(var)
    if not var or var[0] ~= "OnNameChanged" then return false end
    if not nv_on then return false end
    if not espInWorld() then return false end
    local incoming = tostring(var[1] or "")
    if incoming == "" then return false end
    local b = nvGetBase()
    if not b or nvStripCoord(incoming) ~= b then return false end
    if nvBuildTag() == b then return false end
    runThread(function() sleep(120) nvApply(true) end, "buremnickreset")
    return false
end)
-- ===== end Nickname Setup =====

function showBuremSetting()
    local dlg = "set_border_color|187,153,255,255\n"
        .. "set_bg_color|30,24,51,200\n"
        .. "set_default_color|`9\n"
        .. "add_label_with_icon|big|`wBurem Leak Setting Panel`|left|9222|\n"
        .. "add_spacer|small|\n"
        .. "add_label_with_icon|small|`9DiscordID: `2"..discordids.."|left|14358|\n"
        .. "add_label_with_icon|small|`5DiscordName: `9"..discordname.."|left|9422|\n"
        .. "add_spacer|small|\n"
        .. "add_label_with_icon|small|`9Creator: `5Cicippetani & Burnism|left|242|\n"
        .. "add_label_with_icon|small|`9Discord Server: `2https://discord.gg/yMBDMA5grc|left|482|\n"
        .. "add_spacer|small|\n"
        .. "add_label|`2-- Target & Extraction --`|\n"
        .. "add_button_with_icon|target_display|`wDisplay Block|staticBlueFrame|2946||\n"
        .. "add_button_with_icon|target_shelf|`wDisplay Shelf|staticBlueFrame|3794||\n"
        .. "add_button_with_icon|target_mannq|`wMannequin|staticBlueFrame|10078||\n"
        .. "add_button_with_icon|target_pmaker|`wPath Marker|staticBlueFrame|1684||\n"
        .. "add_button_with_icon|target_vault|`wSafe Vault|staticBlueFrame|8878||\n"
        .. "add_button_with_icon|target_gaia|`wGaia Beacon|staticBlueFrame|6946||\n"
        .. "add_button_with_icon|target_ut|`wUnstable Tesseract|staticBlueFrame|6948||\n"
        .. "add_button_with_icon|extract|`wExtract-O-Snap|staticBlueFrame|6140||\n"
        .. "add_button_with_icon|iddoor|`wID Door Leak|staticBlueFrame|8||\n"
        .. "add_button_with_icon|hunting|`wWorld Finder|staticBlueFrame|3802||\n"
        .. "add_button_with_icon|cheker|`wLock Checker|staticBlueFrame|7188||\n"
        .. "add_button_with_icon|cekvend|`wVending Checker|staticBlueFrame|9268||\n"
        .. "add_button_with_icon|bf|`wBruteforce ID|staticBlueFrame|762||\n"
        .. "add_button_with_icon|esp|`wESP Settings|staticBlueFrame|306||\n"
        .. "add_button_with_icon|mag_filter|`wObject Filter|staticBlueFrame|112||\n"
        .. "add_button_with_icon|label_check|`wLabel Checker|staticBlueFrame|12||\n"
        .. "add_button_with_icon|vendfinder|`wVend Finder|staticBlueFrame|2978||\n"
        .. "add_custom_break|\n"
        .. "add_button|visit|`wVisited Worlds (`2" .. #visit_history .. "/5`w)|noflags|0|0|\n"
        .. "add_button|hide_world|`wHide World: " .. (hide_world and "`2ON" or "`4OFF") .. "|noflags|0|0|\n"
        .. "add_button|ent_check|`wEntrance Check: " .. (ent_show and "`2ON" or "`4OFF") .. "|noflags|0|0|\n"
        .. "add_spacer|small|\n"
        .. "add_custom_break|\n"
        .. "add_button|save_Burem|`2Save Settings`|noflags|0|0|\n"
        .. "add_spacer|small|\n"
        .. "add_quick_exit|\n"
        .. "end_dialog|Buremmenu|Back|OK|"
    sendVariant({ [0] = "OnDialogRequest", [1] = dlg }, -1, 0)
end

function showEspSetting()
    local dlg = "set_border_color|187,153,255,255\n"
        .. "set_bg_color|30,24,51,200\n"
        .. "set_default_color|`9\n"
        .. "add_label_with_icon|big|`wESP Settings|left|306|\n"
        .. "add_spacer|small|\n"
        .. "add_label|`2-- Draw Category --`|\n"
        .. "add_checkbox|esp_path|`wESP Pathmaker|" .. (esp_show.pathmaker and "1" or "0") .. "|\n"
        .. "add_checkbox|esp_disp|`wESP Display Block|" .. (esp_show.display and "1" or "0") .. "|\n"
        .. "add_checkbox|esp_shelf|`wESP Display Shelf|" .. (esp_show.shelf and "1" or "0") .. "|\n"
        .. "add_checkbox|esp_mannq|`wESP Mannequin|" .. (esp_show.mannq and "1" or "0") .. "|\n"
        .. "add_checkbox|esp_gaia|`wESP Gaia|" .. (esp_show.gaia and "1" or "0") .. "|\n"
        .. "add_checkbox|esp_ut|`wESP UT|" .. (esp_show.ut and "1" or "0") .. "|\n"
        .. "add_spacer|small|\n"
        .. "add_label|`2-- Filter --`|\n"
        .. "add_button|esp_pub|" .. (esp_only_public and "`2Show Only Public" or "`4Disable Only Public") .. "|noflags|0|0|\n"
        .. "add_button|esp_lockarea|" .. (esp_hide_lock_area and "`4Hide Inside Lock Area" or "`2Hide Inside Lock Area: OFF") .. "|noflags|0|0|\n"
        .. "add_spacer|small|\n"
        .. "add_quick_exit|\n"
        .. "end_dialog|esp_menu|Close|Continue|"
    sendVariant({ [0] = "OnDialogRequest", [1] = dlg }, -1, 0)
end

AddHook("OnTextPacket", "Burem_setting_hook", function(_, pkt)
    if type(pkt) == "string" then
        if pkt:find("dialog_name|socialportal") then
            if pkt:find("buttonClicked|Buremmenu") then
                showBuremSetting()
                return true
            end
            if pkt:find("buttonClicked|visit") then
                showVisitDlg()
                return true
            end
            if pkt:find("buttonClicked|hide_world") then
                hide_world = not hide_world
                ovlay("Hide World " .. (hide_world and "enabled" or "disabled"))
                sendBuremPortal()
                return true
            end
            if pkt:find("buttonClicked|ent_check") then
                entToggle()
                sendBuremPortal()
                return true
            end
            if pkt:find("buttonClicked|mag_filter") then
                showObjFilterDlg()
                return true
            end
            if pkt:find("buttonClicked|nick_setup") then
                showNickSetup()
                return true
            end
        end
        if pkt:find("dialog_name|mag_filter_dlg") then
            local hid = tonumber(pkt:match("buttonClicked|mag_flt_hid_(%d+)"))
            if hid then
                mag_filter[hid] = true
                ovlay("Filter: hidden " .. hid)
                showObjFilterDlg()
                return true
            end
            local unh = tonumber(pkt:match("buttonClicked|mag_flt_unh_(%d+)"))
            if unh then
                mag_filter[unh] = nil
                ovlay("Filter: shown " .. unh)
                showObjFilterDlg()
                return true
            end
            if pkt:find("buttonClicked|mag_filter_save") then
                showMagnetDlg()
                return true
            end
            if pkt:find("buttonClicked|mag_filter_clear") then
                mag_filter = {}
                ovlay("Object filter reset")
                showObjFilterDlg()
                return true
            end
            return true
        end
    end
    return false
end)

AddHook("OnTextPacket", "Burem_go", function(_, pkt)
    if type(pkt) ~= "string" then return false end
    if pkt:find("dialog_name|esp_menu") then
        if pkt:find("esp_path|") or pkt:find("esp_disp|") or pkt:find("esp_shelf|")
            or pkt:find("esp_mannq|") or pkt:find("esp_gaia|") or pkt:find("esp_ut|") then
            applyEspFromPkt(pkt)
        end
        if pkt:find("buttonClicked|esp_pub") then
            esp_only_public = not esp_only_public
            espRescan()
            ovlay(esp_only_public and "ESP: Show Only Public" or "ESP: Only Public disabled")
            showEspSetting()
            return true
        end
        if pkt:find("buttonClicked|esp_lockarea") then
            esp_hide_lock_area = not esp_hide_lock_area
            espRescan()
            ovlay(esp_hide_lock_area and "ESP: Hide Inside Lock Area `2ON" or "ESP: Hide Inside Lock Area `4OFF")
            showEspSetting()
            return true
        end
        if not pkt:find("buttonClicked|") then
            return false
        end
        return true
    end
    if pkt:find("dialog_name|nick_setup") then
        local changed = false
        local nm = pkt:match("nv_name|([^|\n]*)")
        if nm ~= nil then
            nm = nm:gsub("[|\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if nm ~= nv_name then nv_name = nm changed = true end
        end
        local o = tonumber(pkt:match("nv_on|(%d)"))
        local turnedOff = false
        if o ~= nil and nv_on ~= (o == 1) then
            nv_on = (o == 1)
            turnedOff = not nv_on
            changed = true
        end
        local h = tonumber(pkt:match("nv_hide|(%d)"))
        if h ~= nil and nv_hide ~= (h == 1) then nv_hide = (h == 1) changed = true end
        local t = tonumber(pkt:match("nv_tile|(%d)"))
        if t ~= nil and nv_tile ~= (t == 1) then nv_tile = (t == 1) changed = true end
        if changed then
            if turnedOff then
                nvRestore()
                ovlay("Nickname spoof disabled.")
            else
                nvApply(true)
            end
        end
        if pkt:find("buttonClicked|save") then
            showNickSetup()
            return true
        end
        return true
    end
    if pkt:find("dialog_name|Buremmenu") then
        if pkt:find("buttonClicked|esp") then
            showEspSetting()
            return true
        end
        if pkt:find("buttonClicked|mag_filter") then
            showObjFilterDlg()
            return true
        end
        if pkt:find("buttonClicked|label_check") then
            showLabelDlg()
            return true
        end
        if pkt:find("buttonClicked|vendfinder") then
            vfOpenDialog()
            return true
        end
        if pkt:find("buttonClicked|target_display") then display_scan() attachPublicInfo(display) display_shown = filterPub.disp and onlyPublic(display) or display showList("display_hack", "Display Block Long Take", "2946", display_shown, "disp_", "No Display Block found.", "toggle_unl") return true end
        if pkt:find("buttonClicked|target_shelf") then shelf_scan() attachPublicInfo(shelf) shelf_shown = filterPub.shelf and onlyPublic(shelf) or shelf showList("shelf_hack", "Display Shelf Long Take", "3794", shelf_shown, "shelf_", "No Display Shelf found.", "toggle") return true end
        if pkt:find("buttonClicked|target_mannq") then mannq_scan() attachPublicInfo(mannq) mannq_shown = filterPub.mannq and onlyPublic(mannq) or mannq showList("mannq_hack", "Mannequin Long Take", "1420", mannq_shown, "mannq_", "No Mannequin found.", "toggle") return true end
        if pkt:find("buttonClicked|target_pmaker") then pmaker_scan() attachPublicInfo(pmaker) pmaker_shown = filterPub.pm and onlyPublic(pmaker) or pmaker showList("pmaker_hack", "Path Maker", "1684", pmaker_shown, "pm_", "No Path Maker found.", "toggle") return true end
        if pkt:find("buttonClicked|target_vault") then vault_scan() showVaultList() return true end
        if pkt:find("buttonClicked|target_gaia") then gaia_scan() attachPublicInfo(gaia) gaia_shown = filterPub.gaia and onlyPublic(gaia) or gaia showList("gaia_hack", "Gaia Long Take", "6946", gaia_shown, "gaia_", "No Gaia found.", "toggle_unl") return true end
        if pkt:find("buttonClicked|target_ut") then ut_scan() attachPublicInfo(ut) ut_shown = filterPub.ut and onlyPublic(ut) or ut showList("ut_hack", "UT Long Take", "6948", ut_shown, "ut_", "No UT found.", "toggle_unl") return true end
        if pkt:find("buttonClicked|extract") then showMagnetDlg() return true end
        if pkt:find("buttonClicked|iddoor") then ovlay("ID Door Leak active, enter a door to leak the ID.") return true end
        if pkt:find("buttonClicked|hunting") then showFinderSetup() return true end
        if pkt:find("buttonClicked|cheker") then showChecker() return true end
        if pkt:find("buttonClicked|cekvend") then
            vendAll = scanVends()
            if #vendAll == 0 then ovlay("No vend in this world.") return true end
            vendFilter = ""
            vendPage = 1
            showCekDialog()
            return true
        end
        if pkt:find("buttonClicked|bf") then showBfDlg() return true end
        if pkt:find("buttonClicked|visit") then
            showVisitDlg()
            return true
        end
        if pkt:find("buttonClicked|hide_world") then
            hide_world = not hide_world
            ovlay("Hide World " .. (hide_world and "enabled" or "disabled"))
            showBuremSetting()
            return true
        end
        if pkt:find("buttonClicked|ent_check") then
            entToggle()
            showBuremSetting()
            return true
        end
        if pkt:find("buttonClicked|save_Burem") then ovlay("Settings saved.") return true end
    end
    if pkt:find("dialog_name|save_setup") then
        for i = 1, 3 do
            local v = pkt:match("save" .. i .. "|([^|\n]*)")
            if v ~= nil then
                save_slots[i] = v:gsub("[|\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
            end
        end
        local ok = {}
        for i = 1, 3 do
            if save_slots[i] ~= "" then table.insert(ok, tostring(i)) end
        end
        ovlay("Save tersimpan: " .. (#ok > 0 and table.concat(ok, ",") or "kosong"))
        return true
    end
    if pkt:find("dialog_name|checkerw") then
        local li = pkt:match("buttonClicked|lock_(%d+)")
        if li then showLockDetail(tonumber(li)) return true end
        local f = pkt:match("filteruidinput|([^|\n]*)")
        if f ~= nil then filterUID = f:gsub("%s+", "") showChecker() return true end
    end
    if pkt:find("dialog_name|lockdetail") then showChecker() return true end
    if pkt:find("dialog_name|cek_vend") then
        if pkt:find("buttonClicked|cek_prev") then
            if vendPage > 1 then vendPage = vendPage - 1 end
            showCekDialog()
            return true
        end
        if pkt:find("buttonClicked|cek_next") then
            vendPage = vendPage + 1
            showCekDialog()
            return true
        end
        local vi = tonumber(pkt:match("buttonClicked|cekvend_(%d+)"))
        if vi then
            local v = vendShown[vi]
            if v then
                local vw = getWorld()
                local vworld = (v.world and v.world ~= "" and v.world) or (vw and vw.name) or ""
                vend_esp = { x = v.x, y = v.y, world = vworld }
                ovlay("Vend ESP: " .. v.name .. " (" .. v.x .. "," .. v.y .. ")")
                showCekDialog()
            end
            return true
        end
        local f = pkt:match("cek_filter|([^|\n]*)")
        if f ~= nil then
            f = f:gsub("^%s+", ""):gsub("%s+$", "")
            if f ~= vendFilter then
                vendFilter = f
                vendPage = 1
            else
                vendAll = scanVends()
            end
            showCekDialog()
            return true
        end
        if pkt:find("buttonClicked|cek_apply") then
            vendAll = scanVends()
            vendPage = 1
            showCekDialog()
            return true
        end
        return true
    end
    if pkt:find("dialog_name|set_find_world") then
        local t = pkt:match("world_t|(%w+)")
        local l = tonumber(pkt:match("world_l|(%d+)") or "")
        local n = pkt:match("world_n|([^\n|]*)")
        local d = tonumber(pkt:match("world_dly|(%d+)") or "")
        local p = pkt:match("world_p|(%w+)")
        if t then h_typ = t end
        if l then h_len = l end
        if n then h_name = n end
        if d then h_delay = d end
        if p then h_pos = p end
        visited = {}
        ovlay("Finder config saved.")
        return true
    end
    if pkt:find("dialog_name|bf_menu") then
        local dly = tonumber(pkt:match("bf_delay|([^|\n]*)") or "")
        if dly then
            if dly < 200 then dly = 200 end
            if dly > 10000 then dly = 10000 end
            bf_delay = dly
        end
        if pkt:find("buttonClicked|bf_prog_reset") then
            if bf_running then ovlay("BF running. Pause via Friends first.") return true end
            bf_index = 1
            bf_paused = false
            bf_stopped = false
            bf_found = false
            bf_attempts = 0
            ovlay("BF progress reset.")
            showBfDlg()
            return true
        end
        if pkt:find("buttonClicked|bf_clearlist") then
            if bf_running then ovlay("BF running. Pause via Friends first.") return true end
            bf_ids = {}
            bf_index = 1
            bf_paused = false
            bf_stopped = false
            bf_found = false
            bf_attempts = 0
            ovlay("Wordlist cleared.")
            showBfDlg()
            return true
        end
        if pkt:find("buttonClicked|bf_continue") then
            if bf_paused then bfStart()
            else ovlay("Nothing to continue. Use Start.") end
            return true
        end
        if pkt:find("buttonClicked|bf_start") then
            bfStart()
            return true
        end
        if pkt:find("buttonClicked|bf_edit") then
            showWordlistDlg()
            return true
        end
        return true
    end
    if pkt:find("dialog_name|wl_edit") then
        if pkt:find("buttonClicked|wl_clear") then
            if bf_running then ovlay("BF running. Pause via Friends first.") return true end
            bf_ids = {}
            bf_index = 1
            bf_paused = false
            bf_stopped = false
            bf_found = false
            bf_attempts = 0
            ovlay("Wordlist cleared.")
            showWordlistDlg()
            return true
        end
        if pkt:find("buttonClicked|wl_add") then
            local body = tostring(pkt:match("wl_input|(.*)") or "")
            body = body:gsub("\r", "")
            body = body:gsub("\\n", "\n")
            local cut = body:find("buttonClicked")
            if cut then body = body:sub(1, cut - 1) end
            local cut2 = body:find("embed_data")
            if cut2 then body = body:sub(1, cut2 - 1) end
            local added = bfAddList(bfParse(body))
            ovlay("Added `2" .. added .. "`7 IDs. Total `2" .. #bf_ids .. "`7.")
            showWordlistDlg()
            return true
        end
        if pkt:find("buttonClicked|wl_back") then
            showBfDlg()
            return true
        end
        return true
    end
    return false
end)

AddHook("OnTextPacket", "BuremHook", function(_, packet)
    if type(packet) ~= "string" then return false end
    if packet:find("action|friends") then
        local did = false
        if hunt_run then hunt_run = false ovlay("Auto hunting stopped.") did = true end
        if bf_running then
            bf_running = false
            if not bf_found then
                bf_stopped = true
                bf_paused = true
                ovlay("BF paused at " .. (bf_index - 1) .. "/" .. #bf_ids .. ". Open /bf to continue.")
            end
            did = true
        end
        if did then return true end
        return false
    end
    if packet:find("action|input\n") then
        local teks = (packet:match("text|([^\n]*)") or ""):lower()
        if teks:find("^/display") then display_scan() attachPublicInfo(display) display_shown = filterPub.disp and onlyPublic(display) or display showList("display_hack", "Display Block Long Take", "2946", display_shown, "disp_", "No Display Block found.", "toggle_unl") return true end
        if teks:find("^/shelf") then shelf_scan() attachPublicInfo(shelf) shelf_shown = filterPub.shelf and onlyPublic(shelf) or shelf showList("shelf_hack", "Display Shelf Long Take", "3794", shelf_shown, "shelf_", "No Display Shelf found.", "toggle") return true end
        if teks:find("^/mannq") then mannq_scan() attachPublicInfo(mannq) mannq_shown = filterPub.mannq and onlyPublic(mannq) or mannq showList("mannq_hack", "Mannequin Long Take", "1420", mannq_shown, "mannq_", "No Mannequin found.", "toggle") return true end
        if teks:find("^/pmaker") then pmaker_scan() attachPublicInfo(pmaker) pmaker_shown = filterPub.pm and onlyPublic(pmaker) or pmaker showList("pmaker_hack", "Path Maker", "1684", pmaker_shown, "pm_", "No Path Maker found.", "toggle") return true end
        if teks:find("^/vault") then vault_scan() showVaultList() return true end
        if teks:find("^/gaia") then gaia_scan() attachPublicInfo(gaia) gaia_shown = filterPub.gaia and onlyPublic(gaia) or gaia showList("gaia_hack", "Gaia Long Take", "6946", gaia_shown, "gaia_", "No Gaia found.", "toggle_unl") return true end
        if teks:find("^/ut") then ut_scan() attachPublicInfo(ut) ut_shown = filterPub.ut and onlyPublic(ut) or ut showList("ut_hack", "UT Long Take", "6948", ut_shown, "ut_", "No UT found.", "toggle_unl") return true end
        if teks:find("^/magnet") then showMagnetDlg() return true end
        if teks:find("^/label") then showLabelDlg() return true end
        if teks:find("^/portal") then sendBuremPortal() return true end
        if teks:find("^/check") then showChecker() return true end
        if teks:find("^/cekvend") then
            local kw = teks:match("^/cekvend%s*(.-)%s*$") or ""
            kw = kw:gsub("^%s+", ""):gsub("%s+$", "")
            vendAll = scanVends()
            if #vendAll == 0 then ovlay("No vend in this world.") return true end
            vendFilter = kw
            vendPage = 1
            showCekDialog()
            return true
        end
        if teks:find("^/wordlist") then showWordlistDlg() return true end
        if teks:find("^/bf") then showBfDlg() return true end
        if teks:find("^/setsave") then showSaveDialog() return true end
        local saveN = teks:match("^/save%s*(%d+)")
        if saveN then saveJoin(tonumber(saveN)) return true end
        if teks:find("^/set") then showFinderSetup() return true end
        if teks:find("^/q") then
            local world = makeWorldName()
            if world then addVisit(world) sendPacket(3, "action|join_request\nname|" .. world .. "\ninvitedWorld|0") ovlay("Joining " .. world)
            else ovlay("Invalid config. Check /set.") end
            return true
        end
        if teks:find("^/s%s") or teks == "/s" or teks:find("^/start") then huntLoop() return true end
        if teks:find("^/menu") or teks:find("^/help") then showHelpDlg() return true end
    end
    if packet:find("action|store") and packet:find("location|gem") then
        local world = makeWorldName()
        if world then addVisit(world) sendPacket(3, "action|join_request\nname|" .. world .. "\ninvitedWorld|0") ovlay("Joining " .. world)
        else ovlay("Invalid config. Check /set.") end
        return true
    end
    if packet:find("dialog_name|visit_hist") then
        local idx = tonumber(packet:match("buttonClicked|visit_world_(%d+)"))
        if idx and visit_history[idx] then
            local w = visit_history[idx]
            sendPacket(3, "action|join_request\nname|" .. w .. "\ninvitedWorld|0")
            ovlay("Joining " .. w)
        end
        return true
    end
    if packet:find("dialog_name|display_hack") then
        if packet:find("buttonClicked|disp_pub_on") then
            filterPub.disp = true
            display_shown = onlyPublic(display)
            showList("display_hack", "Display Block Long Take", "2946", display_shown, "disp_", "No unlocked Display Block found.", "toggle_unl")
            return true
        end
        if packet:find("buttonClicked|disp_pub_off") then
            filterPub.disp = false
            display_shown = display
            showList("display_hack", "Display Block Long Take", "2946", display_shown, "disp_", "No Display Block found.", "toggle_unl")
            return true
        end
        local idx = tonumber(packet:match("buttonClicked|disp_(%d+)"))
        if idx and display_shown[idx] then
            local d = display_shown[idx]
            sendPacket(2, "action|dialog_return\ndialog_name|displayblock\ntilex|" .. d.x .. "|\ntiley|" .. d.y .. "|\n")
            ovlay("Success Long Take Display Block")
        end
        return true
    end
    if packet:find("dialog_name|shelf_hack") then
        if packet:find("buttonClicked|shelf_pub_on") then
            filterPub.shelf = true
            shelf_shown = onlyPublic(shelf)
            showList("shelf_hack", "Display Shelf Long Take", "3794", shelf_shown, "shelf_", "No public Display Shelf found.", "toggle")
            return true
        end
        if packet:find("buttonClicked|shelf_pub_off") then
            filterPub.shelf = false
            shelf_shown = shelf
            showList("shelf_hack", "Display Shelf Long Take", "3794", shelf_shown, "shelf_", "No Display Shelf found.", "toggle")
            return true
        end
        local idx = tonumber(packet:match("buttonClicked|shelf_(%d+)"))
        if idx and shelf_shown[idx] then
            local d = shelf_shown[idx]
            sendPacket(2, "action|dialog_return\ndialog_name|dispshelf\ntilex|" .. d.x .. "|\ntiley|" .. d.y .. "|\nbuttonClicked|remove\n")
            ovlay("Success Long Take Display Shelf")
        end
        return true
    end
    if packet:find("dialog_name|mannq_hack") then
        if packet:find("buttonClicked|mannq_pub_on") then
            filterPub.mannq = true
            mannq_shown = onlyPublic(mannq)
            showList("mannq_hack", "Mannequin Long Take", "1420", mannq_shown, "mannq_", "No public Mannequin found.", "toggle")
            return true
        end
        if packet:find("buttonClicked|mannq_pub_off") then
            filterPub.mannq = false
            mannq_shown = mannq
            showList("mannq_hack", "Mannequin Long Take", "1420", mannq_shown, "mannq_", "No Mannequin found.", "toggle")
            return true
        end
        local idx = tonumber(packet:match("buttonClicked|mannq_(%d+)"))
        if idx and mannq_shown[idx] then
            local d = mannq_shown[idx]
            sendPacket(2, "action|dialog_return\ndialog_name|mannequin_edit\ntilex|" .. d.x .. "|\ntiley|" .. d.y .. "|\nbuttonClicked|clear\ncheckbox|0\ncheckbox|0\ncheckbox|0\ncheckbox|0\n")
            ovlay("Success Long Take Mannequin")
        end
        return true
    end
    if packet:find("dialog_name|pmaker_hack") then
        if packet:find("buttonClicked|pm_pub_on") then
            filterPub.pm = true
            pmaker_shown = onlyPublic(pmaker)
            showList("pmaker_hack", "Path Maker", "1684", pmaker_shown, "pm_", "No public Path Maker found.", "toggle")
            return true
        end
        if packet:find("buttonClicked|pm_pub_off") then
            filterPub.pm = false
            pmaker_shown = pmaker
            showList("pmaker_hack", "Path Maker", "1684", pmaker_shown, "pm_", "No Path Maker found.", "toggle")
            return true
        end
        local idx = tonumber(packet:match("buttonClicked|pm_(%d+)"))
        if idx and pmaker_shown[idx] then
            local d = pmaker_shown[idx]
            local here = ""
            local w = getWorld()
            if w and w.name then here = w.name end
            sendPacket(2, "action|dialog_return\ndialog_name|sign_edit\ntilex|" .. d.x .. "|\ntiley|" .. d.y .. "|\nsign_text|x0xburn\n")
            sendPacket(3, "action|join_request\nname|" .. here .. "|x0xburn|invitedWorld|0")
            ovlay("Success Change ID to x0xburn")
        end
        return true
    end
    if packet:find("dialog_name|vault_hack") then
        local sel = tonumber(packet:match("selecttarget|(%d+)"))
        if sel and sel > 0 then vault_itemid = sel end
        local idx = tonumber(packet:match("buttonClicked|vault_(%d+)"))
        if idx and vault[idx] then
            local d = vault[idx]
            sendPacket(2, "action|dialog_return\ndialog_name|storageboxxtreme\ntilex|" .. d.x .. "|\ntiley|" .. d.y .. "|\nitemid|" .. vault_itemid .. "|\nbuttonClicked|accept\nitemcount|1\n")
            ovlay("Success Bypass Safe Vault (item " .. vault_itemid .. ")")
        end
        return true
    end
    if packet:find("dialog_name|gaia_hack") then
        if packet:find("buttonClicked|gaia_pub_on") then
            filterPub.gaia = true
            gaia_shown = onlyPublic(gaia)
            showList("gaia_hack", "Gaia Long Take", "6946", gaia_shown, "gaia_", "No unlocked Gaia found.", "toggle_unl")
            return true
        end
        if packet:find("buttonClicked|gaia_pub_off") then
            filterPub.gaia = false
            gaia_shown = gaia
            showList("gaia_hack", "Gaia Long Take", "6946", gaia_shown, "gaia_", "No Gaia found.", "toggle_unl")
            return true
        end
        local idx = tonumber(packet:match("buttonClicked|gaia_(%d+)"))
        if idx and gaia_shown[idx] then
            local d = gaia_shown[idx]
            sendPacket(2, "action|dialog_return\ndialog_name|itemsucker_seed\ntilex|" .. d.x .. "|\ntiley|" .. d.y .. "|\nbuttonClicked|retrieveitem\nchk_enablesucking|1\n")
            ovlay("Success Long Take Gaia")
        end
        return true
    end
    if packet:find("dialog_name|ut_hack") then
        if packet:find("buttonClicked|ut_pub_on") then
            filterPub.ut = true
            ut_shown = onlyPublic(ut)
            showList("ut_hack", "UT Long Take", "6948", ut_shown, "ut_", "No unlocked UT found.", "toggle_unl")
            return true
        end
        if packet:find("buttonClicked|ut_pub_off") then
            filterPub.ut = false
            ut_shown = ut
            showList("ut_hack", "UT Long Take", "6948", ut_shown, "ut_", "No UT found.", "toggle_unl")
            return true
        end
        local idx = tonumber(packet:match("buttonClicked|ut_(%d+)"))
        if idx and ut_shown[idx] then
            local d = ut_shown[idx]
            sendPacket(2, "action|dialog_return\ndialog_name|itemsucker_block\ntilex|" .. d.x .. "|\ntiley|" .. d.y .. "|\nbuttonClicked|retrieveitem\nchk_enablesucking|1\n")
            ovlay("Success Long Take UT")
        end
        return true
    end
    if packet:find("dialog_name|mag_list") then
        local oid = tonumber(packet:match("buttonClicked|mag_(%d+)"))
        if oid then
            sendPacket(2, "action|dialog_return\ndialog_name|extractor\ntilex|0|\ntiley|0|\nstartIndex|0|\nextractorID|6140|\nbuttonClicked|extractOnceObj_" .. oid .. "\n")
            ovlay("Magnet pull oid " .. oid)
            return true
        end
        local q = packet:match("mag_search|([^|\n]*)")
        if q ~= nil then
            q = q:gsub("[|\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if #q > 50 then q = q:sub(1, 50) end
            magSearch = q
        end
        if packet:find("buttonClicked|mag_search_apply") or q ~= nil then
            showMagnetDlg()
            return true
        end
        return true
    end
    return false
end)

espRescan()
showHelpDlg()
