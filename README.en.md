# BeamMP-SXMY_Plugin

A modular server plugin for the SXMY server: `main.lua` main loader + auto-discovered modules + Chinese/English log switching. Built for **BeamMP-Server v3.x** (Lua 5.3).

> Note: The Chinese version is at [README.md](README.md).

## Features

- **Modular architecture**: `main.lua` acts as the main loader, each feature lives in its own file and can be toggled in the config file.
- **Auto-discovered modules**: the module list is read automatically from `config.toml`, no code changes needed to add features.
- **Welcome message (WelcomeMsg)**: sends the configured welcome text to a player on join via private message, supports any language, `\n` splits into multiple messages.
- **Auth**: `/reg` register, `/login` login, SHA-256 password hashing; unauthenticated players cannot chat or spawn vehicles; password rules configurable.
- **NameTag**: without Auth, players set a chat nickname with `/n name` and messages get a `[nickname]` prefix; with Auth, the logged-in account nickname is used automatically.
- **VehicleTag**: after login or setting a `/n` nickname, the nickname tag is drawn above all of the player's vehicles (including their own cars) and the BeamMP official tags are hidden; requires the `SXMYVehicleTag` client mod.
- **Chinese/English log switching**: set `[General] language` to `zh` or `en`, the plugin console logs output only the selected language.
- **Server info log (loginfo)**: outputs server start time, server version and server map on startup, each line can be toggled separately.

## Directory Structure

```
Resources/Server/BeamMP-SXMY_Plugin/
├── main.lua              # Main loader: reads config and loads modules by switch
├── config.toml          # Config file: language and feature switches
├── README.md            # Chinese README
├── README.en.md         # English README (this file)
└── modules/             # Module directory (subfolder, not auto-loaded; loaded via require in main.lua)
    ├── lib.lua          # Shared config library (parsing, language, discovery)
    ├── Auth.lua         # Auth feature (register/login/blocking)
    ├── NameTag.lua      # Chat nickname feature
    ├── VehicleTag.lua   # Vehicle tag feature (requires the client mod)
    ├── WelcomeMsg.lua   # Welcome message feature
    └── loginfo.lua      # Server info log feature
```

## Installation

1. Extract the release archive `BeamMP-SXMY_Plugin.zip`, then extract the `server` and `client` folders into the BeamMP server's `Resources` folder:
   - `server` → `Resources/Server` (contains the plugin folder `BeamMP-SXMY_Plugin`)
   - `client` → `Resources/Client` (contains the vehicle-tag client mod `SXMY-client.zip`, auto-downloaded by players on join)
2. (Optional) Adjust the language and feature switches in `Resources/Server/BeamMP-SXMY_Plugin/config.toml`.
3. Start/restart the server; the console prints the plugin loading status, example output (`[LUA]` is the BeamMP built-in prefix):

```
[time] [LUA] [SXMY_Plugin] Plugin loaded
[time] [LUA] [SXMY_Plugin] Loaded 2/2 features
[time] [LUA] [SXMY_Plugin] Loaded features:
[time] [LUA] [SXMY_Plugin] 1. WelcomeMsg
[time] [LUA] [SXMY_Plugin] 2. loginfo
[time] [LUA] [SXMY_Loginfo] Server start time: 2026.08.18-14.30.00
[time] [LUA] [SXMY_Loginfo] Server version: 3.9.3
[time] [LUA] [SXMY_Loginfo] Server map: gridmap
[time] [LUA] [SXMY_WelcomeMsg] Welcome Text :
[time] [LUA] [SXMY_WelcomeMsg] Welcome to SXMY
```

(`Loaded X/Y features`: X = loaded, Y = enabled in config; the `showtest` startup test text prints only once)

## Configuration

The config file is at `Resources/Server/BeamMP-SXMY_Plugin/config.toml`; a **server restart** is required after changes.

**Auto-generated config**: each feature module generates its **own** config section on load — missing keys are appended with defaults (and zh/en comments) to `config.toml`. **Removing a module file (i.e. dropping that feature) stops its config section from being generated**; your custom settings (e.g. welcome text, password rules) are never overwritten. A fresh install auto-generates the full config on first start.

