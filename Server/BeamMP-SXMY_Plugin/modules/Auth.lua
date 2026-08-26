-- =====================================================================================
-- BeamMP-SXMY_Plugin - modules/Auth.lua / 身份认证模块
-- Auth module / 身份认证功能模块
-- Registration and login with SHA-256 password hashing / 注册与登录（密码 SHA-256 哈希）
-- Unauthenticated players cannot chat or spawn vehicles / 未认证玩家无法聊天与刷车
-- Loaded only when enabled in config.toml / 仅在 config.toml 启用时被加载
-- =====================================================================================

local lib = require("modules.lib") -- shared config library / 共享配置库

-- 本模块配置：缺失键自动追加（含中英注释），用户已有配置不覆盖 / this module's own config: missing keys appended with comments, user settings kept
lib.ensureSection("Auth", {
    { key = "enable", v = true, c = "身份认证功能开关 / Auth module switch" },
    { key = "passwdlen", v = 8, c = "密码最小长度（位）/ Minimum password length (characters)" },
    { key = "passwdcase", v = false, c = "是否要求大小写混合（不要求也可使用）/ Require mixed case (optional)" },
    { key = "passwdsymbol", v = false, c = "是否要求特殊符号（不要求也可使用）/ Require special characters (optional)" },
    { key = "maxRegsPerIP", v = 3, c = "单个IP最多注册账户数（0 不限制）/ Max registrations per IP (0 = unlimited)" },
    { key = "pbkdf2Iter", v = 1000, c = "PBKDF2 慢哈希迭代次数（越大越安全但登录越慢）/ PBKDF2 slow-hash iterations (higher = safer but slower logins)" },
    { key = "nickLength", v = 15, c = "昵称最大字符数（注册限制与 listSXMY 表格列宽）/ Max nickname length (registration limit and listSXMY column width)" },
    { key = "LoginMsg", v = "欢迎 <name> 登录服务器", c = "登录成功广播消息（/say），<name> 为玩家昵称，留空则不发送 / Login broadcast message, <name> = nickname, empty = disabled" },
})
-- 未启用时退出，不注册任何事件 / exit early when disabled, no events are registered
if not lib.get("Auth", "enable", true) then
    print("[SXMY_Plugin] " .. lib.msg("Auth 已禁用", "Auth disabled"))
    return
end

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

-- SHA-256 core: hashes msg and returns the 8 state words / SHA-256 核心：哈希消息并返回 8 个状态字
local function sha256Core(msg)
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
    return H
end

