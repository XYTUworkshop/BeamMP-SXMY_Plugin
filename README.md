# BeamMP-SXMY_Plugin

BeamMP 服务器插件，为 SXMY 服务器提供模块化的插件开发基础：`main.lua` 主加载 + 自动发现模块 + 中英日志切换。基于 **BeamMP-Server v3.x**（Lua 5.3）开发。

> 说明：英文版见 [README.en.md](README.en.md)。

## 功能特性

- **模块化架构**：`main.lua` 作为主加载器，每个功能一个独立文件，可在配置文件中单独开关
- **自动发现模块**：模块列表自动从 `config.toml` 读取，新增功能无需修改任何代码
- **进服信息（WelcomeMsg）**：玩家进入服务器时私信发送配置的欢迎文本，支持任意语言，`\n` 换行分多条发送
- **身份认证（Auth）**：`/reg` 注册、`/login` 登录、`/logout` 退出，密码 PBKDF2 慢哈希存储；未登录玩家聊天不可见、不可刷车；已登录玩家不可重复注册/登录（需先 `/logout`）；密码规则（长度/大小写/特殊符号）可配置
- **管理员账号（OPAuth）**：需启用 Auth；服务器控制台 `opSXMY 昵称` 设置管理员（记录于 `opusers.txt`）；管理员可在聊天框使用映射命令（默认 `/list`、`/reload`、`/op`），执行结果私信返回；非管理员使用提示「权限不足」
  OPAuth: requires Auth; the server console command `opSXMY nickname` grants admin (stored in `opusers.txt`); admins can use the mapped chat commands (default `/op`, `/opSXMY`) with private-message results; non-admins get "Permission denied"
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
├── OPAuth.lua       # 管理员账号功能（需启用 Auth）
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
[时间] [LUA] [SXMY_WelcomeMsg] Welcome to SXMY
[时间] [LUA] [SXMY_WelcomeMsg] Enjoy :D
```

（`已加载X/Y个功能`：X 为成功加载数，Y 为配置中启用的模块数；`showtest` 启动测试文本仅输出一次）

## 配置说明

配置文件位于 `Resources/Server/BeamMP-SXMY_Plugin/config.toml`，修改后**需重启服务器**生效。

**配置自动生成（规范化）**：每个功能模块由**自己**负责生成自己的配置节——每次启动时 `config.toml` 会被**规范化**：每个节内的配置项按**固定顺序**排列（`enable` 永远在最上面，同一功能的相关项在一起）；缺失的配置项在**正确位置**插入默认值（含中英注释）；**不在模块定义中的多余配置项会被删除**（并在控制台提示）；旧版本产生的**重复节自动合并**（冲突键保留第一个值）。**删除模块文件（即不需要该功能）后，其配置项不再生成**；你修改过的**配置值**（如欢迎文本、密码规则、开关）永远不会被覆盖，且规范化只作用于各功能节，其他节与文件结构原样保留。全新安装时首次启动即自动生成完整配置。

```toml
[General]
language = "zh"    # 插件日志语言（"zh" 中文，"en" 英文） / Plugin log language ("zh" Chinese, "en" English)

[Auth]
enable = true          # 身份认证功能开关 / Auth module switch
passwdlen = 8          # 密码最小长度（位）/ Minimum password length (characters)
passwdcase = false     # 是否要求大小写混合（不要求也可使用）/ Require mixed case (optional)
passwdsymbol = false   # 是否要求特殊符号（不要求也可使用）/ Require special characters (optional)
LoginMsg = "欢迎 <name> 登录服务器"  # 登录成功广播消息（/say），<name> 为玩家昵称，留空则不发送 / Login broadcast message, <name> = nickname, empty = disabled

[OPAuth]
enable = false                  # 管理员账号功能开关（需启用 Auth）/ Admin (OP) module switch (requires Auth)
command = ["op-opSXMY", "opSXMY-opSXMY"]  # 管理员聊天命令-服务端命令映射：玩家命令(带/)-服务端命令 / OP chat command -> server command mapping: playerCommand(with /)-serverCommand

[NameTag]
enable = true      # 聊天昵称功能开关（Auth 启用时自动使用登录昵称）/ Chat nickname module switch (uses the login nickname when Auth is enabled)

