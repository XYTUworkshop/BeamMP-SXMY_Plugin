-- main.lua — SXMY_Plugin 入口
-- main 的职责：
--   1. 生成配置文件（config.toml 缺失/为空时写入默认）
--   2. 加载插件（lib/ 下的模块）
--   3. 查询插件配置
--   4. 载入插件
--
-- 命令系统：SXMY <子命令> <参数...>，所有输入大小写不敏感
-- 文案集中管理：Language/zh.json、en.json 等，代码通过 T(key, ...) 取用

SXMY = SXMY or {}
SXMY.PLUGIN_NAME = "SXMY_Plugin"
SXMY.VERSION = "2.0.0.2609011529_Alpha"
SXMY.CONFIG_FILE = "Resources/Server/SXMY_Plugin/config.toml"
SXMY.LANGUAGE_PATH = "Resources/Server/SXMY_Plugin/Language/"
SXMY.LIB_PATH = "Resources/Server/SXMY_Plugin/lib/"

local function Log(msg)
    print("[SXMY] " .. msg)
end

-- ============================================================
-- i18n：语言文件加载 + 翻译函数
-- ============================================================

local i18n_data = {}

function SXMY.T(key, ...)
    if type(key) ~= "string" then return tostring(key) end
    local t = i18n_data
    local dot = key:find(".", 1, true)
    while dot do
        local part = key:sub(1, dot - 1)
        t = t[part]
        if t == nil then return key end
        key = key:sub(dot + 1)
        dot = key:find(".", 1, true)
    end
    local v = t[key]
    if type(v) ~= "string" then return key end
    local args = { ... }
    if #args > 0 then
        v = v:gsub("{(%d+)}", function(n)
            local a = args[tonumber(n)]
            if a == nil then return "{" .. n .. "}" end
            return tostring(a)
        end)
    end
    return v
end

local function Raw(key)
    local t = i18n_data
    local dot = key:find(".", 1, true)
    while dot do
        local part = key:sub(1, dot - 1)
        t = t[part]
        if t == nil then return nil end
        key = key:sub(dot + 1)
        dot = key:find(".", 1, true)
    end
    return t[key]
end

local function LoadLanguage(lang)
    i18n_data = {}
    local f = io.open(SXMY.LANGUAGE_PATH .. lang .. ".json", "rb")
    if not f then
        Log(SXMY.T("i18n.loadFailed", lang))
        return
    end
    local content = f:read("*a")
    f:close()
    if not (Util and Util.JsonDecode) then
        Log(SXMY.T("i18n.noJsonDecoder"))
        return
    end
    local ok, data = pcall(Util.JsonDecode, content)
    if not ok or type(data) ~= "table" then
        Log(SXMY.T("i18n.parseFailed", lang))
        return
    end
    i18n_data = data
end

-- ============================================================
-- 轻量 TOML 解析（config.toml 子集：段/键值/字符串/布尔/数字/注释）
-- ============================================================

local function ParseToml(content)
    local root = {}
    local current = root
    for line in content:gmatch("[^\r\n]+") do
        local trimmed = line:gsub("^%s+", "")
        if trimmed == "" or trimmed:sub(1, 1) == "#" then
            -- 空行/注释
        elseif trimmed:sub(1, 1) == "[" then
            local sec = trimmed:match("^%[%s*([%w_%-]+)%s*%]$")
            if sec then
                current = {}
                root[sec] = current
            end
        else
            local key, val = trimmed:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
            if key and val then
                local s = val:match('^"(.*)"$')
                if not s then
                    -- 非字符串：去掉行尾注释
                    val = val:gsub("%s*#.*$", "")
                    val = val:gsub("%s+$", "")
                    s = val:match('^"(.*)"$')
                end
                if s then
                    -- 保留字面内容（text 用 <\n> 作换行标记，不做反斜杠转义）
                    s = s:gsub('\\"', '"')
                    current[key] = s
                elseif val == "true" then
                    current[key] = true
                elseif val == "false" then
                    current[key] = false
                else
                    local num = tonumber(val)
                    if num then current[key] = num end
                end
            end
        end
    end
    return root
end

-- ============================================================
-- 配置：默认值 / 加载 / 读取 / 修改
-- ============================================================

local DEFAULT_CONFIG = {
    general = {
        Language = "zh",
    },
    WelcomeMsg = {
        enable = true,
        delay = 5,
        text = "Welcome to SXMY server<\\n>Enjoy",
    },
    DataBase = {
        enable = false,
        address = "127.0.0.1:3306",
        BaseName = "",
        BaseUser = "",
        Basepwd = "",
    },
}

