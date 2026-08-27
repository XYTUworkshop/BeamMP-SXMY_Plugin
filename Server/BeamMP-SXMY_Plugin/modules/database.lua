-- BeamMP-SXMY_Plugin - modules/database.lua / 数据库同步模块
-- Database sync module / 数据库同步功能模块
-- 通过自制数据库客户端（任意语言）访问数据库，替代本地 users.txt / opusers.txt / banusers.txt
-- Talks to the database through a self-made client (any language), replacing the local files
-- 客户端协议见 README「数据库客户端协议」/ client protocol: see README "Database client protocol"
-- 需要启用 Auth 才有效 / only works when Auth is enabled

local lib = require("modules.lib")

local DB_DIR = "Resources/Server/BeamMP-SXMY_Plugin/database" -- 相对服务器工作目录 / relative to the server working dir
local DB_SECT = "DATABASE"

-- 自动生成/规范化配置节（与其他模块一致：全新安装首次启动自动生成，缺键补默认值，多余键删除）/
-- auto-generate/normalize the config section (like other modules: generated on first start, missing keys get defaults, extra keys are removed)
lib.ensureSection("DATABASE", {
    { key = "enable", v = false, c = "数据库同步功能开关（需启用 Auth，默认关）/ Database sync module switch (requires Auth, off by default)" },
    { key = "dbaddr", v = "127.0.0.1:3306", c = "数据库地址（域名:端口）/ Database address (host:port)" },
    { key = "dbname", v = "", c = "数据库名称 / Database name" },
    { key = "dbuser", v = "", c = "数据库用户名 / Database user" },
    { key = "dbpwd", v = "", c = "数据库密码（注意会出现在客户端进程参数中）/ Database password (note: it appears in the client process arguments)" },
    { key = "users", v = true, c = "同步 users（账户）到数据库并删除本地 users.txt / Sync users (accounts) to the database and remove users.txt" },
    { key = "opusers", v = true, c = "同步 opusers（管理员）到数据库并删除本地 opusers.txt / Sync opusers (admins) to the database and remove opusers.txt" },
    { key = "banusers", v = true, c = "同步 banusers（封禁）到数据库并删除本地 banusers.txt / Sync banusers (bans) to the database and remove banusers.txt" },
})

-- 配置 / configuration
local enabled = lib.get(DB_SECT, "enable", false)
local syncUsers = lib.get(DB_SECT, "users", true)
local syncOpusers = lib.get(DB_SECT, "opusers", true)
local syncBanusers = lib.get(DB_SECT, "banusers", true)
local dbaddr = lib.get(DB_SECT, "dbaddr", "127.0.0.1:3306")
local dbname = lib.get(DB_SECT, "dbname", "")
local dbuser = lib.get(DB_SECT, "dbuser", "")
local dbpwd = lib.get(DB_SECT, "dbpwd", "")
-- 拆分地址与端口 / split the address and the port
local dbhost, dbport = dbaddr:match("^(.-):(%d+)$")
if not dbhost then
    dbhost, dbport = dbaddr, "3306"
end

local clientPath = nil -- 探测到的客户端路径 / the detected client path

-- 识别系统目录名（win/linux/osx）/ detect the system folder name (win/linux/osx)
local function detectSystem()
    if package.config:sub(1, 1) == "/" then
        local uname = ""
        local fh = io.popen("uname")
        if fh then
            uname = fh:read("*l") or ""
            fh:close()
        end
        if uname:lower():find("darwin") then
            return "osx"
        end
        return "linux"
    end
    return "win"
end

