# 踩坑记录：悬浮窗卡片不显示 / 无法浮在其他应用之上

本文件记录本次排查中**我（AI 助手）犯过的错误**，以及从中得到的教训。
目的：避免同类问题再次发生，也方便后来者（人或 AI）少走弯路。

> 背景：需求是「切到后台后，词汇卡仍能浮在其它应用之上」。
> 现象是切后台后卡片根本不显示。最终定位到两个叠加的根因，见文末「正确结论」。

---

## 错误 1：过早下结论，把「切后台」当成问题所在

**我做了什么：**
一开始把现象理解为「切到后台后卡片浮不到其它应用之上」，于是围绕 `moveToBackground`、
`TYPE_APPLICATION_OVERLAY`、ROM 后台限制、`startForegroundService` 等方向展开分析。

**为什么错：**
日志里其实一直在重复一个致命错误：

```
E/flutter: [ERROR:flutter/runtime/dart_isolate.cc(887)] Could not resolve main entrypoint function.
E/flutter: [ERROR:flutter/runtime/runtime_controller.cc(581)] Could not create root isolate.
E/flutter: [ERROR:flutter/shell/common/shell.cc(808)] Could not launch engine with configuration.
```

这说明**第二个 Flutter 引擎（承载悬浮窗的那个）压根没启动**，和「切后台」没有直接关系。
真正的问题不是「切后台浮不上去」，而是「悬浮窗引擎从来没起来」。

**教训：**
- 先读日志里**第一个** `E/` 级别的错误，而不是先套用「常见原因」。
- 把「用户描述的现象」和「日志证明的事实」分开；现象可能误导方向。

---

## 错误 2：误判根因是「桌面引擎快照被误打包」

**我做了什么：**
注意到 APK 里 `flutter_assets/isolate_snapshot_data` 有 11.5MB、`vm_snapshot_data` 为 0 字节，
且与 `windows-x64/isolate_snapshot.bin`（11,587,405 字节）**字节数完全一致**。
于是断定：这是 Windows 桌面引擎的快照被误打包，Android 加载它导致解析失败。

**为什么错（部分错）：**
- 这个现象**确实存在**，也**确实是个问题**（该删）。
- 但它**不是**本次「悬浮窗不显示」的根因。
- 我把「字节数相同」当成了「确凿证据」，其实只证明了文件来源，没证明它就是引擎失败的原因。
- 删掉快照、APK 从 192MB 降到 163MB 后，`Could not resolve main entrypoint function`
  **依然存在**——这直接证伪了我的判断。可我一开始还信誓旦旦地宣称「根因已定位」。

**教训：**
- **「删掉后错误消失了」才算验证了根因**。不能只凭静态比对就下结论。
- 修完必须**回归验证**（重装、复现、看日志），而不是看到文件没了就宣布成功。
- 一个 bug 可能同时有多个问题叠加，修掉 A 不代表 B 也修好了。

---

## 错误 3：忽略关键细节——错误在「App 启动时」就出现，与点「应用」无关

**我做了什么：**
很长一段时间默认「错误是点应用、启动悬浮窗时才发生的」。

**为什么错：**
重新抓 logcat 后发现：错误发生在 **App 冷启动、`MainActivity` 刚起来**的时刻
（进程 `Start proc` 之后几百毫秒内），用户根本还没点任何按钮。
原因是 `flutter_overlay_window` 插件在 `onAttachedToActivity` 里就**预创建**了第二个引擎
（入口 `overlayMain`），并把坏的引擎缓存进了 `FlutterEngineCache`。之后 `OverlayService`
复用的都是这个坏引擎，永远无法自愈。

**教训：**
- 注意错误出现的**时间点**：启动时 / 交互时 / 后台时，指向的代码路径完全不同。
- 看框架/插件的 `onAttachedToActivity` 这类生命周期钩子，别只盯着业务代码。
- **单例 + 缓存**是坑：坏对象一旦进了缓存，后续都会用坏的（本次 `FlutterEngineCache` 就是如此）。

---

## 错误 4：反复错误地「保留入口符号」，写了无效的补丁

**我（以及之前的代码）做了什么：**
为了不让 `overlayMain` 被 tree-shake，尝试了多种「保引用」写法，并在 `main.dart` 顶部写了
一大段注释论证：
- `if (kConstFalse) { overlayMain(); }` —— 常量条件为假，整块被编译器消除，无效。
- 把函数存进 `final` 字段 —— App-JIT/AOT 只保留「可能被执行」的代码，仍被裁，无效。
- 用运行时条件 `_shouldRunOverlayEntrypoint = Platform.executableArguments.contains(...)`
  让 `overlayMain` 看起来「可能被调用」—— 符号确实进了 kernel_blob��
  `overlayMain` 字符串在 kernel_blob 里出现了 10 次），但**报错依旧**。

**为什么错：**
我一直假设问题是「符号被 tree-shake 了」，于是不断加固「保引用」。
但 kernel_blob 里明明有 `overlayMain`，报错却还在 → 说明问题**不是符号不存在**，
而是**引擎按名字查不到它**。

