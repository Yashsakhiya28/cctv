pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val propertiesFile = file("local.properties")

        // 1. Explicitly check if the file even exists
        if (!propertiesFile.exists()) {
            throw GradleException("CRITICAL ERROR: local.properties is missing from your android/ directory!")
        }

        propertiesFile.inputStream().use { properties.load(it) }
        val sdkPath = properties.getProperty("flutter.sdk")

        // 2. Explicitly check if the key is missing
        if (sdkPath == null) {
            throw GradleException("CRITICAL ERROR: 'flutter.sdk' property is missing inside local.properties!")
        }

        sdkPath
    }

    // Connects the local Flutter SDK tools to this build
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")