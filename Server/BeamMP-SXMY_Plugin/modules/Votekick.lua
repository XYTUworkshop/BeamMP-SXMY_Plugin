-- BeamMP-SXMY_Plugin - modules/Votekick.lua / 玩家投票踢出模块
-- Votekick module: players start a vote to kick a player (by Auth nickname); the vote passes
-- when agree / logged-in-players >= the configured percentage; the kick uses PlayerKick (kickSXMY).
-- 玩家发起投票踢出某玩家（按 Auth 昵称）；同意数/登录人数 >= 配置百分比时通过，踢出复用 PlayerKick（kickSXMY）
-- Commands: /votekick <nickname> (also /votokick), /vote t = agree, /vote f = disagree
-- 命令：/votekick <昵称>（兼容 /votokick），/vote t 赞同，/vote f 反对
-- Requires Auth (login nicknames and the online-player count) / 依赖 Auth（登录昵称与在线人数统计）

local lib = require("modules.lib")

-- 自身开关（模块统一机制）；同时要求 Auth 启用 / own switch (standard module mechanism); also requires Auth
local enabled = lib.get("Votekick", "enable", true)
if not enabled or not lib.enabled("Auth") then
    print("[SXMY_Votekick] " .. lib.msg("未启用 Auth 功能 Votekick 不工作", "Auth is disabled, Votekick is not active"))
    return {}
end

lib.ensureSection("Votekick", {
    { key = "enable", v = true, c = "投票踢出功能开关（需启用 Auth）/ Votekick module switch (requires Auth)" },
    { key = "timeout", v = 60, c = "投票超时时间（秒）/ Vote timeout (seconds)" },
    { key = "cooldown", v = 120, c = "发起投票后的冷却时间（秒）/ Cooldown after starting a vote (seconds)" },
    { key = "percentage", v = 60, c = "票数百分比（同意数/登录人数 >= 此值则踢出）/ Vote percentage (agree / logged-in >= this value kicks the player)" },
})

-- 当前投票状态（同一时间仅一个投票）/ current vote state (only one vote at a time)
-- vote = { target = 昵称, targetPid = 目标玩家ID, initiator = 发起人ID, total = 发起时登录人数, agree = {nick}, voters = {nick -> t/f}, endTime = 结束时间戳 }
-- 冷却与投票均按 Auth 昵称记账：同一账号只能投一票，断线重连换 pid 无法绕过，同 NAT 的不同账号各自独立
-- cooldown and votes are both keyed by the Auth nickname: one vote per account, reconnect with a new pid cannot bypass it, and different accounts behind the same NAT stay independent
local vote = nil
-- 冷却记录（按昵称）：nick -> 上次发起时间 / cooldown records keyed by nickname: nick -> last vote start time
local lastVote = {}

-- 私信 / broadcast helpers / 私信与广播辅助
local function notify(player_id, text)
    MP.SendChatMessage(player_id, text)
end
local function broadcast(text)
    MP.SendChatMessage(-1, text)
end

-- 统计当前已登录（Auth）的玩家人数 / count the players currently logged in via Auth
local function countLoggedIn()
    local n = 0
    if type(SXMY_Auth_GetLoginNick) == "function" then
        local okp, players = pcall(MP.GetPlayers)
        if okp and type(players) == "table" then
            for pid in pairs(players) do
                if SXMY_Auth_GetLoginNick(pid) then
                    n = n + 1
                end
            end
        end
    end
    return n
end

-- 结束投票并清空状态 / end the vote and clear the state
local function endVote()
    vote = nil
end