local config_data = nil -- 生效配置（默认 + 文件合并）

local function deep_copy(t)
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then out[k] = deep_copy(v) else out[k] = v end
    end
    return out
end

local function deep_merge(base, override)
    for k, v in pairs(override) do
        if type(v) == "table" and type(base[k]) == "table" then
            deep_merge(base[k], v)
        else
            base[k] = v
        end
    end
    return base
end

local function WriteDefaultConfig()
    local f = io.open(SXMY.CONFIG_FILE, "wb")
    if not f then
        Log(SXMY.T("config.cannotCreate", SXMY.CONFIG_FILE))
        return
    end
    f:write(SXMY.T("config.defaultTemplate"))
    f:close()
    Log(SXMY.T("config.generated", SXMY.CONFIG_FILE))
end

-- 加载配置：文件缺失/为空 -> 生成默认；解析失败 -> 默认值
local function LoadConfig()
    local f = io.open(SXMY.CONFIG_FILE, "rb")
    if not f then
        WriteDefaultConfig()
        config_data = deep_copy(DEFAULT_CONFIG)
        return
    end
    local content = f:read("*a")
    f:close()
    if content:gsub("%s", "") == "" then
        WriteDefaultConfig()
        config_data = deep_copy(DEFAULT_CONFIG)
        return
    end
    local ok, parsed = pcall(ParseToml, content)
    if not ok or type(parsed) ~= "table" then
        Log(SXMY.T("config.parseFailed"))
        config_data = deep_copy(DEFAULT_CONFIG)
        return
    end
    config_data = deep_merge(deep_copy(DEFAULT_CONFIG), parsed)
end

-- 暴露给 lib 模块：当前生效配置（只读约定）
SXMY.Config = {}

local function GetLanguage()
    local lang = config_data.general and config_data.general.Language
    if type(lang) == "string" then
        lang = lang:lower()
        if lang == "zh" or lang == "en" then return lang end
    end
    return "zh"
end

-- 按配置语言重新加载语言文件
local function ReloadLanguage()
    LoadLanguage(GetLanguage())
end

-- pattern 转义（配置项名/段名可能含 - 等）
local function Esc(s)
    return s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

-- TOML 值格式化（写回文件用；仅转义引号，保留 <\n> 字面标记）
local function FormatTomlValue(v)
    if type(v) == "boolean" then return v and "true" or "false" end
    if type(v) == "number" then return tostring(v) end
    local s = tostring(v)
    s = s:gsub('"', '\\"')
    return '"' .. s .. '"'
end

