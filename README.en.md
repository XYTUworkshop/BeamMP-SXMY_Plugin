# BeamMP-SXMY_Plugin v1.0.0

A modular server plugin for the SXMY server: `main.lua` main loader + auto-discovered modules + Chinese/English log switching. Built for **BeamMP-Server v3.x** (Lua 5.3).

> Note: The Chinese version is at [README.md](README.md).

## Features

- **Modular architecture**: `main.lua` acts as the main loader, each feature lives in its own file and can be toggled in the config file.
- **Auto-discovered modules**: the module list is scanned from the `modules/` folder, no code changes needed to add features; each module generates its own config section (enabled by default when no config key exists).
- **Welcome message (WelcomeMsg)**: sends the configured welcome text to a player on join via private message, supports any language, `\n` splits into multiple messages.
- **Auth**: `/reg` register, `/login` log in, `/logout` log out, PBKDF2 slow-hash password storage; unauthenticated players cannot chat or spawn vehicles; logged-in players cannot re-register/log in again (must `/logout` first); password rules configurable.
- **Admin accounts (OPAuth)**: requires Auth; the server console command `opSXMY nickname` grants admin; admins can use the mapped chat commands (default `/reload`, `/list`, `/op`, `/kick`, `/ban`, `/banip`, `/unban`) with private-message results; non-admins get "Permission denied".
- **Player bans (PlayerBan)**: requires Auth; `banSXMY nickname duration reason` bans the login permission, `banipSXMY nickname duration reason` bans the current IP; banned players are kicked on register/login (with remaining time + reason) and their registration is not saved; records stored in `banusers.txt`.
- **Chat nicknames (NameTag)**: without Auth, players set a chat nickname with `/n name` and messages get a `[nickname]` prefix; with Auth, the logged-in account nickname is used automatically.
- **Vehicle tags (VehicleTag)**: after login or setting a `/n` nickname, the nickname tag is drawn above all of the player's vehicles (including their own cars) and the BeamMP official tags are hidden; requires the `SXMY-client` client mod.
- **Chinese/English log switching**: set `[General] language` to `zh` or `en`, the plugin console logs output only the selected language.
- **Player kick (PlayerKick)**: the server console command `kickSXMY nickname reason` kicks an online player by their Auth login nickname; admins can use the mapped `/kick nickname reason` (default mapping) with private-message results.
- **Server info log (loginfo)**: outputs server start time, server version and server map on startup, each line can be toggled separately.
- **Votekick**: requires Auth; players start a vote with `/votekick nickname` (also `/votokick`), `/vote t` agrees and `/vote f` disagrees; when agree / logged-in-at-start ≥ the configured percentage, PlayerKick kicks the player and the result is broadcast; initiator cooldown and vote timeout supported.
- **Database storage (Database)**: requires Auth; syncs `users.txt` / `opusers.txt` / `banusers.txt` to the database (local files are removed only on success) and then Auth / OPAuth / PlayerBan read/write the database directly; the database client is bundled (`database/dbclient.py`) and the protocol is open for any language.

## Directory Structure

```
Resources/Server/BeamMP-SXMY_Plugin/
├── main.lua             # Main loader: reads config and loads modules by switch
├── config.toml          # Config file: language and feature switches
├── README.md            # Chinese README
├── README.en.md         # English README (this file)
├── database/            # Database client directory (self-made, see "Database Client Protocol")
│   ├── dbclient.py      # Bundled MySQL client (pure Python stdlib)
│   ├── dbclient.bat     # Windows root wrapper
│   ├── win/dbclient.bat # Windows wrapper (calls python)
│   └── linux/dbclient   # Linux wrapper (calls python3)
└── modules/             # Module directory (subfolder, not auto-loaded; loaded via require in main.lua)
    ├── lib.lua          # Shared config library (parsing, language, discovery)
    ├── Auth.lua         # Auth feature (register/login/blocking)
    ├── OPAuth.lua       # Admin (OP) feature (requires Auth)
    ├── PlayerBan.lua    # Player ban feature (requires Auth)
    ├── PlayerKick.lua   # Player kick feature (requires Auth)
    ├── Votekick.lua     # Votekick feature (requires Auth)
    ├── database.lua     # Database sync feature (requires Auth)
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
[time] [LUA] [SXMY_Plugin] Loaded 10/10 features
[time] [LUA] [SXMY_Plugin] Loaded features:
[time] [LUA] [SXMY_Plugin] 1. Auth
[time] [LUA] [SXMY_Plugin] 2. loginfo
[time] [LUA] [SXMY_Plugin] 3. NameTag
[time] [LUA] [SXMY_Plugin] 4. OPAuth
[time] [LUA] [SXMY_Plugin] 5. PlayerKick
[time] [LUA] [SXMY_Plugin] 6. PlayerBan
[time] [LUA] [SXMY_Plugin] 7. Votekick
[time] [LUA] [SXMY_Plugin] 8. database
[time] [LUA] [SXMY_Plugin] 9. VehicleTag
[time] [LUA] [SXMY_Plugin] 10. WelcomeMsg
[time] [LUA] [SXMY_Loginfo] Server start time: 2026.08.18-14.30.00
[time] [LUA] [SXMY_Loginfo] Server version: 3.9.3
[time] [LUA] [SXMY_Loginfo] Server map: gridmap
[time] [LUA] [SXMY_WelcomeMsg] Welcome Text :
[time] [LUA] [SXMY_WelcomeMsg] Welcome to SXMY
[time] [LUA] [SXMY_WelcomeMsg] Enjoy :D
```

