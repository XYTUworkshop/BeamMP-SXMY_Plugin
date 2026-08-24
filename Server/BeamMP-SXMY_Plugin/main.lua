-- =====================================================================================
-- BeamMP-SXMY_Plugin - main.lua (Main Loader / 主加载器)
-- 根据 config.toml 中的开关加载各个功能模块 / Loads each feature module according to the switches in config.toml
-- 功能模块位于 "modules" 子文件夹，通过 require() 加载（子文件夹不会被自动加载）/ Modules live in the "modules" subfolder and are require()d, never auto-loaded
-- 支持控制台 reloadSXMY 命令热重载 / console command reloadSXMY hot-reloads the plugin
-- =====================================================================================

-- 清模块 require 缓存，确保热重载时所有模块重新执行 / clear the module require cache so all modules re-run on hot reload
-- Collect first, then remove: deleting while pairs() iterates may skip entries / 先收集再删除：pairs 遍历中删除可能跳过部分项
local cachedModules = {}
for name in pairs(package.loaded) do
    if name:match("^modules%.") then
        cachedModules[#cachedModules + 1] = name
    end
end
for _, name in ipairs(cachedModules) do
    package.loaded[name] = nil
end

local lib = require("modules.lib") -- shared config library / 共享配置库

-- 配置文件绝对路径（失败时回退相对路径）/ absolute config path (relative fallback)
local function getConfigPath()
    local fh = io.popen("cd")
    if fh then
        local cwd = fh:read("*a"):gsub("%s+$", "")
        fh:close()
        if cwd ~= "" then
            return cwd .. "\\Resources\\Server\\BeamMP-SXMY_Plugin\\config.toml"
        end
    end
    return "Resources/Server/BeamMP-SXMY_Plugin/config.toml"
end

-- 首启检测：配置文件不存在时提示，模块加载时自动生成 / first-run check: hint when the config file is missing (modules generate it on load)
local configMissing = not lib.configExists()
if configMissing then
    print("[SXMY_Plugin] " .. lib.msg("未发现配置文件 正在生成", "Config file not found, generating"))
end

-- Ensure the General config section exists (plugin-wide defaults) / 确保 General 配置节存在（插件级默认值）
lib.ensureSection("General", { language = "zh" })

-- 加载全部模块：扫描 modules/ 目录，每个模块自行生成配置并按自身 enable 决定是否启用
-- Load every module: scan the modules folder; each module writes its own config and checks its own enable
-- 删除模块文件即不再生成其配置项 / removing a module file stops its config section from being generated
local moduleFiles = lib.scanModules() -- present module files / 存在的模块文件
local loadedOK = {} -- name -> loaded without error / 模块名 -> 是否加载成功
for _, moduleName in ipairs(moduleFiles) do
    local ok = pcall(require, "modules." .. moduleName)
    loadedOK[moduleName] = ok
    if not ok then
        print("[SXMY_Plugin] " .. lib.msg("模块加载失败: ", "Module load failed: ") .. moduleName)
    end
end

-- 统计：已启用（config enable=true）且加载成功的模块 / count modules that are enabled and loaded
local loadedCount = 0 -- enabled and loaded modules / 已启用且成功加载的模块数
local totalCount = #moduleFiles -- all present modules / 存在的模块总数
local loadedNames = {} -- names of enabled loaded modules / 已启用模块名
for _, moduleName in ipairs(lib.getEnabledModules()) do
    if loadedOK[moduleName] then
        loadedCount = loadedCount + 1
        loadedNames[#loadedNames + 1] = moduleName
    end
end

-- 首启时配置文件已生成提示 / first-run: config generated hint
if configMissing then
    print("[SXMY_Plugin] " .. lib.msg("配置文件已生成 路径：", "Config file generated at: ") .. getConfigPath())
end

-- Startup summary logs, printed once / 启动汇总日志，仅输出一次
print("[SXMY_Plugin] " .. lib.msg("插件加载完成", "Plugin loaded"))
print("[SXMY_Plugin] " .. lib.msg("已加载%d/%d个功能", "Loaded %d/%d features"):format(loadedCount, totalCount))
print("[SXMY_Plugin] " .. lib.msg("已加载的功能：", "Loaded features:"))
for i, moduleName in ipairs(loadedNames) do
    print("[SXMY_Plugin] " .. i .. ". " .. moduleName)
end

-- Loginfo output (if the module is loaded, printed once) / loginfo 输出（若已加载，仅一次）
if type(SXMY_loginfo_Startup) == "function" then
    SXMY_loginfo_Startup()
end

-- Welcome text test output (if enabled, printed once) / 欢迎文本测试输出（若启用，仅一次）
if type(SXMY_WelcomeMsg_ShowTestOutput) == "function" then
    SXMY_WelcomeMsg_ShowTestOutput()
end

-- Auth startup info (if the module is loaded, printed once) / Auth 启动信息（若已加载，仅一次）
if type(SXMY_Auth_ShowInfo) == "function" then
    SXMY_Auth_ShowInfo()
end

-- NameTag startup info (if the module is loaded, printed once) / NameTag 启动信息（若已加载，仅一次）
if type(SXMY_NameTag_ShowInfo) == "function" then
    SXMY_NameTag_ShowInfo()
end

-- ==================== 热重载 / Hot reload ====================
-- 本文件路径（相对服务器工作目录）/ path to this file (relative to the server working directory)
local MAIN_FILE = "Resources/Server/BeamMP-SXMY_Plugin/main.lua"
local RELOAD_COOLDOWN = 3 -- seconds between reloads / 重载冷却秒数
local lastReload = 0

-- 通过写回相同字节更新 mtime 触发 PluginMonitor 重载（Windows 的 rename 不覆盖已存在文件，故直接写回）/ rewrite identical bytes to update mtime and trigger the PluginMonitor reload
local function touchMainFile()
    local fh, err = io.open(MAIN_FILE, "rb")
    if not fh then
        return false, err
    end
    local content = fh:read("*a")
    fh:close()
    local w, werr = io.open(MAIN_FILE, "wb")
    if not w then
        return false, werr
    end
    local ok, werr2 = w:write(content)
    w:close()
    if not ok then
        return false, werr2
    end
    return true
end

-- 服务器控制台命令：reloadSXMY 热重载插件（开发与生产环境）/ console command: reloadSXMY hot-reloads the plugin
function SXMY_Plugin_onConsoleInput(cmd)
    if cmd:match("^reloadSXMY%s*$") then
        local now = os.time()
        if now - lastReload < RELOAD_COOLDOWN then
            return lib.msg("重载过于频繁 请稍后再试", "Reload too often, try again later")
        end
        lastReload = now
        local ok, err = touchMainFile()
        if ok then
            return lib.msg("正在热重载插件...", "Hot reloading plugin...")
        end
        return lib.msg("重载失败: ", "Reload failed: ") .. tostring(err)
    end
    return nil -- 不处理其他命令 / do not handle other commands
end

MP.RegisterEvent("onConsoleInput", "SXMY_Plugin_onConsoleInput")