-- 按优先级探测客户端：database/<系统>/、database/windows/、database/ 根目录 / probe the client: database/<system>/, database/windows/, database/ root
local function findClient()
    local candidates = {}
    local sys = detectSystem()
    if sys == "win" then
        candidates = {
            DB_DIR .. "/win/dbclient.exe",
            DB_DIR .. "/win/dbclient.bat",
            DB_DIR .. "/win/dbclient.cmd",
            DB_DIR .. "/windows/dbclient.exe",
        }
    elseif sys == "osx" then
        candidates = { DB_DIR .. "/osx/dbclient" }
    else
        candidates = { DB_DIR .. "/linux/dbclient" }
    end
    candidates[#candidates + 1] = DB_DIR .. "/dbclient" -- 跨平台兜底 / cross-platform fallback
    candidates[#candidates + 1] = DB_DIR .. "/dbclient.bat" -- Windows 根目录包装 / root wrapper (Windows)
    candidates[#candidates + 1] = DB_DIR .. "/dbclient.cmd" -- Windows 根目录包装 / root wrapper (Windows)
    candidates[#candidates + 1] = DB_DIR .. "/dbclient.sh" -- Linux 根目录包装 / root wrapper (Linux)
    for _, p in ipairs(candidates) do
        local fh = io.open(p, "r")
        if fh then
            fh:close()
            return p
        end
    end
    return nil
end

-- 值拒绝命令注入字符（平台区分）：
-- 共同拒绝（cmd 与 sh 双引号内均危险）：" & | < > ^ % ( )
-- Linux sh 额外拒绝：$（变量/命令替换）、反引号、;、!
-- Windows cmd 中 $ 是字面量（PBKDF2 哈希格式 pbkdf2$盐$迭代$hex 含 $，必须允许）
-- values reject command-injection characters (platform-aware):
-- common rejections (dangerous in double quotes on both cmd and sh): " & | < > ^ % ( )
-- Linux sh additionally rejects $ (variable/command substitution), backticks, ; and !
-- On Windows cmd $ is a literal, so it is allowed (the PBKDF2 hash format pbkdf2$salt$iter$hex contains $)
local function safeValue(value)
    if value == nil then
        return false
    end
    local s = tostring(value)
    if s:find('"', 1, true) or s:find("&", 1, true) or s:find("|", 1, true) or s:find("<", 1, true)
        or s:find(">", 1, true) or s:find("^", 1, true) or s:find("%", 1, true) or s:find("(", 1, true)
        or s:find(")", 1, true) then
        return false
    end
    if package.config:sub(1, 1) == "/" then
        if s:find("$", 1, true) or s:find("`", 1, true) or s:find(";", 1, true) or s:find("!", 1, true) then
            return false
        end
    end
    return true
end

-- 连接参数（每个命令都带上，客户端据此连接数据库）；含不安全字符时返回 nil（调用方按失败处理）/
-- connection arguments (passed with every command); returns nil when they contain unsafe characters (the caller treats it as a failure)
local function connArgs()
    if not (safeValue(dbhost) and safeValue(dbport) and safeValue(dbname) and safeValue(dbuser) and safeValue(dbpwd)) then
        return nil
    end
    return '--host "' .. dbhost .. '" --port "' .. dbport .. '" --db "' .. tostring(dbname) .. '" --user "' .. tostring(dbuser) .. '" --pass "' .. tostring(dbpwd) .. '"'
end

-- 缓存的工作目录（io.popen("cd") 获取，仅首次调用） / cached working directory (from io.popen("cd"), fetched once)
local cwd = nil
local function getCwd()
    if cwd ~= nil then
        return cwd
    end
    local fh = io.popen("cd")
    if fh then
        cwd = fh:read("*a"):gsub("%s+$", "")
        fh:close()
    end
    cwd = cwd or ""
    return cwd
end

-- 客户端路径转绝对路径（Windows 用反斜杠，cmd 才能可靠执行；相对路径 + 正斜杠会导致 "'Resources' is not recognized"）/
-- turn the client path into an absolute one (backslashes on Windows so cmd can run it; relative paths with slashes cause "'Resources' is not recognized")
local function absoluteClientPath()
    local c = getCwd()
    if c == "" or not clientPath then
        return clientPath
    end
    if package.config:sub(1, 1) == "/" then
        return c .. "/" .. clientPath
    end
    return c .. "\\" .. clientPath:gsub("/", "\\")
end

-- 执行客户端命令，返回 stdout / run the client command and return its stdout
local function exec(args)
    -- Windows cmd /c 的引号剥离规则：命令以引号开头时会剥离首尾引号导致整串被当命令名；
    -- 加 call 前缀使首字符非引号，绕开该规则 / cmd /c strips the surrounding quotes when the command starts with a quote,
    -- which turns the whole string into a single command name; prefixing "call" (first char not a quote) avoids that rule
    local prefix = ""
    if package.config:sub(1, 1) ~= "/" then
        prefix = "call "
    end
    local cargs = connArgs()
    if not cargs then
        -- 连接参数含不安全字符（如密码含引号/百分号）：按失败处理，不执行命令 / unsafe connection args (e.g. a quote or % in the password): treat as a failure, do not run
        return "ERROR: unsafe connection arguments"
    end
    local fh = io.popen(prefix .. '"' .. absoluteClientPath() .. '" ' .. cargs .. " " .. args, "r")
    if not fh then
        return nil
    end
    local out = fh:read("*a")
    fh:close()
    return out
end

-- 输出以 ERROR 开头视为失败（严格匹配 ERROR: 或 ERROR+空白，避免把 ERRORxxx 昵称数据行误判）/
-- an output starting with ERROR is a failure (strict: ERROR: or ERROR+space, so a nickname row like "ERRORabc = x" is not mistaken for an error)
local function isError(out)
    return out == nil or out:match("^%s*ERROR[:%s]") ~= nil
end

-- 写操作的成功判定：客户端必须输出 OK（dbclient 写命令成功输出 "OK"）；
-- 任何其他输出（含 cmd 的 "'Resources' is not recognized" 等错误文本、空输出）一律视为失败，杜绝假成功 /
-- success check for write commands: the client must print "OK" (dbclient prints it on success);
-- any other output (including cmd error text like "'Resources' is not recognized" or an empty output) is a failure, no false positives
local function okStatus(out)
    return out ~= nil and out:match("^%s*OK%s*$") ~= nil
end

-- 表名白名单（防表名注入命令行） / whitelist of valid tables (prevents table-name injection into the command line)
local VALID_TABLES = { users = true, opusers = true, banusers = true }

-- 初始化是否成功（dbInit 通过后才允许读写，失败时各模块回退本地文件）/ whether the init succeeded (read/write only after a successful init; on failure modules fall back to the local files)
local dbReady = false

-- 键的安全字符：昵称/IP/前缀键（字母数字下划线点冒号连字符）/ safe characters for keys (nicknames/IPs/prefixed keys)
local function safeKey(key)
    return key ~= nil and tostring(key):match("^[%w_%.%:%-]+$") ~= nil
end

-- 参数用双引号包裹（值可能含空格），内部双引号转义 / wrap args in double quotes (values may contain spaces), escape inner quotes
local function quoteArg(arg)
    return '"' .. tostring(arg):gsub('"', '\\"') .. '"'
end

local function dbInit()
    return okStatus(exec("init"))
end

-- 读全表：每行 `key = value` / read a whole table: one `key = value` per line
local function dbLoad(tableName)
    if not VALID_TABLES[tableName] then
        return nil
    end
    local out = exec("load " .. tableName)
    if isError(out) then
        return nil
    end
    local rows = {}
    for line in (out .. "\n"):gmatch("(.-)\r?\n") do
        local k, v = line:match("^(.-) = (.*)$")
        if k and k ~= "" then
            rows[k] = v
        end
    end
    return rows
end

local function dbSet(tableName, key, value)
    if not VALID_TABLES[tableName] or not safeKey(key) or not safeValue(value) then
        return false
    end
    return okStatus(exec("set " .. tableName .. " " .. quoteArg(key) .. " " .. quoteArg(value)))
end

local function dbDel(tableName, key)
    if not VALID_TABLES[tableName] or not safeKey(key) then
        return false
    end
    return okStatus(exec("del " .. tableName .. " " .. quoteArg(key)))
end

-- 把本地文件同步至数据库（成功才删除本地文件）/ sync a local file into the database (delete the local file only on success)
local function syncTable(tableName, filePath)
    local fh = io.open(filePath, "r")
    if not fh then
        return true -- 无本地文件 = 无待同步数据 / nothing to sync
    end
    local ok = true
    for line in fh:lines() do
        local key, value = line:match("^(.-) = (.*)$")
        if tableName == "opusers" then
            local nick = line:match("^%s*(%S+)%s*$")
            if nick and nick ~= "" then
                ok = dbSet(tableName, nick, "1") and ok
            end
        elseif key then
            ok = dbSet(tableName, key, value) and ok
        end
    end
    fh:close()
    if ok then
        os.remove(filePath)
        print("[SXMY_DATABASE] " .. lib.msg("已将本地文件同步至数据库并删除：", "Synced and removed the local file: ") .. filePath)
    else
        print("[SXMY_DATABASE] " .. lib.msg("同步失败 保留本地文件：", "Sync failed, local file kept: ") .. filePath)
    end
    return ok
end

-- ===== 供 Auth / OPAuth / PlayerBan 调用的全局接口 / global API for Auth / OPAuth / PlayerBan =====
function SXMY_Database_IsEnabled(tableName)
    if not enabled or not clientPath or not dbReady then
        return false
    end
    if tableName == "users" then
        return syncUsers
    elseif tableName == "opusers" then
        return syncOpusers
    elseif tableName == "banusers" then
        return syncBanusers
    end
    return false
end

function SXMY_Database_Load(tableName)
    if not SXMY_Database_IsEnabled(tableName) then
        return nil
    end
    return dbLoad(tableName)
end

function SXMY_Database_Set(tableName, key, value)
    if not SXMY_Database_IsEnabled(tableName) then
        return false
    end
    return dbSet(tableName, key, value)
end

function SXMY_Database_Del(tableName, key)
    if not SXMY_Database_IsEnabled(tableName) then
        return false
    end
    return dbDel(tableName, key)
end

-- ===== 模块主体：探测客户端 → 初始化 → 同步并删除本地文件 / probe the client -> init -> sync and remove the local files =====
if not lib.enabled("Auth") then
    print("[SXMY_DATABASE] " .. lib.msg("未启用 Auth 功能 database 不工作", "Auth is not enabled, database is not active"))
    return {}
end

clientPath = findClient()
if not clientPath then
    print("[SXMY_DATABASE] " .. lib.msg("未找到数据库客户端 请在 database/ 目录放置（见 README 客户端协议）", "Database client not found, place it in the database/ directory (see the README client protocol)"))
    return {}
end

if not dbInit() then
    print("[SXMY_DATABASE] " .. lib.msg("数据库客户端初始化失败（检查连接信息与客户端实现）", "Database client init failed (check the connection info and the client implementation)"))
    return {}
end

print("[SXMY_DATABASE] " .. lib.msg("数据库客户端已连接 (", "Database client connected (") .. clientPath .. lib.msg(")", ")"))
dbReady = true

if syncUsers then
    syncTable("users", "Resources/Server/BeamMP-SXMY_Plugin/users.txt")
end
if syncOpusers then
    syncTable("opusers", "Resources/Server/BeamMP-SXMY_Plugin/opusers.txt")
end
if syncBanusers then
    syncTable("banusers", "Resources/Server/BeamMP-SXMY_Plugin/banusers.txt")
end