(Example only; the actual module load order may differ slightly)

(`Loaded X/Y features`: X = enabled and loaded modules, Y = total module files in `modules/`; the `showtest` startup test text prints only once)

## Configuration

The config file is at `Resources/Server/BeamMP-SXMY_Plugin/config.toml`; a **server restart** is required after changes.

**Auto-generated config (normalized)**: each feature module generates its **own** config section — on every start `config.toml` is **normalized**: keys inside each section are kept in a **fixed order** (`enable` always first, related options grouped together); missing keys are inserted **at their correct position** with defaults (and zh/en comments); **extra keys not defined by a module are removed** (a console hint is printed); duplicate sections from earlier versions are **merged automatically** (a conflicting key keeps its first value). **Removing a module file (i.e. dropping that feature) stops its config section from being generated**; the **values** you changed (e.g. welcome text, password rules, toggles) are never overwritten, and normalization only touches each module's own section — other sections and file structure stay untouched. A fresh install auto-generates the full config on first start.

```toml
[General]
language = "zh"    # Plugin log language ("zh" Chinese, "en" English)

[DATABASE]
enable = false       # Database sync module switch (requires Auth, off by default)
dbaddr = "127.0.0.1:3306"  # Database address (host:port)
dbname = ""          # Database name
dbuser = ""          # Database user
dbpwd = ""           # Database password (note: it appears in the client process arguments)
users = true         # Sync users (accounts) to the database and remove users.txt
opusers = true       # Sync opusers (admins) to the database and remove opusers.txt
banusers = true      # Sync banusers (bans) to the database and remove banusers.txt

[Auth]
enable = true          # Auth module switch
passwdlen = 8          # Minimum password length (characters)
passwdcase = false     # Require mixed case (optional)
passwdsymbol = false   # Require special characters (optional)
maxRegsPerIP = 3       # Max registrations per IP (0 = unlimited)
pbkdf2Iter = 1000      # PBKDF2 slow-hash iterations (higher = safer but slower logins)
nickLength = 15        # Max nickname length (registration limit and listSXMY column width)
LoginMsg = "欢迎 <name> 登录服务器"  # Login broadcast message (/say), <name> = nickname, empty = disabled

[loginfo]
enable = true          # Server info log module switch
startTime = true       # Show server start time
serverVersion = true   # Show server version
serverMap = true       # Show server map (read from ServerConfig.toml)

[NameTag]
enable = true      # Chat nickname module switch (uses the login nickname when Auth is enabled)

[OPAuth]
enable = false                  # Admin (OP) module switch (requires Auth)
command = ["reload-reloadSXMY", "list-listSXMY", "op-opSXMY", "ban-banSXMY", "banip-banipSXMY", "unban-unbanSXMY", "kick-kickSXMY"]  # OP chat command -> server command mapping: playerCommand(with /)-serverCommand

[PlayerKick]
enable = true  # Player kick module switch (kickSXMY command)

[PlayerBan]
enable = true      # Player ban module switch (requires Auth)

[Votekick]
enable = true  # Votekick module switch (requires Auth)
timeout = 60  # Vote timeout (seconds)
cooldown = 120  # Cooldown after starting a vote (seconds)
percentage = 60  # Vote percentage (agree / logged-in >= this value kicks the player)

[VehicleTag]
enable = true      # Vehicle tag module switch (requires the SXMY-client client mod)

[WelcomeMsg]
enable = true      # Welcome message module switch
delay = 12         # Send delay (seconds), waits for the player to sync
showtest = true    # Show welcome text test on startup (after plugin and loginfo output)
text = "Welcome to SXMY \nEnjoy :D"  # Welcome text, any language, \n splits into multiple messages
```

