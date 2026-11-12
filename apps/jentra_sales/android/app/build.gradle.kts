import com.flutter.gradle.FlutterPluginConstants.PLATFORM_ARCH_MAP

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val targetPlatforms = providers.gradleProperty("target-platform").orNull
val splitPerAbi = providers.gradleProperty("split-per-abi").orNull == "true"

android {
    namespace = "com.jentra.sales"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        // A separate development identity; no store signing material is used.
        applicationId = "com.jentra.sales.dev"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Package native plugins only for ABIs with a compiled Flutter engine.
        if (targetPlatforms != null && !splitPerAbi) {
            ndk.abiFilters.clear()
            ndk.abiFilters.addAll(targetPlatforms.split(',').map { PLATFORM_ARCH_MAP.getValue(it) })
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

kotlin {
    compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 }
}
flutter { source = "../.." }
