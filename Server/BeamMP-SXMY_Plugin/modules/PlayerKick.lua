-- BeamMP-SXMY_Plugin - modules/PlayerKick.lua / 玩家踢出模块
-- Player kick module: kick an online player by their Auth login nickname, with an optional reason.
-- 按 Auth 登录昵称踢出在线玩家，可指定可选理由（与 banSXMY 同样的查找方式）
-- 服务端命令 kickSXMY <昵称> <理由（可空）>，经 OPAuth 的 command 映射（kick-kickSXMY）供管理员在聊天框使用，结果私信返回
-- 依赖 Auth（按昵称查找），与 PlayerBan 相同 / depends on Auth (lookup by nickname), same as PlayerBan

local lib = require("modules.lib")

-- 自身开关（模块统一机制）/ own switch (standard module mechanism)
local enabled = lib.get("PlayerKick", "enable", true)
if not enabled then
    print("[SXMY_PlayerKick] " .. lib.msg("已禁用", "Disabled"))
    return {}
end

lib.ensureSection("PlayerKick", {
    { key = "enable", v = true, c = "玩家踢出功能开关 / Player kick module switch" },
})

-- 按 Auth 登录昵称查找在线玩家（返回 id；未登录/未找到时返回 nil + 错误提示）
-- find an online player by their Auth login nickname (returns the id; nil + error message when missing)
local function findPlayerId(target)
    if type(SXMY_Auth_GetPlayerIdByNick) ~= "function" then
        return nil, lib.msg("Auth 功能未启用 无法按昵称踢出", "Auth is not enabled, cannot kick by nickname")
    end
    local pid = SXMY_Auth_GetPlayerIdByNick(target)
    if not pid then
        return nil, lib.msg("未找到在线玩家：", "No online player named: ") .. target
    end
    return pid
end

-- 踢出玩家：MP.DropPlayer 是 v3 踢人 API；失败或明确拒绝时回退私信 / kick a player: MP.DropPlayer is the v3 kick API; fall back to a private message on error or explicit refusal
local function kick(player_id, reason)
    local ok, res = pcall(MP.DropPlayer, player_id, reason or "")
    if not ok or res == false then
        MP.SendChatMessage(player_id, reason or "")
    end
end

-- 服务端命令：kickSXMY <昵称> <理由（可空）>（控制台与 OPAuth 动态分发共用，返回非 nil 表示已处理）
-- server command: kickSXMY <nickname> <reason (optional)> (used by the console and the OPAuth dynamic dispatch; non-nil return = handled)
function SXMY_PlayerKick_onConsoleInput(cmd)
    -- kickSXMY <昵称> <理由（可空）> / kickSXMY <nickname> <reason (optional)>
    local target, reason = cmd:match("^kickSXMY%s+(%S+)%s*(.-)%s*$")
    if not target then
        -- 命令名正确但参数不完整 → 返回用法提示（否则控制台会显示 Unknown command）/ correct command name but incomplete arguments -> usage hint (otherwise the console shows "Unknown command")
        if cmd == "kickSXMY" or cmd:match("^kickSXMY%s") then
            return lib.msg("用法：kickSXMY <昵称> <理由（可空）>", "Usage: kickSXMY <nickname> <reason (optional)>")
        end
        return nil -- 非本模块命令 / not this module's command
    end
    local foundId, err = findPlayerId(target)
    if not foundId then
        return err
    end
    kick(foundId, reason)
    if reason and reason ~= "" then
        return lib.msg("已踢出 ", "Kicked ") .. target .. lib.msg(" 理由：", ", reason: ") .. reason
    end
    return lib.msg("已踢出 ", "Kicked ") .. target
end

MP.RegisterEvent("onConsoleInput", "SXMY_PlayerKick_onConsoleInput")
