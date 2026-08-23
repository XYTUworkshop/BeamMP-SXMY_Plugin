-- =====================================================================================
-- BeamMP-SXMY_Plugin - main.lua (Main Loader / 主加载器)
-- 根据 config.toml 中的开关加载各个功能模块 / Loads each feature module according to the switches in config.toml
-- 功能模块位于 "modules" 子文件夹，通过 require() 加载（子文件夹不会被自动加载）/ Modules live in the "modules" subfolder and are require()d, never auto-loaded
-- =====================================================================================

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

-- Startup summary logs / 启动汇总日志
print("[SXMY_Plugin] " .. lib.msg("插件加载完成", "Plugin loaded"))
print("[SXMY_Plugin] " .. lib.msg("已加载%d/%d个功能", "Loaded %d/%d features"):format(loadedCount, totalCount))
print("[SXMY_Plugin] " .. lib.msg("已加载的功能：", "Loaded features:"))
for i, moduleName in ipairs(loadedNames) do
    print("[SXMY_Plugin] " .. i .. ". " .. moduleName)
end
