# SXMY_Plugin

BeamMP 服务器插件，基于 Lua 开发。

## 当前版本

**2.0.0.2609011529_Alpha**

## 目录结构

```
Resources/
├── README.MD       本说明文件
├── LICENSE         GPL-3.0 许可证文本
├── Client/         客户端资源
└── Server/
    └── SXMY_Plugin/  插件本体
        ├── main.lua        入口：配置生成 / 插件加载 / 配置查询 / 插件载入
        ├── config.toml     主配置（见下文"配置文件"）
        ├── Language/       语言文件（zh.json / en.json）
        └── lib/            功能模块（01.WelcomeMsg ~ 11.VoteKick）
```

## 配置文件（config.toml）

主配置位于 `Resources/Server/SXMY_Plugin/config.toml`，首次启动或文件为空时自动生成默认内容。修改后可通过命令热重载（见下文"命令用法"）。

```toml
# 服务器全局语言
[general]
Language = "zh"          # zh / en，切换插件输出语言

# 进服欢迎信息
[WelcomeMsg]
enable = true            # 插件开关：true 启用 / false 禁用
delay = 5                # 玩家同步完成(now synced!)后延迟多少秒发送欢迎信息（≥0）
text = "Welcome to SXMY server<\n>Enjoy"   # 欢迎文本，<\n> 为换行标记（实际为分多句发送）

# 数据库（文件/数据库双模式）
[DataBase]
enable = false            # 模块开关：true 启用 / false 禁用
address = "127.0.0.1:3306" # 数据库地址：域名/ipv4:端口
BaseName = ""             # 数据库名
BaseUser = ""             # 数据用户名（空则默认 root）
Basepwd = ""              # 数据库密码
```

## 功能

### WelcomeMsg —— 进服欢迎

玩家进服（`xxx is now synced!`，此时玩家可见聊天框）后，按 `delay` 秒延迟向该玩家私信发送 `text` 中的欢迎文本：

- `text` 中的 `<\n>` 为换行标记，发送时会被拆分为多条私信依次发送
- 设置 `text` 时必须使用引号包裹：`SXMY Config WelcomeMsg-text "文本内容" y`
- 插件启动时会报告该功能状态，例如：

```
[SXMY] 功能 WelcomeMsg 已启用
[SXMY] 延迟 5s 进服文本: "Welcome to SXMY server<\n>Enjoy"
```

## 命令用法

所有命令大小写不敏感（`SXMY` / `sxmy` / `SxMy` 均可触发）。

### SXMY —— 显示帮助

```
> SXMY
[SXMY]命令    用法
[SXMY]Reload  用于热重载插件的各个配置
[SXMY]Config  用于切换各项配置并热重载
```

### SXMY DB —— 查询数据库实时状态

```
> SXMY DB                # 查询数据库连接状态（实时检查）
[SXMY] 数据库状态：未启用              # enable=false 时
[SXMY] 数据库状态：已连接              # enable=true 且连接成功
[SXMY] 数据库地址：127.0.0.1:3306
[SXMY] 数据库名称：mydb
[SXMY] 数据库状态：断开连接            # enable=true 但连接失败
```

### SXMY Reload —— 热重载功能

```
> SXMY Reload            # 重载所有功能
> SXMY Reload <功能名>    # 重载指定功能（如 main、WelcomeMsg）
> SXMY Reload help       # 查看可用功能列表
```

### SXMY Config —— 切换配置项并热重载

```
> SXMY Config <配置项> <配置值> <y(热重载)/n(不重载)>   # y 为默认
> SXMY Config                                        # 查看配置项列表与用法
```

可用配置项：

| 配置项 | 值 | 用法 |
|---|---|---|
| `main-Language` | zh / en | `SXMY Config main-Language <zh/en> <y/n>` |
| `WelcomeMsg-enable` | true / false | `SXMY Config WelcomeMsg-enable <true(启用)/false(禁用)> <y/n>` |
| `WelcomeMsg-delay` | ≥0 的数字 | `SXMY Config WelcomeMsg-delay <x> <y/n>` |
| `WelcomeMsg-text` | 任意文本 | `SXMY Config WelcomeMsg-text "<text>" <y/n>` |

示例：

```
> SXMY Config main-Language en y          # 切换为英文并热重载
> SXMY Config WelcomeMsg-delay 3 y        # 欢迎延迟 3 秒
> SXMY Config WelcomeMsg-text "欢迎光临" y # 修改欢迎文本
```

## 许可证

本项目使用 **GPL-3.0 许可证**，仅供学习参考使用，可自由修改与分发。

完整许可证文本见 [LICENSE](./LICENSE)。
