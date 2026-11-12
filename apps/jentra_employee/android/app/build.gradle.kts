import com.flutter.gradle.FlutterPluginConstants.PLATFORM_ARCH_MAP

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Explicit opt-in for a small, locally signed development APK. Ordinary release
// builds retain their separate application identity and signing requirement.
val developmentRelease = providers.gradleProperty("jentraDevelopmentRelease").orNull == "true"
val productionSigning = providers.gradleProperty("jentraProductionSigning").orNull == "true"
val targetPlatforms = providers.gradleProperty("target-platform").orNull
val splitPerAbi = providers.gradleProperty("split-per-abi").orNull == "true"
if (developmentRelease && productionSigning) error("Choose one employee signing identity.")
fun signingValue(name: String): String = providers.environmentVariable(name).orNull
    ?.takeIf { it.isNotBlank() } ?: error("Employee release signing is not configured: $name")

android {
    namespace = "com.jentra.employee"
    // Native protected storage requires API 37; installed platform is available.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jentra.employee"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Package native plugins only for ABIs with a compiled Flutter engine.
        if (targetPlatforms != null && !splitPerAbi) {
            ndk.abiFilters.clear()
            ndk.abiFilters.addAll(targetPlatforms.split(',').map { PLATFORM_ARCH_MAP.getValue(it) })
        }
    }

    if (productionSigning) {
        signingConfigs.create("employeeProduction") {
            storeFile = file(signingValue("JENTRA_EMPLOYEE_KEYSTORE"))
            storeType = "PKCS12"
            storePassword = signingValue("JENTRA_EMPLOYEE_SIGNING_PASSWORD")
            keyAlias = "jentra-employee"
            keyPassword = signingValue("JENTRA_EMPLOYEE_SIGNING_PASSWORD")
        }
    }
    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (developmentRelease) {
                applicationIdSuffix = ".dev"
                signingConfig = signingConfigs.getByName("debug")
            } else if (productionSigning) {
                signingConfig = signingConfigs.getByName("employeeProduction")
            } else {
                // Store distribution requires a separately configured release keystore.
                signingConfig = null
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
