# Minecraft Plugin Ecosystem

โปรเจกต์นี้คือ ecosystem ของ Minecraft plugin หลายตัวที่ทำงานร่วมกัน รันบน **Paper/Spigot (Bukkit API)** สำหรับ Minecraft **26.2** ทุก plugin แชร์ database และระบบตั้งค่าผ่านเว็บ (web-config) ตัวเดียวกัน

## Target platform

- **Minecraft / Server**: Paper (หรือ fork ที่ compatible) เวอร์ชัน `26.2`
- **Java**: **Java 25** — ยืนยันแล้วว่า `io.papermc.paper:paper-api:26.2` ต้องการ JVM runtime `25 ขึ้นไป` (build จะ fail ถ้าตั้ง toolchain ต่ำกว่านี้) Gradle `toolchain` ตั้งไว้ที่ `25` ใน `gradle/libs.versions.toml` + root `build.gradle.kts` (bytecode 25 รันบน server ที่ใช้ Java 26 ได้)
- **Build tool**: Gradle (Kotlin DSL, `build.gradle.kts`) แบบ **multi-module project** — ใช้ **Gradle wrapper** (`./gradlew`, distribution `9.6.1`) ที่ commit ไว้ใน repo ทุกเครื่อง build ได้เหมือนกันโดยไม่ต้องลง Gradle เอง; JDK 25 ถูก auto-provision ผ่าน foojay-resolver `1.0.0` (ตั้งใน `settings.gradle.kts`)
- **Paper API coordinate**: `io.papermc.paper:paper-api:26.2.build.34-alpha` (build 34 = server jar `paper-26.2-34.jar`) จาก repo `https://repo.papermc.io/repository/maven-public/`

## โครงสร้าง repo (multi-module Gradle)

```
minecraft-plugins/
├── settings.gradle.kts
├── build.gradle.kts                   # root: shared config (java toolchain, repositories, plugins ทั้งหมด)
├── gradle/libs.versions.toml          # version catalog กลาง
├── minecraft-plugin-core/             # shared API/library — ทุก plugin depend on ตัวนี้
│   └── src/main/java/.../core/
│       ├── api/                      # interface ที่ plugin อื่นเรียกใช้ผ่าน ServicesManager
│       ├── db/                       # DataSource, migration, repository ฐาน
│       └── config/                   # client เชื่อมต่อ web-config (REST/poll หรือ webhook)
├── minecraft-plugin-money/            # feature plugin: สกุลเงิน/เศรษฐกิจ (compileOnly core + shadow, ใช้ central DB)
├── minecraft-plugin-healthbar/        # feature plugin: health bar เหนือหัว entity เมื่อโดนผู้เล่นตี (compileOnly core, อ่าน per-player setting)
├── minecraft-plugin-menu/             # feature plugin: UI เมนูต่อผู้เล่น (/menu) — render setting ที่ plugin อื่น register ผ่าน Paper Dialog API
├── minecraft-plugin-<feature3>/
├── webconfig/                         # web service แยกหาก (อ่าน/เขียน DB เดียวกับ plugin)
└── docs/
```

> ทุก module ที่เป็น plugin (รวม core) ใช้ prefix `minecraft-plugin-<name>` ให้ตรงกันทั้ง repo — เช่น `minecraft-plugin-core`, `minecraft-plugin-money`, `minecraft-plugin-healthbar`, `minecraft-plugin-menu`

> **feature plugin ไม่จำเป็นต้องใช้ DB/service ของ core ทุกตัว** — ทุกตัว depend on core (เพื่อ `EcosystemData` + logging กลาง ตาม convention) แต่ตัวที่ไม่มี persistent state (เช่น `minecraft-plugin-healthbar`) ใช้แค่ config dir รวม + `PluginLog` พอ ไม่ต้องขอ `DatabaseService` หรือ register service ใด ๆ

## หลักการออกแบบ ecosystem

1. **`minecraft-plugin-core` คือจุดรวม** — ไม่ใส่ logic เกมเฉพาะอย่างไว้ใน core มีแค่:
   - Interface/service ที่ plugin อื่นต้องเรียกใช้ (register ผ่าน Bukkit `ServicesManager`)
   - การเชื่อมต่อ DB กลาง (connection pool เดียว, schema migration เดียว)
   - Client สำหรับอ่านค่าที่ตั้งจาก web-config