(The real `config.toml` is generated with bilingual zh/en comments; only the comment language differs from this English example — the keys and values are identical.)

| Key | Description |
|---|---|
| `[General].language` | Plugin log language: `"zh"` Chinese, `"en"` English |
| `[Auth].enable` | Enable/disable the auth feature |
| `[Auth].passwdlen` | Minimum password length (characters), default 8 |
| `[Auth].passwdcase` | Require both uppercase and lowercase letters in the password |
| `[Auth].passwdsymbol` | Require a special character in the password |
| `[Auth].maxRegsPerIP` | Max registrations per IP (0 = unlimited), default 3 |
| `[Auth].pbkdf2Iter` | PBKDF2 slow-hash iterations, default 1000 (higher = safer but slower logins) |
| `[Auth].nickLength` | Max nickname length (registration limit and listSXMY column width), default 15 |
| `[Auth].LoginMsg` | Login broadcast message (`/say`), `<name>` replaced by the nickname, empty = disabled |
| `[OPAuth].enable` | Enable/disable the admin (OP) feature (requires Auth enabled too) |
| `[OPAuth].command` | Admin chat-command to server-command mapping array: `["playerCommand-serverCommand", ...]`, player commands use `/`; default `["reload-reloadSXMY", "list-listSXMY", "op-opSXMY", "ban-banSXMY", "banip-banipSXMY", "unban-unbanSXMY", "kick-kickSXMY"]`, freely add/remove entries |
| `[PlayerKick].enable` | Player kick module switch (the `kickSXMY` command, requires Auth) |
| `[PlayerBan].enable` | Player ban module switch (requires Auth) |
| `[Votekick].enable` | Votekick module switch (requires Auth) |
| `[Votekick].timeout` | Vote timeout (seconds), default 60 |
| `[Votekick].cooldown` | Cooldown after starting a vote (seconds), default 120 |
| `[Votekick].percentage` | Vote percentage (agree / logged-in ≥ this value kicks), default 60 |
| `[NameTag].enable` | Enable/disable the chat nickname feature |
| `[VehicleTag].enable` | Enable/disable the vehicle tag feature (requires `Resources/Client/SXMY-client.zip`) |
| `[WelcomeMsg].enable` | Enable/disable the welcome message feature |
| `[WelcomeMsg].delay` | Send delay in seconds, waits for the player to sync, default 12 |
| `[WelcomeMsg].showtest` | Show the welcome text test on startup (after plugin and loginfo output) |
| `[WelcomeMsg].text` | Welcome text, any language, `\n` splits into multiple messages |
| `[DATABASE].enable` | Database sync switch (requires Auth, off by default) |
| `[DATABASE].dbaddr` | Database address (host:port), default `127.0.0.1:3306` |
| `[DATABASE].dbname` | Database name |
| `[DATABASE].dbuser` / `[DATABASE].dbpwd` | Database user / password |
| `[DATABASE].users` / `[DATABASE].opusers` / `[DATABASE].banusers` | Sync the matching local file to the database (default on) |
| `[loginfo].enable` | Enable/disable the loginfo feature |
| `[loginfo].startTime` | Show the server start time |
| `[loginfo].serverVersion` | Show the server version |
| `[loginfo].serverMap` | Show the server map (read from `ServerConfig.toml`) |

## Database Client Protocol

When `[DATABASE]` is enabled, `modules/database.lua` invokes the client executable in the `database/` folder for syncing and read/write. **The client is fully self-made** (any language) as long as it follows the protocol below; the plugin bundles `database/dbclient.py` (a pure-Python-stdlib MySQL client with no dependencies; the server needs `python`).

### Location and probing

The client is probed in this order and the first one found is used:

```
database/win/dbclient.exe|.bat|.cmd      # Windows
database/windows/dbclient.exe            # Windows
database/osx/dbclient                    # macOS
database/linux/dbclient                  # Linux
database/dbclient(.bat|.cmd|.sh)         # cross-platform fallback
```

### Command protocol

Each invocation (reconnects every time):

```
<client> --host <host> --port <port> --db <dbname> --user <user> --pass <password> <command> [args...]
```

