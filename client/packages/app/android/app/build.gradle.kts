import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// key.properties is gitignored (public repo, CI writes it from secrets).
// Without it, release builds fall back to debug signing so a contributor's
// `flutter run --release` still works.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
    // Present but incomplete means CI wrote an empty or malformed secret. Left
    // alone that silently debug-signs a release, which only a later step
    // catches and only if someone added one.
    val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    val absent = required.filter { keystoreProperties[it]?.toString().isNullOrBlank() }
    require(absent.isEmpty()) {
        "key.properties exists but is missing: $absent. Refusing to fall back " +
            "to debug signing for a release build."
    }
}

// The Google Services plugin processes google-services.json into the string
// resources FirebaseApp reads to auto-initialize on Android. That file is
// gitignored (see the repo root .gitignore): this repo is public and the
// file carries an API key, so applying the plugin unconditionally would fail
// every contributor's Gradle configuration until they downloaded their own
// copy. Skipping it instead leaves Firebase with no default options to
// auto-init from, which FcmTokenChannel (packages/platform) already treats
// as an ordinary registration failure rather than a build break - see its
// FirebaseFcmTokenSource doc.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "top.npcserver.slimm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications' Android implementation uses java.time
        // APIs that only exist natively on API 26+; desugaring is what lets
        // it keep working down to this app's actual minSdk.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "top.npcserver.slimm"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // A release build ships the class and method names of a messaging
            // client otherwise, which hands an attacker a free map of the auth
            // and push paths.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Required by isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
