-- lib/01.WelcomeMsg.lua — 功能：进服欢迎信息
-- 职责：
--   1. 玩家进服后（onPlayerJoining）按配置延迟发送欢迎私信
--   2. 配置项：WelcomeMsg-enable / WelcomeMsg-delay / WelcomeMsg-text
--   3. 功能：WelcomeMsg（Reload 重载 / 启动报告）
-- 依赖 main.lua 提供的：SXMY.T / SXMY.Config / SXMY.SetConfigValue
--                 / SXMY.RegisterConfigItem / SXMY.RegisterFeature

-- 读取本模块配置（实时从 SXMY.Config 取，缺省用内置默认）
local function GetCfg()
    local c = (SXMY.Config and SXMY.Config.WelcomeMsg) or {}
    local enable = true
    if c.enable ~= nil then
        enable = (c.enable == true)
    end
    local delay = tonumber(c.delay) or 5
    if delay < 0 then delay = 5 end
    local text = c.text
    if type(text) ~= "string" or text == "" then
        text = "Welcome to SXMY server<\\n>Enjoy"
    end
    return { enable = enable, delay = delay, text = text }
end

-- ============================================================
-- 欢迎发送（把 <\n> 标记替换为换行，再按行拆分为多句私信发送）
-- ============================================================

local function SendWelcome(pid)
    local cfg = GetCfg()
    local text = cfg.text:gsub("<\\n>", "\n")
    for line in text:gmatch("[^\n]+") do
        MP.SendChatMessage(pid, line)
    end
end

-- 延迟队列：pid -> 触发时刻（os.time 墙上秒）
local pending = {}

local function OnPlayerJoining(pid)
    local cfg = GetCfg()
    if not cfg.enable then
        return 0
    end
    if cfg.delay <= 0 then
        SendWelcome(pid)
    else
        pending[pid] = os.time() + cfg.delay
    end
    return 0
end

-- 定时器：检查到期玩家并发送
local function Tick()
    local now = os.time()
    for pid, fire in pairs(pending) do
        if now >= fire then
            pending[pid] = nil
            SendWelcome(pid)
        end
    end
    return 0
end

-- 全局入口（按名注册给 MP.RegisterEvent）
function SXMY_WelcomeMsg_Join(pid)
    return OnPlayerJoining(pid)
end

function SXMY_WelcomeMsg_Tick()
    return Tick()
end

-- onPlayerJoin = 玩家同步完成（now synced!），此时玩家可见聊天框
MP.RegisterEvent("onPlayerJoin", "SXMY_WelcomeMsg_Join")
MP.RegisterEvent("SXMY_WelcomeMsg_Tick", "SXMY_WelcomeMsg_Tick")
MP.CreateEventTimer("SXMY_WelcomeMsg_Tick", 100)

-- ============================================================
-- 配置项注册
-- ============================================================

SXMY.RegisterConfigItem("WelcomeMsg-enable", {
    name = "WelcomeMsg-enable",
    usage = function()
        return SXMY.T("config.usageWmEnable")
    end,
    validate = function(v)
        v = v:lower()
        if v == "true" then return true, true end
        if v == "false" then return true, false end
        return false, v
    end,
    available = function()
        return "true/false"
    end,
    apply = function(v)
        SXMY.SetConfigValue("WelcomeMsg", "enable", v)
    end,
    reload = function()
        -- 配置已写入 SXMY.Config，无需额外动作
    end,
})

SXMY.RegisterConfigItem("WelcomeMsg-delay", {
    name = "WelcomeMsg-delay",
    usage = function()
        return SXMY.T("config.usageWmDelay")
    end,
    validate = function(v)
        local num = tonumber(v)
        if num and num >= 0 then
            return true, num
        end
        return false, v
    end,
    available = function()
        return SXMY.T("config.wmDelayValue")
    end,
    apply = function(v)
        SXMY.SetConfigValue("WelcomeMsg", "delay", v)
    end,
    reload = function()
    end,
})

SXMY.RegisterConfigItem("WelcomeMsg-text", {
    name = "WelcomeMsg-text",
    requireQuoted = true,
    usage = function()
        return SXMY.T("config.usageWmText")
    end,
    validate = function(v)
        return true, v
    end,
    available = function()
        return "any text"
    end,
    apply = function(v)
        SXMY.SetConfigValue("WelcomeMsg", "text", v)
    end,
    reload = function()
    end,
})

-- ============================================================
-- 功能注册
-- ============================================================

SXMY.RegisterFeature("WelcomeMsg", {
    name = "WelcomeMsg",
    reload = function()
        -- 配置实时读取，无需缓存
    end,
    report = function()
        local cfg = GetCfg()
        if cfg.enable then
            print(SXMY.T("main.featureEnabled", "WelcomeMsg"))
            print(SXMY.T("welcome.reportDelay", cfg.delay, cfg.text))
        else
            print(SXMY.T("main.featureDisabled", "WelcomeMsg"))
        end
    end,
})
