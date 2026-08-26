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
                -- Array value: key = ["a", "b", "c"] / 数组值（TOML 数组，单行）
                local keyArr, arrStr = trimmed:match('^(%w+)%s*=%s*%[(.-)%]%s*$')
                if keyArr then
                    local arr = {}
                    for item in (arrStr .. ","):gmatch("%s*([^,]-)%s*,") do
                        if item ~= "" then
                            -- Strip surrounding quotes if present / 去除引号
                            arr[#arr + 1] = item:match('^"(.*)"$') or item
                        end
                    end
                    cfg[section .. "." .. keyArr] = arr
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
    local v = cfg[section .. ".enabled"]
    if v == nil then
        v = cfg[section .. ".enable"]
    end
    if v == nil then
        -- 无配置键 = 默认启用（模块文件存在即生效，配置节由模块自动生成；避免"未生成节→禁用→不生成节"死循环）/
        -- no config key = enabled by default (the module runs and generates its own section; avoids the "no section -> disabled -> no section" deadlock)
        return true
    end
    return v == true
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
    elseif type(v) == "table" then
        -- Array default: ["a", "b"] / 数组默认值
        local parts = {}
        for _, item in ipairs(v) do
            parts[#parts + 1] = '"' .. tostring(item) .. '"'
        end
        return "[" .. table.concat(parts, ", ") .. "]"
    end
    -- Escape newlines as literal \n so the value stays on one line / 将换行转义为字面 \n 保持单行
    return '"' .. tostring(v):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n") .. '"'
end

-- Build a config row from a default item / 由默认条目构造配置行
local function buildRow(item)
    local line = item.key .. " = " .. formatValue(item.value)
    if item.comment then
        line = line .. "  # " .. item.comment
    end
    return line
end

-- Atomically write the config file and refresh the cache / 原子写入配置文件并刷新缓存
-- Strategy: write temp -> backup original (if any) -> swap -> restore backup on failure / 策略：写临时文件 -> 备份原文件（若有）-> 替换 -> 失败回滚备份
local function writeConfig(out)
    local tmp = CONFIG_PATH .. ".tmp"
    local bak = CONFIG_PATH .. ".bak"
    local fw, werr = io.open(tmp, "w")
    if not fw then
        print("[SXMY_Plugin] " .. lib.msg("配置写入失败", "Config write failed") .. ": " .. tostring(werr))
        return
    end
    local written = fw:write(table.concat(out, "\n"))
    local closed = fw:close()
    if not written or not closed then
        -- Write failed (e.g. disk full): drop the temp file, keep the original / 写入失败（如磁盘满）：删除临时文件，保留原配置
        local removedTmp, terr = os.remove(tmp)
        if not removedTmp then
            print("[SXMY_Plugin] " .. lib.msg("临时文件删除失败", "Failed to remove temp file") .. ": " .. tostring(terr))
        end
        print("[SXMY_Plugin] " .. lib.msg("配置写入失败", "Config write failed"))
        return
    end
    -- Does the original config exist? If not, skip the backup (fresh creation) / 原配置是否存在？不存在则跳过备份（新建场景）
    local originalExists = false
    local probe = io.open(CONFIG_PATH, "r")
    if probe then
        originalExists = true
        probe:close()
    end
    if originalExists then
        -- Move the original aside as a backup, then swap in the new file / 原文件先移为备份，再替换为新文件
        os.remove(bak)
        local backed, berr = os.rename(CONFIG_PATH, bak)
        if not backed then
            local removedTmp, terr = os.remove(tmp)
            if not removedTmp then
                print("[SXMY_Plugin] " .. lib.msg("临时文件删除失败", "Failed to remove temp file") .. ": " .. tostring(terr))
            end
            print("[SXMY_Plugin] " .. lib.msg("配置写入失败", "Config write failed") .. ": " .. tostring(berr))
            return
        end
    end
    local ok, rerr = os.rename(tmp, CONFIG_PATH)
    if not ok then
        if originalExists then
            -- Restore the backup / 回滚：恢复备份
            local restored, rerr2 = os.rename(bak, CONFIG_PATH)
            if not restored then
                -- Double failure: keep the backup and stop, never lose the config / 双重失败：保留备份并中止，绝不丢失配置
                print("[SXMY_Plugin] " .. lib.msg("配置写入失败，原配置已备份至", "Config write failed, original backed up at") .. " " .. bak .. " (" .. tostring(rerr2) .. ")")
                return
            end
        end
        local removedTmp, terr = os.remove(tmp)
        if not removedTmp then
            print("[SXMY_Plugin] " .. lib.msg("临时文件删除失败", "Failed to remove temp file") .. ": " .. tostring(terr))
        end
        print("[SXMY_Plugin] " .. lib.msg("配置写入失败", "Config write failed") .. ": " .. tostring(rerr))
        return
    end
    -- Success: drop the backup / 成功：删除备份
    local removedBak, bberr = os.remove(bak)
    if not removedBak then
        print("[SXMY_Plugin] " .. lib.msg("备份文件删除失败", "Failed to remove backup file") .. ": " .. tostring(bberr))
    end
    -- Re-read the config so the cache reflects the new state / 重读配置使缓存反映最新状态
    cached = nil
    cachedSections = nil
    lib.getConfig()
end

-- Normalize a config section to the module's ordered defaults / 按模块有序默认值规范化配置节
--   - missing keys are inserted at their correct position (default value + comment)
--   - extra keys (not in defaults) are removed
--   - keys already present keep the user's value and trailing comment
--   - duplicate headers from earlier versions are merged; the first value of a conflicting key wins
-- 缺失键在正确位置插入（默认值+注释）、多余键删除、已有键保留用户值与行尾注释、
-- 旧版重复节自动合并（冲突键保留第一节的值）
-- defaults: ordered array of { key = "name", v = value, c = "中文 / English comment" } (c optional)
-- defaults：有序数组 { key = "名称", v = 值, c = "中文 / English 注释" }（c 可选）
function lib.ensureSection(section, defaults)
    -- Normalize defaults into an ordered list / 将 defaults 规范为有序条目列表
    local items = {}
    if type(defaults) == "table" and #defaults > 0 then
        -- Ordered array format / 有序数组格式
        for _, spec in ipairs(defaults) do
            if type(spec) == "table" and spec.key then
                items[#items + 1] = { key = spec.key, value = spec.v, comment = spec.c }
            elseif type(spec) == "table" then
                for k, v in pairs(spec) do
                    items[#items + 1] = { key = k, value = v }
                end
            else
                items[#items + 1] = { key = spec, value = true }
            end
        end
    else
        -- Legacy unordered table format, kept for compatibility / 旧版无序表格式（兼容保留）
        for key, spec in pairs(defaults) do
            local value, comment
            if type(spec) == "table" then
                value = spec.v
                comment = spec.c
            else
                value = spec
            end
            items[#items + 1] = { key = key, value = value, comment = comment }
        end
    end

    -- Read the current file / 读取原文件
    local fh = io.open(CONFIG_PATH, "r")
    local content = ""
    if fh then
        content = fh:read("*a")
        fh:close()
    end

    local lines = {}
    if content ~= "" then
        for line in (content .. "\n"):gmatch("(.-)\n") do
            lines[#lines + 1] = line:gsub("\r$", "")
        end
        -- Drop trailing empty lines so the block comparison stays stable across runs / 丢弃末尾空行，保证多次运行比较稳定（不会反复重写）
        while #lines > 0 and lines[#lines] == "" do
            lines[#lines] = nil
        end
    end

    -- Locate every [section] header (duplicates may exist from earlier versions) / 定位所有目标节标题（旧版可能重复）
    local esc = section:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local headers = {}
    for i, line in ipairs(lines) do
        if line:match("^%[%s*" .. esc .. "%s*%]$") then
            headers[#headers + 1] = i
        end
    end

    -- Section missing: append a new one at the end / 节不存在：文件末尾追加新节
    if #headers == 0 then
        local out = {}
        for i, line in ipairs(lines) do
            out[#out + 1] = line
        end
        if #out > 0 and out[#out] ~= "" then
            out[#out + 1] = ""
        end
        out[#out + 1] = "[" .. section .. "]"
        for _, item in ipairs(items) do
            out[#out + 1] = buildRow(item)
        end
        writeConfig(out)
        return
    end

    -- Collect keys from every target block (first occurrence wins), keep non-key lines
    -- 收集所有目标节块的键（首次出现优先），保留非键行（注释、空行）
    -- Other sections are never touched / 其他节完全不受影响
    local keyRows = {} -- key -> row / 键 -> 行
    local preLines = {} -- non-key lines in order / 非键行（注释、空行）按顺序
    local seen = {}
    local inTarget = false
    for _, line in ipairs(lines) do
        local secName = line:match("^%[%s*(.-)%s*%]$")
        if secName then
            inTarget = (secName == section)
        elseif inTarget then
            local keyName = line:match("^(%w+)%s*=")
            if keyName then
                if not seen[keyName] then
                    seen[keyName] = true
                    keyRows[keyName] = line
                end
            else
                preLines[#preLines + 1] = line
            end
        end
    end

    -- Rebuild the block in the default order / 按默认顺序重建节块
    local newBlock = { "[" .. section .. "]" }
    local changed = false
    for _, item in ipairs(items) do
        if keyRows[item.key] then
            -- Keep the user's row (value + trailing comment) / 保留用户行（值 + 行尾注释）
            newBlock[#newBlock + 1] = keyRows[item.key]
        else
            -- Insert the default row at the correct position / 在正确位置插入默认行
            newBlock[#newBlock + 1] = buildRow(item)
            changed = true
        end
        keyRows[item.key] = nil
    end
    -- Keep non-key lines (comments, blanks) at the end of the block so the comparison stays stable / 非键行（注释、空行）保留在节尾，保证比较稳定（不会反复重写）
    for _, line in ipairs(preLines) do
        newBlock[#newBlock + 1] = line
    end
    -- Remaining keys are extras: removed / 剩余键为多余项：删除
    local extras = 0
    for _ in pairs(keyRows) do
        extras = extras + 1
    end
    if extras > 0 then
        changed = true
        print("[SXMY_Plugin] " .. lib.msg("已移除多余配置项：", "Removed extra config keys: ") .. section)
    end

    -- Rebuild the whole file: replace the first target block with the normalized one,
    -- drop duplicate target headers and their rows, never touch other sections
    -- 整文件重建：第一个目标节替换为规范化块，删除重复的目标节标题及其行，其他节原样保留
    local out = {}
    local i = 1
    local firstHandled = false
    local skipping = false
    while i <= #lines do
        local line = lines[i]
        local secName = line:match("^%[%s*(.-)%s*%]$")
        if secName then
            if secName == section then
                if firstHandled then
                    -- Duplicate target header: skip it and its rows / 重复目标节标题：跳过其及后续行
                    skipping = true
                else
                    firstHandled = true
                    skipping = false
                    for _, l in ipairs(newBlock) do
                        out[#out + 1] = l
                    end
                    -- Jump past the original first block / 跳过第一个目标节的原始行
                    i = i + 1
                    while i <= #lines and not lines[i]:match("^%[%s*(.-)%s*%]$") do
                        i = i + 1
                    end
                    i = i - 1 -- the while loop below increments to the next header / 循环末尾 i+1 跳到下一标题
                end
            else
                skipping = false
                out[#out + 1] = line
            end
        else
            if not skipping then
                out[#out + 1] = line
            end
        end
        i = i + 1
    end

    -- Compare with the original file / 与原文件比较
    local same = #out == #lines
    if same then
        for j = 1, #out do
            if out[j] ~= lines[j] then
                same = false
                break
            end
        end
    end
    if same and not changed then
        -- Already normalized: refresh the cache so getEnabledModules() sees the sections even when nothing was written / 已规范化：刷新缓存，即使无写入也要保证 getEnabledModules() 能读到节
        cached = nil
        lib.getConfig()
        return -- already normalized / 已规范化，无需写入
    end

    writeConfig(out)
end

return lib -- module export / 模块导出
