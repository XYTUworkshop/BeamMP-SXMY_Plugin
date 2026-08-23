-- =====================================================================================
-- BeamMP-SXMY_Plugin - modules/NameTag.lua / 聊天昵称模块
-- Chat nickname module / 聊天昵称功能模块
-- Without Auth: players set their own tag with /n, chat messages get a [tag] prefix
-- 未启用 Auth：玩家用 /n 设置自己的昵称，聊天消息带 [昵称] 前缀
-- With Auth: the logged-in account nickname is used automatically as the chat nickname
-- 启用 Auth：自动使用登录账号昵称作为聊天昵称
-- Loaded only when enabled in config.toml / 仅在 config.toml 启用时被加载
-- =====================================================================================

local lib = require("modules.lib") -- shared config library / 共享配置库

-- Whether the Auth module is enabled in the config / Auth 模块是否在配置中启用
local authEnabled = lib.get("Auth", "enable", false)

local playerTags = {} -- player_id -> custom tag, non-Auth mode only / 玩家自定义昵称（仅非 Auth 模式）

-- Get the chat nickname of a player / 获取玩家的聊天昵称
local function getNick(player_id)
    if authEnabled then
        -- Auth mode: use the logged-in account nickname / Auth 模式：使用登录账号昵称
        if type(SXMY_Auth_GetNick) == "function" then
            return SXMY_Auth_GetNick(player_id)
        end
        return nil
    end
    -- Non-Auth mode: use the /n custom tag / 非 Auth 模式：使用 /n 自定义昵称
    local tag = playerTags[player_id]
    if tag and tag ~= "" then
        return tag
    end
    return nil
end

-- Hint after the player finished loading (non-Auth mode only) / 玩家完成加载后提示（仅非 Auth 模式）
function SXMY_NameTag_onPlayerJoining(player_id)
    if not authEnabled then
        MP.SendChatMessage(player_id, lib.msg("请使用[/n 名字] 标记自己的名字", "Use [/n name] to set your name tag"))
    end
end

-- Chat handler: prefix messages with the nickname / 聊天处理：为消息添加昵称前缀
function SXMY_NameTag_onChatMessage(player_id, player_name, message)
    if authEnabled then
        -- Auth mode: only logged-in players get the nickname prefix; / commands stay private (Auth handles them)
        -- Auth 模式：仅已登录玩家带昵称前缀；/ 命令保持私有（由 Auth 处理）
        local nick = getNick(player_id)
        if nick and message:sub(1, 1) ~= "/" then
            MP.SendChatMessage(-1, "<" .. nick .. "> " .. message)
            return 1
        end
        return 0
    end

    -- Non-Auth mode: /n command / 非 Auth 模式：/n 命令
    if message:sub(1, 3) == "/n " then
        local tag = message:sub(4):match("^%s*(.-)%s*$")
        if tag and tag ~= "" then
            playerTags[player_id] = tag
            print("*" .. player_name .. lib.msg("已经将自己名字标记为", " set their name tag to ") .. tag)
            MP.SendChatMessage(player_id, lib.msg("你的名字已标记为 [" .. tag .. "]", "Your name tag is now [" .. tag .. "]"))
        else
            MP.SendChatMessage(player_id, lib.msg("标记失败：名字不能为空", "Tag failed: tag cannot be empty"))
        end
        return 1
    end

    -- Prefix normal messages with the tag / 普通消息添加昵称前缀
    local tag = playerTags[player_id]
    if tag then
        MP.SendChatMessage(-1, "<" .. tag .. "> " .. message)
        return 1
    end
    return 0
end

-- Clean up on disconnect / 玩家断开时清理
function SXMY_NameTag_onPlayerDisconnect(player_id)
    playerTags[player_id] = nil
end

-- Show startup info: enabled status and mode, printed after the other modules / 显示启动信息：启用状态与模式（在其他模块之后输出）
function SXMY_NameTag_ShowInfo()
    print("[SXMY_NameTag] " .. lib.msg("已启用", "Enabled"))
    if authEnabled then
        print("[SXMY_NameTag] " .. lib.msg("自动(Auth启用)模式", "Automatic mode (Auth enabled)"))
    else
        print("[SXMY_NameTag] " .. lib.msg("手动(Auth未启用)模式", "Manual mode (Auth disabled)"))
    end
end

-- Register event handlers / 注册事件处理函数
MP.RegisterEvent("onPlayerJoining", "SXMY_NameTag_onPlayerJoining")
MP.RegisterEvent("onChatMessage", "SXMY_NameTag_onChatMessage")
MP.RegisterEvent("onPlayerDisconnect", "SXMY_NameTag_onPlayerDisconnect")
