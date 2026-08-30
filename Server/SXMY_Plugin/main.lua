-- main.lua — SXMY_Plugin 入口
-- main 的职责（逐步实现）：
--   1. 生成配置文件（config.toml 缺失/为空时写入默认）
--   2. 加载插件（lib/ 下的模块）
--   3. 查询插件配置
--   4. 载入插件
--
-- 命令系统：SXMY <子命令> <参数...>，所有输入大小写不敏感
-- 文案集中管理：Language/zh.json、en.json 等，代码通过 T(key, ...) 取用

SXMY = SXMY or {}
SXMY.PLUGIN_NAME = "SXMY_Plugin"
SXMY.CONFIG_FILE = "Resources/Server/SXMY_Plugin/config.toml"
SXMY.LANGUAGE_PATH = "Resources/Server/SXMY_Plugin/Language/"

-- ============================================================
-- i18n：语言文件加载 + 翻译函数
-- ============================================================

local i18n_data = {} -- 当前语言数据

local function Log(msg)
    print("[SXMY] " .. msg)
end

-- 取文案：T("config.generated", path)，点号路径 + {1}{2} 占位符；缺失回退 key
local function T(key, ...)
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

-- 取原始值（如 meta.commandWidth）
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
        Log(T("i18n.loadFailed", lang))
        return
    end
    local content = f:read("*a")
    f:close()
    if not (Util and Util.JsonDecode) then
        Log(T("i18n.noJsonDecoder"))
        return
    end
    local ok, data = pcall(Util.JsonDecode, content)
    if not ok or type(data) ~= "table" then
        Log(T("i18n.parseFailed", lang))
        return
    end
    i18n_data = data
end

-- ============================================================
-- 配置：生成默认 + 读取/修改 Language
-- ============================================================

local function ReadConfigLanguage()
    local f = io.open(SXMY.CONFIG_FILE, "rb")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    if content:gsub("%s", "") == "" then return nil end
    local lang = content:match('Language%s*=%s*"([^"]+)"')
    if lang then
        lang = lang:lower()
        if lang == "zh" or lang == "en" then return lang end
    end
    return nil
end

local function WriteDefaultConfig()
    local f = io.open(SXMY.CONFIG_FILE, "wb")
    if not f then
        Log(T("config.cannotCreate", SXMY.CONFIG_FILE))
        return
    end
    f:write(T("config.defaultTemplate"))
    f:close()
    Log(T("config.generated", SXMY.CONFIG_FILE))
end

local function GetLanguage()
    local lang = ReadConfigLanguage()
    if not lang then
        WriteDefaultConfig()
        return "zh"
    end
    return lang
end

