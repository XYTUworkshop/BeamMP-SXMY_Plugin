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
                            -- Try to parse numbers (e.g. delay = 12) / 尝试解析数字（如 delay = 12）
                            local num = tonumber(val)
                            if num then
                                cfg[section .. "." .. key2] = num
                            else
                                cfg[section .. "." .. key2] = val
                            end
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

-- Check whether the config file exists / 检查配置文件是否存在
function lib.configExists()
    local fh = io.open(CONFIG_PATH, "r")
    if fh then
        fh:close()
        return true
    end
    return false
end

-- Scan the modules folder and return the module file names (excluding lib) / 扫描 modules 目录返回模块文件名（不含 lib）
-- Used by main.lua so every present module loads itself and writes its own config
-- 供 main.lua 使用：存在的模块都自行加载并生成自己的配置
function lib.scanModules()
    local list = {}
    local fh = io.popen('dir /b "Resources\\Server\\BeamMP-SXMY_Plugin\\modules\\*.lua"')
    if not fh then
        return list
    end
    for line in fh:lines() do
        -- Trim trailing whitespace/CR first, then strip the .lua extension (dir output ends with CRLF)
        -- 先去尾部空白/回车，再去除 .lua 扩展名（dir 输出以 CRLF 结尾）
        local name = line:gsub("%s+$", ""):gsub("%.lua$", "")
        if name ~= "" and name ~= "lib" then
            list[#list + 1] = name
        end
    end
    fh:close()
    return list
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

-- Format a default value for writing into the config file / 将默认值格式化为写入配置文件的文本
local function formatValue(v)
    if type(v) == "boolean" then
        return v and "true" or "false"
    elseif type(v) == "number" then
        return tostring(v)
    end
    -- Escape newlines as literal \n so the value stays on one line / 将换行转义为字面 \n 保持单行
    return '"' .. tostring(v):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n") .. '"'
end

-- Ensure a config section exists: insert missing keys with defaults and comments, keep existing user settings
-- 确保配置节存在：缺失键用默认值与注释补入，保留用户已有配置
-- The whole file is rewritten so a section header is never duplicated / 整体重写，不会产生重复的节标题
-- defaults entries: { key = value } or { key = { v = value, c = "中文 / English comment" } }
-- defaults 条目：{ key = value } 或 { key = { v = 值, c = "中文 / English 注释" } }
function lib.ensureSection(section, defaults)
    local cfg = lib.getConfig()
    local missing = {}
    for key, spec in pairs(defaults) do
        if cfg[section .. "." .. key] == nil then
            local value, comment
            if type(spec) == "table" then
                value = spec.v
                comment = spec.c
            else
                value = spec
            end
            missing[#missing + 1] = { key = key, value = value, comment = comment }
        end
    end

    -- Read the current file, or start from scratch / 读取原文件（不存在则从空开始）
    local fh = io.open(CONFIG_PATH, "r")
    local content = ""
    if fh then
        content = fh:read("*a")
        fh:close()
    end

    -- Count the target section headers to detect duplicated sections from earlier versions / 统计目标节标题数（检测旧版产生的重复节）
    local esc = section:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local headerCount = 0
    if content ~= "" then
        for line in (content .. "\n"):gmatch("(.-)\n") do
            if line:gsub("\r$", ""):match("^%[%s*" .. esc .. "%s*%]$") then
                headerCount = headerCount + 1
            end
        end
    end

    -- Nothing missing and no duplicate headers to merge: nothing to do / 无缺失键且无重复节需合并：无需处理
    if #missing == 0 and headerCount <= 1 then
        return
    end

    -- Build the lines to add / 构造要添加的键行
    local newLines = {}
    for _, item in ipairs(missing) do
        local line = item.key .. " = " .. formatValue(item.value)
        if item.comment then
            line = line .. "  # " .. item.comment
        end
        newLines[#newLines + 1] = line
    end

    -- Rewrite the file: insert missing keys inside the existing section, otherwise append a new section at the end
    -- Duplicated target sections (from earlier versions) are merged into one; conflicting keys keep the first value
    -- 整体重写：缺失键插入原节内末尾；节不存在则在文件末尾追加新节
    -- 旧版本产生的重复节会被自动合并，冲突键保留第一节的值
    local out = {}
    if content ~= "" then
        local currentSection = nil
        local inserted = false
        local targetSeen = false -- first [section] header seen / 已见到第一个目标节标题
        local inFirstBlock = false -- currently inside the first target block / 当前在目标节第一节块内
        local inDupBlock = false -- currently inside a duplicated target block / 当前在重复的目标节块内
        local targetKeys = {} -- keys present in the first target block / 第一节块已有的键
        for line in (content .. "\n"):gmatch("(.-)\n") do
            local cleanLine = line:gsub("\r$", "")
            local secName = cleanLine:match("^%[%s*(.-)%s*%]$")
            if secName then
                if secName == section and targetSeen then
                    -- Duplicate target header: skip it, its keys merge into the first block / 跳过重复节标题，键并入第一节
                    inFirstBlock = false
                    inDupBlock = true
                else
                    if secName == section then
                        targetSeen = true
                        inFirstBlock = true
                        inDupBlock = false
                    else
                        inFirstBlock = false
                        inDupBlock = false
                    end
                    -- Insert missing keys at the end of the (first) target block / 在目标节块末尾插入缺失键
                    if currentSection == section and not inserted then
                        for _, l in ipairs(newLines) do
                            out[#out + 1] = l
                        end
                        inserted = true
                    end
                    currentSection = secName
                    out[#out + 1] = cleanLine
                end
            else
                local keyName = cleanLine:match("^(%w+)%s*=")
                if inDupBlock and keyName and targetKeys[keyName] then
                    -- Conflicting key in the duplicate block: keep the first value / 重复节中的冲突键：保留第一节的值
                else
                    if inFirstBlock and keyName then
                        targetKeys[keyName] = true
                    end
                    out[#out + 1] = cleanLine
                end
            end
        end
        -- The target section is the last one in the file / 目标节是文件最后一个节
        if not inserted and currentSection == section then
            for _, l in ipairs(newLines) do
                out[#out + 1] = l
            end
            inserted = true
        end
        -- Section not found: append a new section at the end / 节不存在：末尾追加新节
        if not inserted then
            if out[#out] ~= "" then
                out[#out + 1] = ""
            end
            out[#out + 1] = "[" .. section .. "]"
            for _, l in ipairs(newLines) do
                out[#out + 1] = l
            end
        end
    else
        -- Empty or missing file: create the section / 空文件或不存在：直接创建节
        out[#out + 1] = "[" .. section .. "]"
        for _, l in ipairs(newLines) do
            out[#out + 1] = l
        end
    end

    -- Write to a temp file then replace, so a failed write never corrupts the config / 写临时文件再替换，写失败不损坏配置
    local tmp = CONFIG_PATH .. ".tmp"
    local fw, werr = io.open(tmp, "w")
    if not fw then
        print("[SXMY_Plugin] " .. lib.msg("配置写入失败", "Config write failed") .. ": " .. tostring(werr))
        return
    end
    fw:write(table.concat(out, "\n"))
    fw:close()
    os.remove(CONFIG_PATH)
    local ok, rerr = os.rename(tmp, CONFIG_PATH)
    if not ok then
        print("[SXMY_Plugin] " .. lib.msg("配置写入失败", "Config write failed") .. ": " .. tostring(rerr))
    end
    -- Re-read the config so the cache reflects the new defaults / 重读配置使缓存包含新默认值
    cached = nil
    cachedSections = nil
    lib.getConfig()
end

return lib -- module export / 模块导出
