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
  （**第二轮的「问题一」就是这件事的完整版**，见下文。）

---

# 第二轮踩坑记录

> 背景：第一轮修好「引擎起不来」之后，用户报告两个新问题：
> **① 打开软件后直接切到后台，没有词汇卡浮出来；**
> **② 点过一次「应用」，之后「应用 / 设置」按钮再点都没有明显效果（切回前台后卡片不显示 / 点不出设置）。**

---

## 错误 7：把 `MissingPluginException` 当成「非阻断、不影响」而放过

**我做了什么：**
第一轮结尾，我把
`MissingPluginException: No implementation found for method updateFlag on channel x-slayer/overlay`
写进了「遗留（非阻断）」，理由是「不影响卡片显示」。

**为什么错：**
- 它确实**不影响第一次显示**，但它意味着**触摸标志（穿透 / 可触摸）的下发整体失效**。
- 更糟的是：这个异常会让**同一条异步调用链后面的逻辑直接跳出**，
  于是「设置按钮点击 → 关穿透 → 打开设置」这条链路从第二次开始就断掉了。
- 用户描述的「按钮点了没反应」，就是这条被忽略的异常造成的。

**教训：**
- **「不影响主流程」不等于「可以不管」**。异常会中断调用链、会掩盖后续 bug。
- 把警告写进「遗留」时，要写清楚**它会在什么路径上造成什么后果**，
  否则下次排查会把它当成已知无害项跳过。

---

## 错误 8：没读插件原生源码，凭 Dart 侧 API 想当然

**我做了什么：**
看到 Dart 侧 `FlutterOverlayWindow.updateFlag()` 存在，就默认「调用它就能改触摸标志」。

**为什么错：**
翻 `flutter_overlay_window-1.0.2` 的原生源码才发现：

- `updateFlag` 走的是 **`x-slayer/overlay`** 这个 channel —— 它注册在
  **悬浮窗引擎（`OverlayService` 里的第二个引擎）** 上，不在主引擎上；
- 也就是说：**悬浮窗窗口不存在 / 引擎没就绪时调用，必然抛 `MissingPluginException`**；
- 而且它**只是改一次标志，不会「记住」意图**：等窗口晚一点建好，标志回到
  `showOverlay()` 时传的值，之前那次调用等于白调。
- 另一个更大的坑：`OverlayService.onStartCommand` 里如果窗口已存在，会
  **先 `cleanupAndStopSelf()` 再 `addView()`** —— 首次 `showOverlay` 后引擎会被
  **销毁并重建一次**，重建后卡片数据（`shareData` 推送的）和触摸标志**全部丢光**。

**教训：**
- 用第三方插件时，**跨引擎 / 跨 channel 的 API 一定要看原生注册在哪个引擎上**。
  「Dart 侧有这个方法」≠「任何时刻都能调」。
- 看 `onStartCommand` / `onAttachedToActivity` 这种钩子，确认**对象生命周期**：
  有没有「创建 → 销毁 → 重建」这种隐性重启。

---

## 错误 9：把「状态」当成「一次调用」，没有做「期望状态 + 就绪补发」

**我做了什么：**
`setClickThrough()` / `setAdjustMode()` 里都是「算一下标志，调一次 `updateFlag`，完事」。

**为什么错：**
在这个插件的时序下，**「调一次」根本不可靠**：

- 窗口没建好 → 抛异常（意图丢失）；
- 引擎被重建 → 之前下发的标志丢失；
- `shareData` 在引擎就绪前发送 → 消息丢失。

结果是**状态没有收敛**：Dart 侧以为「已经穿透了」，原生侧却是「可触摸」，
或者反过来 —— 表现就是「按钮点了没反应 / 卡片挡不住触摸 / 卡片不显示」。

**正确做法（已落地）：**
把**触摸标志、卡片列表、卡片样式、页面可见性**都当作**期望状态**存在
`MobileOverlayPlatform` 里；引擎每次回传 `ready` 握手时，由 `onEngineReady()`
**无条件重放**一遍：

```dart
Future<void> onEngineReady() async {
  _engineReady = true;
  await _applyFlag(adjustMode: !_clickThrough);                       // 重放触摸标志
  await _pushCards(_lastCards, adjustMode: !_clickThrough,
      visible: !_pageVisible, cardStyle: _lastStyle);                 // 重放卡片 + 可见性
}
```