-- 修改 config.toml 中的 Language（保留用户其他内容；无该行则追加）
local function SetConfigLanguage(lang)
    local content = nil
    local f = io.open(SXMY.CONFIG_FILE, "rb")
    if f then
        content = f:read("*a")
        f:close()
    end
    if content and content:match('Language%s*=%s*"[^"]*"') then
        content = content:gsub('Language%s*=%s*"[^"]*"', 'Language = "' .. lang .. '"')
    elseif content then
        content = content .. '\n[general]\nLanguage = "' .. lang .. '"\n'
    else
        content = 'Language = "' .. lang .. '"\n'
    end
    local w = io.open(SXMY.CONFIG_FILE, "wb")
    if w then
        w:write(content)
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
                if base and base ~= "" then
                    langs[#langs + 1] = base
                end
            end
        end
    end
    if #langs == 0 then
        langs = { "zh", "en" }
    end
    table.sort(langs)
    return langs
end

-- 按配置语言重新加载语言文件（Language 配置项/功能的重载动作）
local function ReloadLanguage()
    local lang = ReadConfigLanguage()
    if not lang then lang = "zh" end
    LoadLanguage(lang)
    return lang
end

-- ============================================================
-- 注册系统：命令 / 配置项 / 功能（lib 模块可调用注册）
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
-- help 输出：表头 + 命令列表
-- 列宽规则：每列 = 最长内容 + 2（表头间隔 = 2+x，x = 最长命令-commandWidth，2+x<0 时 x=0）
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
    -- 表头：命令 + 2+x 空格 + 用法（第二列停在 commandWidth+2+x 显示位置）
    local lines = { T("help.header", string.rep(" ", 2 + x)) }
    -- 命令行：命令名 + max(0, commandWidth+2+x-命令名长) 空格 + 描述
    -- 第二列与表头"用法"对齐（当前 4+2+2-6 = 2 空格，同用户示例）
    for _, upper in ipairs(command_order) do
        local c = commands[upper]
        local cmd_pad = cw + 2 + x - #c.name
        if cmd_pad < 0 then cmd_pad = 0 end
        lines[#lines + 1] = T("help.linePrefix") .. c.name .. string.rep(" ", cmd_pad) .. T(c.descKey)
    end
    lines[#lines + 1] = "[SXMY]"
    return table.concat(lines, "\n")
end

-- ============================================================
-- 子命令：Config —— 切换配置项并热重载
-- ============================================================

local function ConfigUsage()
    local lines = { T("config.usage") }
    for _, upper in ipairs(config_order) do
        lines[#lines + 1] = T("config.usageItems", config_items[upper].name)
    end
    lines[#lines + 1] = T("config.usageValueHint")
    lines[#lines + 1] = T("config.usageReload")
    return table.concat(lines, "\n")
end

local function ConfigHandler(parts)
    local item = parts[3]
    if not item then
        return ConfigUsage()
    end
    local cfg = config_items[item:upper()]
    if not cfg then
        return ConfigUsage()
    end
    local value = parts[4]
    if not value then
        return cfg.usage()
    end
    local ok, normalized = cfg.validate(value)
    if not ok then
        return T("config.invalidValue", value, cfg.available())
    end
    cfg.apply(normalized)
    -- 热重载开关：缺省 y（重载）；仅 y 为重载
    local reload = true
    local r = parts[5]
    if r then
        reload = (r:lower() == "y")
    end
    if reload and cfg.reload then
        cfg.reload()
    end
    return T("config.setOk", cfg.name, normalized)
end

-- 配置项：Language
SXMY.RegisterConfigItem("Language", {
    name = "Language",
    usage = function()
        return T("config.usageItem", "Language") .. "\n"
            .. T("config.usageItemValues", table.concat(ListLanguages(), "/"))
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
        SetConfigLanguage(v)
    end,
    reload = function()
        ReloadLanguage()
    end,
})

-- ============================================================
-- 子命令：Reload —— 热重载插件功能
-- ============================================================

local function ReloadUsage()
    local names = {}
    for _, upper in ipairs(feature_order) do
        names[#names + 1] = features[upper].name
    end
    return T("reload.usage") .. "\n"
        .. T("reload.usageFeatures", table.concat(names, "/"))
end

local function ReloadHandler(parts)
    local feature = parts[3]
    if not feature then
        -- 无参数：重载所有功能
        for _, upper in ipairs(feature_order) do
            features[upper].reload()
        end
        return T("reload.done")
    end
    if feature:lower() == "help" then
        return ReloadUsage()
    end
    local feat = features[feature:upper()]
    if not feat then
        return T("reload.unknownFeature", feature)
    end
    feat.reload()
    return T("reload.doneFeature", feat.name)
end

-- 功能：Language（重新加载语言文件）
SXMY.RegisterFeature("Language", {
    name = "Language",
    reload = function()
        ReloadLanguage()
    end,
})

-- ============================================================
-- 命令注册与入口分派
-- ============================================================

SXMY.RegisterCommand("Reload", "help.descReload", ReloadHandler)
SXMY.RegisterCommand("Config", "help.descConfig", ConfigHandler)

local function SplitArgs(input)
    local parts = {}
    for w in input:gmatch("%S+") do
        parts[#parts + 1] = w
    end
    return parts
end

-- onConsoleInput 处理器（需为全局函数，供 MP.RegisterEvent 按名注册）
function SXMY_HandleConsoleInput(input)
    if type(input) ~= "string" then
        return nil
    end
    local parts = SplitArgs(input)
    if #parts == 0 then
        return nil
    end
    if parts[1]:upper() ~= "SXMY" then
        return nil -- 非本插件命令，不拦截
    end
    if #parts == 1 then
        return BuildHelp()
    end
    local sub = commands[parts[2]:upper()]
    if not sub then
        return BuildHelp() -- 未知子命令：输出帮助
    end
    return sub.handler(parts)
end

-- ============================================================
-- 启动流程
-- ============================================================

LoadLanguage("zh") -- 兜底语言
local lang = GetLanguage() -- 可能生成默认配置文件（文案用当前语言）
LoadLanguage(lang) -- 按配置语言加载

MP.RegisterEvent("onConsoleInput", "SXMY_HandleConsoleInput")
