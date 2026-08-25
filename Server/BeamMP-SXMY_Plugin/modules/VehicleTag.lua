-- =====================================================================================
-- BeamMP-SXMY_Plugin - modules/VehicleTag.lua / 车辆标签模块
-- Vehicle tag module / 车辆标签功能模块
-- Broadcasts nickname data to all clients, which replace the BeamMP vehicle tag
-- 向所有客户端广播昵称数据，客户端用它替换 BeamMP 车辆标签
-- Requires the SXMYVehicleTag client mod in Resources/Client / 需要 Resources/Client 中的 SXMYVehicleTag 客户端 mod
-- Loaded only when enabled in config.toml / 仅在 config.toml 启用时被加载
-- =====================================================================================

local lib = require("modules.lib") -- shared config library / 共享配置库

-- 本模块配置：按默认顺序规范化（缺失键插入、多余项删除，用户已有配置不覆盖）/ this module's config: normalized to the default order (missing keys inserted, extras removed, user settings kept)
lib.ensureSection("VehicleTag", {
    { key = "enable", v = true, c = "车辆标签功能开关（需 Resources/Client 的 SXMYVehicleTag mod）/ Vehicle tag module switch (requires the SXMYVehicleTag client mod)" },
})
-- 未启用时退出，不注册任何事件 / exit early when disabled, no events are registered
if not lib.get("VehicleTag", "enable", true) then
    print("[SXMY_Plugin] " .. lib.msg("VehicleTag 已禁用", "VehicleTag disabled"))
    return
end

local nickCache = {} -- player_id -> nickname, used to sync to newly joined players / 昵称缓存（用于同步给新进服玩家）

-- Broadcast a nickname update to all clients / 向所有客户端广播昵称更新
-- player_id -> displayed nickname; remove=true clears the tag / player_id -> 显示昵称；remove=true 清除标签
function SXMY_VehicleTag_Update(player_id, nick, remove)
    if remove then
        nickCache[player_id] = nil
        MP.TriggerClientEvent(-1, "SXMY_NickUpdate", Util.JsonEncode({ pid = player_id, remove = true }))
    else
        nickCache[player_id] = nick
        MP.TriggerClientEvent(-1, "SXMY_NickUpdate", Util.JsonEncode({ pid = player_id, nick = nick }))
    end
end

-- Sync all current nicknames to a newly joined player, so they see tags of players who spawned earlier
-- 将当前所有昵称同步给新进服玩家，使其能看到先进服玩家已刷车辆的标签
function SXMY_VehicleTag_onPlayerJoin(player_id)
    for pid, nick in pairs(nickCache) do
        MP.TriggerClientEvent(player_id, "SXMY_NickUpdate", Util.JsonEncode({ pid = pid, nick = nick }))
    end
end

-- Clear the tag when a player disconnects / 玩家断开时清除其标签
function SXMY_VehicleTag_onPlayerDisconnect(player_id)
    SXMY_VehicleTag_Update(player_id, nil, true)
end

-- Register event handlers / 注册事件处理函数
MP.RegisterEvent("onPlayerJoin", "SXMY_VehicleTag_onPlayerJoin")
MP.RegisterEvent("onPlayerDisconnect", "SXMY_VehicleTag_onPlayerDisconnect")
