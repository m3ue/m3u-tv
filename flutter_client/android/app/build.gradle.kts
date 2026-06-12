import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val media3Version = "1.10.1"
val lifecycleVersion = "2.9.4"

val androidSigningPropertiesFile = rootProject.file("signing.properties")
val androidSigningProperties = Properties().apply {
    if (androidSigningPropertiesFile.isFile) {
        androidSigningPropertiesFile.inputStream().use(::load)
    }
}
val releaseSigningKeys = listOf(
    "ANDROID_KEYSTORE_PATH",
    "ANDROID_KEY_ALIAS",
    "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_PASSWORD",
)

fun releaseSigningValue(name: String): String? =
    providers.gradleProperty(name).orNull
        ?: providers.environmentVariable(name).orNull
        ?: androidSigningProperties.getProperty(name)?.takeIf { it.isNotBlank() }

fun missingReleaseSigningKeys(): List<String> =
    releaseSigningKeys.filter { releaseSigningValue(it).isNullOrBlank() }

android {
    namespace = "com.m3ue.m3utv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.m3ue.m3utv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePath = releaseSigningValue("ANDROID_KEYSTORE_PATH")
            if (keystorePath != null) {
                storeFile = file(keystorePath)
            }
            keyAlias = releaseSigningValue("ANDROID_KEY_ALIAS")
            storePassword = releaseSigningValue("ANDROID_KEYSTORE_PASSWORD")
            keyPassword = releaseSigningValue("ANDROID_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    implementation("androidx.lifecycle:lifecycle-process:$lifecycleVersion")
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-exoplayer-hls:$media3Version")
    implementation("androidx.media3:media3-session:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}


gradle.taskGraph.whenReady {
    val releaseTaskRequested = allTasks.any { task ->
        task.project == project && task.name.contains("Release")
    }
    if (releaseTaskRequested) {
        val missing = missingReleaseSigningKeys()
        check(missing.isEmpty()) {
            "Release signing requires ${missing.joinToString()} from Gradle properties, " +
                "environment variables, or android/signing.properties (ignored by git)."
        }
        val keystorePath = releaseSigningValue("ANDROID_KEYSTORE_PATH")!!
        check(file(keystorePath).isFile) {
            "Release signing keystore was not found at ANDROID_KEYSTORE_PATH; " +
                "provide the keystore outside git before building release artifacts."
        }
    }
}
