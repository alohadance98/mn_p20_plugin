group = "com.mn.plugin"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.3.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

// The vendor AARs (MnSdk / MnFuelSdk) live in a file-based Maven repository
// inside this plugin. A library module cannot depend on a bare local .aar, and
// the consuming app must be able to resolve them too, so the repository is
// registered on every project of the host build.
val mnMavenRepo = file("maven")
rootProject.allprojects {
    repositories {
        maven { url = uri(mnMavenRepo) }
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.mn.plugin"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        // The vendor AARs require API 28+.
        minSdk = 28
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.amoymn:mnsdk:1.3.1")
    implementation("com.amoymn:mnfuelsdk:1.0.0")
}
