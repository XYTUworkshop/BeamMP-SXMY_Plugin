-- =====================================================================================
-- BeamMP-SXMY_Plugin - main.lua (Main Loader / 主加载器)
-- 根据 config.toml 中的开关加载各个功能模块 / Loads each feature module according to the switches in config.toml
-- 功能模块位于 "modules" 子文件夹，通过 require() 加载（子文件夹不会被自动加载）/ Modules live in the "modules" subfolder and are require()d, never auto-loaded
-- 支持控制台 reloadSXMY 命令热重载 / console command reloadSXMY hot-reloads the plugin
-- =====================================================================================

-- 清模块 require 缓存，确保热重载时模块重新执行 / clear the module require cache so modules re-run on hot reload
for name in pairs(package.loaded) do
    if name:match("^modules%.") then
        package.loaded[name] = nil
    end
end

local lib = require("modules.lib") -- shared config library / 共享配置库

-- Load a module and return whether it succeeded / 加载模块并返回是否成功
local function loadModule(moduleName)
    local ok, err = pcall(require, "modules." .. moduleName)
    if ok then
        return true
    end
    print("[SXMY_Plugin] " .. lib.msg("模块加载失败: ", "Module load failed: ") .. moduleName .. " -> " .. tostring(err))
    return false
end

-- Auto-discover enabled modules from config.toml, no manual list to maintain / 自动从 config.toml 发现已启用模块，无需手动维护列表
local loadedCount = 0 -- modules loaded successfully / 成功加载的模块数
local totalCount = 0 -- enabled modules in total / 启用的模块总数
local loadedNames = {} -- names of successfully loaded modules / 成功加载的模块名
for _, moduleName in ipairs(lib.getEnabledModules()) do
    totalCount = totalCount + 1
    if loadModule(moduleName) then
        loadedCount = loadedCount + 1
        loadedNames[#loadedNames + 1] = moduleName
    end
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
