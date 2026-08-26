-- BeamMP-SXMY_Plugin - modules/PlayerBan.lua / 玩家封禁模块
-- Player ban module: ban a nickname (login permission) or the IP a nickname is currently using,
-- with a duration and an optional reason. Bans are stored in banusers.txt next to users.txt.
-- 按昵称（登录权限）或昵称当前使用的 IP 封禁玩家，可指定时长与可选理由；记录存于 users.txt 同目录的 banusers.txt
-- Requires Auth: without Auth this module does nothing / 依赖 Auth：未启用 Auth 时本模块不工作

local lib = require("modules.lib")

-- 自身开关（模块统一机制）；同时要求 Auth 启用 / own switch (standard module mechanism); also requires Auth
local enabled = lib.get("PlayerBan", "enable", true)
if not enabled or not lib.enabled("Auth") then
    print("[SXMY_PlayerBan] " .. lib.msg("未启用 Auth 功能 PlayerBan 不工作", "Auth is disabled, PlayerBan is not active"))
    return {}
end

lib.ensureSection("PlayerBan", {
    { key = "enable", v = true, c = "玩家封禁功能开关（需启用 Auth）/ Player ban module switch (requires Auth)" },
})

-- 封禁记录文件（与 users.txt 同目录）/ ban record file (same folder as users.txt)
local BAN_FILE = "Resources/Server/BeamMP-SXMY_Plugin/banusers.txt"
-- key = "nick:<昵称>" 或 "ip:<IP>" -> { expires = 结束时间戳, reason = 原因 } / key = "nick:<nickname>" or "ip:<IP>" -> { expires = expiry timestamp, reason = reason }
local bans = {}

-- epoch 时间戳转可读格式 YYYYMMDDHHMM（本地时区）/ epoch to the readable local time format YYYYMMDDHHMM
local function formatTime(epoch)
    return os.date("%Y%m%d%H%M", epoch)
end

-- 可读格式 YYYYMMDDHHMM 转 epoch（本地时区）/ parse the readable time format back to epoch (local time)
local function parseTime(str)
    local y, mo, d, h, mi = str:match("^(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)$")
    if not y then
        return nil
    end
    return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = 0 })
end

-- 读取封禁记录（替换中途崩溃时尝试从备份恢复）/ load the ban records (recover from the backup after a crash mid-swap)
local function loadBans()
    bans = {}
    local fh = io.open(BAN_FILE, "r")
    if not fh then
        -- 主文件缺失但存在备份（替换中途崩溃）：恢复并告警 / main file missing but a backup exists (crash mid-swap): recover and warn
        local bak = io.open(BAN_FILE .. ".bak", "r")
        if bak then
            bak:close()
            print("[SXMY_PlayerBan] " .. lib.msg("检测到封禁记录备份 正在恢复", "Ban record backup found, recovering"))
            local ok = os.rename(BAN_FILE .. ".bak", BAN_FILE)
            if ok then
                fh = io.open(BAN_FILE, "r")
            end
        end
        if not fh then
            return
        end
    end
    for line in fh:lines() do
        -- 新格式：<IP/nick> <YYYYMMDDHHMM> <原因（可空）>/ new format: <IP/nick> <YYYYMMDDHHMM> <reason (optional)>
        local key, timeStr, reason = line:match("^%s*(%S+)%s+(%d%d%d%d%d%d%d%d%d%d%d%d)%s*(.-)%s*$")
        if key and timeStr then
            local ts = parseTime(timeStr)
            if ts then
                bans[key] = { expires = ts, reason = reason }
            end
        else
            -- 兼容旧格式：<key> = <epoch>:<原因>（[^=]- 非贪婪，避免把 = 前的空格吃进键名）/ legacy format: <key> = <epoch>:<reason> ([^=]- non-greedy so the space before = is not part of the key)
            local legacyKey, untilTs, legacyReason = line:match("^%s*([%a_]+:[^=]-)%s*=%s*(%d+):(.*)$")
            if legacyKey and untilTs then
                local ts = tonumber(untilTs)
                if ts then
                    bans[legacyKey] = { expires = ts, reason = legacyReason }
                end
            end
        end
    end
    fh:close()
end

