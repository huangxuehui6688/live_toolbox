plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.livetoolbox.live_toolbox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.livetoolbox.live_toolbox"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 只保留 arm64-v8a：鸿蒙真机与当代安卓机均为此架构，
        // 可剔除 armeabi-v7a / x86_64 的原生库（实测约省 77MB）
        //
        // 注意：这里必须先 clear() 再 add()，不能写成 `abiFilters += listOf("arm64-v8a")`。
        // 原因：Flutter Gradle 插件在 `plugins {}` 应用阶段就已经跑过一次
        // FlutterPlugin.addFlutterTasks() -> configureAbiWithoutSplits()：
        //     defaultConfig.ndk { abiFilters.clear(); abiFilters.addAll(PLATFORM_ABI_LIST) }
        // 把 abiFilters 预填成 {armeabi-v7a, arm64-v8a, x86_64}。
        // 而 abiFilters 是 Set<String>，`+=` 等价于 addAll，往集合里写一个已存在的元素是空操作，
        // 所以旧写法等于没写 —— 三个架构的原生库全被打进了 APK。
        // 本 android {} 块在 `plugins {}` 之后执行，因此这里的 clear() + add() 才是最终生效值。
        //
        // 本项目只在 arm64 真机上运行（小米 M2101K9C / 华为鸿蒙 PLU-AL10），不依赖模拟器，
        // 所以这里对 debug 和 release 一并收紧。若将来需要在 x86_64 模拟器上调试，
        // 必须在此放开 "x86_64"（或改用 androidComponents.onVariants 只对 release 生效），
        // 否则模拟器会因缺少对应架构的 .so 直接崩溃。
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    // 第二道保险：无论 abiFilters 是否被上游插件改写，打包阶段直接丢弃非 arm64 的原生库。
    // onnxruntime / sherpa-onnx / tflite / xeno_native 等预编译 .so 是由插件 AAR 带进来的，
    // 只有在这两项过滤之下才能保证不进 APK。
    packaging {
        jniLibs {
            excludes += listOf(
                "lib/armeabi-v7a/**",
                "lib/armeabi/**",
                "lib/x86/**",
                "lib/x86_64/**"
            )
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
