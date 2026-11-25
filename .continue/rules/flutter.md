---
globs: "**/*.dart"
description: 在 Flutter 项目中修改或验证悬浮窗 / 平台通道（MethodChannel、flutter_overlay_window）相关代码时适用
---

1. 声明修复成功前必须真机验证：`flutter analyze` + `flutter test` 只是门槛，不是结论；必须装到真机抓 logcat / `dumpsys window` 确认窗口 `Surface: shown=true mDrawState=HAS_DRAWN`，并实测 MISTAKES.md 里的回归清单。
2. 异步平台调用（shareData / updateFlag / invokeMethod）的 catch 中不得只写 `catch (_) {}` 静默吞异常，至少要 `debugPrint` 失败原因，否则后续排查时「下发有没有成功」完全不可见。
3. 区分「现象」与「事实」：日志里没看到某行输出，只能说明该路径没走，不能推断功能失败；要用 dumpsys / 进程列表等独立证据交叉验证。
4. 根因未证实前不要宣布「根因已定位」，用「删掉/改掉后错误是否消失」来验证假设。