-- BeamMP-SXMY_Plugin - modules/OPAuth.lua / 管理员账号模块
-- Admin (OP) account module / 管理员（OP）账号功能模块
-- Only works when the Auth feature is enabled / 仅在启用 Auth 功能时工作

local lib = require("modules.lib")

-- 前置条件：Auth 必须已启用 / prerequisite: Auth must be enabled
if not lib.enabled("Auth") then
    print("[SXMY_OPAuth] " .. lib.msg("未启用 Auth 功能 OPAuth 不工作", "Auth is disabled, OPAuth is inactive"))
    return {}
end

-- 生成并规范化本模块配置节 / generate and normalize this module's config section
lib.ensureSection("OPAuth", {
    { key = "enable", v = true, c = "管理员账号功能开关（需启用 Auth）/ Admin (OP) module switch (requires Auth)" },
    { key = "command", v = { "reload-reloadSXMY", "list-listSXMY", "op-opSXMY","ban-banSXMY", "banip-banipSXMY","unban-unbanSXMY", "kick-kickSXMY" }, c = "管理员聊天命令-服务端命令映射，格式：玩家命令(带/)-服务端命令 / OP chat command -> server command mapping, format: playerCommand(with /)-serverCommand" },
})

local OP_FILE = "Resources/Server/BeamMP-SXMY_Plugin/opusers.txt" -- op file, relative to working dir / 管理员文件（相对服务器工作目录）

local opSet = {} -- nickname -> true / 昵称 -> 是否管理员

-- Load the op list from the file / 从文件加载管理员列表
local function loadOps()
    local fh, err = io.open(OP_FILE, "r")
    if not fh then
        return
    end
    for line in fh:lines() do
        local nick = line:match("^%s*(%S+)%s*$")
        if nick then
            opSet[nick] = true
        end
    end
    fh:close()
end

-- Append an op to the file / 追加写入管理员
local function appendOp(nick)
    local fh, err = io.open(OP_FILE, "a")
    if not fh then
        return false, err
    end
    local ok = fh:write(nick, "\n")
    fh:close()
    return ok, nil
end

-- 判断昵称是否为管理员 / check whether a nickname is an OP
function SXMY_OPAuth_IsOp(nick)
    return nick ~= nil and opSet[nick] == true
end