-- 广播当前投票状态（每次投票后提示）：xxx已投票 当前投票人数X/Y 同意率Z% / broadcast the vote status after each vote: xxx voted, current votes X/Y, agree rate Z%
local function broadcastStatus(voterNick)
    local agreeCount = 0
    for _ in pairs(vote.agree) do
        agreeCount = agreeCount + 1
    end
    local votedCount = 0
    for _ in pairs(vote.voters) do
        votedCount = votedCount + 1
    end
    -- 同意率 = 同意数 / 已投票数（字面同意率）/ agree rate = agree / voted (the literal agree ratio)
    local agreeRate = votedCount > 0 and math.floor(agreeCount / votedCount * 100) or 0
    broadcast(voterNick .. lib.msg("已投票 当前投票人数", " voted. Current votes: ") .. votedCount .. "/" .. vote.total ..
        lib.msg(" 同意率", ", agree rate: ") .. agreeRate .. "%")
end

-- 判定投票是否通过；通过则调用 PlayerKick 踢出并结束投票，返回 true / check whether the vote passed; kick via PlayerKick and end the vote when it did, returns true
local function checkVote()
    if not vote then
        return
    end
    -- 使用发起时快照的百分比（防投票进行中改配置导致异常判定）/ use the percentage snapshotted at start (a config change mid-vote cannot skew the result)
    local percentage = vote.pct or lib.get("Votekick", "percentage", 60)
    local agreeCount = 0
    for _ in pairs(vote.agree) do
        agreeCount = agreeCount + 1
    end
    if agreeCount / vote.total >= percentage / 100 then
        -- 复用 PlayerKick（kickSXMY）按 Auth 昵称踢出 / reuse PlayerKick (kickSXMY) to kick by Auth nickname
        local kickResult = nil
        if type(SXMY_PlayerKick_onConsoleInput) == "function" then
            kickResult = SXMY_PlayerKick_onConsoleInput("kickSXMY " .. vote.target)
        else
            broadcast(lib.msg("踢出功能未启用，投票已结束", "The kick feature is not enabled, the vote is closed"))
            endVote()
            return true
        end
        -- 中英文都检查，避免 locale 不同导致误报 / check both languages so the locale does not cause a false report
        local notFound = (kickResult and (kickResult:find("未找到在线玩家", 1, true) or kickResult:find("No online player", 1, true)))
        if notFound then
            broadcast(vote.target .. lib.msg(" 已被投票踢出（该玩家已不在服务器）", " has been vote-kicked (the player is no longer online)"))
        else
            broadcast(vote.target .. lib.msg(" 已被投票踢出", " has been vote-kicked"))
        end
        endVote()
        return true
    end
    return false
end