**教训：**
- 面对「对象可能被重建」的跨引擎/跨进程状态，**幂等的「期望状态 + 就绪重放」**
  比「一次性命令」可靠得多。
- 重放要做到**幂等无副作用**：标志多发一次、卡片多推一次都不会出问题。

---

## 错误 10：以为「只要调用 `showOverlay` 就会显示」，忘了「谁来触发」

**我做了什么：**
之前只有**用户点「应用」**才会走 `_applyMobileOverlay()` → `showOverlay()`。
于是「打开软件直接切后台」时，**根本没有任何代码去创建悬浮窗**，自然什么都不显示。

**为什么错：**
我把「显示悬浮卡」绑定在了**一个具体的 UI 动作**上，而不是绑定在
**「应用不在前台」这个状态**上。需求是「切后台后仍能看到卡片」，
那触发条件就应该是**生命周期变化**。

**正确做法（已落地）：**
`_AppRootState` 混入 `WidgetsBindingObserver`，在
`paused / hidden / inactive` 时调用 `_ensureFloatingOnBackground()`：
权限已授予 → 直接创建悬浮窗并推送卡片（**不**在切后台时弹权限页）；
`resumed` 时再同步回主界面状态。

**教训：**
- **先想清楚「触发条件」是状态还是事件**。需求里的「切到后台」是状态变化，
  就该用生命周期钩子，而不是借某个按钮的副作用。
- 别把核心功能挂在某个具体按钮的点击回调上，否则「用户没点那个按钮」就是 bug。

---

## 错误 11：移动端沿用了桌面端的「关穿透」逻辑，造成透明 Activity 挡住下层应用

**我做了什么：**
`MainScreen` 里原本是：首帧后 `setClickThrough(true)`，然后**无条件**启动光标轮询；
轮询里 `getGlobalCursorPos()` 返回 `null`（移动端没有全局光标）时，
就**直接 `setClickThrough(false)`**，理由是「移动端点不到设置按钮」。

**为什么错：**
`setClickThrough(false)` 在 Android 上等价于把**主应用 Activity** 的窗口
变成「可触摸」。用户切到后台后，这个**透明的全屏 Activity** 仍然覆盖在其他应用之上
**拦截触摸** —— 表现就是「浮上去的卡片点不动 / 下层应用没反应」。
而且每次轮询都这么干，几乎等于把主窗口永久设成可触摸。

**正确做法（已落地）：**
- 移动端**不启动**光标轮询（`if (!_isMobile) _startCursorWatch();`）；
- 轮询里 `cursor == null` 时**什么都不改**，不再乱关穿透；
- 主应用窗口保持穿透，**只在用户真正点「设置」按钮时**临时关闭穿透
  （`_SettingsButton.onTap`），进入设置界面后输入框才可点。

**教训：**
- **「临时关闭穿透」是有代价的**：关掉之后那个窗口就会拦截触摸。
  在移动端尤其危险，因为窗口是**全屏覆盖**的。
- 桌面端的「光标热区」技巧不能直接搬到移动端，**平台能力不同**（移动端没有全局光标）。

---

## 错误 12：把「页面可见性」当成一次通知，而不是一个需要被记住的状态

**我做了什么：**
打开设置界面时调 `setCardsVisible(false)`，返回主界面时调 `setCardsVisible(true)`。

**为什么错：**
同样是「一次性命令 vs 状态」的问题：悬浮窗引擎在打开设置界面的同一时刻
**可能正在重建**，那一次 `visible:false` 就丢了 → 引擎重建后又把卡片显示出来，
和设置界面里的预览**重复显示**。

**正确做法（已落地）：**
新增 `MobileController.setPageVisible(bool)` / `MobileOverlayPlatform.setPageVisible()`，
把「设置界面是否显示」记成 `_pageVisible` 状态；`onEngineReady()` 重放时按它决定
`visible`。这样无论引擎重建多少次，可见性都会收敛到正确值。

**教训：**
- 「界面是否在前台」也是状态，**必须进期望状态缓存**，不能只发一次通知。

---

## 错误 13：修改被「回滚」了却没察觉，导致分析结果与实际代码不符

**我做了什么：**
把 `lib/services/overlay_mobile.dart` 整份重写后，直接继续往下改，
之后 `flutter analyze` 报出 `onEngineReady` / `setPageVisible` 未定义 ——
说明**文件被外部（编辑器 / 用户操作）还原成了旧版本**，我的整份重写丢了。

