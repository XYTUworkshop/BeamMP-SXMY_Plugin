-- lib/02.DataBase.lua — 功能：数据库（文件模式 FL / 数据库模式 DB）
-- 职责：
--   1. 配置项：DataBase-enable / address / BaseName / Basepwd
--   2. 功能：Database（启动报告三行状态 / Reload）
--   3. 模式：
--      * 数据库模式（enable=true 且连接成功）：调用 DBmode/db.py（MySQL）
--      * 文件模式（未启用或连接失败）：调用 FLmode/fl.py（操作 DataBase/.files）
--   4. 对外接口：SXMY.DataBase.FLCreate/FLDelete/FLRead/FLWrite
--                 SXMY.DataBase.DBCreateTable/DBDropTable/DBRead/DBWrite
-- 依赖 main.lua：SXMY.T / SXMY.Config / SXMY.SetConfigValue
--            / SXMY.RegisterConfigItem / SXMY.RegisterFeature

local DB_PATH = "Resources/Server/SXMY_Plugin/DataBase/"
local FL_SCRIPT = DB_PATH .. "FLmode/fl.py"
local DB_SCRIPT = DB_PATH .. "DBmode/db.py"

-- ============================================================
-- 配置读取
-- ============================================================

local function GetCfg()
    local c = (SXMY.Config and SXMY.Config.DataBase) or {}
    local enable = (c.enable == true)
    local address = c.address
    if type(address) ~= "string" or address == "" then
        address = "127.0.0.1:3306"
    end
    local bname = c.BaseName
    if type(bname) ~= "string" then bname = "" end
    -- 数据库用户名：配置为空时默认 root
    local buser = c.BaseUser
    if type(buser) ~= "string" or buser == "" then
        buser = "root"
    end
    local bpwd = c.Basepwd
    if type(bpwd) ~= "string" then bpwd = "" end
    return { enable = enable, address = address, BaseName = bname,
        BaseUser = buser, Basepwd = bpwd }
end

-- ============================================================
-- 脚本调用（跨平台 python 选择）
-- ============================================================

local function GetPythonCmd()
    local osname = "linux"
    if MP and MP.GetOSName then
        osname = tostring(MP.GetOSName() or "linux"):lower()
    end
    if osname:find("windows", 1, true) then
        return "python"
    end
    return "python3"
end

-- 运行脚本：RunScript(script, {arg1, arg2, ...}) -> ok, output
-- os.execute 执行，输出重定向到临时文件再读回（BeamMP 的 io.popen 会阻塞 Lua 状态）
local OUT_FILE = "Resources/Server/SXMY_Plugin/DataBase/.files/.result"

local function RunScript(script, args)
    local cmd = GetPythonCmd() .. ' "' .. script .. '"'
    for _, a in ipairs(args) do
        local s = tostring(a)
        s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
        cmd = cmd .. ' "' .. s .. '"'
    end
    if os and os.execute then
        local ok, how, code = os.execute(cmd .. ' > "' .. OUT_FILE .. '" 2>&1')
        local success = (ok == true) or (code == 0)
        local out = ""
        if success then
            local f = io.open(OUT_FILE, "rb")
            if f then
                out = f:read("*a")
                f:close()
            end
        end
        return success, out
    end
    if io and io.popen then
        local handle = io.popen(cmd, "r")
        if not handle then
            return false, "ERR: cannot run script"
        end
        local out = handle:read("*a")
        local code = handle:close()
        if code == nil then code = 0 end
        return code == 0, out or ""
    end
    return false, "ERR: os.execute and io.popen unavailable"
end

-- ============================================================
-- 数据库连接测试（db.py ping）
-- ============================================================

local function DBPing()
    local cfg = GetCfg()
    local ok, out = RunScript(DB_SCRIPT,
        { "ping", cfg.address, cfg.BaseUser, cfg.Basepwd, "information_schema" })
    if not ok then return false end
    return out:find("OK", 1, true) ~= nil
end

-- ============================================================
-- 对外操作接口（供其他模块调用）
-- ============================================================

SXMY.DataBase = SXMY.DataBase or {}

-- 文件模式（操作 DataBase/.files 下文件）
function SXMY.DataBase.FLCreate(name, content)
    return RunScript(FL_SCRIPT, { "create", name, content or "" })
end

function SXMY.DataBase.FLDelete(name)
    return RunScript(FL_SCRIPT, { "delete", name })
end

function SXMY.DataBase.FLRead(name)
    return RunScript(FL_SCRIPT, { "read", name })
end

function SXMY.DataBase.FLWrite(name, content)
    return RunScript(FL_SCRIPT, { "write", name, content or "" })
end