-- 原子写封禁记录（Windows 兼容：rename 不能覆盖已存在文件，用 备份-替换-回滚；写失败不替换，删备份前校验行数）
-- atomically save the ban records (Windows-safe: rename cannot overwrite, use backup-swap-rollback; abort on write failure, verify line count before deleting the backup)
local function saveBans()
    local tmp = BAN_FILE .. ".tmp"
    local fw = io.open(tmp, "w")
    if not fw then
        print("[SXMY_PlayerBan] " .. lib.msg("封禁记录保存失败", "Failed to save ban records"))
        return
    end
    local count = 0
    for key, ban in pairs(bans) do
        local ok = fw:write(key, " ", formatTime(ban.expires), ban.reason and ban.reason ~= "" and (" " .. ban.reason) or "", "\n")
        if not ok then
            fw:close()
            os.remove(tmp)
            print("[SXMY_PlayerBan] " .. lib.msg("封禁记录保存失败 磁盘写入错误", "Failed to save ban records, disk write error"))
            return
        end
        count = count + 1
    end
    local okc = fw:close()
    if not okc then
        os.remove(tmp)
        print("[SXMY_PlayerBan] " .. lib.msg("封禁记录保存失败 磁盘写入错误", "Failed to save ban records, disk write error"))
        return
    end
    local bak = BAN_FILE .. ".bak"
    os.remove(bak)
    local backed, berr = os.rename(BAN_FILE, bak)
    if backed then
        local ok, rerr = os.rename(tmp, BAN_FILE)
        if ok then
            -- 删除唯一备份前校验新文件行数与内存记录一致（忽略结尾空行；verify 打开失败视为不一致）
            -- verify the new file matches memory before deleting the only backup (ignore the trailing empty line; a failed verify counts as inconsistent)
            local verify = io.open(BAN_FILE, "r")
            local lines = 0
            local verified = false
            if verify then
                verified = true
                for line in verify:lines() do
                    if line ~= "" then
                        lines = lines + 1
                    end
                end
                verify:close()
            end
            if verified and lines == count then
                os.remove(bak)
            else
                -- 回滚：先删除新文件（Windows rename 不能覆盖已存在文件），再恢复备份 / rollback: remove the new file first (Windows rename cannot overwrite), then restore the backup
                os.remove(BAN_FILE)
                os.rename(bak, BAN_FILE)
                os.remove(tmp)
                print("[SXMY_PlayerBan] " .. lib.msg("封禁记录保存校验失败 已回滚", "Ban record verification failed, rolled back"))
            end
        else
            -- 恢复备份 / restore the backup
            os.rename(bak, BAN_FILE)
            os.remove(tmp)
            print("[SXMY_PlayerBan] " .. lib.msg("封禁记录保存失败: ", "Failed to save ban records: ") .. tostring(rerr))
        end
    else
        -- 原文件不存在（首次保存）→ 直接移入 / first save: nothing to back up, move directly
        local ok, rerr = os.rename(tmp, BAN_FILE)
        if not ok then
            os.remove(tmp)
            print("[SXMY_PlayerBan] " .. lib.msg("封禁记录保存失败: ", "Failed to save ban records: ") .. tostring(rerr))
        end
    end
end

-- 解析时长：<数量><单位>，m=分钟 h=小时 d=天 M=月(30天) y=年(365天) / parse a duration: <amount><unit>, m=minute h=hour d=day M=month(30d) y=year(365d)
local function parseDuration(input)
    local amount, unit = input:match("^(%d+)([mhdMy])$")
    if not amount then
        return nil
    end
    local seconds = tonumber(amount)
    if unit == "m" then
        seconds = seconds * 60
    elseif unit == "h" then
        seconds = seconds * 3600
    elseif unit == "d" then
        seconds = seconds * 86400
    elseif unit == "M" then
        seconds = seconds * 30 * 86400
    elseif unit == "y" then
        seconds = seconds * 365 * 86400
    end
    return seconds
end

-- 剩余时间格式：0d 0h 0m / format the remaining time as 0d 0h 0m
local function formatRemaining(untilTs)
    local remaining = math.max(0, untilTs - os.time())
    local d = math.floor(remaining / 86400)
    local h = math.floor((remaining % 86400) / 3600)
    local m = math.floor((remaining % 3600) / 60)
    return string.format("%dd %dh %dm", d, h, m)
end