**为什么错：**
- 我用「整文件重写」的方式改动一个**正在被用户同时查看/编辑**的文件，
  这种大手笔写入很容易被覆盖或被回滚，且失败了很难发现。
- 发现报错后，我先去 `grep` 确认哪些改动还在、哪些没了，才避免重复劳动。

**正确做法（已落地）：**
改用**定点小改动**（`single_find_and_replace` 逐段替换）在**当前真实内容**上打补丁，
每改完一段就 `flutter analyze` 一次。改完后再 `grep` 全部符号 + `view_diff` 复核。

**教训：**
- 不要对用户正在编辑的文件做「整文件删除后重建」；**用最小 diff 修改**。
- 每次改完**立刻静态检查**，能第一时间发现「改动没落地」。
- 遇到「我明明改了却报未定义」时，第一反应应该是**重新读文件确认实际内容**，
  而不是怀疑分析器。

---

## 第二轮的正确结论（最终生效的修复）

### 问题一：`updateFlag` 不生效（按钮切换失效）

**根因**（读插件原生源码 + 日志确认）：
1. `updateFlag` 注册在**悬浮窗引擎**的 channel 上，窗口不存在 / 引擎未就绪时调用抛
   `MissingPluginException`，且**不记住意图**；
2. `OverlayService.onStartCommand` 会「先 cleanup 再 addView」→ 引擎**被重建一次**，
   重建后**触摸标志与卡片数据全部丢失**；
3. 异常中断了后续调用链 → 「设置 → 关穿透 → 打开设置」从第二次起就断了。

**修复**（`lib/services/overlay_mobile.dart`、`lib/services/mobile_controller.dart`）：
- 新增**期望状态**：`_clickThrough` / `_lastCards` / `_lastStyle` / `_pageVisible`；
- 新增 `onEngineReady()`：每次收到 `ready` 握手，**重放**触摸标志 + 卡片 + 可见性；
- `setClickThrough()` 先记录期望值再下发；`_applyFlag()` / `_pushCards()` 包
  `try/catch`，引擎未就绪时不再中断后续逻辑；
- `overlay_main.dart` 的握手消息带上 `count`，日志里可看出引擎被重建了几次。

### 问题二：打开软件直接切后台没有悬浮卡

**根因**：「显示悬浮卡」被绑死在「点应用」这个动作上，切后台时**没有任何代码触发**
`showOverlay()`。

**修复**（`lib/main.dart`、`lib/screens/main_screen.dart`）：
- `_AppRootState` 混入 `WidgetsBindingObserver`；
- `paused / hidden / inactive` → `_ensureFloatingOnBackground()`：权限已授予就**直接
  创建悬浮窗并推送卡片**（切后台时不弹权限页）；
- `resumed` → `_syncMobileOverlay()` 恢复主界面状态；
- 移动端**不再**启动光标轮询、**不再**一启动就把主窗口设为可触摸，
  避免透明 Activity 拦截下层应用触摸；
- 可见性统一走 `setPageVisible()`，随期望状态一起被重放。

### 验证结果
- `flutter analyze lib test`：无告警；
- `flutter test`：17 个用例全部通过；
- 建议按下面顺序在设备上回归（配合 `[lifecycle]` / `[apply]` / `[overlay] ready sent` /
  `[main] overlay ready` 日志）：
  1. 冷启动 → 直接切后台 → 应看到 `background → overlay shown`，卡片浮出；
  2. 回到应用 → 点「设置」→ 改内容 → 点「应用」→ **重复多次**，每次都应生效；
  3. 打开设置界面期间，悬浮窗内卡片应保持隐藏。

### 仍存在的系统级限制（非代码问题）
- 部分国产 ROM（MIUI / EMUI / ColorOS）会限制自启动 / 杀前台服务，可能导致
  切后台瞬间服务被回收（卡片「闪一下就没了」）。需要在系统设置里给本应用
  开启「自启动 / 后台运行 / 悬浮窗」白名单。
- 以上修复依赖 `flutter_overlay_window 1.0.2` 的上述行为；升级插件版本后建议
  回归验证一次（`onEngineReady()` 的「重放」是幂等的，本身不会产生副作用）。

---

# 第三轮踩坑记录

> 背景：前两轮修好「引擎起不来」「切后台不显示 / 按钮失效」之后，
> 用户报告：**手机端主界面会同时显示两份词汇卡**——悬浮窗里一份、主界面里一份。

