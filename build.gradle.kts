// Root build script — shared configuration applied to every plugin module.
// Module-specific bits (dependencies, plugin.yml processing) live in each
// module's own build.gradle.kts.

plugins {
    java
    alias(libs.plugins.shadow) apply false
}

group = "com.mrfermz.mcplugins"
version = "0.1.0"

subprojects {
    apply(plugin = "java")

    group = rootProject.group
    version = rootProject.version

    repositories {
        mavenCentral()
        maven("https://repo.papermc.io/repository/maven-public/")
    }

    java {
        toolchain {
            // Keep in sync with `java` in gradle/libs.versions.toml.
            languageVersion.set(JavaLanguageVersion.of(25))
        }
    }

    tasks.withType<JavaCompile>().configureEach {
        options.encoding = "UTF-8"
        options.compilerArgs.add("-parameters")
    }

    tasks.withType<Test>().configureEach {
        useJUnitPlatform()
    }

    // Collect every module's deployable jar (shadowJar if present, else the
    // plain jar) into the root /jar directory as <module-name>.jar, so all
    // plugin jars for the whole ecosystem land in one place after a build.
    afterEvaluate {
        val deployJarTaskName = if (tasks.findByName("shadowJar") != null) "shadowJar" else "jar"
        val deployJarTask = tasks.named(deployJarTaskName)
        val collectJar = tasks.register<Copy>("collectJar") {
            // shadowJar (when present) reuses the plain jar's archive name/path
            // (archiveClassifier = ""), so both tasks are "producers" of that
            // file from Gradle's point of view — depend on both explicitly.
            dependsOn(deployJarTask, tasks.named("jar"))
            from(deployJarTask)
            into(rootProject.layout.projectDirectory.dir("jar"))
            rename { "${project.name}.jar" }
        }
        tasks.named("build") {
            dependsOn(collectJar)
        }
    }
}
