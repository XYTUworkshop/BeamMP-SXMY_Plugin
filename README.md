# BeamMP-SXMY_Plugin

BeamMP 服务器插件，为 SXMY 服务器提供模块化的插件开发基础：`main.lua` 主加载 + 自动发现模块 + 中英日志切换。基于 **BeamMP-Server v3.x**（Lua 5.3）开发。

> 说明：英文版见 [README.en.md](README.en.md)。

## 功能特性

- **模块化架构**：`main.lua` 作为主加载器，每个功能一个独立文件，可在配置文件中单独开关
- **自动发现模块**：模块列表自动从 `config.toml` 读取，新增功能无需修改任何代码
- **进服信息（WelcomeMsg）**：玩家进入服务器时私信发送配置的欢迎文本，支持任意语言，`\n` 换行分多条发送
- **身份认证（Auth）**：`/reg` 注册、`/login` 登录，密码 SHA-256 哈希存储；未登录玩家聊天不可见、不可刷车；密码规则（长度/大小写/特殊符号）可配置
- **聊天昵称（NameTag）**：未启用 Auth 时玩家用 `/n 名字` 设置聊天昵称，消息带 `[昵称]` 前缀；启用 Auth 时自动使用登录账号昵称
- **车辆标签（VehicleTag）**：玩家登录或设置 `/n` 昵称后，其所有车辆上方（含玩家自己的车）显示昵称标签，并隐藏 BeamMP 官方标签；需要随服务器下发的 `SXMYVehicleTag` 客户端 mod
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
    ├── Auth.lua         # 身份认证功能（注册/登录/拦截）
    ├── NameTag.lua      # 聊天昵称功能
    ├── VehicleTag.lua   # 车辆标签功能（需客户端 mod）
    ├── WelcomeMsg.lua   # 进服信息功能
    └── loginfo.lua      # 服务器信息日志功能
```

## 安装方法

1. 解压发布包 `BeamMP-SXMY_Plugin.zip`，将其中 `server` 与 `client` 两个文件夹解压进 BeamMP 服务器的 `Resources` 文件夹：
   - `server` → `Resources/Server`（内含插件文件夹 `BeamMP-SXMY_Plugin`）
   - `client` → `Resources/Client`（内含车辆标签客户端 mod `SXMY-client.zip`，玩家进服时自动下载）
2. （可选）修改 `Resources/Server/BeamMP-SXMY_Plugin/config.toml` 中的语言与功能开关
3. 启动/重启服务器，控制台会打印插件加载状态，示例输出如下（`[LUA]` 为 BeamMP 自带前缀）：

```
[时间] [LUA] [SXMY_Plugin] 插件加载完成
[时间] [LUA] [SXMY_Plugin] 已加载2/2个功能
[时间] [LUA] [SXMY_Plugin] 已加载的功能：
[时间] [LUA] [SXMY_Plugin] 1. WelcomeMsg
[时间] [LUA] [SXMY_Plugin] 2. loginfo
[时间] [LUA] [SXMY_Loginfo] 服务器启动时间: 2026.08.18-14.30.00
[时间] [LUA] [SXMY_Loginfo] 服务器版本: 3.9.3
[时间] [LUA] [SXMY_Loginfo] 服务器地图: gridmap
[时间] [LUA] [SXMY_WelcomeMsg] 欢迎文本：
[时间] [LUA] [SXMY_WelcomeMsg] 欢迎来到SXMY
```

（`已加载X/Y个功能`：X 为成功加载数，Y 为配置中启用的模块数；`showtest` 启动测试文本仅输出一次）

## 配置说明

配置文件位于 `Resources/Server/BeamMP-SXMY_Plugin/config.toml`，修改后**需重启服务器**生效。

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

| 配置项 | 说明 |
|---|---|
| `[General].language` | 插件日志语言：`"zh"` 中文，`"en"` 英文 |
| `[Auth].enable` | 启用/禁用身份认证功能 |
| `[Auth].passwdlen` | 密码最小长度（位），默认 8 |
| `[Auth].passwdcase` | 是否要求密码同时包含大小写字母 |
| `[Auth].passwdsymbol` | 是否要求密码包含特殊符号 |
| `[Auth].LoginMsg` | 登录成功广播消息（`/say`），`<name>` 替换为玩家昵称，留空则不发送 |
| `[NameTag].enable` | 启用/禁用聊天昵称功能 |
| `[VehicleTag].enable` | 启用/禁用车辆标签功能（需 `Resources/Client/SXMYVehicleTag.zip`） |
| `[WelcomeMsg].enable` | 启用/禁用进服信息功能 |
| `[WelcomeMsg].delay` | 发送延迟（秒），等待玩家同步完成，默认 12 |
| `[WelcomeMsg].showtest` | 启动时显示欢迎文本测试（在插件与 loginfo 输出后） |
| `[WelcomeMsg].text` | 进服信息文本，支持所有语言，`\n` 换行分多条发送 |
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

## 命令说明（Auth）

在游戏内聊天框输入：

| 命令 | 说明 |
|---|---|
| `/reg 昵称 密码 确认密码` | 注册并登录 |
| `/login 昵称 密码` | 登录 |
| `/n 昵称` | 设置聊天昵称（仅未启用 Auth 时） |

- 未登录玩家：聊天消息他人不可见，**不可刷载具**（含编辑/替换车辆）；每 5 秒私信提示注册/登录；登录失败 5 次锁定 60 秒
- 已登录玩家：`/` 开头的消息他人不可见（命令不广播）
- 账户保存于插件根目录 `users.txt`，密码为 SHA-256 哈希

## 安全注意事项

- 密码通过聊天输入，`ServerConfig.toml` 中 `LogChat = true` 时服务器控制台/日志会记录聊天内容（含密码），建议仅管理员可见服务器控制台
- 密码以加盐 SHA-256 存储（`盐$哈希` 格式），兼容旧版无盐账户；生产环境仍建议升级为慢哈希（如 bcrypt）
- 已内置登录失败锁定（连续 5 次/锁定 60 秒），优先按玩家 IP 追踪，重连更换服务器 ID 无法绕过
- 昵称仅允许字母、数字、下划线，防止破坏账户文件格式

## 常见问题

- **修改 config.toml 后不生效？** 需要重启服务器，config.toml 仅在启动时读取。
- **如何切换日志语言？** 将 `config.toml` 中 `[General] language` 改为 `"en"` 或 `"zh"` 后重启。
- **新增功能模块？** 在 `modules/` 下新建 `.lua` 文件，并在 `config.toml` 中添加对应的 `[模块名]` 节与 `enable` 开关即可。`main.lua` 会自动发现并加载所有已启用的模块，无需修改任何代码。

## 许可证

本项目仅供学习参考使用，可自由修改与分发。
