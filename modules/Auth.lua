-- =====================================================================================
-- BeamMP-SXMY_Plugin - modules/Auth.lua / 身份认证模块
-- Auth module / 身份认证功能模块
-- Registration and login with SHA-256 password hashing / 注册与登录（密码 SHA-256 哈希）
-- Unauthenticated players cannot chat or spawn vehicles / 未认证玩家无法聊天与刷车
-- Loaded only when enabled in config.toml / 仅在 config.toml 启用时被加载
-- =====================================================================================

local lib = require("modules.lib") -- shared config library / 共享配置库

local ACCOUNTS_FILE = "Resources/Server/BeamMP-SXMY_Plugin/users.txt" -- accounts file, relative to working dir / 账户文件（相对服务器工作目录）
local PROMPT_INTERVAL = 5 -- prompt interval in seconds / 提示间隔秒数
local PROMPT_START_DELAY = 15 -- delay before the first prompt, after the welcome message / 首次提示延迟（欢迎消息之后）
local MAX_LOGIN_FAILS = 5 -- max consecutive login failures before locking / 连续登录失败锁定阈值
local LOGIN_LOCK_SECONDS = 60 -- lock duration after too many failures / 登录锁定秒数

-- ==================== SHA-256 (pure Lua, Lua 5.3 bitwise ops) / 纯 Lua SHA-256 ====================
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
} -- SHA-256 round constants / SHA-256 轮常量

-- Rotate x right by n bits / 循环右移 n 位
local function rrot(x, n)
    return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF
end