-- 数据库模式（MySQL 表操作）
function SXMY.DataBase.DBCreateTable(table_name, schema)
    local cfg = GetCfg()
    return RunScript(DB_SCRIPT, { "create_table", cfg.address, cfg.BaseUser, cfg.Basepwd,
        cfg.BaseName, table_name, schema })
end

function SXMY.DataBase.DBDropTable(table_name)
    local cfg = GetCfg()
    return RunScript(DB_SCRIPT, { "drop_table", cfg.address, cfg.BaseUser, cfg.Basepwd,
        cfg.BaseName, table_name })
end

function SXMY.DataBase.DBRead(table_name)
    local cfg = GetCfg()
    return RunScript(DB_SCRIPT, { "read", cfg.address, cfg.BaseUser, cfg.Basepwd,
        cfg.BaseName, table_name })
end

function SXMY.DataBase.DBWrite(table_name, set_sql, where_sql)
    local cfg = GetCfg()
    return RunScript(DB_SCRIPT, { "write", cfg.address, cfg.BaseUser, cfg.Basepwd,
        cfg.BaseName, table_name, set_sql, where_sql })
end

-- ============================================================
-- 配置项注册
-- ============================================================

SXMY.RegisterConfigItem("DataBase-enable", {
    name = "DataBase-enable",
    usage = function()
        return SXMY.T("config.usageDbEnable")
    end,
    validate = function(v)
        v = v:lower()
        if v == "true" then return true, true end
        if v == "false" then return true, false end
        return false, v
    end,
    available = function()
        return "true/false"
    end,
    apply = function(v)
        SXMY.SetConfigValue("DataBase", "enable", v)
    end,
    reload = function()
    end,
})

SXMY.RegisterConfigItem("DataBase-address", {
    name = "DataBase-address",
    usage = function()
        return SXMY.T("config.usageDbAddress")
    end,
    validate = function(v)
        return true, v
    end,
    available = function()
        return SXMY.T("config.dbAddressValue")
    end,
    apply = function(v)
        SXMY.SetConfigValue("DataBase", "address", v)
    end,
    reload = function()
    end,
})

SXMY.RegisterConfigItem("DataBase-BaseName", {
    name = "DataBase-BaseName",
    usage = function()
        return SXMY.T("config.usageDbBaseName")
    end,
    validate = function(v)
        return true, v
    end,
    available = function()
        return SXMY.T("config.dbBaseNameValue")
    end,
    apply = function(v)
        SXMY.SetConfigValue("DataBase", "BaseName", v)
    end,
    reload = function()
    end,
})

SXMY.RegisterConfigItem("DataBase-BaseUser", {
    name = "DataBase-BaseUser",
    usage = function()
        return SXMY.T("config.usageDbBaseUser")
    end,
    validate = function(v)
        return true, v
    end,
    available = function()
        return SXMY.T("config.dbBaseUserValue")
    end,
    apply = function(v)
        SXMY.SetConfigValue("DataBase", "BaseUser", v)
    end,
    reload = function()
    end,
})

SXMY.RegisterConfigItem("DataBase-Basepwd", {
    name = "DataBase-Basepwd",
    usage = function()
        return SXMY.T("config.usageDbBasepwd")
    end,
    validate = function(v)
        return true, v
    end,
    available = function()
        return SXMY.T("config.dbBasepwdValue")
    end,
    apply = function(v)
        SXMY.SetConfigValue("DataBase", "Basepwd", v)
    end,
    reload = function()
    end,
})

-- ============================================================
-- 命令：DB —— 查询数据库实时状态
-- ============================================================

local function DbHandler()
    local cfg = GetCfg()
    if not cfg.enable then
        return SXMY.T("database.statusDisabled")
    end
    local lines = {}
    if DBPing() then
        lines[#lines + 1] = SXMY.T("database.statusConnected")
    else
        lines[#lines + 1] = SXMY.T("database.statusDisconnected")
    end
    lines[#lines + 1] = SXMY.T("database.statusAddress", cfg.address)
    lines[#lines + 1] = SXMY.T("database.statusName", cfg.BaseName)
    return table.concat(lines, "\n")
end

SXMY.RegisterCommand("DB", "help.descDb", DbHandler)

-- ============================================================
-- 功能注册（启动报告三行）
-- ============================================================

SXMY.RegisterFeature("Database", {
    name = "Database",
    reload = function()
    end,
    report = function()
        local cfg = GetCfg()
        if not cfg.enable then
            print(SXMY.T("database.disabled"))
            print(SXMY.T("database.fileModeUnused"))
        else
            print(SXMY.T("database.enabled"))
            if DBPing() then
                print(SXMY.T("database.connected"))
                print(SXMY.T("database.usingDb"))
            else
                print(SXMY.T("database.connectFailed"))
                print(SXMY.T("database.usingFile"))
            end
        end
    end,
})