[WelcomeMsg]
enable = true      # 进服信息功能开关 / Welcome message module switch
delay = 12         # 发送延迟（秒），等待玩家同步完成 / Send delay (seconds), waits for the player to sync
showtest = true    # 启动时显示欢迎文本测试（在插件与 loginfo 输出后）/ Show welcome text test on startup (after plugin and loginfo output)
text = "Welcome to SXMY \nEnjoy :D"  # 进服信息文本，支持所有语言，\n 换行分多条发送 / Welcome text, any language, \n splits into multiple messages

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
| `[Auth].maxRegsPerIP` | 单个 IP 最多注册账户数（0 不限制），默认 3 |
| `[Auth].pbkdf2Iter` | PBKDF2 慢哈希迭代次数，默认 1000（越大越安全但登录越慢）|
| `[Auth].nickLength` | 昵称最大字符数（注册限制与 listSXMY 表格列宽），默认 15 |
| `[Auth].LoginMsg` | 登录成功广播消息（`/say`），`<name>` 替换为玩家昵称，留空则不发送 |
| `[OPAuth].enable` | 启用/禁用管理员账号功能（需同时启用 Auth）|
| `[OPAuth].command` | 管理员聊天命令-服务端命令映射数组：`["玩家命令-服务端命令", ...]`，玩家命令带 `/` |
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
| `/login 昵称 密码` | 登录（已登录时需先 `/logout`）|
| `/logout` | 退出登录（清除登录状态、删除全部车辆与车辆标签昵称）|
| `/n 昵称` | 设置聊天昵称（仅未启用 Auth 时） |
| `/list` | 管理员命令：私信返回在线玩家表格（映射 `listSXMY`）|
| `/reload` | 管理员命令：热重载插件（映射 `reloadSXMY`）|
| `/op 昵称` | 管理员命令：将已注册昵称设为管理员（映射 `opSXMY`）|

- OPAuth 命令仅对**已登录且被设为管理员**的玩家生效，其他人使用私信提示「权限不足」
- **不支持映射官方服务端命令**（如 `exit`）：插件无法注入服务器控制台命令，外部强杀进程不优雅
- **新增服务端命令无需修改 OPAuth**：模块提供全局 `SXMY_模块名_onConsoleInput(命令)` 函数（处理时返回非 nil），并在 `[OPAuth].command` 中添加 `"玩家命令-服务端命令"` 映射即可（示例：`SXMY_Example_onConsoleInput` 处理 `exampleSXMY`，映射 `"ex-exampleSXMY"`）

- 未登录玩家：聊天消息他人不可见，**不可刷载具**（含编辑/替换车辆）；每 5 秒私信提示注册/登录；登录失败 5 次锁定 60 秒
- 已登录玩家：`/` 开头的消息他人不可见（命令不广播）
- 账户保存于插件根目录 `users.txt`，密码为 PBKDF2 慢哈希

## 控制台命令

| 命令 | 说明 |
|---|---|
| `reloadSXMY` | 热重载插件（在服务器控制台输入）。修改插件文件后无需重启服务器即可生效；注意：重载后玩家的登录状态会重置，需重新登录 |
| `listSXMY` | 输出在线玩家表格：昵称 / 玩家名 / 车辆数 / PID（列宽由 `[Auth].nickLength` 决定） |
| `opSXMY 昵称` | 将已注册昵称设为管理员（记录于 `opusers.txt`，需启用 OPAuth）|

## 安全注意事项

- 密码通过聊天输入，`ServerConfig.toml` 中 `LogChat = true` 时服务器控制台/日志会记录聊天内容（含密码），建议仅管理员可见服务器控制台
- 密码以 **PBKDF2-HMAC-SHA256 慢哈希**存储（`pbkdf2$盐$迭代次数$哈希` 格式），迭代次数通过 `[Auth].pbkdf2Iter` 配置（默认 1000，增大可显著提高破解成本但登录变慢）；旧版加盐/无盐 SHA-256 账户首次登录成功后**自动透明升级**为慢哈希
- 已内置登录失败锁定（连续 5 次/锁定 60 秒），优先按玩家 IP 追踪，重连更换服务器 ID 无法绕过
- 昵称仅允许字母、数字、下划线，防止破坏账户文件格式

## 常见问题

- **修改 config.toml 后不生效？** 需要重启服务器，config.toml 仅在启动时读取。
- **如何切换日志语言？** 将 `config.toml` 中 `[General] language` 改为 `"en"` 或 `"zh"` 后重启。
- **新增功能模块？** 在 `modules/` 下新建 `.lua` 文件，并在 `config.toml` 中添加对应的 `[模块名]` 节与 `enable` 开关即可。`main.lua` 会自动发现并加载所有已启用的模块，无需修改任何代码。

## 许可证

本项目使用 GPL-3.0 许可证，仅供学习参考使用，可自由修改与分发。
