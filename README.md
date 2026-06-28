# minecraft-plugin-ai

Ecosystem ของ **Minecraft plugin หลายตัวที่ทำงานร่วมกัน** บน **Paper/Spigot (Bukkit API) เวอร์ชัน 26.2** — ทุก plugin แชร์ database และระบบตั้งค่าผ่านเว็บ (web-config) ตัวเดียวกัน เป็น **multi-module Gradle project** ที่รวมแต่ละ plugin เป็น git submodule

> repo นี้คือ **root/umbrella repo** ที่ถือ Gradle build ส่วนกลาง + submodule ของแต่ละ plugin — รายละเอียด convention/architecture เต็ม ๆ อยู่ใน [CLAUDE.md](CLAUDE.md), รายละเอียดเฉพาะแต่ละ plugin อยู่ใน `README.md` ของ module นั้น ๆ

## Modules

| Module (Gradle) | ชื่อใน `/pl` | หน้าที่ | DB? |
|-----------------|-------------|---------|-----|
| [`minecraft-plugin-core`](minecraft-plugin-core/) | `Core` | shared API/library — HikariCP pool เดียว, web-config client, service API, per-player settings (`SettingsRegistry` + `PlayerPreferenceService`), `EcosystemData`, `PluginLog` (load เป็น plugin แยกบน server) | เป็นเจ้าของ pool |
| [`minecraft-plugin-money`](minecraft-plugin-money/) | `Money` | เศรษฐกิจ/สกุลเงิน — balance, pay, คำสั่งแอดมิน | ใช้ central DB |
| [`minecraft-plugin-healthbar`](minecraft-plugin-healthbar/) | `Healthbar` | หลอดเลือดลอยเหนือหัว entity เมื่อโดนผู้เล่นตี | ไม่แตะ DB |
| [`minecraft-plugin-menu`](minecraft-plugin-menu/) | `Menu` | UI เมนูต่อผู้เล่น (`/menu`) — render per-player setting ที่ plugin อื่น register ไว้ผ่าน Paper Dialog API แล้วเขียนค่ากลับผ่าน `PlayerPreferenceService` | ไม่มี state เอง |

> feature plugin ทุกตัว `compileOnly(project(":minecraft-plugin-core"))` + `depend: [Core]` ใน `plugin.yml` แล้วคุยกับ core ตอน runtime ผ่าน Bukkit `ServicesManager` (ตัวช่วย `com.mrfermz.mcplugins.core.CoreApi`) — ห้าม plugin reference class ภายในของอีก plugin ตรง ๆ

## Target platform

- **Server**: Paper (หรือ fork ที่ compatible) `26.2` — Paper API `io.papermc.paper:paper-api:26.2.build.34-alpha`
- **Java**: **25** (Paper API 26.2 ต้องการ JVM 25+; bytecode 25 รันบน server ที่ใช้ Java 26 ได้) — toolchain auto-provision ผ่าน foojay-resolver
- **Build**: Gradle (Kotlin DSL) ผ่าน wrapper ที่ commit ไว้ — ไม่ต้องลง Gradle เอง

## Getting started

repo นี้ใช้ git submodule สำหรับแต่ละ plugin — clone พร้อม submodule:

```bash
git clone --recurse-submodules https://github.com/MrFermz/minecraft-plugin-ai.git
# ถ้า clone มาแล้วแต่ submodule ว่าง:
git submodule update --init --recursive
```

## Build

```bash
./gradlew build                              # build ทั้ง ecosystem
./gradlew :minecraft-plugin-money:build      # build plugin เดียว
```

- deployable jar ของทุก module ถูกรวมไว้ที่ root **`/jar`** เดียวหลัง build → `jar/minecraft-plugin-core.jar`, `jar/minecraft-plugin-money.jar`, ฯลฯ (jar ผ่าน shadow/relocate; `/jar` ถูก gitignore เพราะเป็น build artifact)
- **build จบที่ `/jar` เท่านั้น** — การเอา jar ไปวางบน server เป็นขั้นตอนที่ทำเอง ไม่มี task copy ไป server อัตโนมัติ และ **ไม่ต้องสตาร์ท server เพื่อทดสอบ**

