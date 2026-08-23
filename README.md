# BeamMP-SXMY_Plugin

BeamMP 服务器插件，为 SXMY 服务器提供模块化的插件开发基础：`main.lua` 主加载 + 自动发现模块 + 中英日志切换。基于 **BeamMP-Server v3.x**（Lua 5.3）开发。

> 说明：英文版见 [README.en.md](README.en.md)。

## 功能特性

- **模块化架构**：`main.lua` 作为主加载器，每个功能一个独立文件，可在配置文件中单独开关
- **自动发现模块**：模块列表自动从 `config.toml` 读取，新增功能无需修改任何代码
- **中英日志切换**：`[General] language` 可设置 `zh` 或 `en`，插件控制台日志只输出所选语言
- **服务器信息日志（loginfo）**：启动时输出服务器启动时间、服务器版本、服务器地图，每项可单独开关

## 目录结构

```
Resources/Server/BeamMP-SXMY_Plugin/
├── main.lua              # 主加载器：读取配置并按开关加载模块
├── config.toml          # 配置文件：语言与各功能开关
├── README.md            # 中文说明（本文件）
├── README.en.md         # 英文说明
└── modules/             # 功能模块目录（子文件夹，不会被自动加载，由 main.lua require 加载）
    ├── lib.lua          # 共享配置解析库（配置解析、语言切换、模块发现）
    └── loginfo.lua      # 服务器信息日志功能
```

## 安装方法

1. 将 `BeamMP-SXMY_Plugin` 文件夹复制到服务器的 `Resources/Server/` 目录下
2. （可选）修改 `config.toml` 中的语言与功能开关
3. 启动/重启服务器，控制台会打印插件加载状态，示例输出如下（`[LUA]` 为 BeamMP 自带前缀）：

```
[时间] [LUA] [SXMY_Plugin] 插件加载完成
[时间] [LUA] [SXMY_Plugin] 已加载1/1个功能
[时间] [LUA] [SXMY_Plugin] 已加载的功能：
[时间] [LUA] [SXMY_Plugin] 1. loginfo
[时间] [LUA] [SXMY_Loginfo] 服务器启动时间: 2026.08.18-14.30.00
[时间] [LUA] [SXMY_Loginfo] 服务器版本: 3.9.3
[时间] [LUA] [SXMY_Loginfo] 服务器地图: gridmap
```

（`已加载X/Y个功能`：X 为成功加载数，Y 为配置中启用的模块数；loginfo 在 main 汇总之后通过 `onInit` 事件输出）

## 配置说明

配置文件位于 `Resources/Server/BeamMP-SXMY_Plugin/config.toml`，修改后**需重启服务器**生效。

```toml
# 插件语言
[General]
language = "zh"   # "zh" 中文日志，"en" 英文日志

# 服务器信息日志
[loginfo]
enable = true          # 功能开关
startTime = true       # 显示服务器启动时间
serverVersion = true   # 显示服务器版本
serverMap = true       # 显示服务器地图
```

| 配置项 | 说明 |
|---|---|
| `[General].language` | 插件日志语言：`"zh"` 中文，`"en"` 英文 |
| `[loginfo].enable` | 启用/禁用 loginfo 功能 |
| `[loginfo].startTime` | 显示服务器启动时间 |
| `[loginfo].serverVersion` | 显示服务器版本 |
| `[loginfo].serverMap` | 显示服务器地图（从 `ServerConfig.toml` 获取） |

## 开发功能模块

1. 在 `modules/` 下新建 `.lua` 文件（子文件夹不会被自动加载，需 `require()`）
2. 在 `config.toml` 中添加对应节与开关：

```toml
[MyModule]
enable = true
```

（开关键支持 `enable` 与 `enabled` 两种写法）

3. 重启服务器，`main.lua` 会自动发现并加载该模块，并在启动汇总中列出

模块内可通过 `lib = require("modules.lib")` 使用配置接口（`lib.getConfig()`、`lib.enabled(节名)`、`lib.get(节, 键, 默认)`、`lib.msg(中文文本, 英文文本)`）。如需在 main 汇总之后执行逻辑，可注册 `onInit` 事件。事件处理函数建议使用 `SXMY_模块名_事件名` 前缀避免冲突。

## 常见问题

- **修改 config.toml 后不生效？** 需要重启服务器，config.toml 仅在启动时读取。
- **如何切换日志语言？** 将 `config.toml` 中 `[General] language` 改为 `"en"` 或 `"zh"` 后重启。
- **新增功能模块？** 在 `modules/` 下新建 `.lua` 文件，并在 `config.toml` 中添加对应的 `[模块名]` 节与 `enable` 开关即可。`main.lua` 会自动发现并加载所有已启用的模块，无需修改任何代码。

## 许可证

本项目仅供学习参考使用，可自由修改与分发。
