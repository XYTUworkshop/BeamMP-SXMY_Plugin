# BeamMP-SXMY_Plugin

BeamMP 服务器插件（Server Plugin），为 SXMY 服务器提供模块化的插件开发基础：`main.lua` 主加载 + 自动发现模块 + 中英日志切换。基于 **BeamMP-Server v3.x**（Lua 5.3）开发。

A modular server plugin for the SXMY server: `main.lua` main loader + auto-discovered modules + Chinese/English log switching. Built for **BeamMP-Server v3.x** (Lua 5.3).

> 说明：本文件为中文版 README，英文版见 [README.en.md](README.en.md)。
> Note: This is the Chinese README, the English version is at [README.en.md](README.en.md).

## 功能特性 / Features

- **模块化架构**：`main.lua` 作为主加载器，每个功能一个独立文件，可在配置文件中单独开关
  Modular architecture: `main.lua` acts as the main loader, each feature lives in its own file and can be toggled in the config file.
- **自动发现模块**：模块列表自动从 `config.toml` 读取，新增功能无需修改任何代码
  Auto-discovered modules: the module list is read automatically from `config.toml`, no code changes needed to add features.
- **中英日志切换**：`[General] language` 可设置 `zh` 或 `en`，插件控制台日志只输出所选语言
  Chinese/English log switching: set `[General] language` to `zh` or `en`, the plugin console logs output only the selected language.
- **服务器信息日志（loginfo）**：启动时输出服务器启动时间、服务器版本、服务器地图，每项可单独开关
  Server info log (loginfo): outputs server start time, server version and server map on startup, each line can be toggled separately.

## 目录结构 / Directory Structure

```
Resources/Server/BeamMP-SXMY_Plugin/
├── main.lua              # 主加载器：读取配置并按开关加载模块 / Main loader: reads config and loads modules by switch
├── config.toml          # 配置文件：语言与各功能开关 / Config file: language and feature switches
├── README.md            # 中文说明（本文件）/ Chinese README (this file)
├── README.en.md         # 英文说明 / English README
└── modules/             # 功能模块目录（子文件夹，不会被自动加载，由 main.lua require 加载）
                         # Module directory (subfolder, not auto-loaded; loaded via require in main.lua)
    ├── lib.lua          # 共享配置解析库（配置解析、语言切换、模块发现）/ Shared config library (parsing, language, discovery)
    └── loginfo.lua      # 服务器信息日志功能 / Server info log feature
```

## 安装方法 / Installation

1. 将 `BeamMP-SXMY_Plugin` 文件夹复制到服务器的 `Resources/Server/` 目录下
   Copy the `BeamMP-SXMY_Plugin` folder into your server's `Resources/Server/` directory.
2. （可选）修改 `config.toml` 中的语言与功能开关
   (Optional) Adjust the language and feature switches in `config.toml`.
3. 启动/重启服务器，控制台会打印插件加载状态，示例输出如下（`[LUA]` 为 BeamMP 自带前缀）：
   Start/restart the server; the console prints the plugin loading status, example output (`[LUA]` is the BeamMP built-in prefix):
   ```
   [时间] [LUA] [SXMY_Plugin] 插件加载完成
   [时间] [LUA] [SXMY_Plugin] 已加载1/1个功能
   [时间] [LUA] [SXMY_Plugin] 已加载的功能：
   [时间] [LUA] [SXMY_Plugin] 1. loginfo
   [时间] [LUA] [SXMY_Loginfo] 服务器启动时间: 2026.08.18-14.30.00
   [时间] [LUA] [SXMY_Loginfo] 服务器版本: 3.1.0
   [时间] [LUA] [SXMY_Loginfo] 服务器地图: gridmap
   ```
   （`已加载X/Y个功能`：X 为成功加载数，Y 为配置中启用的模块数；loginfo 在 main 汇总之后通过 `onInit` 事件输出 / `Loaded X/Y features`: X = loaded, Y = enabled in config; loginfo prints after the main summary via the `onInit` event）