-- 修改配置：更新内存 SXMY.Config 并写回 config.toml（保留用户其他内容）
function SXMY.SetConfigValue(section, key, value)
    -- 更新内存
    if not config_data[section] then config_data[section] = {} end
    config_data[section][key] = value
    SXMY.Config = config_data
    -- 写文件
    local content = ""
    local f = io.open(SXMY.CONFIG_FILE, "rb")
    if f then content = f:read("*a"); f:close() end
    local lines = {}
    -- 按 \n 切分并保留空行（末尾补 \n 保证最后一行也产出）
    for line in (content .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    -- 去掉尾随空元素（末尾补的 \n 会产生一个空串）
    while #lines > 0 and lines[#lines] == "" do
        lines[#lines] = nil
    end
    local e_sec, e_key = Esc(section), Esc(key)
    local sec_idx = nil
    for i, l in ipairs(lines) do
        if l:match("^%[%s*" .. e_sec .. "%s*%]") then sec_idx = i break end
    end
    local newline = key .. " = " .. FormatTomlValue(value)
    if sec_idx then
        local replaced = false
        local i = sec_idx + 1
        while i <= #lines and not lines[i]:match("^%s*%[") do
            if lines[i]:match("^%s*" .. e_key .. "%s*=") then
                lines[i] = newline
                replaced = true
                break
            end
            i = i + 1
        end
        if not replaced then
            table.insert(lines, i, newline)
        end
    else
        lines[#lines + 1] = ""
        lines[#lines + 1] = "[" .. section .. "]"
        lines[#lines + 1] = newline
    end
    local w = io.open(SXMY.CONFIG_FILE, "wb")
    if w then
        w:write(table.concat(lines, "\n"))
        w:close()
    end
end

-- 可用语言列表：读 Language 目录下 .json 文件名（无 FS 时回退 zh/en）
local function ListLanguages()
    local langs = {}
    if FS and FS.ListFiles then
        local ok, files = pcall(FS.ListFiles, SXMY.LANGUAGE_PATH)
        if ok and type(files) == "table" then
            for _, fn in ipairs(files) do
                local base = fn:match("^(.-)%.json$")
                if base and base ~= "" then langs[#langs + 1] = base end
            end
        end
    end
    if #langs == 0 then langs = { "zh", "en" } end
    table.sort(langs)
    return langs
end

-- ============================================================
-- 注册系统：命令 / 配置项 / 功能（lib 模块调用）
-- ============================================================

local commands = {}
local command_order = {}

function SXMY.RegisterCommand(name, descKey, handler)
    local upper = name:upper()
    commands[upper] = { name = name, descKey = descKey, handler = handler }
    command_order[#command_order + 1] = upper
end

local config_items = {}
local config_order = {}

function SXMY.RegisterConfigItem(name, item)
    local upper = name:upper()
    config_items[upper] = item
    config_order[#config_order + 1] = upper
end

local features = {}
local feature_order = {}

function SXMY.RegisterFeature(name, feature)
    local upper = name:upper()
    features[upper] = feature
    feature_order[#feature_order + 1] = upper
end

-- ============================================================
-- help 输出：表头 + 命令列表（第二列停在 commandWidth+2+x 显示位置）
-- ============================================================

local function BuildHelp()
    local longest = 0
    for _, upper in ipairs(command_order) do
        local n = commands[upper].name
        if #n > longest then longest = #n end
    end
    local cw = Raw("meta.commandWidth")
    if type(cw) ~= "number" then cw = 4 end
    local x = longest - cw
    if 2 + x < 0 then x = 0 end
    local lines = { SXMY.T("help.header", string.rep(" ", 2 + x)) }
    for _, upper in ipairs(command_order) do
        local c = commands[upper]
        local cmd_pad = cw + 2 + x - #c.name
        if cmd_pad < 0 then cmd_pad = 0 end
        lines[#lines + 1] = SXMY.T("help.linePrefix") .. c.name .. string.rep(" ", cmd_pad) .. SXMY.T(c.descKey)
    end
    lines[#lines + 1] = "[SXMY]"
    return table.concat(lines, "\n")
end

-- ============================================================
-- 子命令：Config
-- ============================================================

local function ConfigUsage()
    local lines = { SXMY.T("config.usage") }
    for _, upper in ipairs(config_order) do
        lines[#lines + 1] = SXMY.T("config.usageItems", config_items[upper].name)
    end
    lines[#lines + 1] = SXMY.T("config.usageValueHint")
    lines[#lines + 1] = SXMY.T("config.usageReload")
    return table.concat(lines, "\n")
end

local function ConfigHandler(parts, quoted)
    local item = parts[3]
    if not item then return ConfigUsage() end
    local cfg = config_items[item:upper()]
    if not cfg then return ConfigUsage() end
    local value = parts[4]
    if not value then return cfg.usage() end
    -- 要求引号包裹的配置项（如 WelcomeMsg-text）
    if cfg.requireQuoted and not (quoted and quoted[4]) then
        return SXMY.T("config.quotedRequired", cfg.name)
    end
    local ok, normalized = cfg.validate(value)
    if not ok then
        return SXMY.T("config.invalidValue", value, cfg.available())
    end
    cfg.apply(normalized)
    local reload = true
    local r = parts[5]
    if r then reload = (r:lower() == "y") end
    if reload and cfg.reload then cfg.reload() end
    if reload then
        return SXMY.T("config.setOkReloaded", cfg.name, normalized)
    end
    return SXMY.T("config.setOkNotReloaded", cfg.name, normalized)
end

-- 配置项：main-Language
SXMY.RegisterConfigItem("main-Language", {
    name = "main-Language",
    usage = function()
        return SXMY.T("config.usageItem", "main-Language") .. "\n"
            .. SXMY.T("config.usageItemValues", table.concat(ListLanguages(), "/"))
    end,
    validate = function(v)
        v = v:lower()
        for _, l in ipairs(ListLanguages()) do
            if l == v then return true, v end
        end
        return false, v
    end,
    available = function()
        return table.concat(ListLanguages(), "/")
    end,
    apply = function(v)
        SXMY.SetConfigValue("general", "Language", v)
    end,
    reload = function()
        ReloadLanguage()
    end,
})

-- ============================================================
-- 子命令：Reload
-- ============================================================

local function ReloadUsage()
    local names = {}
    for _, upper in ipairs(feature_order) do
        names[#names + 1] = features[upper].name
    end
    return SXMY.T("reload.usage") .. "\n"
        .. SXMY.T("reload.usageFeatures", table.concat(names, "/"))
end

local function ReloadHandler(parts)
    local feature = parts[3]
    if not feature then
        for _, upper in ipairs(feature_order) do
            local ok, err = pcall(features[upper].reload)
            if not ok then
                Log(SXMY.T("reload.featureError", features[upper].name, tostring(err)))
            end
        end
        return SXMY.T("reload.done")
    end
    if feature:lower() == "help" then return ReloadUsage() end
    local feat = features[feature:upper()]
    if not feat then return SXMY.T("reload.unknownFeature", feature) end
    local ok, err = pcall(feat.reload)
    if not ok then return SXMY.T("reload.featureError", feat.name, tostring(err)) end
    return SXMY.T("reload.doneFeature", feat.name)
end

-- 功能：main（重载语言等 main 级配置）
SXMY.RegisterFeature("main", {
    name = "main",
    reload = function()
        ReloadLanguage()
    end,
})

-- ============================================================
-- 命令注册与入口分派
-- ============================================================

SXMY.RegisterCommand("Reload", "help.descReload", ReloadHandler)
SXMY.RegisterCommand("Config", "help.descConfig", ConfigHandler)

-- 参数切分：支持 "带空格参数" 与 '单引号参数'；
-- 返回 parts 与 quoted（每个参数是否被引号包裹）
local function SplitArgs(input)
    local parts, quoted = {}, {}
    local i = 1
    local n = #input
    while i <= n do
        while i <= n and input:sub(i, i):match("%s") do i = i + 1 end
        if i > n then break end
        local c = input:sub(i, i)
        if c == '"' or c == "'" then
            local q = c
            local buf = {}
            i = i + 1
            while i <= n do
                local ch = input:sub(i, i)
                if ch == q then i = i + 1 break end
                buf[#buf + 1] = ch
                i = i + 1
            end
            parts[#parts + 1] = table.concat(buf)
            quoted[#parts] = true
        else
            local buf = {}
            while i <= n and not input:sub(i, i):match("%s") do
                buf[#buf + 1] = input:sub(i, i)
                i = i + 1
            end
            parts[#parts + 1] = table.concat(buf)
            quoted[#parts] = false
        end
    end
    return parts, quoted
end

function SXMY_HandleConsoleInput(input)
    if type(input) ~= "string" then return nil end
    local parts, quoted = SplitArgs(input)
    if #parts == 0 then return nil end
    if parts[1]:upper() ~= "SXMY" then return nil end
    if #parts == 1 then return BuildHelp() end
    local sub = commands[parts[2]:upper()]
    if not sub then return BuildHelp() end
    return sub.handler(parts, quoted)
end

-- ============================================================
-- lib 模块加载
-- ============================================================

local function LoadModules()
    local files = {}
    if FS and FS.ListFiles then
        local ok, list = pcall(FS.ListFiles, SXMY.LIB_PATH)
        if ok and type(list) == "table" then
            for _, fn in ipairs(list) do
                if fn:match("%.lua$") then files[#files + 1] = fn end
            end
        end
    end
    table.sort(files)
    for _, fn in ipairs(files) do
        local chunk, err = loadfile(SXMY.LIB_PATH .. fn)
        if not chunk then
            Log(SXMY.T("main.moduleLoadFailed", fn, tostring(err)))
        else
            local okc, e2 = pcall(chunk)
            if not okc then
                Log(SXMY.T("main.moduleLoadFailed", fn, tostring(e2)))
            end
        end
    end
end

-- ============================================================
-- 启动流程
-- ============================================================

LoadLanguage("zh")       -- 兜底语言
LoadConfig()             -- 加载配置（缺失/空则生成默认）
SXMY.Config = config_data
LoadLanguage(GetLanguage()) -- 按配置语言加载

Log(SXMY.T("main.starting"))
LoadModules()            -- 加载 lib 模块（模块在此注册功能/配置项）
Log(SXMY.T("main.loaded"))

-- 功能启动报告（各模块输出"功能 X 已启用/未启用"等）
for _, upper in ipairs(feature_order) do
    local f = features[upper]
    if f.report then
        local ok, err = pcall(f.report)
        if not ok then
            Log(SXMY.T("main.reportFailed", f.name, tostring(err)))
        end
    end
end

MP.RegisterEvent("onConsoleInput", "SXMY_HandleConsoleInput")