-- SHA-256 hash of a string, returns 64 lowercase hex chars / 字符串 SHA-256，返回 64 位小写十六进制
-- Global so it can be tested and reused / 设为全局以便测试与复用
function SXMY_Auth_sha256(msg)
    local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
    -- Pad: 0x80, zeros, then 64-bit big-endian bit length / 填充：0x80、零、64 位大端长度
    local bitlen = #msg * 8
    local padded = msg .. "\128" .. string.rep("\0", (55 - #msg) % 64) .. string.pack(">I8", bitlen)
    for i = 1, #padded, 64 do
        local w = {}
        for j = 0, 15 do
            w[j] = string.unpack(">I4", padded, i + j * 4)
        end
        for j = 16, 63 do
            local s0 = rrot(w[j - 15], 7) ~ rrot(w[j - 15], 18) ~ (w[j - 15] >> 3)
            local s1 = rrot(w[j - 2], 17) ~ rrot(w[j - 2], 19) ~ (w[j - 2] >> 10)
            w[j] = (w[j - 16] + s0 + w[j - 7] + s1) & 0xFFFFFFFF
        end
        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
        for j = 0, 63 do
            local S1 = rrot(e, 6) ~ rrot(e, 11) ~ rrot(e, 25)
            local ch = (e & f) ~ (~e & g)
            local temp1 = (h + S1 + ch + K[j + 1] + w[j]) & 0xFFFFFFFF
            local S0 = rrot(a, 2) ~ rrot(a, 13) ~ rrot(a, 22)
            local maj = (a & b) ~ (a & c) ~ (b & c)
            local temp2 = (S0 + maj) & 0xFFFFFFFF
            h, g, f, e, d, c, b, a = g, f, e, (d + temp1) & 0xFFFFFFFF, c, b, a, (temp1 + temp2) & 0xFFFFFFFF
        end
        H[1] = (H[1] + a) & 0xFFFFFFFF
        H[2] = (H[2] + b) & 0xFFFFFFFF
        H[3] = (H[3] + c) & 0xFFFFFFFF
        H[4] = (H[4] + d) & 0xFFFFFFFF
        H[5] = (H[5] + e) & 0xFFFFFFFF
        H[6] = (H[6] + f) & 0xFFFFFFFF
        H[7] = (H[7] + g) & 0xFFFFFFFF
        H[8] = (H[8] + h) & 0xFFFFFFFF
    end
    local hex = {}
    for _, v in ipairs(H) do
        hex[#hex + 1] = string.format("%08x", v)
    end
    return table.concat(hex)
end
-- ==================== end SHA-256 / SHA-256 结束 ====================

local accounts = {} -- nickname -> password hash, loaded from file / 昵称 -> 密码哈希（从文件加载）
local players = {} -- player_id -> { nick, loggedIn, joinedAt, lastPrompt } / 玩家状态表
local loginFails = {} -- player_id -> { count, lockedUntil, lastTry } for brute-force protection / 登录失败记录（防暴力破解，断线保留防重连绕过）

-- Load accounts from the file / 从文件加载账户
local function loadAccounts()
    accounts = {}
    local fh, err = io.open(ACCOUNTS_FILE, "r")
    if not fh then
        print("[SXMY_Auth] " .. lib.msg("账户文件读取失败", "Failed to read accounts file") .. " (" .. tostring(err) .. ")")
        return
    end
    for line in fh:lines() do
        -- Hash format: "salt$sha256" for new accounts, plain sha256 for legacy ones / 新账户格式 salt$sha256，旧账户为纯 sha256
        local nick, hash = line:match("^(%S+)%s*=%s*(%S+)$")
        if nick and hash then
            accounts[nick] = hash
        end
    end
    fh:close()
end

-- Append a new account to the file / 向文件追加新账户
local function saveAccount(nick, hash)
    local fh, err = io.open(ACCOUNTS_FILE, "a")
    if not fh then
        print("[SXMY_Auth] " .. lib.msg("账户文件写入失败", "Failed to write accounts file") .. " (" .. tostring(err) .. ")")
        return false
    end
    fh:write(nick, " = ", hash, "\n")
    fh:close()
    accounts[nick] = hash
    return true
end

-- Get the player's IP for brute-force tracking / 获取玩家 IP（用于暴力破解追踪）
local function getPlayerIp(player_id)
    local ids = MP.GetPlayerIdentifiers(player_id)
    if type(ids) == "table" then
        local ip = ids["ip"]
        if type(ip) == "string" and ip ~= "" then
            return ip
        end
    end
    return nil
end

-- Lock key: IP if available, otherwise the player id (server ids are reused) / 锁定键：优先 IP，否则用玩家 id（服务器 id 会复用）
local function getLockKey(player_id)
    local ip = getPlayerIp(player_id)
    if ip then
        return "ip:" .. ip
    end
    return "pid:" .. tostring(player_id)
end

-- Generate a per-account salt (16 hex chars) / 生成每账户盐（16 位十六进制）
local saltCounter = 0
local function makeSalt(player_id)
    saltCounter = saltCounter + 1
    return SXMY_Auth_sha256(tostring(os.time()) .. tostring(player_id) .. tostring(saltCounter)):sub(1, 16)
end

-- Send a private message in the selected language / 以所选语言发送私信
local function notify(player_id, zhText, enText)
    MP.SendChatMessage(player_id, lib.msg(zhText, enText))
end

-- Split text into non-empty trimmed lines by \n escapes and real newlines / 按 \n 转义与真实换行将文本拆分为非空行（去除首尾空白）
local function splitLines(text)
    local normalized = text:gsub("\\n", "\n"):gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    for line in (normalized .. "\n"):gmatch("(.-)\n") do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            lines[#lines + 1] = trimmed
        end
    end
    return lines
end

-- Get the absolute path of the accounts file (falls back to the relative path) / 获取账户文件的绝对路径（失败时回退相对路径）
local function getAccountsPath()
    local fh = io.popen("cd")
    if fh then
        local cwd = fh:read("*a"):gsub("%s+$", "")
        fh:close()
        if cwd ~= "" then
            return cwd .. "\\" .. ACCOUNTS_FILE:gsub("/", "\\")
        end
    end
    return ACCOUNTS_FILE
end

-- Show startup info: accounts file path and login text, printed after the other modules / 显示启动信息：账户文件路径与登录文本（在其他模块之后输出）
function SXMY_Auth_ShowInfo()
    -- Accounts file absolute path / 账户文件绝对路径
    print("[SXMY_Auth] " .. lib.msg("用户路径：", "Accounts path: ") .. getAccountsPath())
    -- Login text config / 登录文本配置
    local loginMsg = lib.get("Auth", "LoginMsg", "")
    print("[SXMY_Auth] " .. lib.msg("登录文本：", "Login text: "))
    if loginMsg and loginMsg ~= "" then
        for _, line in ipairs(splitLines(loginMsg)) do
            print("[SXMY_Auth] " .. line)
        end
    end
end

-- Get the logged-in nickname of a player, or nil if not logged in (used by NameTag) / 获取玩家的登录昵称，未登录返回 nil（供 NameTag 使用）
function SXMY_Auth_GetNick(player_id)
    local st = players[player_id]
    if st and st.loggedIn then
        return st.nick
    end
    return nil
end

-- Split a string into whitespace-separated arguments / 将字符串按空白拆分为参数
local function splitArgs(str)
    local args = {}
    for word in str:gmatch("%S+") do
        args[#args + 1] = word
    end
    return args
end

-- Validate the password against the configured rules / 按配置规则校验密码
local function checkPassword(player_id, passwd)
    local minLen = lib.get("Auth", "passwdlen", 8)
    if #passwd < minLen then
        notify(player_id, "密码长度不能少于" .. minLen .. "位", "Password must be at least " .. minLen .. " characters")
        return false
    end
    if lib.get("Auth", "passwdcase", false) then
        local hasUpper = passwd:find("%u") ~= nil
        local hasLower = passwd:find("%l") ~= nil
        if not (hasUpper and hasLower) then
            notify(player_id, "密码需同时包含大写和小写字母", "Password must contain both uppercase and lowercase letters")
            return false
        end
    end
    if lib.get("Auth", "passwdsymbol", false) then
        -- Special character = any char that is not a letter or digit / 特殊符号 = 非字母数字字符
        if not passwd:find("[^%w]") then
            notify(player_id, "密码需包含特殊符号", "Password must contain a special character")
            return false
        end
    end
    return true
end

-- Handle the /reg command / 处理 /reg 命令
local function handleRegister(player_id, args)
    if #args ~= 3 then
        notify(player_id, "请使用/reg 昵称 密码 确认密码 进行注册", "Please use /reg nickname password confirmpassword to register")
        return
    end
    local nick, passwd, confirm = args[1], args[2], args[3]
    -- Nickname limited to letters, digits and underscores to keep the file format safe / 昵称仅限字母数字下划线以保持文件格式安全
    if not nick:match("^[%w_]+$") then
        notify(player_id, "昵称只能包含字母、数字和下划线", "Nickname may only contain letters, digits and underscores")
        return
    end
    if passwd ~= confirm then
        notify(player_id, "密码与确认密码不同 请重试", "Passwords do not match, please retry")
        return
    end
    if not checkPassword(player_id, passwd) then
        return
    end
    if accounts[nick] then
        notify(player_id, "该昵称已被使用 请更换昵称或登录", "Nickname already taken, use another or log in")
        return
    end
    local salt = makeSalt(player_id)
    if not saveAccount(nick, salt .. "$" .. SXMY_Auth_sha256(salt .. passwd)) then
        notify(player_id, "账户保存失败 请联系管理员", "Failed to save account, contact an admin")
        return
    end
    players[player_id] = { nick = nick, loggedIn = true, joinedAt = os.time(), lastPrompt = os.time() }
    notify(player_id, "注册成功 已登录", "Registered successfully, logged in")
end

-- Handle the /login command with brute-force protection / 处理 /login 命令（含防暴力破解）
local function handleLogin(player_id, args)
    if #args ~= 2 then
        notify(player_id, "请使用/login 昵称 密码 进行登录", "Please use /login nickname password to log in")
        return
    end
    -- Lock key is the IP when available, so reconnecting with a new server id cannot bypass it / 锁定键优先 IP，重连换服务器 id 无法绕过
    local lockKey = getLockKey(player_id)
    -- Check the lockout first / 先检查锁定状态
    local failRecord = loginFails[lockKey]
    if failRecord and failRecord.lockedUntil and os.time() < failRecord.lockedUntil then
        notify(player_id, "登录尝试过于频繁 请稍后再试", "Too many login attempts, please try again later")
        return
    end
    local nick, passwd = args[1], args[2]
    local stored = accounts[nick]
    if stored then
        -- New format "salt$sha256" or legacy plain sha256 / 新格式 salt$sha256 或旧格式纯 sha256
        local salt, hash = stored:match("^(%x+)%$(%x+)$")
        local passHash
        if salt and hash then
            passHash = SXMY_Auth_sha256(salt .. passwd)
        else
            hash = stored
            passHash = SXMY_Auth_sha256(passwd)
        end
        if hash == passHash then
            loginFails[lockKey] = nil
            players[player_id] = { nick = nick, loggedIn = true, joinedAt = os.time(), lastPrompt = os.time() }
            notify(player_id, "登录成功", "Logged in successfully")
            -- Broadcast the configured login message to everyone (like /say) / 向所有人广播配置的登录消息（类似 /say）
            local loginMsg = lib.get("Auth", "LoginMsg", "")
            if loginMsg and loginMsg ~= "" then
                -- gsub returns two values (string, count); take only the string to avoid a third argument / gsub 返回两个值（字符串、次数），仅取字符串避免多出第三个参数
                local broadcast = loginMsg:gsub("<name>", nick)
                MP.SendChatMessage(-1, broadcast)
            end
            return
        end
    end
    local now = os.time()
    if not failRecord then
        failRecord = { count = 0 }
        loginFails[lockKey] = failRecord
    end
    failRecord.lastTry = now
    failRecord.count = failRecord.count + 1
    if failRecord.count >= MAX_LOGIN_FAILS then
        failRecord.lockedUntil = now + LOGIN_LOCK_SECONDS
        failRecord.count = 0
        notify(player_id, "登录失败次数过多 已锁定" .. LOGIN_LOCK_SECONDS .. "秒", "Too many failed logins, locked for " .. LOGIN_LOCK_SECONDS .. " seconds")
    else
        notify(player_id, "昵称或密码错误", "Wrong nickname or password")
    end
end

-- Chat handler: block unauthenticated players and / commands / 聊天处理：拦截未认证玩家与 / 命令
function SXMY_Auth_onChatMessage(player_id, player_name, message)
    local st = players[player_id]
    local loggedIn = st and st.loggedIn
    -- Commands are never broadcast / 命令消息一律不广播
    if message:sub(1, 1) == "/" then
        if message == "/reg" or message:sub(1, 5) == "/reg " then
            handleRegister(player_id, splitArgs(message:sub(6)))
        elseif message == "/login" or message:sub(1, 7) == "/login " then
            handleLogin(player_id, splitArgs(message:sub(8)))
        end
        return 1
    end
    -- Normal messages are hidden for unauthenticated players / 未认证玩家的普通消息不可见
    if not loggedIn then
        return 1
    end
    return 0
end

-- Vehicle spawn handler: block unauthenticated players / 刷车拦截：未认证玩家不可刷车
function SXMY_Auth_onVehicleSpawn(player_id, vehicle_id, vehicle_data)
    local st = players[player_id]
    if not (st and st.loggedIn) then
        return 1
    end
    return 0
end

-- Vehicle edit handler: block unauthenticated players (replacing/editing counts as spawning) / 车辆编辑拦截：未认证玩家不可编辑/替换车辆
function SXMY_Auth_onVehicleEdited(player_id, vehicle_id, vehicle_data)
    local st = players[player_id]
    if not (st and st.loggedIn) then
        return 1
    end
    return 0
end

-- Record the join time when a player joins / 玩家加入时记录进服时间
function SXMY_Auth_onPlayerJoin(player_id)
    if not players[player_id] then
        players[player_id] = { joinedAt = os.time(), lastPrompt = 0 }
    end
end

-- Periodic tick: prompt unauthenticated players and expire stale login-fail records / 周期检查：提示未认证玩家并清理过期登录失败记录
function SXMY_Auth_Tick()
    local now = os.time()
    -- Expire login-fail records older than the lock window / 清理超过锁定窗口的失败记录
    for player_id, record in pairs(loginFails) do
        if record.lastTry and now - record.lastTry >= LOGIN_LOCK_SECONDS then
            loginFails[player_id] = nil
        end
    end
    for player_id in pairs(MP.GetPlayers()) do
        local st = players[player_id]
        if not (st and st.loggedIn) then
            if not st then
                players[player_id] = { joinedAt = now, lastPrompt = 0 }
                st = players[player_id]
            end
            -- Start prompting after the welcome message has been sent / 欢迎消息发送后开始提示
            if now - st.joinedAt >= PROMPT_START_DELAY and now - st.lastPrompt >= PROMPT_INTERVAL then
                st.lastPrompt = now
                if st.nick and accounts[st.nick] then
                    -- Registered but not logged in: prompt login / 已注册未登录：提示登录
                    notify(player_id, "请使用/login 昵称 密码 进行登录", "Please use /login nickname password to log in")
                else
                    -- Not registered: prompt register and login / 未注册：提示注册与登录
                    notify(player_id, "请使用/reg 昵称 密码 确认密码 进行注册", "Please use /reg nickname password confirmpassword to register")
                    notify(player_id, "请使用/login 昵称 密码 进行登录", "Please use /login nickname password to log in")
                end
            end
        end
    end
end

-- Clean up on disconnect / 玩家断开时清理
-- Note: loginFails is kept so reconnecting cannot bypass the lockout / 注意：保留 loginFails 防止重连绕过锁定
function SXMY_Auth_onPlayerDisconnect(player_id)
    players[player_id] = nil
end

-- Initialize and register events / 初始化并注册事件
loadAccounts()
MP.RegisterEvent("onPlayerJoin", "SXMY_Auth_onPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect", "SXMY_Auth_onPlayerDisconnect")
MP.RegisterEvent("onChatMessage", "SXMY_Auth_onChatMessage")
MP.RegisterEvent("onVehicleSpawn", "SXMY_Auth_onVehicleSpawn")
MP.RegisterEvent("onVehicleEdited", "SXMY_Auth_onVehicleEdited")
MP.RegisterEvent("SXMY_Auth_Tick", "SXMY_Auth_Tick")
MP.CreateEventTimer("SXMY_Auth_Tick", 1000)
