# BeamMP-SXMY_Plugin

A modular server plugin for the SXMY server: `main.lua` main loader + auto-discovered modules + Chinese/English log switching. Built for **BeamMP-Server v3.x** (Lua 5.3).

> Note: The Chinese version is at [README.md](README.md).

## Features

- **Modular architecture**: `main.lua` acts as the main loader, each feature lives in its own file and can be toggled in the config file.
- **Auto-discovered modules**: the module list is read automatically from `config.toml`, no code changes needed to add features.
- **Welcome message (WelcomeMsg)**: sends the configured welcome text to a player on join via private message, supports any language, `\n` splits into multiple messages.
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
    ├── WelcomeMsg.lua   # Welcome message feature
    └── loginfo.lua      # Server info log feature
```

## Installation

1. Copy the `BeamMP-SXMY_Plugin` folder into your server's `Resources/Server/` directory.
2. (Optional) Adjust the language and feature switches in `config.toml`.
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

```toml
[General]
language = "zh"    # 插件日志语言（"zh" 中文，"en" 英文） / Plugin log language ("zh" Chinese, "en" English)

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

Inside a module, use `lib = require("modules.lib")` for config access (`lib.getConfig()`, `lib.enabled(section)`, `lib.get(section, key, default)`, `lib.msg(zhText, enText)`). To run logic after the main summary, register the `onInit` event. Prefix event handlers with `SXMY_ModuleName_EventName` to avoid collisions.

## FAQ

- **Changes to config.toml not applying?** Restart the server; the config is only read at startup.
- **How to switch the log language?** Set `[General] language` in `config.toml` to `"en"` or `"zh"` and restart.
- **Adding a new feature module?** Create a `.lua` file under `modules/`, then add a `[ModuleName]` section with an `enable` switch in `config.toml`. `main.lua` auto-discovers and loads all enabled modules — no code changes needed.

## License

This project is for learning and reference purposes; free to modify and redistribute.
