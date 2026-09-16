import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. key.properties is gitignored and supplied out of band, so a
// clone without it still builds — but it builds DEBUG-SIGNED, and Play rejects
// that at upload with "signed in debug mode". The fallback below is therefore
// deliberately loud: see the check task at the bottom of this file.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "jp.or.kai.kaitan"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "jp.or.kai.kaitan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // With key.properties present this is the real upload key. Without it
            // we fall back to debug so the project still builds for anyone who
            // only wants to run it — but that artifact CANNOT be uploaded.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Without this the failure is silent and expensive: the bundle builds fine, and
// only Play tells you it is debug-signed — after a ~15 minute build and an upload.
gradle.taskGraph.whenReady {
    val bundling = allTasks.any { it.name.contains("Release") && it.name.contains("Bundle") }
    if (bundling && !hasReleaseKey) {
        logger.warn(
            "\n" + "=".repeat(74) + "\n" +
            "  WARNING: android/key.properties is missing.\n" +
            "  This release bundle will be signed with the DEBUG key and Google\n" +
            "  Play WILL REJECT IT (\"signed in debug mode\").\n" +
            "  See README.md section 2. Verify any bundle before uploading:\n" +
            "    keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab\n" +
            "  It must NOT say CN=Android Debug.\n" +
            "=".repeat(74) + "\n"
        )
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