## 配置说明 / Configuration

配置文件位于 `Resources/Server/BeamMP-SXMY_Plugin/config.toml`，修改后**需重启服务器**生效。

The config file is at `Resources/Server/BeamMP-SXMY_Plugin/config.toml`; a **server restart** is required after changes.

```toml
# 插件语言 / Plugin language
[General]
language = "zh"   # "zh" 中文日志 / Chinese logs, "en" 英文日志 / English logs

# 服务器信息日志 / Server info log
[loginfo]
enable = true          # 功能开关 / Module switch
startTime = true       # 显示服务器启动时间 / Show server start time
serverVersion = true   # 显示服务器版本 / Show server version
serverMap = true       # 显示服务器地图 / Show server map
```

| 配置项 / Key | 说明 / Description |
|---|---|
| `[General].language` | 插件日志语言：`"zh"` 中文，`"en"` 英文 / Plugin log language: `"zh"` Chinese, `"en"` English |
| `[loginfo].enable` | 启用/禁用 loginfo 功能 / Enable/disable the loginfo feature |
| `[loginfo].startTime` | 显示服务器启动时间 / Show the server start time |
| `[loginfo].serverVersion` | 显示服务器版本 / Show the server version |
| `[loginfo].serverMap` | 显示服务器地图（从 `ServerConfig.toml` 获取）/ Show the server map (read from `ServerConfig.toml`) |

## 开发功能模块 / Writing Feature Modules

1. 在 `modules/` 下新建 `.lua` 文件（子文件夹不会被自动加载，需 `require()`）
   Create a `.lua` file under `modules/` (subfolder files are not auto-loaded; load them with `require()`).
2. 在 `config.toml` 中添加对应节与开关：
   Add a section with a switch in `config.toml`:
   ```toml
   [MyModule]
   enable = true
   ```
   （开关键支持 `enable` 与 `enabled` 两种写法 / Both `enable` and `enabled` keys are supported）
3. 重启服务器，`main.lua` 会自动发现并加载该模块，并在启动汇总中列出
   Restart the server; `main.lua` auto-discovers and loads the module, and lists it in the startup summary.

模块内可通过 `lib = require("modules.lib")` 使用配置接口（`lib.getConfig()`、`lib.enabled(节名)`、`lib.get(节, 键, 默认)`、`lib.msg(中文, English)`）。如需在 main 汇总之后执行逻辑，可注册 `onInit` 事件。事件处理函数建议使用 `SXMY_模块名_事件名` 前缀避免冲突。

Inside a module, use `lib = require("modules.lib")` for config access (`lib.getConfig()`, `lib.enabled(section)`, `lib.get(section, key, default)`, `lib.msg(zhText, enText)`). To run logic after the main summary, register the `onInit` event. Prefix event handlers with `SXMY_ModuleName_EventName` to avoid collisions.

## 常见问题 / FAQ

- **修改 config.toml 后不生效？** 需要重启服务器，config.toml 仅在启动时读取。
  Changes to config.toml not applying? Restart the server; the config is only read at startup.
- **如何切换日志语言？** 将 `config.toml` 中 `[General] language` 改为 `"en"` 或 `"zh"` 后重启。
  How to switch the log language? Set `[General] language` in `config.toml` to `"en"` or `"zh"` and restart.
- **新增功能模块？** 在 `modules/` 下新建 `.lua` 文件，并在 `config.toml` 中添加对应的 `[模块名]` 节与 `enable` 开关即可。`main.lua` 会自动发现并加载所有已启用的模块，无需修改任何代码。
  Adding a new feature module? Create a `.lua` file under `modules/`, then add a `[ModuleName]` section with an `enable` switch in `config.toml`. `main.lua` auto-discovers and loads all enabled modules — no code changes needed.

## 许可证 / License

本项目仅供学习参考使用，可自由修改与分发。

This project is for learning and reference purposes; free to modify and redistribute.
