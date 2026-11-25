plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.vocab_overlay"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.vocab_overlay"
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

// ---------------------------------------------------------------------------
// 关键修复：删除误打包进来的“桌面端引擎快照”（悬浮窗引擎启动失败的根因）
// ---------------------------------------------------------------------------
//
// 现象：
//   运行应用时日志反复出现
//     E/flutter: Could not resolve main entrypoint function.
//     E/flutter: Could not run the run main Dart entrypoint.
//     E/flutter: Could not launch engine with configuration.
//   导致 flutter_overlay_window 创建的第二个 Flutter 引擎（入口 overlayMain）
//   无法启动，悬浮窗里的 Dart 代码永远不执行 → 卡片不显示；切到后台后卡片也
//   浮不到其它应用之上。
//
// 原因：
//   在 Windows 主机上做 debug（JIT）构建时，Flutter 工具会把 **Windows 桌面
//   引擎**的快照
//     bin/cache/artifacts/engine/windows-x64/isolate_snapshot.bin (11,587,405 字节)
//   误复制成 Android 的
//     flutter_assets/isolate_snapshot_data
//   以及 0 字节的 vm_snapshot_data。（已用字节大小比对确认为同一文件。）
//
//   Android 引擎启动时，只要 flutter_assets 里存在**非空**的
//   isolate_snapshot_data，就会优先加载它而不是 kernel_blob.bin。但这个快照是
//   x64 桌面架构的，在 Android 上无法解析任何 Dart 入口点 → 报错。
//
// 处理：
//   这些文件对 Android 没有任何用处（Android 只用 kernel_blob.bin 或 libapp.so），
//   因此无论出现在哪个阶段都直接删除。为了可靠，必须：
//     1) 在 copyFlutterAssets / mergeAssets **运行之前**清掉「源目录」
//        （app/intermediates/flutter/<variant>/flutter_assets），否则拷贝任务
//        会把坏文件复制出去；
//     2) 在它们**运行之后**再扫一遍所有产出目录（finalizedBy），
//        防止 UP-TO-DATE 复用了旧的坏产出；
//     3) 把清理任务挂到打包任务之前，作为最后一道保险。
// ---------------------------------------------------------------------------

androidComponents {
    onVariants(selector().all()) { variant ->
        val variantDir = variant.name
        val capitalized = variantDir.replaceFirstChar { it.uppercaseChar() }

        // 项目根的 build/（android/ 的上一级），Flutter 的产物都在这里。
        val flutterBuildDir: File = rootProject.projectDir.parentFile.resolve("build")

        // 所有可能包含“待打包快照”的目录。
        fun snapshotDirs(): List<File> = listOf(
            // ★ 源目录：flutter assemble 的输出，copyFlutterAssets 从这里复制。
            flutterBuildDir.resolve(
                "app/intermediates/flutter/$variantDir/flutter_assets",
            ),
            // copyFlutterAssets 的输出。
            flutterBuildDir.resolve(
                "app/intermediates/assets/$variantDir/" +
                    "copyFlutterAssets$capitalized/flutter_assets",
            ),
            // 部分 AGP 版本的合并目录。
            flutterBuildDir.resolve(
                "app/intermediates/assets/$variantDir/merge${capitalized}Assets/flutter_assets",
            ),
            flutterBuildDir.resolve(
                "app/intermediates/assets/$variantDir/merge${capitalized}Assets",
            ),
            flutterBuildDir.resolve(
                "app/intermediates/merged_assets/$variantDir/merge${capitalized}Assets/out/flutter_assets",
            ),
            flutterBuildDir.resolve(
                "app/intermediates/merged_assets/$variantDir/merge${capitalized}Assets/out",
            ),
        )

        val badNames = listOf("isolate_snapshot_data", "vm_snapshot_data")

        fun deleteBadSnapshots(tag: String) {
            snapshotDirs().forEach { dir ->
                badNames.forEach { name ->
                    val f = dir.resolve(name)
                    if (f.exists()) {
                        // 0 字节的 vm_snapshot_data 同样删除：Android 用不到，
                        // 留着只会误导引擎启动逻辑。
                        val ok = f.delete()
                        logger.lifecycle(
                            "[flutter-fix:$tag] $name -> " +
                                "${if (ok) "deleted" else "FAILED"} (${f.path})",
                        )
                    }
                }
            }
        }

        // 清理任务：纯删除操作，禁用 up-to-date 检查确保每次都执行。
        val cleanBefore = tasks.register("removeDesktopEngineSnapshotBefore$capitalized") {
            description = "拷贝前移除桌面引擎误打包的 isolate/vm snapshot 文件"
            group = "flutter"
            outputs.upToDateWhen { false }
            doLast { deleteBadSnapshots("before") }
        }

        val cleanAfter = tasks.register("removeDesktopEngineSnapshotAfter$capitalized") {
            description = "打包后移除桌面引擎误打包的 isolate/vm snapshot 文件"
            group = "flutter"
            outputs.upToDateWhen { false }
            doLast { deleteBadSnapshots("after") }
        }

        // 1) 拷贝 / 合并任务 **运行前** 清源目录：设为其前置依赖。
        tasks.matching {
            it.name.equals("copyFlutterAssets$capitalized", ignoreCase = true) ||
                it.name.equals("merge${capitalized}Assets", ignoreCase = true)
        }.configureEach {
            dependsOn(cleanBefore)
            // 2) 运行后再扫一遍所有产出目录。
            finalizedBy(cleanAfter)
        }

        // 3) 最后一道保险：打包任务前再清一次（覆盖任何遗漏的时序）。
        tasks.matching {
            it.name.equals("package$capitalized", ignoreCase = true) ||
                it.name.equals("package${capitalized}Bundle", ignoreCase = true)
        }.configureEach {
            dependsOn(cleanAfter)
        }
    }
}