-- 踢出消息（<br> 换行，客户端聊天支持）/ kick message (<br> newline, supported by the client chat)
local function kickMessage(ban)
    local msg = lib.msg("你在此服务器已被封禁", "You are banned from this server") .. "<br>" ..
        lib.msg("剩余时间：", "Remaining: ") .. formatRemaining(ban.expires) .. "<br>"
    if ban.reason and ban.reason ~= "" then
        msg = msg .. lib.msg("原因：", "Reason: ") .. ban.reason
    end
    return msg
end

-- 踢出玩家：MP.DropPlayer 是 v3 踢人 API；失败或明确拒绝时回退私信 / kick a player: MP.DropPlayer is the v3 kick API; fall back to a private message on error or explicit refusal
local function kick(player_id, ban)
    local reason = kickMessage(ban)
    local ok, res = pcall(MP.DropPlayer, player_id, reason)
    if not ok or res == false then
        MP.SendChatMessage(player_id, reason)
    end
end

-- 立即踢出在线目标，使封禁即时生效（防止在线规避）/ kick online targets immediately so the ban applies right away
local function kickOnline(target, kind, ban)
    if kind == "nick" then
        if type(SXMY_Auth_GetPlayerIdByNick) == "function" then
            local pid = SXMY_Auth_GetPlayerIdByNick(target)
            if pid then
                kick(pid, ban)
            end
        end
    elseif kind == "ip" then
        -- 踢出所有使用该 IP 的已登录玩家 / kick every logged-in player using this IP
        if type(SXMY_Auth_GetLoginNick) == "function" then
            local players = MP.GetPlayers()
            if type(players) == "table" then
                for pid in pairs(players) do
                    if SXMY_Auth_GetLoginNick(pid) then
                        local ids = MP.GetPlayerIdentifiers(pid)
                        local ip = ids and ids.ip
                        if ip == target then
                            kick(pid, ban)
                        end
                    end
                end
            end
        end
    end
end

-- 新增/更新一条封禁（保存后立即踢出在线目标）/ add or update a ban record (kicks online targets right after saving)
local function doBan(target, untilTs, reason, kind)
    bans[kind .. ":" .. target] = { expires = untilTs, reason = reason or "" }
    saveBans()
    kickOnline(target, kind, bans[kind .. ":" .. target])
    return lib.msg("已封禁 " .. target .. " 剩余时间：", "Banned " .. target .. ", remaining: ") .. formatRemaining(untilTs) ..
        (reason and reason ~= "" and (lib.msg(" 原因：", ", reason: ") .. reason) or "")
end

-- banipSXMY：封禁昵称当前使用的 IP / banipSXMY: ban the IP currently used by the nickname
local function banIp(target, seconds, reason)
    local pid = nil
    if type(SXMY_Auth_GetPlayerIdByNick) == "function" then
        pid = SXMY_Auth_GetPlayerIdByNick(target)
    end
    if not pid then
        return lib.msg("未找到在线玩家 " .. target .. "（昵称需已登录）", "No online player with nickname " .. target .. " (must be logged in)")
    end
    local ids = MP.GetPlayerIdentifiers(pid)
    local ip = ids and ids.ip
    if not ip or ip == "" then
        return lib.msg("无法获取 " .. target .. " 的 IP", "Cannot get the IP of " .. target)
    end
    return doBan(ip, os.time() + seconds, reason, "ip")
end