## Config / data บน server

ทั้ง ecosystem แชร์โฟลเดอร์เดียวคือ **`plugins/antitle/`** (ไม่กระจายเป็น `plugins/<PluginName>/` ต่อ plugin) — แต่ละ plugin มีไฟล์ config แบน `<module>.yml`:

```
plugins/antitle/
├── config.yml        # global: DB pool + web-config client (core เป็นเจ้าของ)
├── database.db       # central SQLite (ถ้า database.type = sqlite)
├── money.yml         # config ของ money
└── healthbar.yml     # config ของ healthbar
```

resolve path ผ่าน `EcosystemData` ของ core (เพราะ Bukkit `getDataFolder()` เป็น `final` override ไม่ได้) — feature plugin **ห้ามเรียก `getDataFolder()`/`getConfig()`/`saveDefaultConfig()` ตรง ๆ**

## Database

`minecraft-plugin-core` เป็นเจ้าของ HikariCP pool เดียว register เป็น `DatabaseService` เลือก engine ผ่าน `database.type` ใน global `config.yml`:

- `sqlite` (default, embedded, zero-config) — เหมาะ dev
- `postgresql` — **แนะนำสำหรับ production**
- `mysql` / `mariadb` (ผ่าน MariaDB driver)

เปลี่ยน engine = แก้ config อย่างเดียว โค้ด plugin ไม่ต้องแก้ (คุยผ่าน `DataSource` + `DatabaseService.dialect()`) แต่ละ plugin namespace ตารางด้วย prefix ของตัวเอง (`DatabaseService.tablePrefix("money")` → `money_`)

## Per-player settings

ค่าตั้ง **ต่อผู้เล่นแต่ละคน** (ไม่ใช่ config ของ server) ใช้ระบบกลางที่ core เป็นเจ้าของ — feature plugin ไม่เก็บ per-player setting เป็นตาราง/ไฟล์ของตัวเอง:

- feature plugin **นิยาม** setting ของตัวเองตอน `onEnable` ผ่าน `CoreApi.settings(server).register(...)` (key namespaced เช่น `money.top.visible`, `healthbar.display`) แล้วอ่านค่าผ่าน `CoreApi.preferences(server)` (มี default เสมอ)
- ค่าเก็บในตาราง `setting_values` ของ central DB; `set(...)` มีผล **realtime** (อัปเดต in-memory cache ทันที) แล้ว flush ลง DB แบบ async
- ทั้ง `SettingsRegistry` + `PlayerPreferenceService` เป็น **optional** สำหรับ consumer — ถ้า core DB ไม่ขึ้น feature ต้องยังทำงานได้ด้วยค่า default
- `minecraft-plugin-menu` (`/menu`) เป็นแค่ **UI** — render setting ทั้งหมดที่ register ไว้เป็น Paper Dialog แล้วเขียนค่ากลับ ไม่มี state/ตารางของตัวเอง; เพิ่ม setting ใหม่ = register ที่ feature plugin ไม่ต้องแตะ Menu

## เพิ่ม plugin ใหม่

1. เพิ่ม submodule + `include(...)` ใน `settings.gradle.kts`
2. `compileOnly(project(":minecraft-plugin-core"))` ใน `build.gradle.kts`
3. ตั้ง `name:` ใน `plugin.yml` เป็น **ชื่อสั้นคำเดียว PascalCase** (เช่น `Quest`) + `depend: [Core]`
4. ใช้ `EcosystemData` + `PluginLog` ของ core; ขอ DB ผ่าน `CoreApi.database(server)` ถ้าต้องใช้

ดูรายละเอียดเต็มที่ [CLAUDE.md](CLAUDE.md)

## License

ยังไม่ได้กำหนด