-- SHA-256 hash of a string, returns 64 lowercase hex chars / 字符串 SHA-256，返回 64 位小写十六进制
-- Global so it can be tested and reused / 设为全局以便测试与复用
function SXMY_Auth_sha256(msg)
    local H = sha256Core(msg)
    local hex = {}
    for _, v in ipairs(H) do
        hex[#hex + 1] = string.format("%08x", v)
    end
    return table.concat(hex)
end

-- SHA-256 raw digest (32 bytes) / SHA-256 原始摘要（32 字节）
local function sha256Raw(msg)
    local H = sha256Core(msg)
    local out = {}
    for _, v in ipairs(H) do
        out[#out + 1] = string.char(math.floor(v / 0x1000000) % 0x100, math.floor(v / 0x10000) % 0x100, math.floor(v / 0x100) % 0x100, v % 0x100)
    end
    return table.concat(out)
end
-- ==================== end SHA-256 / SHA-256 结束 ====================

-- ==================== PBKDF2-HMAC-SHA256 (slow hash) / 慢哈希 ====================
local DEFAULT_PBKDF2_ITER = 1000 -- PBKDF2 iteration default / PBKDF2 迭代次数默认值
-- PBKDF2 iterations from config, clamped to a positive integer / 从配置读取迭代次数（限制为正整数）
local function getIterations()
    local v = tonumber(lib.get("Auth", "pbkdf2Iter", DEFAULT_PBKDF2_ITER))
    if not v or v < 1 then
        return DEFAULT_PBKDF2_ITER
    end
    return math.floor(v)
end

-- HMAC-SHA256 / HMAC-SHA256 消息认证码
local function hmacSha256(key, msg)
    if #key > 64 then
        key = sha256Raw(key)
    end
    local ipad, opad = {}, {}
    for i = 1, 64 do
        local b = key:byte(i) or 0
        ipad[i] = string.char(b ~ 0x36)
        opad[i] = string.char(b ~ 0x5c)
    end
    local inner = sha256Raw(table.concat(ipad) .. msg)
    return sha256Raw(table.concat(opad) .. inner)
end

-- Byte-wise XOR of two equal-length strings / 逐字节异或两个等长字符串
local function xorBytes(a, b)
    local out = {}
    for i = 1, #a do
        out[i] = string.char(a:byte(i) ~ b:byte(i))
    end
    return table.concat(out)
end

-- PBKDF2-HMAC-SHA256, returns dkLen raw bytes / PBKDF2-HMAC-SHA256，返回 dkLen 原始字节
local function pbkdf2(password, salt, iterations, dkLen)
    local out = {}
    local block = 1
    while true do
        local u = hmacSha256(password, salt .. string.pack(">I4", block))
        local t = u
        for _ = 2, iterations do
            u = hmacSha256(password, u)
            t = xorBytes(t, u)
        end
        out[#out + 1] = t
        block = block + 1
        if #table.concat(out) >= dkLen then
            break
        end
    end
    return table.concat(out):sub(1, dkLen)
end

-- Raw bytes to lowercase hex / 原始字节转小写十六进制
local function hexEncode(raw)
    local hex = {}
    for i = 1, #raw do
        hex[i] = string.format("%02x", raw:byte(i))
    end
    return table.concat(hex)
end

-- PBKDF2 password hash as "pbkdf2$salt$iter$hex" / PBKDF2 密码哈希字符串
local function pbkdf2Hash(password, salt)
    local iter = getIterations()
    return "pbkdf2$" .. salt .. "$" .. tostring(iter) .. "$" .. hexEncode(pbkdf2(password, salt, iter, 32))
end

-- Parse a stored hash string into { mode, salt, iter, hex } / 解析存储的哈希字符串
local function parseStored(stored)
    local salt, iter, hex = stored:match("^pbkdf2%$([%x]+)%$(%d+)%$([%x]+)$")
    if salt and iter and hex and #hex == 64 then
        return { mode = "pbkdf2", salt = salt, iter = tonumber(iter), hex = hex }
    end
    local salt2, hex2 = stored:match("^(%x+)%$(%x+)$")
    if salt2 and hex2 and #hex2 == 64 then
        return { mode = "sha256", salt = salt2, hex = hex2 }
    end
    if stored:match("^%x+$") and #stored == 64 then
        return { mode = "sha256", salt = nil, hex = stored }
    end
    return nil
end
-- ==================== end PBKDF2 / PBKDF2 结束 ====================

local accounts = {} -- nickname -> password hash, loaded from file / 昵称 -> 密码哈希（从文件加载）
local players = {} -- player_id -> { nick, loggedIn, joinedAt, lastPrompt } / 玩家状态表
local loginFails = {} -- player_id -> { count, lockedUntil, lastTry } for brute-force protection / 登录失败记录（防暴力破解，断线保留防重连绕过）

-- Load accounts from the file / 从文件加载账户
-- Each line may carry the registration IP: "nick = hash [ip]" / 每行可带注册 IP："nick = hash [ip]"
local function loadAccounts()
    accounts = {}
    ipRegCount = {}
    local fh, err = io.open(ACCOUNTS_FILE, "r")
    if not fh then
        print("[SXMY_Auth] " .. lib.msg("账户文件读取失败", "Failed to read accounts file") .. " (" .. tostring(err) .. ")")
        return
    end
    for line in fh:lines() do
        -- Hash format: "salt$sha256" for new accounts, plain sha256 for legacy ones / 新账户格式 salt$sha256，旧账户为纯 sha256
        -- The registration IP is optional, legacy accounts have none / 注册 IP 可选，旧账户没有
        local nick, hash, ip = line:match("^(%S+)%s*=%s*(%S+)%s*(%S*)$")
        if nick and hash then
            accounts[nick] = hash
            if ip and ip ~= "" then
                ipRegCount[ip] = (ipRegCount[ip] or 0) + 1
            end
        end
    end
    fh:close()
end

-- Append a new account to the file, recording the registration IP / 向文件追加新账户（记录注册 IP）
local function saveAccount(nick, hash, ip)
    local fh, err = io.open(ACCOUNTS_FILE, "a")
    if not fh then
        print("[SXMY_Auth] " .. lib.msg("账户文件写入失败", "Failed to write accounts file") .. " (" .. tostring(err) .. ")")
        return false
    end
    fh:write(nick, " = ", hash, (ip and ip ~= "" and " " .. ip or ""), "\n")
    fh:close()
    accounts[nick] = hash
    if ip and ip ~= "" then
        ipRegCount[ip] = (ipRegCount[ip] or 0) + 1
    end
    return true
end

-- Rewrite the account file after a legacy account logs in (transparent PBKDF2 upgrade) / 旧账户登录成功后重写账户文件（透明升级为 PBKDF2）
local function upgradeAccount(nick, passwd, salt)
    local newHash = pbkdf2Hash(passwd, salt)
    local lines = {}
    local fh, ferr = io.open(ACCOUNTS_FILE, "r")
    if fh then
        for line in fh:lines() do
            lines[#lines + 1] = line
        end
        fh:close()
    else
        print("[SXMY_Auth] " .. lib.msg("账户文件读取失败", "Failed to read accounts file") .. " (" .. tostring(ferr) .. ")")
        return
    end
    local out = {}
    local replaced = false
    for _, line in ipairs(lines) do
        local n, h, ip = line:match("^(%S+)%s*=%s*(%S+)%s*(%S*)$")
        if n == nick then
            out[#out + 1] = nick .. " = " .. newHash .. (ip and ip ~= "" and " " .. ip or "")
            replaced = true
        else
            out[#out + 1] = line
        end
    end
    if not replaced then
        out[#out + 1] = nick .. " = " .. newHash
    end
    -- Atomic rewrite: temp file -> backup -> swap -> restore on failure / 原子重写：临时文件 -> 备份 -> 替换 -> 失败回滚
    local tmp = ACCOUNTS_FILE .. ".tmp"
    local fw, werr = io.open(tmp, "w")
    if not fw then
        print("[SXMY_Auth] " .. lib.msg("账户文件升级写入失败", "Failed to write upgraded accounts file") .. " (" .. tostring(werr) .. ")")
        return
    end
    fw:write(table.concat(out, "\n"), "\n")
    fw:close()
    local bak = ACCOUNTS_FILE .. ".bak"
    os.remove(bak)
    local backed, berr = os.rename(ACCOUNTS_FILE, bak)
    if backed then
        local ok, rerr = os.rename(tmp, ACCOUNTS_FILE)
        if ok then
            os.remove(bak)
            accounts[nick] = newHash
            print("[SXMY_Auth] " .. lib.msg("账户已升级为慢哈希", "Account upgraded to slow hash") .. ": " .. nick)
        else
            os.rename(bak, ACCOUNTS_FILE)
            print("[SXMY_Auth] " .. lib.msg("账户文件升级失败", "Failed to upgrade accounts file") .. " (" .. tostring(rerr) .. ")")
        end
    else
        os.remove(tmp)
        print("[SXMY_Auth] " .. lib.msg("账户文件升级失败", "Failed to upgrade accounts file") .. " (" .. tostring(berr) .. ")")
    end
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

-- Handle the /logout command: clear the login state / 处理 /logout 命令：清除登录状态
local function handleLogout(player_id)
    local st = players[player_id]
    if not (st and st.loggedIn) then
        notify(player_id, "尚未登录", "You are not logged in")
        return
    end
    -- Despawn all of the player's vehicles / 删除该玩家的所有车辆
    local ok, vehs = pcall(MP.GetPlayerVehicles, player_id)
    if ok and type(vehs) == "table" then
        for vehId in pairs(vehs) do
            pcall(MP.RemoveVehicle, player_id, vehId)
        end
    end
    -- Keep the record (joinedAt drives the periodic prompts), just clear the login state and nickname / 保留记录（joinedAt 用于周期提示），仅清除登录状态与昵称
    players[player_id] = { loggedIn = false, joinedAt = os.time(), lastPrompt = os.time() }
    notify(player_id, "已退出登录", "Logged out")
    -- Clear the vehicle-tag nickname if enabled / 若启用车牌标签系统则清除昵称
    if type(SXMY_VehicleTag_Update) == "function" then
        SXMY_VehicleTag_Update(player_id, nil, true)
    end
end

-- Handle the /reg command / 处理 /reg 命令
local function handleRegister(player_id, args)
    -- Already-logged-in players must /logout first before registering again / 已登录玩家需先 /logout 才能重新注册
    local st0 = players[player_id]
    if st0 and st0.loggedIn then
        notify(player_id, "您已登录 如需重新注册请先使用/logout", "You are already logged in, use /logout first")
        return
    end
    if #args ~= 3 then
        notify(player_id, "请使用/reg 昵称 密码 确认密码 进行注册", "Please use /reg nickname password confirmpassword to register")
        return
    end
    local nick, passwd, confirm = args[1], args[2], args[3]
    -- Ban check hook (PlayerBan module): kicks when the nickname or IP is banned, and the account is NOT saved / 封禁检查钩子（PlayerBan 模块）：昵称或 IP 被封禁则踢出，且不保存账号
    if type(SXMY_PlayerBan_Check) == "function" and SXMY_PlayerBan_Check(player_id, nick, getPlayerIp(player_id)) then
        return
    end
    -- Nickname limited to letters, digits and underscores to keep the file format safe / 昵称仅限字母数字下划线以保持文件格式安全
    if not nick:match("^[%w_]+$") then
        notify(player_id, "昵称只能包含字母、数字和下划线", "Nickname may only contain letters, digits and underscores")
        return
    end
    -- Length limit, the nickname flows into the client vehicle tag API / 长度限制（昵称会流向客户端车辆标签 API）
    local maxNick = lib.get("Auth", "nickLength", 15)
    if #nick > maxNick then
        notify(player_id, ("昵称过长 最多%d个字符"):format(maxNick), ("Nickname too long, max %d characters"):format(maxNick))
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
    -- Per-IP registration limit (0 = unlimited) / 单 IP 注册数量限制（0 不限制）
    local maxRegs = lib.get("Auth", "maxRegsPerIP", 3)
    if maxRegs and maxRegs > 0 then
        local ip = getPlayerIp(player_id)
        if ip and (ipRegCount[ip] or 0) >= maxRegs then
            notify(player_id, "该IP注册的账号数量已达上限", "Registration limit reached for this IP")
            return
        end
    end
    local salt = makeSalt(player_id)
    if not saveAccount(nick, pbkdf2Hash(passwd, salt), getPlayerIp(player_id)) then
        notify(player_id, "账户保存失败 请联系管理员", "Failed to save account, contact an admin")
        return
    end
    players[player_id] = { nick = nick, loggedIn = true, joinedAt = os.time(), lastPrompt = os.time() }
    notify(player_id, "注册成功 已登录", "Registered successfully, logged in")
    -- Notify the vehicle tag system if enabled / 若启用车牌标签系统则通知昵称更新
    if type(SXMY_VehicleTag_Update) == "function" then
        SXMY_VehicleTag_Update(player_id, nick)
    end
end

-- 供 PlayerBan 使用：按登录昵称反查在线玩家 id / find the online player id by a logged-in nickname (used by PlayerBan)
function SXMY_Auth_GetPlayerIdByNick(nick)
    if type(nick) ~= "string" then
        return nil
    end
    for pid, st in pairs(players) do
        if st.loggedIn and st.nick == nick then
            return pid
        end
    end
    return nil
end

-- Handle the /login command with brute-force protection / 处理 /login 命令（含防暴力破解）
local function handleLogin(player_id, args)
    -- Already-logged-in players must /logout first before logging in again / 已登录玩家需先 /logout 才能重新登录
    local st0 = players[player_id]
    if st0 and st0.loggedIn then
        notify(player_id, "您已登录 如需重新登录请先使用/logout", "You are already logged in, use /logout first")
        return
    end
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
    -- Ban check hook (PlayerBan module): kicks when the nickname or IP is banned / 封禁检查钩子（PlayerBan 模块）：昵称或 IP 被封禁则踢出
    if type(SXMY_PlayerBan_Check) == "function" and SXMY_PlayerBan_Check(player_id, nick, getPlayerIp(player_id)) then
        return
    end
    local stored = accounts[nick]
    if stored then
        -- New format "pbkdf2$salt$iter$hex" or legacy "salt$sha256" / plain sha256 / 新格式 pbkdf2$salt$iter$hex 或旧格式 salt$sha256 / 纯 sha256
        local parsed = parseStored(stored)
        local passOK = false
        if parsed then
            if parsed.mode == "pbkdf2" then
                -- Slow-hash verification / 慢哈希验证
                passOK = hexEncode(pbkdf2(passwd, parsed.salt, parsed.iter, 32)) == parsed.hex
            else
                -- Legacy single SHA-256 (with or without salt); upgrade transparently on success / 旧版单次 SHA-256（带盐或不带盐），成功登录后透明升级
                local legacy = SXMY_Auth_sha256((parsed.salt or "") .. passwd)
                passOK = legacy == parsed.hex
                if passOK then
                    upgradeAccount(nick, passwd, parsed.salt or makeSalt(player_id))
                end
            end
        end
        if passOK then
            -- Reject logging in with a nickname another online player already uses / 拒绝已被其他在线玩家使用的昵称（防同昵称多会话）
            local nickInUse = false
            for _, other in pairs(players) do
                if other.loggedIn and other.nick == nick then
                    nickInUse = true
                    break
                end
            end
            if nickInUse then
                notify(player_id, "该昵称已在线 请勿重复登录", "That nickname is already online, do not log in twice")
                return
            end
            loginFails[lockKey] = nil
            players[player_id] = { nick = nick, loggedIn = true, joinedAt = os.time(), lastPrompt = os.time() }
            notify(player_id, "登录成功", "Logged in successfully")
            -- Notify the vehicle tag system if enabled / 若启用车牌标签系统则通知昵称更新
            if type(SXMY_VehicleTag_Update) == "function" then
                SXMY_VehicleTag_Update(player_id, nick)
            end
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
        elseif message == "/logout" or message:sub(1, 8) == "/logout " then
            handleLogout(player_id)
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

-- Periodic tick: prompt unauthenticated players, despawn their leftover vehicles, and expire stale login-fail records / 周期检查：提示未认证玩家、删除其残留车辆并清理过期登录失败记录
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
            -- Despawn vehicles left from a previous session (reconnect, hot-reload) / 删除上次会话残留的车辆（重连、热重载后未登录）
            local ok, vehs = pcall(MP.GetPlayerVehicles, player_id)
            if ok and type(vehs) == "table" then
                for vehId in pairs(vehs) do
                    pcall(MP.RemoveVehicle, player_id, vehId)
                end
            end
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

-- Generate the online-player table rows (shared by the console command and OPAuth private replies) / 生成在线玩家表格行（控制台命令与 OPAuth 私信共用）
-- 列宽：NickName = 昵称限制+2，Name = 15+2，Car 与 ID 右对齐 2 位、间隔 2 空格 / columns: NickName = nick limit + 2, Name = 15 + 2, Car/ID right-aligned 2-wide with 2 spaces
function SXMY_Auth_ListRows()
    local rows = {}
    local maxNick = lib.get("Auth", "nickLength", 15)
    local nickCol = maxNick + 2
    local nameCol = 17 -- 15 chars + 2 separator spaces / 15 字符 + 2 个分隔空格
    rows[#rows + 1] = "NickName" .. (" "):rep(nickCol - 8) .. "Name" .. (" "):rep(nameCol - 4) .. "Car  ID"
    for pid, name in pairs(MP.GetPlayers()) do
        local nick = players[pid] and players[pid].nick or "-"
        local cars = 0
        local ok, vehs = pcall(MP.GetPlayerVehicles, pid)
        if ok and type(vehs) == "table" then
            -- The API returns a map (vehicleID -> data), so count entries with pairs, not # / 该 API 返回字典（vehicleID -> data），用 pairs 计数而非 #
            for _ in pairs(vehs) do
                cars = cars + 1
            end
        end
        rows[#rows + 1] = nick .. (" "):rep(nickCol - #nick) .. name .. (" "):rep(nameCol - #name) .. string.format("%2d", cars) .. "  " .. string.format("%2d", pid)
    end
    return rows
end

-- Get the currently logged-in nickname of a player (nil if not logged in) / 获取玩家当前登录昵称（未登录返回 nil）
function SXMY_Auth_GetLoginNick(player_id)
    local st = players[player_id]
    if st and st.loggedIn and st.nick then
        return st.nick
    end
    return nil
end

-- Check whether an account exists / 检查账户是否存在
function SXMY_Auth_AccountExists(nick)
    return accounts[nick] ~= nil
end

-- 控制台命令：listSXMY —— 输出对齐的在线玩家表格 / console command: listSXMY — print an aligned online-player table
function SXMY_Auth_onConsoleInput(command)
    if not command or not command:match("^listSXMY%s*$") then
        return nil
    end
    local rows = SXMY_Auth_ListRows()
    for _, line in ipairs(rows) do
        print("[SXMY_Auth] " .. line)
    end
    -- Return an empty string (not nil): the console treats nil as "not handled" and prints "Unknown command";
    -- any non-nil value suppresses that and an empty string produces no extra output / 返回空串而非 nil：控制台将 nil 视为"未处理"并打印 Unknown command；非 nil 值可阻止，空串不产生额外输出
    return ""
end

-- Initialize and register events / 初始化并注册事件
loadAccounts()
MP.RegisterEvent("onPlayerJoin", "SXMY_Auth_onPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect", "SXMY_Auth_onPlayerDisconnect")
MP.RegisterEvent("onChatMessage", "SXMY_Auth_onChatMessage")
MP.RegisterEvent("onVehicleSpawn", "SXMY_Auth_onVehicleSpawn")
MP.RegisterEvent("onVehicleEdited", "SXMY_Auth_onVehicleEdited")
MP.RegisterEvent("onConsoleInput", "SXMY_Auth_onConsoleInput")
MP.RegisterEvent("SXMY_Auth_Tick", "SXMY_Auth_Tick")
MP.CreateEventTimer("SXMY_Auth_Tick", 1000)