-- 设置管理员（服务端命令 opSXMY <nickname>；byNick 为授予者昵称，nil 表示服务器控制台）/ set an OP (console command opSXMY <nickname>; byNick = the granter's nickname, nil = server console)
local function setOp(nick, byNick)
    if opSet[nick] then
        return lib.msg("该玩家已是管理员", "That player is already an OP")
    end
    -- The nickname must be a registered account / 昵称必须是已注册账户
    if type(SXMY_Auth_AccountExists) ~= "function" or not SXMY_Auth_AccountExists(nick) then
        return lib.msg("该昵称未注册 无法设置为管理员", "That nickname is not registered, cannot be set as OP")
    end
    local ok, err = appendOp(nick)
    if not ok then
        return lib.msg("管理员写入失败", "Failed to write the op file") .. ": " .. tostring(err)
    end
    opSet[nick] = true
    -- Audit log: who granted admin to whom / 审计日志：谁在何时授予谁管理员
    print("[SXMY_OPAuth] " .. tostring(byNick or lib.msg("控制台", "console")) .. lib.msg(" 授予 ", " granted admin to ") .. nick)
    return lib.msg("已将 ", "Set ") .. nick .. lib.msg(" 设置为管理员", " as OP")
end

-- 读取配置的命令映射（玩家命令 -> 服务端命令）/ read the configured command mapping (player command -> server command)
local function getCommandMap()
    local map = {}
    local cmd = lib.get("OPAuth", "command", nil)
    if type(cmd) == "table" then
        for _, entry in ipairs(cmd) do
            local player, server = tostring(entry):match("^(%S+)-(%S+)$")
            if player and server then
                map[player] = server
            end
        end
    end
    return map
end

-- 服务器控制台命令：opSXMY <nickname> / console command: opSXMY <nickname>
function SXMY_OPAuth_onConsoleInput(command)
    if not command then
        return nil
    end
    local nick = command:match("^opSXMY%s+([%w_]+)%s*$")
    if not nick then
        return nil
    end
    return setOp(nick, nil)
end

-- 玩家聊天命令：按配置映射（/reload /list /op）→ 权限检查 → 执行 → 私信返回结果
-- player chat commands: per config mapping (/reload /list /op) -> permission check -> execute -> private-message the result
function SXMY_OPAuth_onChatMessage(player_id, player_name, message)
    if not message or message:sub(1, 1) ~= "/" then
        return 0
    end
    local cmdName, rest = message:match("^/(%S+)%s*(.*)$")
    if not cmdName then
        return 0
    end
    local serverCmd = getCommandMap()[cmdName]
    if not serverCmd then
        return 0 -- 不是映射的命令 / not a mapped command
    end
    -- 权限检查：必须已登录且是管理员 / permission: must be logged in and an OP
    local nick = nil
    if type(SXMY_Auth_GetLoginNick) == "function" then
        nick = SXMY_Auth_GetLoginNick(player_id)
    end
    if not nick then
        return 1 -- 未登录：静默拦截（Auth 会提示注册/登录）/ not logged in: silently block (Auth prompts instead)
    end
    if not SXMY_OPAuth_IsOp(nick) then
        MP.SendChatMessage(player_id, lib.msg("权限不足", "Permission denied"))
        return 1
    end
    -- 执行对应的服务端命令并私信返回结果 / run the mapped server command and reply via private message
    local result
    if serverCmd == "opSXMY" then
        -- 管理员可委派：/op 昵称（需已注册）；保留特判以记录授予者审计来源 / OPs can delegate: /op nickname (must be registered); special-cased to record the granter for the audit log
        local target = rest:match("^([%w_]+)%s*$")
        if not target then
            result = lib.msg("用法：/op 昵称", "Usage: /op nickname")
        else
            result = setOp(target, nick)
        end
    elseif serverCmd == "listSXMY" then
        -- 表格逐行私信 / send the table rows one by one
        if type(SXMY_Auth_ListRows) == "function" then
            for _, line in ipairs(SXMY_Auth_ListRows()) do
                MP.SendChatMessage(player_id, line)
            end
        end
        return 1
    elseif serverCmd == "exit" then
        -- 官方命令（如 exit）不支持映射：没有 API 注入服务器控制台命令，
        -- 外部强杀（taskkill /f / pkill -9）不优雅。走动态调用后提示「未知命令映射」。
        -- Official commands (like exit) are not supported: there is no API to inject server console input,
        -- and external hard kills are not graceful. Falls through and reports "Unknown command mapping".
        result = lib.msg("未知命令映射", "Unknown command mapping")
    else
        -- 动态调用各模块的 onConsoleInput handler：新增服务端命令无需修改本模块
        -- 只需模块提供全局 SXMY_*_onConsoleInput 函数并返回非 nil（表示已处理）
        -- dynamically invoke every module's onConsoleInput handler; new server commands need no change here
        -- as long as a module exposes a global SXMY_*_onConsoleInput that returns non-nil when handled
        local full = (rest ~= "") and (serverCmd .. " " .. rest) or serverCmd
        local handled = false
        for name, fn in pairs(_G) do
            if type(fn) == "function" and name:match("^SXMY_.*_onConsoleInput$") then
                local ok, r = pcall(fn, full)
                if ok and r ~= nil then
                    result = r
                    handled = true
                    break
                end
            end
        end
        if not handled then
            result = lib.msg("未知命令映射", "Unknown command mapping")
        end
    end
    MP.SendChatMessage(player_id, tostring(result))
    return 1
end

-- Initialize and register events / 初始化并注册事件
loadOps()
MP.RegisterEvent("onConsoleInput", "SXMY_OPAuth_onConsoleInput")
MP.RegisterEvent("onChatMessage", "SXMY_OPAuth_onChatMessage")
