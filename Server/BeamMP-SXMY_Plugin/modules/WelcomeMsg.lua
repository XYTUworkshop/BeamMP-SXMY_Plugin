-- =====================================================================================
-- BeamMP-SXMY_Plugin - modules/WelcomeMsg.lua / 进服信息模块
-- Welcome message module / 进服信息功能模块
-- Sends the configured text to a player after they join the server / 玩家进入服务器后，将配置中的 text 私信发送给该玩家
-- Supports any language and \n line breaks, each line sent as a separate message / 支持所有语言与 \n 换行，每行作为一条独立消息发送
-- Delayed send, because SendChatMessage rejects players who are still syncing / 延迟发送，因为同步中的玩家会被 SendChatMessage 拒绝
-- Loaded only when enabled in config.toml / 仅在 config.toml 启用时被加载
-- =====================================================================================

local lib = require("modules.lib") -- shared config library / 共享配置库

-- 本模块配置：缺失键自动追加（含中英注释），用户已有配置不覆盖 / this module's own config: missing keys appended with comments, user settings kept
lib.ensureSection("WelcomeMsg", {
    { key = "enable", v = true, c = "进服信息功能开关 / Welcome message module switch" },
    { key = "delay", v = 5, c = "发送延迟（秒），等待玩家同步完成 / Send delay (seconds), waits for the player to sync" },
    { key = "showtest", v = true, c = "启动时显示欢迎文本测试（在插件与 loginfo 输出后）/ Show welcome text test on startup (after plugin and loginfo output)" },
    { key = "text", v = "Welcome to SXMY \nEnjoy :D", c = "进服信息文本，支持所有语言，\\n 换行分多条发送 / Welcome text, any language, \\n splits into multiple messages" },
})
-- 未启用时退出，不注册任何事件 / exit early when disabled, no events are registered
if not lib.get("WelcomeMsg", "enable", true) then
    print("[SXMY_Plugin] " .. lib.msg("WelcomeMsg 已禁用", "WelcomeMsg disabled"))
    return
end

local pending = {} -- player id -> join timestamp, waiting to send / 玩家 id -> 加入时间戳（待发送）
local sent = {} -- player ids already welcomed, prevents duplicates / 已发送欢迎的玩家，防止重复

-- Split text into non-empty trimmed lines by \n escapes and real newlines / 按 \n 转义与真实换行将文本拆分为非空行（去除首尾空白）
local function splitLines(text)
    -- Normalize \n escapes and real newlines to \n / 统一 \n 转义与真实换行为 \n
    local normalized = text:gsub("\\n", "\n"):gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    for line in (normalized .. "\n"):gmatch("(.-)\n") do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            lines[#lines + 1] = trimmed
        end
    end
    return lines
end

-- Send all lines of the configured text to a player / 向玩家发送配置文本的所有行
local function deliver(player_id)
    local text = lib.get("WelcomeMsg", "text")
    if not text or text == "" then
        return
    end
    local lines = splitLines(text)
    for _, line in ipairs(lines) do
        MP.SendChatMessage(player_id, line)
    end
    sent[player_id] = true
end

-- Get the send delay in seconds from config, default 12 / 从配置获取发送延迟秒数，默认 12
local function getDelay()
    return lib.get("WelcomeMsg", "delay", 12)
end

-- Schedule the welcome for a player (once) / 安排玩家的欢迎消息（仅一次）
local function schedule(player_id)
    if not sent[player_id] and not pending[player_id] then
        pending[player_id] = os.time()
    end
end

-- Player fully loaded and joined: schedule the send / 玩家已加入并加载完成：安排发送
function SXMY_WelcomeMsg_onPlayerJoin(player_id)
    schedule(player_id)
end

-- Player is loading: schedule the send (fallback) / 玩家加载中：安排发送（兜底）
function SXMY_WelcomeMsg_onPlayerJoining(player_id)
    schedule(player_id)
end

-- Periodic tick: send once the delay has passed and the player is connected / 周期检查：延迟过后且玩家在线时发送
function SXMY_WelcomeMsg_Tick()
    local now = os.time()
    for player_id, joinedAt in pairs(pending) do
        if now - joinedAt >= getDelay() then
            pending[player_id] = nil
            if not sent[player_id] and MP.IsPlayerConnected(player_id) then
                deliver(player_id)
            end
        end
    end
end

-- Clean up on disconnect / 玩家断开时清理
function SXMY_WelcomeMsg_onPlayerDisconnect(player_id)
    pending[player_id] = nil
    sent[player_id] = nil
end

-- Show the configured text on startup for testing, after plugin and loginfo output / 启动时显示配置文本（测试用），在插件与 loginfo 输出之后
function SXMY_WelcomeMsg_ShowTestOutput()
    -- Only print when enabled in config / 仅当配置启用时输出
    if not lib.get("WelcomeMsg", "showtest", false) then
        return
    end
    local text = lib.get("WelcomeMsg", "text")
    if not text or text == "" then
        return
    end
    local lines = splitLines(text)
    print("[SXMY_WelcomeMsg] " .. lib.msg("欢迎文本：", "Welcome Text :"))
    for _, line in ipairs(lines) do
        print("[SXMY_WelcomeMsg] " .. line)
    end
end

-- Register event handlers / 注册事件处理函数
MP.RegisterEvent("onPlayerJoin", "SXMY_WelcomeMsg_onPlayerJoin")
MP.RegisterEvent("onPlayerJoining", "SXMY_WelcomeMsg_onPlayerJoining")
MP.RegisterEvent("onPlayerDisconnect", "SXMY_WelcomeMsg_onPlayerDisconnect")
MP.RegisterEvent("SXMY_WelcomeMsg_Tick", "SXMY_WelcomeMsg_Tick")
MP.CreateEventTimer("SXMY_WelcomeMsg_Tick", 1000)