-- 处理聊天命令：/votekick（/votokick）与 /vote / chat commands: /votekick (/votokick) and /vote
function SXMY_Votekick_onChatMessage(player_id, player_name, message)
    if not message or message:sub(1, 1) ~= "/" then
        return 0
    end
    -- ===== /votekick <昵称>（兼容 /votokick 拼写）/ start a vote =====
    local targetNick = message:match("^/vot[eo]kick%s+([%w_]+)%s*$")
    if targetNick then
        -- 0. 配置校验：百分比需在 1-100（0 或过低会一票即踢，视为配置错误）/ config check: percentage must be 1-100 (0 or too low would kick with one vote, treat as misconfiguration)
        local pct = lib.get("Votekick", "percentage", 60)
        if pct < 1 or pct > 100 then
            notify(player_id, lib.msg("投票配置错误：percentage 需在 1-100 之间", "Vote config error: percentage must be between 1 and 100"))
            return 1
        end
        -- 1. 发起人需已登录（昵称是冷却与投票的唯一身份）/ the initiator must be logged in (the nickname is the identity for cooldowns and votes)
        local initiatorNick = nil
        if type(SXMY_Auth_GetLoginNick) == "function" then
            initiatorNick = SXMY_Auth_GetLoginNick(player_id)
        end
        if not initiatorNick then
            notify(player_id, lib.msg("请先登录后再发起投票", "Please log in before starting a vote"))
            return 1
        end
        -- 2. 冷却检查（按昵称，断线重连换 pid 无法绕过）/ cooldown check (by nickname, reconnect with a new pid cannot bypass it)
        local cooldown = lib.get("Votekick", "cooldown", 120)
        local now = os.time()
        if lastVote[initiatorNick] and now - lastVote[initiatorNick] < cooldown then
            notify(player_id, lib.msg("你的投票发起速度太快了", "You are starting votes too quickly"))
            return 1
        end
        -- 3. 已有进行中的投票 / an ongoing vote already exists
        if vote then
            notify(player_id, lib.msg("目前已有投票", "A vote is already in progress"))
            return 1
        end
        -- 4. 目标需已登录且在线 / the target must be logged in and online
        local targetPid = nil
        if type(SXMY_Auth_GetPlayerIdByNick) == "function" then
            targetPid = SXMY_Auth_GetPlayerIdByNick(targetNick)
        end
        if not targetPid then
            notify(player_id, lib.msg("未找到在线玩家：", "No online player named: ") .. targetNick)
            return 1
        end
        -- 5. 开始投票（记录发起时的登录人数）/ start the vote (record the logged-in count now)
        lastVote[initiatorNick] = now
        local total = countLoggedIn()
        vote = {
            target = targetNick, targetPid = targetPid,
            initiator = player_id, total = math.max(1, total),
            pct = pct, -- 发起时快照百分比，投票进行中改配置不影响本次判定 / snapshot the percentage at start so config changes do not affect this vote
            agree = {}, voters = {},
            endTime = now + lib.get("Votekick", "timeout", 60),
        }
        broadcast(initiatorNick .. lib.msg(" 发起了投票 踢出 ", " started a vote to kick ") .. targetNick ..
            lib.msg(" 使用/vote t赞同 使用/vote f反对", " use /vote t to agree, /vote f to disagree"))
        return 1
    end
    -- ===== /vote t（赞同）/vote f（反对）/ cast a vote =====
    local yes = message:match("^/vote%s+t%s*$")
    local no = message:match("^/vote%s+f%s*$")
    if yes or no then
        if not vote then
            notify(player_id, lib.msg("目前没有进行中的投票", "No vote in progress"))
            return 1
        end
        local nick = nil
        if type(SXMY_Auth_GetLoginNick) == "function" then
            nick = SXMY_Auth_GetLoginNick(player_id)
        end
        if not nick then
            notify(player_id, lib.msg("请先登录后再投票", "Please log in before voting"))
            return 1
        end
        -- 每账号一票（按昵称，同 NAT 的不同账号各自独立，断线重连换 pid 无法重复投）/ one vote per account (by nickname; different accounts behind the same NAT stay independent, reconnect with a new pid cannot vote twice)
        if vote.voters[nick] ~= nil then
            notify(player_id, lib.msg("你已投票", "You already voted"))
            return 1
        end
        vote.voters[nick] = yes and true or false
        if yes then
            vote.agree[nick] = true
        end
        -- 投票后广播状态；投票通过时（已广播踢出结果）不再重复广播状态 / broadcast the status after each vote; skip it when the vote just passed (the kick result is already broadcast)
        if not checkVote() then
            broadcastStatus(nick)
        end
        return 1
    end
    return 0
end

-- 每秒检查投票超时 / check the vote timeout every second
function SXMY_Votekick_Tick()
    if not vote then
        return
    end
    if os.time() >= vote.endTime then
        broadcast(lib.msg("投票已超时", "The vote has timed out"))
        endVote()
    end
end

-- 冷却记录按 IP 保留（重连不清，防止绕过冷却）；此处不再需要断线清理 / cooldown records stay keyed by IP and survive reconnects (no cleanup here, so the cooldown cannot be bypassed)

MP.RegisterEvent("onChatMessage", "SXMY_Votekick_onChatMessage")
MP.RegisterEvent("SXMY_Votekick_Tick", "SXMY_Votekick_Tick")
MP.CreateEventTimer("SXMY_Votekick_Tick", 1000)