**教训：**
- 当一个「修复」反复失败时，先**质疑前提假设**（「是 tree-shake 吗？」），
  而不是在错误前提上继续加码。
- 用**事实**检验假设：我去数了 kernel_blob 里 `overlayMain` 的出现次数，
  这一步反而应该更早做，能省去很多无效补丁。

---

## 错误 5：以为 `export` 能让入口被解析到，结果还是不行

**我做了什么：**
想到 `DartEntrypoint(bundlePath, "overlayMain")` 是在**入口库（应用 main 库）的顶层命名空间**
里按名字查找，而原来的 `import 'overlay_main.dart' as overlay_entry;` 是**带前缀的 import**，
`overlayMain` 只是 `overlay_entry` 的成员、不是 main.dart 的顶层符号。
于是我加了一行：

```dart
export 'overlay_main.dart' show overlayMain;
```

认为这样 `overlayMain` 就成了主库顶层符号，能被查到。

**为什么错：**
重装测试后，`Could not resolve main entrypoint function` **依然存在**。
`export` 在这里并没有达到我预期的效果（至少在 debug JIT/kernel 下的 `DartEntrypoint`
按名解析路径上没生效）。我又一次在没验证的情况下先宣布「核心修复」。

**教训：**
- **改完立刻验证**，不要先写「★核心修复★」再测。这次我又犯了错误 2 的毛病。
- `export` 和「在目标库内直接定义」不是一回事；跨库再导出的符号，在引擎按名查找时
  是否可见，**必须以实测为准**。

---

## 错误 6：多次宣布「已修复」但都没真正验证

**我做了什么：**
在错误 2、错误 5 后，都基于「文件被我删掉了 / 我加了 export」就宣称修好了，
然后才去装设备跑日志，结果都被打脸。

**教训：**
- **「我认为对」≠「已验证对」**。在涉及原生/引擎/构建产物的场景，必须：
  重新构建 → 重装 APK → 复现操作 → 看关键日志 → 确认错误消失。
- 构建产物可能是**陈旧的**（本次一开始那个 01:05 的 APK 就是旧包，
  里面还带着坏的快照，误导了判断）。

---

## 正确结论（最终生效的修复）

### 根因是**两个问题叠加**

1. **误打包的桌面引擎快照**（次要，但真实存在）
   - Windows 上 debug 构建时，`windows-x64/isolate_snapshot.bin`（x64 架构）被误复制成
     Android 的 `flutter_assets/isolate_snapshot_data`。
   - 处理：在 `android/app/build.gradle.kts` 里用三道清理删掉
     `isolate_snapshot_data` / `vm_snapshot_data`：
     ① copy/merge **之前**清源目录；② copy/merge **之后**扫所有产出目录；
     ③ 打包任务前兜底再清一次。
   - 效果：APK 体积从 192MB → 163MB，快照文件不再进包。
   - **但它不是「引擎解析不到入口」的根因。**

2. **入口函数不在 main 库根命名空间**（真正根因）
   - 插件原生用 `DartEntrypoint(appBundlePath, "overlayMain")` 按名字在**应用 main 库的顶层
     命名空间**查找 `overlayMain`；而它定义在 `overlay_main.dart`，无论 `import ... as` 还是
     `export`，引擎都查不到 → `Could not resolve main entrypoint function` → 第二个引擎
     启动失败 → 悬浮窗永远空的。
   - **修复**：在 `lib/main.dart` 里**直接定义**顶层入口函数：

     ```dart
     @pragma("vm:entry-point")
     void overlayMain() => overlay_entry.runOverlayApp();
     ```

     同时把 `lib/overlay_main.dart` 里原来的 `void overlayMain()` 改名为
     `void runOverlayApp()`（业务实现不变），由 main.dart 的 `overlayMain` 委托调用。

### 验证结果
- `Could not resolve main entrypoint function` / `Could not launch engine` 等错误**全部消失**。
- 日志出现 `[overlay] recv: {"visible":true}` —— **第二个悬浮窗引擎真正跑起来并收到消息**。

### 遗留（非阻断）
- `MissingPluginException: No implementation found for method updateFlag on channel x-slayer/overlay`
  —— `flutter_overlay_window 1.0.2` 原生 Java 侧没有实现 `updateFlag`（Dart 侧有）。
  发生在「悬浮窗已存在时更新触摸标志」的路径，会让那次调用抛异常，但不影响卡片显示。
  可选修法：把 `updateFlag` 调用改成「关闭再重开悬浮窗」，或在 `try/catch` 里降级。

---

## 一句话总结我犯的错

> 我在**错误的前提下反复加固无效补丁**（以为是 tree-shake、以为是桌面快照），
> **多次未验证就宣布修复**，**忽略了错误在启动时即出现**这一关键事实；
> 真正根因只是「入口函数没有直接定义在 main.dart 的顶层命名空间里」。
> 教训：**先读第一个错误、区分现象与事实、用「删掉/改掉后错误是否消失」来验证根因、
> 永远回归实测再宣布成功。**
