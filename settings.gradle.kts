rootProject.name = "minecraft-plugins"

// Auto-provision the JDK declared by the toolchain so `./gradlew build`
// works on any machine, even if only a different JDK is installed locally.
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
        maven("https://repo.papermc.io/repository/maven-public/") {
            name = "papermc"
        }
    }
}

// Every plugin module uses the `minecraft-plugin-<name>` prefix (see CLAUDE.md).
include("minecraft-plugin-core")
include("minecraft-plugin-money")
include("minecraft-plugin-healthbar")
