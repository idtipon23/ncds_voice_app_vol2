plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 🟢 ตัดไฟล์ ListenableFuture เดี่ยวๆ ทิ้ง เพื่อป้องกัน Duplicate Class
configurations.all {
    exclude(group = "com.google.guava", module = "listenablefuture")
}

android {
    namespace = "com.example.ncds_voice_app_vol1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // 📍 กำหนดค่า Compile Options ระดับ Android (เวอร์ชัน 17 ตามโปรเจกต์)
    compileOptions {
        isCoreLibraryDesugaringEnabled = true // 👈 เปิดใช้งาน Desugaring ที่นี่
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.ncds_voice_app_vol1"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true // 👈 ใช้รูปแบบ Kotlin DSL
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        resources {
            excludes += listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/ASL2.0",
                "META-INF/*.kotlin_module"
            )
            pickFirsts += listOf(
                "**/libcrypto.so",
                "**/libssl.so"
            )
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

// 🟢 เพิ่ม dependencies ตัวจริงเข้ามา
dependencies {
    implementation("androidx.concurrent:concurrent-futures:1.1.0")
    implementation("com.google.guava:guava:32.1.3-android")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4") // 👈 รูปแบบวงเล็บและ Double Quotes สำหรับ .kts
}