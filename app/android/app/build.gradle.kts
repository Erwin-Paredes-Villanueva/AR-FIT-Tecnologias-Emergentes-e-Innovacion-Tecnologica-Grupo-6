import java.util.Properties

// Credenciales de Snap Camera Kit (archivo local, fuera de git)
val cameraKit = Properties().apply {
    val f = rootProject.file("camerakit.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pe.arfit.arfit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "pe.arfit.arfit"
        // ML Kit, cámara y escáner QR requieren Android 7.0+
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["cameraKitApiToken"] = cameraKit.getProperty("cameraKitApiToken", "")
        manifestPlaceholders["cameraKitLensGroupId"] = cameraKit.getProperty("cameraKitLensGroupId", "")
    }

    buildTypes {
        release {
            // APK académico firmado con la clave de depuración (instalable directamente)
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

dependencies {
    // Probador 3D: motor de lentes de Snapchat (seguimiento corporal + simulación de tela)
    implementation("com.snap.camerakit:support-camera-activity:1.50.0")
}