| Command | Description |
|---|---|
| `init` | Initialize: make sure the three tables exist (may contain DDL); no output on success |
| `load <table>` | Read the whole table, print one `key = value` line per row (separated by ` = `) |
| `set <table> <key> <value>` | Upsert a row (overwrite when the key exists) |
| `del <table> <key>` | Delete a row |

### Tables and value format

`sxmy_auth` stores one account per row with separate columns (`nick` PK, `hash`, `ip`; `ip` is empty when absent); `sxmy_opusers` / `sxmy_banusers` are key-value tables (`bk` PK, `bv` value) whose value matches the local file format. The client `load` always prints `key = value` lines:

| Table | Storage | `load` output example |
|---|---|---|
| `sxmy_auth` | `nick` / `hash` / `ip` columns, one account per row | `Tangzixy = pbkdf2$salt$iter$hash regIP` |
| `sxmy_opusers` | `bk` = nickname / `bv` = `1` | `Tangzixy = 1` |
| `sxmy_banusers` | `bk` = `nick:nickname` or `ip:IP` / `bv` = `YYYYMMDDHHMM:reason` | `nick:evil = 202812310000:cheating` |

(A legacy `sxmy_auth` with the `bk`/`bv` structure is migrated automatically to `nick`/`hash`/`ip` by `init`, keeping the data.)

### Output and error conventions

- Success: `init`/`set`/`del` print `OK` (the Lua side treats "non-empty and not ERROR" as success; an empty output means a client failure and is treated as a failure); `load` prints `key = value` lines
- Failure: print one line starting with `ERROR:` on stdout (e.g. `ERROR: MySQL error 1045: ...`), exit code non-zero
- `database.lua` treats output starting with `ERROR:` or `ERROR ` as failure (a nickname row like `ERRORxxx = ...` is not misjudged); **a failed `set` during sync keeps the local file** (it is not removed)

### Key/value safe characters

- Keys (nicknames/IPs/prefixed keys) allow only letters, digits, underscore, dot, colon and hyphen
- Values (e.g. ban reasons) must **not** contain `" & | < > ^ % ( )` (these can be parsed by Windows cmd as command injection; writes containing them are rejected and the local file is kept)

### Security notes

- The database password appears in the client process command line (visible in the process list); restrict local access to the server
- `config.toml` holds the database credentials in plain text: do not commit it to a public repository, restrict its file permissions (readable only by the server account), and use a dedicated low-privilege database account for the plugin (only `SELECT/INSERT/UPDATE/DELETE` on the needed tables)
- The client is responsible for SQL-injection protection (the bundled `dbclient.py` escapes keys/values)
- The key/value safe-character limits above apply (values must not contain `" & | < > ^ % ( )`; writes containing them are rejected and the local file is kept)

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

## Auth Commands

Type in the in-game chat:

| Command | Description |
|---|---|
| `/reg nickname password confirmpassword` | Register and log in |
| `/login nickname password` | Log in (`/logout` first if already logged in) |
| `/logout` | Log out (clears the login state, despawns all vehicles and clears the vehicle-tag nickname) |
| `/n nickname` | Set the chat nickname (only when Auth is disabled) |
| `/votekick nickname` | Start a vote to kick the player (also `/votokick`; must be logged in, target must be logged in and online; private hints on cooldown/ongoing vote) |
| `/vote t` | Agree with the current vote (one vote per account, no repeats); the current status is broadcast after each vote: `xxx voted. Current votes X/Y, agree rate Z%` |
| `/vote f` | Disagree with the current vote (not counted as agree) |
| `/op nickname` | OP command: grant admin to a registered nickname (maps to `opSXMY`, **default mapping**) |
| `/ban nickname duration reason` | OP command: ban the login permission of a nickname (maps to `banSXMY`, **default mapping**) |
| `/banip nickname duration reason` | OP command: ban the current IP of a nickname (maps to `banipSXMY`, **default mapping**) |
| `/unban nickname` or `/unban ip IP` | OP command: lift a ban (maps to `unbanSXMY`, **default mapping**) |
| `/kick nickname reason` | OP command: kick an online player by their Auth nickname (maps to `kickSXMY`, **default mapping**) |
| `/list` | OP command: private-message the online-player table (maps to `listSXMY`, **default mapping**) |
| `/reload` | OP command: hot-reload the plugin (maps to `reloadSXMY`, **default mapping**) |