2. **Plugin คุยกันผ่าน core API เท่านั้น** ห้าม plugin หนึ่ง reference class ภายในของอีก plugin ตรง ๆ — ถ้าต้องแชร์ฟังก์ชัน ให้ดึง interface นั้นขึ้นไปไว้ใน `minecraft-plugin-core`
3. **Database เดียวสำหรับทุก plugin** — ใช้ connection pool เดียว (HikariCP) ที่ inject จาก `minecraft-plugin-core`, แต่ละ plugin มี schema/table prefix ของตัวเองเพื่อไม่ชนกัน อย่าใช้ DB แยกต่อ plugin
4. **Web-config เป็น service แยกหาก** (อยู่ใน `webconfig/`) อ่าน/เขียนตาราง config เดียวกับที่ plugin อ่าน — plugin ควร cache ค่า config ในเมมโมรีและ refresh เป็นช่วง ๆ (หรือฟัง webhook/pub-sub) ไม่ query DB ทุกครั้งที่ต้องใช้ค่า

## Build & commands

- Build ทั้ง ecosystem: `./gradlew build`
- Build plugin เดียว: `./gradlew :minecraft-plugin-<name>:build`
- jar ที่ deploy ได้ต้องผ่าน shadow/shading (relocate dependency กันชนกับ plugin อื่นบน server เดียวกัน)
- **การตัดสินใจที่ fix แล้ว (ตอนตั้ง module แรก): `minecraft-plugin-core` ถูก load เป็น plugin แยกบน server** (ไม่ shade เข้าแต่ละ plugin) เพื่อให้ connection pool + web-config client มีอยู่ชุดเดียวจริง ๆ — feature plugin ทุกตัวจึง:
  1. `compileOnly(project(":minecraft-plugin-core"))` ใน `build.gradle.kts` (ไม่ bundle core เข้า jar ตัวเอง)
  2. ใส่ `depend: [Core]` ใน `plugin.yml` เพื่อบังคับลำดับ load (อ้างชื่อ plugin สั้นของ core ตาม [convention ชื่อ plugin](#ชื่อ-plugin-ที่โชว์ใน-pl))
  3. คุยกับ core ตอน runtime ผ่าน Bukkit `ServicesManager` (ตัวช่วย `com.mrfermz.mcplugins.core.CoreApi`)
- ใส่ plugin ใหม่: เพิ่ม `include(...)` ใน `settings.gradle.kts` แล้วทำตาม 3 ข้อบน — shadow jar ใช้ relocate เฉพาะ third-party lib เท่านั้น
- หลังแก้โค้ด plugin ตัวไหนแล้ว แค่สั่ง build .jar ออกมาให้ (`./gradlew :minecraft-plugin-<name>:build` หรือ `./gradlew build`) ก็พอ **ห้ามสั่งรัน/สตาร์ท server** เพื่อทดสอบ ไม่ใช่ขั้นตอนที่ต้องทำ
- **jar ทุก module รวมไว้ที่ root `/jar` เดียว** หลัง build — root `build.gradle.kts` มี `collectJar` task (ทำงานผ่าน `afterEvaluate` ต่อ subproject, ผูกกับ `build`) คัดลอก deployable jar ของแต่ละ module (shadowJar ถ้ามี ไม่งั้น jar ธรรมดา) ไปไว้ที่ `jar/<module-name>.jar` เช่น `jar/minecraft-plugin-core.jar`, `jar/minecraft-plugin-money.jar` — `./gradlew build` ตัวเดียวพอสำหรับทั้ง ecosystem, ไม่ต้องไปคุ้ยใน `<module>/build/libs/` ทีละตัว (`/jar` ถูก gitignore ไว้แล้ว เป็น build artifact)
- **ห้ามเพิ่ม task ที่ copy jar ไปที่ `minecraft-server/plugins` (หรือ deploy ไปที่ server ใด ๆ) โดยอัตโนมัติ** — build จบที่ `/jar` เท่านั้น การเอา jar ไปวางที่ server เป็นขั้นตอนที่ผู้ใช้ทำเอง ไม่ใช่ส่วนหนึ่งของ build script

## Config directory บน server

ทั้ง ecosystem **แชร์โฟลเดอร์ config/data เดียว** บน server คือ `plugins/antitle/` (ไม่กระจายเป็น `plugins/<PluginName>/` ต่อ plugin) เพื่อให้ admin ดูแลที่เดียวจบ — แต่ละ plugin มี **ไฟล์ config แบน ๆ ชื่อตามตัวเอง** (`<module>.yml`) ไม่ทำ subfolder ต่อ plugin:

```
plugins/
└── antitle/                 # โฟลเดอร์เดียวของทั้ง ecosystem (ชื่อ fix = "antitle")
    ├── config.yml           # global: DB pool + web-config client — core เป็นเจ้าของ
    ├── database.db          # central SQLite (ถ้า database.type = sqlite)
    ├── money.yml            # ตั้งค่า currency ของ money
    └── <feature>.yml        # 1 feature plugin = 1 ไฟล์ <feature>.yml
```

**วิธีทำ:** Bukkit กำหนด `getDataFolder()` ของแต่ละ plugin เป็น `plugins/<PluginName>/` และเป็น `final` (override ไม่ได้) — เลยให้ **`minecraft-plugin-core` เป็นเจ้าของ helper `com.mrfermz.mcplugins.core.EcosystemData`** ที่ resolve path ไปที่ `plugins/antitle/` ชุดเดียว แล้วทุก plugin เรียกผ่าน helper นี้แทน:

```java
// แทน saveDefaultConfig()+getConfig()  →  plugins/antitle/money.yml
//   (seed ค่า default จาก config.yml ใน jar ครั้งแรกอัตโนมัติ)
FileConfiguration cfg = EcosystemData.config(this, "money");
// global config ของทั้ง ecosystem (core เป็นเจ้าของ)  →  plugins/antitle/config.yml
FileConfiguration shared = EcosystemData.config(this);
// ถ้าต้องเก็บไฟล์ข้อมูลหลาย ๆ ไฟล์จริง ๆ (ไม่ใช่ config) ค่อยขอ dir → plugins/antitle/<module>/
File dir = EcosystemData.folder(this, "money");
```

กติกาของ feature plugin:
- **ห้ามใช้ `getDataFolder()`, `getConfig()`, `saveDefaultConfig()` ตรง ๆ** — สามตัวนี้ผูกกับ `plugins/<PluginName>/` จะทำให้ไฟล์หลุดออกจาก `plugins/antitle/` (ยังวาง `config.yml` เป็น resource ใน jar ได้ตามเดิม — `EcosystemData.config(...)` จะ copy ไปเป็น `<module>.yml` ให้)
- module name ที่ส่งให้ `EcosystemData` ใช้ชื่อสั้น (เช่น `"money"`) ไม่ใช่ชื่อใน `plugin.yml` — ได้ไฟล์ `plugins/antitle/money.yml`
- เพิ่ม plugin ใหม่ = เพิ่มไฟล์ `plugins/antitle/<feature>.yml` ผ่าน helper เดิม ไม่ต้องแตะ core

## Database

- **`minecraft-plugin-core` เป็นเจ้าของ pool เดียว (HikariCP)** ผ่าน `HikariDatabaseService` register เข้า `ServicesManager` เป็น `DatabaseService` — รองรับหลาย engine เลือกผ่าน `database.type` ใน global `config.yml` ของ core:
  - `sqlite` (default, embedded, zero-config — ไฟล์ `plugins/antitle/database.db`) เหมาะ dev
  - `postgresql` — **engine ที่แนะนำสำหรับ production**
  - `mysql` / `mariadb` — รองรับด้วย (ผ่าน MariaDB driver)
  - network engine ใช้ key: `database.host/port/database/username/password/properties` (`properties` เป็น map ต่อท้าย JDBC URL เช่น `sslmode: require`), `pool-size` (sqlite ถูก force = 1 เพราะ single-writer)
- **เปลี่ยน engine = แก้ config อย่างเดียว** — โค้ด plugin ไม่ต้องแก้ เพราะคุยผ่าน `DataSource` + `DatabaseService.dialect()` (consumer ใช้ dialect เลือก SQL ที่ถูกของแต่ละ engine เช่น UPSERT / column type)
- **JDBC driver โหลดตอน runtime ผ่าน Paper library loader** (field `libraries:` ใน `plugin.yml` ของ core: HikariCP + sqlite-jdbc + postgresql + mariadb-java-client) ไม่ shade เข้า jar — โหลดจาก Maven Central ครั้งแรกแล้ว cache ไว้; feature plugin อื่นใช้แค่ `java.sql` ผ่าน `DataSource` ไม่ต้อง depend driver เอง
- แต่ละ plugin namespace ตารางด้วย prefix ของตัวเอง — ขอจาก `DatabaseService.tablePrefix("<module>")` (เช่น money → `money_`) เช่น money เก็บตาราง `money_balances`
- **ห้าม plugin เปิด pool/DB เอง** — ดึง `DataSource` จาก `CoreApi.database(server)` เท่านั้น
- Migration ใช้เครื่องมือเดียว (เช่น Flyway) รันจาก `minecraft-plugin-core` ตอน startup หรือจาก `webconfig` — เลือกจุดเดียวเป็น single source of truth ห้ามมี 2 ที่รัน migration พร้อมกัน (ตอนนี้แต่ละ plugin ยัง `CREATE TABLE IF NOT EXISTS` ของตัวเองไปก่อน จนกว่าจะตั้ง migration กลาง)

## Per-player settings (ค่าตั้งต่อผู้เล่น)

ค่าตั้งที่เป็น **ของผู้เล่นแต่ละคน** (ไม่ใช่ config ของ server) ใช้ระบบกลางที่ core เป็นเจ้าของ — **อย่าให้ feature plugin เก็บ per-player setting เป็นตาราง/ไฟล์ของตัวเอง**

- core register 2 service เข้า `ServicesManager` (เมื่อ DB พร้อม): `SettingsRegistry` (ทะเบียน metadata ของ setting) + `PlayerPreferenceService` (ที่เก็บค่าต่อผู้เล่น, ตาราง `setting_values`) — อยู่ใน package `com.mrfermz.mcplugins.core.settings`
- **feature plugin เป็นคนนิยาม setting ของตัวเอง** — ตอน `onEnable` เรียก `CoreApi.settings(server).register(SettingDefinition...)` (key ตั้งชื่อ namespaced เช่น `money.top.visible`, `healthbar.display`) แล้วอ่านค่าผ่าน `CoreApi.preferences(server)` (มี default เสมอ) — **ห้าม reference plugin `Settings` ตรง ๆ** คุยผ่าน core API เท่านั้น (ตามหลักการข้อ 2)
- **`minecraft-plugin-menu` (`Menu`) เป็นแค่ UI** — render setting ทั้งหมดที่ register ไว้เป็น Paper **Dialog** (`/menu`) แล้วเขียนค่ากลับผ่าน `PlayerPreferenceService` ไม่มี state/ตารางของตัวเอง; เพิ่ม setting ใหม่ = register ที่ feature plugin ไม่ต้องแตะ `Menu`
- `set(...)` อัปเดต in-memory cache ทันที (ค่ามีผล **realtime** ต่อ consumer ที่อ่านสด เช่น `/money top`) แล้ว flush ลง DB แบบ async; ตาราง `setting_values` ตาม convention DB ปกติ (`id` UUID PK, `player_uuid`+`setting_key` UNIQUE, `created_at`/`created_by`)
- ทั้งสอง service เป็น **optional** สำหรับ consumer — null-check/`ifPresent` ไว้ ถ้า core DB ไม่ขึ้น feature ต้องยังทำงานได้ด้วยค่า default

## Conventions

- Package root: **`com.mrfermz.mcplugins`** — core อยู่ใต้ `.core` (`.core.api`, `.core.db`, `.core.config`, `.core.log`, `.core.settings`), feature plugin อยู่ใต้ชื่อตัวเอง เช่น money = `com.mrfermz.mcplugins.money`, menu = `com.mrfermz.mcplugins.menu`
- ห้าม plugin ใดสร้าง connection pool ของตัวเอง — ดึงจาก `minecraft-plugin-core` เท่านั้น
- Logging: ใช้ wrapper กลาง `com.mrfermz.mcplugins.core.log.PluginLog` (`PluginLog.of(this)`) format ข้อความให้เหมือนกันทุก plugin (print ลง console) — **ยังไม่มี centralized log persistence**; ที่ persist ลง DB ตอนนี้คือ money transaction อย่างเดียว (ตาราง `money_transactions` เขียนผ่าน core `DatabaseService`)
- **DB schema convention: ทุกตารางมี `id` เป็น PRIMARY KEY ที่ gen ด้วย UUID ใน Java** (`UUID.randomUUID()`, คอลัมน์ `VARCHAR(36)` ใช้ได้ทุก engine) ไม่ใช้ auto-increment ของ DB — natural key (เช่น player uuid ใน `money_balances`) ทำเป็นคอลัมน์ `UNIQUE` แยกไว้ทำ upsert
- **เวลา/ผู้สร้างในตาราง: ใช้ `created_at` เป็น date column จริง** (`TIMESTAMP`; MySQL/MariaDB = `DATETIME`) เขียนผ่าน `setTimestamp`/อ่านผ่าน `getTimestamp` ไม่เก็บเป็น epoch number — และ `created_by` (UUID ของผู้สั่ง, null = console/system) ไม่ใช้ชื่อ `ts`/`actor`; SQLite ตั้ง `date_class=text` ที่ core pool ให้เก็บ date เป็น ISO text อ่านได้

### ชื่อ plugin ที่โชว์ใน `/pl`

- field `name:` ใน `plugin.yml` = **ชื่อสั้นแบบ PascalCase คำเดียว** ที่อ่านสวยใน `/plugins` (`/pl`) — ไม่ใส่คำว่า `Plugin` หรือ prefix `MinecraftPlugin` ต่อท้าย/นำหน้า เช่น `Core`, `Money`, `Healthbar`
- ชื่อนี้แยกขาดจาก 3 อย่างที่ยังคงเดิม: **ชื่อ Gradle module** (`minecraft-plugin-<name>`), **main class** (`<Name>Plugin` เช่น `MoneyPlugin`), และ **module short name ที่ส่งให้ `EcosystemData`** (`"money"` → `plugins/antitle/money.yml`)
- `depend:`/`softdepend:` ใน `plugin.yml` ของ plugin อื่นต้องอ้างชื่อสั้นนี้ — feature plugin ทุกตัวใช้ `depend: [Core]` (ไม่ใช่ `[MinecraftPluginCore]` แล้ว)
- เพิ่ม plugin ใหม่: ตั้ง `name:` เป็นชื่อสั้นคำเดียวให้ unique บน server แล้วอ้างชื่อนั้นใน `depend` ของตัวอื่น

## Git / commit

- **ทุกครั้งที่ทำงาน/แก้ไขตาม prompt เสร็จ ให้เสนอ commit message มาให้เลย** (เป็น Conventional Commits เช่น `feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`) — แต่ **ห้าม `git add`/stage, `git commit`, `git push` เอง** ปล่อยให้ผู้ใช้เป็นคน commit เอง
- ถ้าการแก้ไขกินหลาย submodule (`minecraft-plugin-core/money/healthbar` เป็น git repo แยกแต่ละตัว) ให้เสนอ commit message **แยกต่อ repo** ที่ถูกแตะ + commit ของ root repo (`minecraft-plugin-ai`) ถ้ามีการแก้ไฟล์ส่วนกลาง (`CLAUDE.md`, `settings.gradle.kts`, ฯลฯ)

## การดูแลเอกสาร

- ไฟล์นี้ (`CLAUDE.md`) เก็บเฉพาะ convention/architecture ที่ใช้ร่วมกันทั้ง ecosystem — เมื่อมีการแก้ไขที่กระทบ convention ส่วนกลาง (เช่น เปลี่ยนวิธี module คุยกัน, เปลี่ยน DB engine, เพิ่ม module ใหม่ที่กระทบโครงสร้าง) ให้ update ไฟล์นี้ตามไปด้วย
- **root `README.md`** (หน้า repo บน GitHub) เป็นภาพรวม ecosystem สำหรับคนนอก — เมื่อมีการเปลี่ยนที่กระทบส่วนกลาง (เพิ่ม/ลบ/เปลี่ยนชื่อ module, ตาราง modules + ชื่อใน `/pl`, วิธี build/clone, target platform, DB engine) ให้ update root `README.md` ควบคู่กับ `CLAUDE.md` ด้วย (CLAUDE.md = convention เชิงลึกสำหรับคนทำงานในโค้ด, README.md = ภาพรวมสำหรับคนนอก)
- แต่ละ module/plugin (เช่น `minecraft-plugin-core`, `minecraft-plugin-<feature>`, `webconfig`) ให้มี `README.md` ของตัวเองอธิบายรายละเอียดเฉพาะของ module นั้น — เมื่อแก้โค้ดใน module ไหน ให้ update README.md ของ module นั้น (สร้างใหม่ถ้ายังไม่มี) แทนการยัดรายละเอียดเฉพาะ module ไว้ใน CLAUDE.md ส่วนกลาง
