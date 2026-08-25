-- =====================================================================================
-- BeamMP-SXMY_Plugin - modules/loginfo.lua / 服务器信息日志模块
-- Server info log module / 服务器信息日志功能模块
-- Shows start time, version and map after the main summary / 在 main 汇总后显示启动时间、版本、地图
-- Called by main.lua after the server is fully ready / 由 main.lua 在服务器完全就绪后调用
-- =====================================================================================

local lib = require("modules.lib") -- shared config library / 共享配置库

-- 本模块配置：缺失键自动追加（含中英注释），用户已有配置不覆盖 / this module's own config: missing keys appended with comments, user settings kept
lib.ensureSection("loginfo", {
    { key = "enable", v = true, c = "服务器信息日志功能开关 / Server info log module switch" },
    { key = "startTime", v = true, c = "显示服务器启动时间 / Show server start time" },
    { key = "serverVersion", v = true, c = "显示服务器版本 / Show server version" },
    { key = "serverMap", v = true, c = "显示服务器地图（读取 ServerConfig.toml）/ Show server map (read from ServerConfig.toml)" },
})
-- 未启用时退出，不注册任何事件 / exit early when disabled, no events are registered
if not lib.get("loginfo", "enable", true) then
    print("[SXMY_Plugin] " .. lib.msg("loginfo 已禁用", "loginfo disabled"))
    return
end

local CONFIG_FILE = "ServerConfig.toml" -- server config, relative to working dir / 服务器配置（相对工作目录）

-- Print a log line with the module prefix / 以模块前缀打印日志行
local function log(msg)
    print("[SXMY_Loginfo] " .. msg)
end

-- Get the map name from the server config file / 从服务器配置文件获取地图名
local function getServerMap()
    local fh, err = io.open(CONFIG_FILE, "r")
    if not fh then
        return nil
    end
    local data = fh:read("*a")
    fh:close()
    local mapPath = data:match('Map%s*=%s*"([^"]+)"')
    if mapPath then
        return mapPath:match("/levels/([^/]+)/info.json") or mapPath
    end
    return nil
end

-- Show server info when the server starts / 服务器启动时显示服务器信息
function SXMY_loginfo_Startup()
    -- Server start time / 服务器启动时间
    if lib.get("loginfo", "startTime", true) then
        log(lib.msg("服务器启动时间: ", "Server start time: ") .. os.date("%Y.%m.%d-%H.%M.%S"))
    end
    -- Server version / 服务器版本
    if lib.get("loginfo", "serverVersion", true) then
        local major, minor, patch = MP.GetServerVersion()
        log(lib.msg("服务器版本: ", "Server version: ") .. string.format("%d.%d.%d", major, minor, patch))
    end
    -- Server map / 服务器地图
    if lib.get("loginfo", "serverMap", true) then
        local mapName = getServerMap()
        if mapName then
            log(lib.msg("服务器地图: ", "Server map: ") .. mapName)
        else
            log(lib.msg("服务器地图: <未知>", "Server map: <unknown>"))
        end
    end
end