---

## 错误 14：给同一个状态安排了「两个绘制者」

**我做了什么：**
移动端主界面 `MainScreen` 一直无条件遍历 `widget.cards` 画卡片（这是桌面端的正确做法，
桌面端没有系统悬浮窗，卡片只能由主窗口画）。同时，移动端又用
`flutter_overlay_window` 的悬浮窗引擎把**同一批卡片**画在了系统悬浮窗上。

**为什么错：**
- **同一个状态（卡片列表）被两个渲染层同时绘制**：主应用窗口画一份，
  悬浮窗引擎再画一份，用户看到的就是「两份卡片」。
- 更糟的是两份是**独立绘制**的，位置来源虽相同，但悬浮窗引擎里的拖动 / 重建
  与主界面无必然同步，看起来就是「卡片重影 / 位置对不上」。
- 前两轮的 `_pageVisible` 只解决了「设置界面打开时隐藏悬浮窗内容」，
  却从未解决「主界面与悬浮窗**同时可见**」这个重叠场景。

**正确做法（已落地，采用了「选一个绘制者」那种更简单的方案）：**
- **只保留一个绘制者**：系统悬浮窗存在时由悬浮窗引擎绘制卡片，
  `MainScreen` **不再重复绘制**（`showLocalCards = !_isMobile || !_overlayActive`）；
- 悬浮窗不存在时（首次启动、还没切后台、用户主动关闭）才由 `MainScreen` 兜底绘制，
  保证「打开软件就能看到卡片」；
- 判断依据是**原生真实状态**：新增 `NativeOverlay.isActive()`
  （`lib/services/overlay_mobile.dart`，无副作用，不修改平台层缓存），
  `MainScreen` 首帧 + 卡片变化时核对一次，并用 700ms 的**低频**轮询兜底
  （悬浮窗的创建 / 销毁是异步的，且可能发生在主界面存续期间）；
- 进入设置界面时额外 `updateCards(..., visible: false)`，把悬浮窗那份数据也同步成
  不可见 + 最新内容，避免返回主界面时闪出旧卡片。

**为什么没采用「方案二：让主界面卡片跟随悬浮窗卡片」：**
那等于让**两个渲染层都保留**、再花力气把它们的坐标 / 尺寸 / 拖动结果实时对齐，
还要处理悬浮窗引擎重建、拖动回传、可见性等一整套同步问题——
**用两份状态去模拟一份状态**，必然持续出现时序 bug。少一个绘制者，就少一整类问题。

**教训：**
- **同一个状态不要有两个渲染者**。跨窗口 / 跨引擎渲染时，先明确「谁负责画」，
  其余渲染层必须显式让位。
- 兜底渲染要用**平台真实状态**（`isActive()`）判断，而不是 Dart 侧的臆想缓存。
- 「两处都显示、再想办法对齐」几乎总是比「只显示一处」更容易出错。

> 我在**错误的前提下反复加固无效补丁**（以为是 tree-shake、以为是桌面快照），
> **多次未验证就宣布修复**，**忽略了错误在启动时即出现**这一关键事实；
> 真正根因只是「入口函数没有直接定义在 main.dart 的顶层命名空间里」。
> 教训：**先读第一个错误、区分现象与事实、用「删掉/改掉后错误是否消失」来验证根因、
> 永远回归实测再宣布成功。**

> 第二轮我**把已知异常降级成「遗留、不影响」**，**没看插件的原生注册位置**，
> 把「状态」当「一次调用」处理，**把功能绑在按钮上而不是状态上**，
> 并且**移动端照搬桌面端的穿透逻辑**，害得透明 Activity 挡住下层应用；
> 还因为**整文件重写被回滚**而短暂迷失。
> 教训：**第三方插件要看原生源码（注册在哪个引擎、生命周期会不会重建）、
> 跨引擎状态一律「期望状态 + 幂等重放」、核心功能挂在状态变化而非按钮回调上、
> 平台差异不能照搬、改动用小 diff 并每次立刻静态检查。**

> 第三轮我**给同一份卡片安排了两个渲染者**（主窗口 + 系统悬浮窗），
> 用户在移动端看到两份重叠的卡片。
> 教训：**跨窗口 / 跨引擎渲染时先定「谁来画」，其余渲染层显式让位；
> 兜底渲染以原生真实状态为准；不要用两份状态去模拟一份状态。**

---

## 一句话总结我犯的错