- Ban duration format: `<amount><unit>`, `m` minute, `h` hour, `d` day, `M` month (30 days, uppercase to distinguish from minutes), `y` year (365 days); e.g. `100m` (1 h 40 min), `5d`.
- Banned players are kicked on **register or login** with "You are banned from this server / Remaining: Xd Xh Xm / Reason: ..."; every account on a `banip`-banned IP (including new registrations) is kicked, and the registration is not saved.
- Ban records are stored in `banusers.txt` next to `users.txt`, one line per record: `IP/nick unbanTime(YYYYMMDDHHMM) reason`, e.g. `nick:Tangzixy 202608091123 speeding`, `ip:1.2.3.4 202608091123`. The file is re-read on every server start; on login/register, players whose unban time has not been reached yet are kicked with the remaining time shown. The legacy timestamp format (`nick:xx = 1787000000:reason`) is still read automatically.
- OPAuth commands only work for players who are **logged in and granted admin**; anyone else gets a private "Permission denied" message.
- **Mapping to official server commands (e.g. `exit`) is not supported**: there is no API to inject server console input, and hard-killing the process is not graceful.
- **New server commands need no OPAuth changes**: a module exposes a global `SXMY_ModuleName_onConsoleInput(command)` function (returning non-nil when handled), then just add a `"playerCommand-serverCommand"` entry to `[OPAuth].command` (e.g. `SXMY_Example_onConsoleInput` handles `exampleSXMY`, mapped as `"ex-exampleSXMY"`).

- Votekick: fast re-initiation within the cooldown shows "You are starting votes too quickly"; an ongoing vote blocks new ones ("A vote is already in progress"); a passed vote kicks by Auth nickname and broadcasts "nickname has been vote-kicked"; a timeout broadcasts "The vote has timed out"; the denominator is the number of logged-in players **when the vote started**, and **both the cooldown and the votes are keyed by the Auth nickname (account)**: one vote per account, reconnecting with a new pid cannot vote twice or bypass the cooldown, and different accounts behind the same IP stay independent.
- Unauthenticated players: chat hidden from others, **cannot spawn vehicles** (including editing/replacing); prompted to register/log in every 5 seconds; locked for 60 seconds after 5 failed logins.
- Logged in: messages starting with `/` are hidden from others (commands are not broadcast).
- Accounts stored in `users.txt`, passwords as PBKDF2 slow hashes.

## Console Commands

| Command | Description |
|---|---|
| `reloadSXMY` | Hot-reload the plugin (type in the server console). Apply plugin file changes without restarting the server; note: players' login states are reset on reload and they must log in again. |
| `listSXMY` | Print the online-player table: nickname / player name / car count / PID (column width driven by `[Auth].nickLength`) |
| `banSXMY nickname duration reason` | Ban the login permission of a nickname (`banusers.txt`, requires PlayerBan) |
| `banipSXMY nickname duration reason` | Ban the current IP of a nickname (requires PlayerBan) |
| `unbanSXMY nickname` / `unbanSXMY ip IP` | Lift a nickname or IP ban (requires PlayerBan) |
| `kickSXMY nickname reason` | Kick an online player by their Auth nickname (exact match, accounts are case-sensitive; reason optional) |
| `opSXMY nickname` | Grant admin to a registered nickname (stored in `opusers.txt`, requires OPAuth) |

## Security Notes

- Passwords are typed in chat; with `LogChat = true` the server console/log records chat (including passwords) — keep the console admin-only.
- Passwords stored as **PBKDF2-HMAC-SHA256 slow hashes** (`pbkdf2$salt$iter$hash`); the iteration count is set via `[Auth].pbkdf2Iter` (default 1000 — higher is much harder to crack but logins get slower). Legacy salted/unsalted SHA-256 accounts are **transparently upgraded** to the slow hash after their first successful login.
- Built-in brute-force protection: lockout after 5 consecutive failed logins (60 seconds), tracked by player IP when available, not bypassable by reconnecting with a new server ID.
- Nicknames are limited to letters, digits and underscores to keep the accounts file format safe.

## FAQ

- **Changes to config.toml not applying?** Restart the server; the config is only read at startup.
- **How to switch the log language?** Set `[General] language` in `config.toml` to `"en"` or `"zh"` and restart.
- **Adding a new feature module?** Just create a `.lua` file under `modules/` (no `config.toml` change needed — a module with no config key is enabled by default and generates its own section); to disable it, set `enable = false` in its section and restart.

## License

This project uses the GPL-3.0 license, for learning and reference purposes only; free to modify and redistribute.