-- 服务端命令：banSXMY / banipSXMY / unbanSXMY（控制台与 OPAuth 动态分发共用）/ server commands: banSXMY / banipSXMY / unbanSXMY (console and OPAuth dynamic dispatch)
function SXMY_PlayerBan_onConsoleInput(cmd)
    -- banSXMY <昵称> <时间> <理由（可空）> / banSXMY <nickname> <time> <reason (optional)>
    local target, timeStr, reason = cmd:match("^banSXMY%s+(%S+)%s+(%S+)%s*(.-)%s*$")
    if target then
        -- 昵称仅限字母数字下划线，防止污染记录文件格式 / nickname limited to letters/digits/underscores to keep the record file format safe
        if not target:match("^[%w_]+$") then
            return lib.msg("昵称只能包含字母、数字和下划线", "Nickname may only contain letters, digits and underscores")
        end
        local seconds = parseDuration(timeStr)
        if not seconds then
            return lib.msg("时间格式错误 用法：<数量><单位>(m分钟 h小时 d天 M月 y)", "Bad time format, usage: <amount><unit>(m minute h hour d day M month y)")
        end
        return doBan(target, os.time() + seconds, reason, "nick")
    end
    -- banipSXMY <昵称> <时间> <理由（可空）> / banipSXMY <nickname> <time> <reason (optional)>
    target, timeStr, reason = cmd:match("^banipSXMY%s+(%S+)%s+(%S+)%s*(.-)%s*$")
    if target then
        local seconds = parseDuration(timeStr)
        if not seconds then
            return lib.msg("时间格式错误 用法：<数量><单位>(m分钟 h小时 d天 M月 y)", "Bad time format, usage: <amount><unit>(m minute h hour d day M month y)")
        end
        return banIp(target, seconds, reason)
    end
    -- unbanSXMY <昵称> / unbanSXMY ip <IP> / 解除昵称或 IP 封禁
    local nick = cmd:match("^unbanSXMY%s+([%w_]+)%s*$")
    if nick then
        if bans["nick:" .. nick] then
            bans["nick:" .. nick] = nil
            saveBans()
            return lib.msg("已解除 " .. nick .. " 的封禁", "Unbanned " .. nick)
        end
        return lib.msg("该昵称未被封禁", "Nickname is not banned")
    end
    local ip = cmd:match("^unbanSXMY%s+ip%s+(%S+)%s*$")
    if ip then
        -- IP 字符集校验，与记录文件解析格式保持一致 / validate the IP charset to match the record file format
        if not ip:match("^[%w%.%:]+$") then
            return lib.msg("IP 格式无效", "Invalid IP format")
        end
        if bans["ip:" .. ip] then
            bans["ip:" .. ip] = nil
            saveBans()
            return lib.msg("已解除 IP " .. ip .. " 的封禁", "Unbanned IP " .. ip)
        end
        return lib.msg("该 IP 未被封禁", "IP is not banned")
    end
    -- 命令名正确但参数不完整 → 返回用法提示（否则控制台会显示 Unknown command）/ correct command name but incomplete arguments -> usage hint (otherwise the console shows "Unknown command")
    if cmd == "banSXMY" or cmd:match("^banSXMY%s") then
        return lib.msg("用法：banSXMY <昵称> <时间>(m分钟 h小时 d天 M月 y) <理由（可空）>", "Usage: banSXMY <nickname> <time>(m minute h hour d day M month y) <reason (optional)>")
    end
    if cmd == "banipSXMY" or cmd:match("^banipSXMY%s") then
        return lib.msg("用法：banipSXMY <昵称> <时间>(m分钟 h小时 d天 M月 y) <理由（可空）>", "Usage: banipSXMY <nickname> <time>(m minute h hour d day M month y) <reason (optional)>")
    end
    if cmd == "unbanSXMY" or cmd:match("^unbanSXMY%s") then
        return lib.msg("用法：unbanSXMY <昵称> 或 unbanSXMY ip <IP>", "Usage: unbanSXMY <nickname> or unbanSXMY ip <IP>")
    end
    return nil -- 非本模块命令 / not this module's command
end

-- 由 Auth 在注册/登录前调用；被封禁则踢出并返回 true / called by Auth before register/login; kicks and returns true when banned
function SXMY_PlayerBan_Check(player_id, nick, ip)
    local now = os.time()
    -- 昵称封禁（登录权限）/ nickname ban (login permission)
    local nickBan = bans["nick:" .. (nick or "")]
    if nickBan then
        if nickBan.expires > now then
            kick(player_id, nickBan)
            return true
        end
        bans["nick:" .. nick] = nil -- 过期清理 / expired, clean up
        saveBans()
    end
    -- IP 封禁（该 IP 的任何账号）/ IP ban (any account on this IP)
    if ip and ip ~= "" then
        local ipBan = bans["ip:" .. ip]
        if ipBan then
            if ipBan.expires > now then
                kick(player_id, ipBan)
                return true
            end
            bans["ip:" .. ip] = nil
            saveBans()
        end
    end
    return false
end

MP.RegisterEvent("onConsoleInput", "SXMY_PlayerBan_onConsoleInput")

loadBans()

-- 暴露封禁记录数供测试 / expose the ban-record count for tests
function SXMY_TEST_banCount()
    local n = 0
    for _ in pairs(bans) do
        n = n + 1
    end
    return n
end