```toml
[General]
language = "zh"    # 插件日志语言（"zh" 中文，"en" 英文） / Plugin log language ("zh" Chinese, "en" English)

[Auth]
enable = true          # 身份认证功能开关 / Auth module switch
passwdlen = 8          # 密码最小长度（位）/ Minimum password length (characters)
passwdcase = false     # 是否要求大小写混合（不要求也可使用）/ Require mixed case (optional)
passwdsymbol = false   # 是否要求特殊符号（不要求也可使用）/ Require special characters (optional)
LoginMsg = "欢迎 <name> 登录服务器"  # 登录成功广播消息（/say），<name> 为玩家昵称，留空则不发送 / Login broadcast message, <name> = nickname, empty = disabled

[NameTag]
enable = true      # 聊天昵称功能开关（Auth 启用时自动使用登录昵称）/ Chat nickname module switch (uses the login nickname when Auth is enabled)

[VehicleTag]
enable = true      # 车辆标签功能开关（需 Resources/Client 的 SXMYVehicleTag mod）/ Vehicle tag module switch (requires the SXMYVehicleTag client mod)

[WelcomeMsg]
enable = true      # 进服信息功能开关 / Welcome message module switch
delay = 12         # 发送延迟（秒），等待玩家同步完成 / Send delay (seconds), waits for the player to sync
showtest = true    # 启动时显示欢迎文本测试（在插件与 loginfo 输出后）/ Show welcome text test on startup (after plugin and loginfo output)
text = "欢迎来到SXMY \n请使用[/n name]标记自己的名字 \nWelcome to SXMY"  # 进服信息文本，支持所有语言，\n 换行分多条发送 / Welcome text, any language, \n splits into multiple messages

[loginfo]
enable = true          # 服务器信息日志功能开关 / Server info log module switch
startTime = true       # 显示服务器启动时间 / Show server start time
serverVersion = true   # 显示服务器版本 / Show server version
serverMap = true       # 显示服务器地图（读取 ServerConfig.toml） / Show server map (read from ServerConfig.toml)
```

| Key | Description |
|---|---|
| `[General].language` | Plugin log language: `"zh"` Chinese, `"en"` English |
| `[Auth].enable` | Enable/disable the auth feature |
| `[Auth].passwdlen` | Minimum password length (characters), default 8 |
| `[Auth].passwdcase` | Require both uppercase and lowercase letters in the password |
| `[Auth].passwdsymbol` | Require a special character in the password |
| `[Auth].maxRegsPerIP` | Max registrations per IP (0 = unlimited), default 3 |
| `[Auth].LoginMsg` | Login broadcast message (`/say`), `<name>` replaced with the nickname, empty disables it |
| `[NameTag].enable` | Enable/disable the chat nickname feature |
| `[VehicleTag].enable` | Enable/disable the vehicle tag feature (requires `Resources/Client/SXMYVehicleTag.zip`) |
| `[WelcomeMsg].enable` | Enable/disable the welcome message feature |
| `[WelcomeMsg].delay` | Send delay in seconds, waits for the player to sync, default 12 |
| `[WelcomeMsg].showtest` | Show the welcome text test on startup (after plugin and loginfo output) |
| `[WelcomeMsg].text` | Welcome text, any language, `\n` splits into multiple messages |
| `[loginfo].enable` | Enable/disable the loginfo feature |
| `[loginfo].startTime` | Show the server start time |
| `[loginfo].serverVersion` | Show the server version |
| `[loginfo].serverMap` | Show the server map (read from `ServerConfig.toml`) |

## Writing Feature Modules

1. Create a `.lua` file under `modules/` (subfolder files are not auto-loaded; load them with `require()`).
2. Add a section with a switch in `config.toml`:

```toml
[MyModule]
enable = true
```

(Both `enable` and `enabled` keys are supported)

3. Restart the server; `main.lua` auto-discovers and loads the module, and lists it in the startup summary.

## Auth Commands

Type in the in-game chat:

| Command | Description |
|---|---|
| `/reg nickname password confirmpassword` | Register and log in |
| `/login nickname password` | Log in |
| `/n nickname` | Set the chat nickname (only when Auth is disabled) |

- Unauthenticated players: chat hidden from others, **cannot spawn vehicles** (including editing/replacing); prompted to register/log in every 5 seconds; locked for 60 seconds after 5 failed logins.
- Logged in: messages starting with `/` are hidden from others (commands are not broadcast).
- Accounts stored in `users.txt`, passwords as SHA-256 hashes.

## Console Commands

| Command | Description |
|---|---|
| `reloadSXMY` | Hot-reload the plugin (type in the server console). Apply plugin file changes without restarting the server; note: players' login states are reset on reload and they must log in again. |

## Security Notes

- Passwords are typed in chat; with `LogChat = true` the server console/log records chat (including passwords) — keep the console admin-only.
- Passwords stored as salted SHA-256 (`salt$hash`), legacy unsalted accounts still work; for production consider a slow hash (e.g. bcrypt).
- Built-in brute-force protection: lockout after 5 consecutive failed logins (60 seconds), tracked by player IP when available, not bypassable by reconnecting with a new server ID.
- Nicknames are limited to letters, digits and underscores to keep the accounts file format safe.

Inside a module, use `lib = require("modules.lib")` for config access (`lib.getConfig()`, `lib.enabled(section)`, `lib.get(section, key, default)`, `lib.msg(zhText, enText)`). To run logic after the main summary, register the `onInit` event. Prefix event handlers with `SXMY_ModuleName_EventName` to avoid collisions.

## FAQ

- **Changes to config.toml not applying?** Restart the server; the config is only read at startup.
- **How to switch the log language?** Set `[General] language` in `config.toml` to `"en"` or `"zh"` and restart.
- **Adding a new feature module?** Create a `.lua` file under `modules/`, then add a `[ModuleName]` section with an `enable` switch in `config.toml`. `main.lua` auto-discovers and loads all enabled modules — no code changes needed.

## License

This project uses the GPL-3.0 license, for learning and reference purposes only; free to modify and redistribute.
