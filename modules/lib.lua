-- =====================================================================================
-- BeamMP-SXMY_Plugin - modules/lib.lua / 共享配置解析库
-- Shared config parsing library / 共享配置解析库
-- Provides config.toml parsing with caching / 提供 config.toml 解析（带缓存）
-- =====================================================================================

-- Config file path relative to the server working directory / 配置路径（相对服务器工作目录）
local CONFIG_PATH = "Resources/Server/BeamMP-SXMY_Plugin/config.toml"

local lib = {} -- library table / 库表
local cached = nil -- parsed config cache / 已解析配置缓存
local cachedSections = nil -- ordered section list cache / 有序节名列表缓存

-- Parse a simple TOML file: [Section] key = value, lines become "Section.key" -> value / 解析简单 TOML 文件：行转换为 "Section.key" -> 值
local function parseConfig(path)
    local cfg = {}
    local sections = {} -- ordered section names / 有序节名
    local seen = {} -- dedupe set / 去重集合
    local fh, err = io.open(path, "r")
    if not fh then
        print("[SXMY_Plugin] " .. lib.msg("配置读取失败", "Config read failed") .. ": " .. tostring(err) .. " (" .. path .. ")")
        return cfg
    end
    local section = nil -- current section name / 当前节名
    for line in fh:lines() do
        -- Strip trailing comments and surrounding whitespace / 去除行尾注释与首尾空白
        local trimmed = line:gsub("%s*#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            local s = trimmed:match("^%[([^%]]+)%]$")
            if s then
                section = s
                -- Collect each section once, in config order / 按配置顺序收集每个节（去重）
                if not seen[s] then
                    seen[s] = true
                    sections[#sections + 1] = s
                end
            else
                -- Quoted string value (may contain spaces) / 带引号的字符串值（可能含空格）
                local key, quoted = trimmed:match('^(%w+)%s*=%s*"(.*)"%s*$')
                if key then
                    cfg[section .. "." .. key] = quoted
                else
                    -- Bare value: boolean or number / 无引号的值：布尔或数字
                    local key2, val = trimmed:match("^(%w+)%s*=%s*(%S+)%s*$")
                    if key2 then
                        if val == "true" then
                            cfg[section .. "." .. key2] = true
                        elseif val == "false" then
                            cfg[section .. "." .. key2] = false
                        else
                            cfg[section .. "." .. key2] = val
                        end
                    end
                end
            end
        end
    end
    fh:close()
    return cfg, sections
end

-- Get the parsed config, parsing once and caching it / 获取解析后的配置（只解析一次并缓存）
function lib.getConfig()
    if not cached then
        cached, cachedSections = parseConfig(CONFIG_PATH)
    end
    return cached
end

-- Get enabled module names in config order, auto-discovering new sections / 按配置顺序获取已启用模块名（自动发现新配置节）
function lib.getEnabledModules()
    lib.getConfig()
    local result = {}
    for _, s in ipairs(cachedSections) do
        if cached[s .. ".enabled"] == true or cached[s .. ".enable"] == true then
            result[#result + 1] = s
        end
    end
    return result
end

-- Get the plugin language: "zh" or "en", defaults to "zh" / 获取插件语言："zh" 或 "en"，默认 "zh"
function lib.getLanguage()
    if cached and cached["General.language"] == "en" then
        return "en"
    end
    return "zh"
end

-- Return the text in the selected language for log output / 返回所选语言的日志文本
function lib.msg(zhText, enText)
    if lib.getLanguage() == "en" then
        return enText
    end
    return zhText
end

-- Check whether a module section is enabled (supports both "enabled" and "enable" keys) / 检查某模块节是否启用（同时支持 "enabled" 与 "enable" 键）
function lib.enabled(section)
    local cfg = lib.getConfig()
    return cfg[section .. ".enabled"] == true or cfg[section .. ".enable"] == true
end

-- Get a string value from a module section / 获取某模块节的字符串值
function lib.get(section, key, default)
    local cfg = lib.getConfig()
    local v = cfg[section .. "." .. key]
    if v == nil then
        return default
    end
    return v
end

return lib -- module export / 模块导出
