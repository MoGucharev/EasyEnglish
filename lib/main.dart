// ignore_for_file: deprecated_member_use

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/legacy.dart';

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'models/vocab_card.dart';
import 'screens/main_screen.dart';
import 'screens/settings_screen.dart';
import 'services/mobile_controller.dart';
import 'services/overlay_desktop.dart' show isDesktopPlatform;
import 'services/overlay_service.dart';
import 'services/storage_service.dart';
// 悬浮窗引擎（第二个 Flutter 引擎）的 Dart 入口 `overlayMain` 定义在
// overlay_main.dart。flutter_overlay_window 的原生实现会在运行时用
// DartEntrypoint(appBundlePath, "overlayMain") 解析该符号。
//
// 关键：debug（JIT/kernel）模式下只有“可达”的函数才会被真正编译进
// kernel_blob；仅靠 `@pragma("vm:entry-point")`（只对 AOT 生效）不够。
// 如果 overlayMain 完全无人引用，第二个引擎就会报
// “Could not resolve main entrypoint function”而完全无法启动。
//
// 注意：**不能用 `if (kConstFalse) { overlayMain(); }` 来“保留引用”**——
// 编译器会在编译期把常量条件为假的 if 整块消除，overlayMain 依旧不可达，
// 符号仍然不在快照里（这正是该报错一直存在的原因）。
//
// 也不能只把函数存进 final 字段：App-JIT / AOT 快照只保留“真正可能被执行”
// 的代码，未被调用的函数照样会被裁掉。
//
// 唯一可靠的做法是让 main() 中的调用**在编译器看来真的可能发生**：条件用
// 运行时才知道的信息（这里用入口参数），编译器无法常量折叠，于是
// overlayMain 及其依赖（_OverlayApp 等）都会被完整保留。
import 'overlay_main.dart' as overlay_entry;

/// ★核心修复★：把 `overlayMain` **直接定义在 main.dart 里**。
///
/// flutter_overlay_window 的原生代码用
///   `DartEntrypoint(appBundlePath, "overlayMain")`
/// 来启动第二个引擎。这个“按名字查找”是在**入口库（应用的 main 库，即
/// package:vocab_overlay/main.dart）的顶层命名空间**里进行的。
///
/// 之前的写法把 `overlayMain` 定义在 `overlay_main.dart`，main.dart 只做：
///   * `import 'overlay_main.dart' as overlay_entry;`（带前缀，不是顶层成员）
///   * `export 'overlay_main.dart' show overlayMain;`（导出也不稳定命中）
/// 因而引擎在 main.dart 的顶层命名空间里找不到 `overlayMain`，报
///   `Could not resolve main entrypoint function`
/// 第二个引擎启动失败 → 悬浮窗永远是空的。
///
/// 直接在 main.dart 里声明一个同名的顶层函数（`@pragma("vm:entry-point")`），
/// 它就成了 main 库根命名空间的真实成员，按名字查找**必定命中**。实现委托给
/// overlay_main.dart 里的 `runOverlayApp`，不复制业务逻辑。
@pragma("vm:entry-point")
void overlayMain() => overlay_entry.runOverlayApp();

/// 是否需要在本次启动中运行“悬浮窗入口”。
///
/// 正常情况下永远为 false（悬浮窗入口由原生 OverlayService 在**另一个引擎**
/// 里按名字拉起）。但因为条件是运行时的、编译器无法判定，`overlayMain`
/// 会被完整编入快照，供原生 `DartEntrypoint` 解析。
bool get _shouldRunOverlayEntrypoint {
  // 只有显式以 `--overlay-entrypoint` 启动才会为 true；实际使用中不会出现。
  return Platform.executableArguments.contains('--overlay-entrypoint');
}

/// 是否为 Android（需要系统悬浮窗）。
bool get _isAndroid => !kIsWeb && Platform.isAndroid;

Future<void> main() async {
  // 运行时条件（永不为真），用于让编译器保留悬浮窗入口符号
  // （详见顶部 import 处注释）。
  if (_shouldRunOverlayEntrypoint) {
    overlayMain();
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  // 仅在桌面端初始化 window_manager；移动端不依赖它（见 OverlayService）。
  if (isDesktopPlatform()) {
    await WindowManager.instance.ensureInitialized();
  }
  await OverlayService.instance.initWindowForOverlay();
  runApp(const VocabOverlayApp());
}

class VocabOverlayApp extends StatelessWidget {
  const VocabOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '词汇悬浮卡',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        useMaterial3: true,
      ),
      // 不再篡改 MediaQuery 的尺寸 / devicePixelRatio。
      //
      // 早期版本把逻辑像素强行改成与物理像素 1:1，以便卡片坐标直接等于
      // 全局光标（物理像素）坐标。但那会让 MediaQuery.size 大于 Flutter
      // 实际渲染区域（View.physicalSize / devicePixelRatio），导致卡片被
      // 放到可视区之外、看起来“无法放到屏幕上的任意位置”。
      //
      // 现在词汇卡坐标统一使用「逻辑像素」（与窗口 / 渲染区域一致），
      // 需要和原生全局光标（物理像素）比较时，在 MainScreen 里通过
      // devicePixelRatio 换算即可。
      home: const AppRoot(),
    );
  }
}

/// 应用根节点：负责在主界面和设置界面之间切换，并处理持久化。
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final StorageService _storage = StorageService();

  List<VocabCard> _cards = <VocabCard>[];
  bool _showSettings = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadCards();
    if (_isAndroid) {
      // 监听悬浮窗引擎回传的卡片位置，实时保存。
      MobileController.instance.onCardsUpdated = _onOverlayCardsUpdated;
      // 悬浮窗引擎就绪（握手）→ 立刻回推当前卡片，消除启动时序丢包。
      MobileController.instance.onOverlayReady = _onOverlayReady;
      MobileController.instance.startListening();
      // 设置界面关闭时让悬浮窗恢复显示（具体状态在 _syncMobileOverlay 里同步）。
      SettingsScreen.onClosed = _syncMobileOverlay;
      // 主界面首次显示时，如果悬浮窗已经在显示（例如从后台切回来、
      // 或主界面被系统销毁后重建），让它重新显示卡片内容。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncMobileOverlay();
      });
    }
    // 首帧渲染后再次确认窗口铺满屏幕：
    // 初始化阶段的 setBounds 可能发生在窗口尚未显示 / 无边框切换之前，
    // 系统有机会把窗口“约束”回默认大小。这里在真正显示后再贴合一次，
    // 保证主界面 / 调整界面都能覆盖整块屏幕，卡片可放到任意位置。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OverlayService.instance.ensureCoverScreen();
    });
  }

  /// 移动端：让悬浮窗“显示 + 显示卡片 + 穿透”（仅在它已经存在时才做）。
  ///
  /// 主界面（本应用窗口）在悬浮窗之下，用户通常看到的是悬浮窗里的卡片。
  /// 因此从设置界面返回主界面时，必须把最新卡片推送给悬浮窗，否则看起来
  /// 就是“回到主界面后词汇卡不显示”。
  Future<void> _syncMobileOverlay() async {
    if (!_isAndroid) return;
    final showing = await MobileController.instance.isShowing();
    if (!showing) return;
    await MobileController.instance.setCardsVisible(true);
    await MobileController.instance.showCards(_cards);
  }

  Future<void> _loadCards() async {
    // 进入应用：根据存储内容将词汇卡生成在主界面上。
    final cards = await _storage.loadCards();
    setState(() {
      _cards = _migrateToLogicalCoords(cards);
      _loaded = true;
    });
  }

  /// 兼容旧版本保存的数据。
  ///
  /// 早期版本把卡片坐标按“物理像素”保存；现在统一使用逻辑像素。若加载到的
  /// 坐标明显超出当前逻辑屏幕（说明是旧物理像素数据），按 devicePixelRatio
  /// 等比缩小回落到逻辑坐标系，避免卡片跑到屏幕可视区之外。
  List<VocabCard> _migrateToLogicalCoords(List<VocabCard> cards) {
    // 空卡片（英文 / 中文都为空）只是占位，坐标没有意义，不参与判断，
    // 否则一张新建的空白卡片就可能把整批正常坐标误判成旧数据。
    final meaningful = cards
        .where((c) => c.english.isNotEmpty || c.chinese.isNotEmpty)
        .toList();
    if (meaningful.isEmpty) return cards;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return cards;
    final view = views.first;
    final dpr = view.devicePixelRatio;
    if (dpr <= 1.0) return cards;
    final logical = view.physicalSize / dpr;
    if (logical.width <= 0 || logical.height <= 0) return cards;

    // 只要有一张卡片的坐标超出逻辑屏幕，就认为整批是旧的物理像素数据。
    final anyOutOfBounds = meaningful.any(
      (c) => c.x > logical.width + 1 || c.y > logical.height + 1,
    );
    if (!anyOutOfBounds) return cards;

    return cards
        .map((c) => c.copyWith(x: c.x / dpr, y: c.y / dpr))
        .toList();
  }

  Future<void> _saveCards(List<VocabCard> cards) async {
    // 退出应用 / 应用时：记录词汇卡数量、位置、英文、中文。
    await _storage.saveCards(cards);
  }

  void _openSettings() {
    setState(() => _showSettings = true);
    // 移动端：隐藏悬浮窗里的卡片，避免与设置界面里的预览重复显示，
    // 也避免在推送数据用尽前出现尺寸 / 位置错位。
    if (_isAndroid) {
      MobileController.instance.setCardsVisible(false);
    }
  }

  Future<void> _backToMain() async {
    // 从设置界面返回主界面（不保存输入框内容，除非点了“应用”）。
    setState(() => _showSettings = false);
    await OverlayService.instance.setClickThrough(true);
    await OverlayService.instance.setAlwaysOnTop(true);
    // 移动端：让悬浮窗重新显示（内存里的 _cards 未变，直接推回去）。
    await _syncMobileOverlay();
  }

  /// 设置界面点“退出”：先保存当前输入的词汇卡，再退出应用。
  Future<void> _exitApp(List<VocabCard> cards) async {
    await _saveCards(cards);
    await OverlayService.instance.closeApp();
  }

  Future<void> _applyFromSettings(List<VocabCard> cards) async {
    // 应用：更新主界面卡片、保存，**立即**返回主界面。
    //
    // 注意：必须先把 _showSettings 置回 false，主界面才可能出现；
    // 且移动端后续的“显示悬浮窗 / 切后台”都要等界面切回来之后再执行，
    // 否则点击“应用”后界面会停在设置页（旧版本就是这样）。
    setState(() {
      _cards = cards;
      _showSettings = false;
    });
    await _saveCards(cards);

    // 让主界面先完成一帧渲染，再处理窗口 / 悬浮窗相关的异步操作。
    await WidgetsBinding.instance.endOfFrame;

    if (_isAndroid) {
      // 移动端：把卡片推送到系统悬浮窗（穿透模式），并切到后台，
      // 让悬浮窗显示在其他应用之上。
      await _applyMobileOverlay(cards);
      return;
    }

    await OverlayService.instance.setClickThrough(true);
    await OverlayService.instance.setAlwaysOnTop(true);
  }

  /// 移动端：申请权限 → 显示悬浮窗（穿透）→ 主应用移到后台。
  Future<void> _applyMobileOverlay(List<VocabCard> cards) async {
    debugPrint('[apply] cards=${cards.length}');
    final granted = await MobileController.instance.ensurePermission();
    debugPrint('[apply] permission granted=$granted');
    if (!granted) {
      // 未授权：留在主界面（用户可再次点“应用”），并给出提示。
      _showMessage('需要“显示在其他应用上层”权限才能显示悬浮卡');
      return;
    }
    // 先让悬浮窗可见，再推送最新卡片（推送失败也会在下次同步时补上）。
    try {
      await MobileController.instance.setCardsVisible(true);
      await MobileController.instance.showCards(cards);
      debugPrint('[apply] showCards done');
    } catch (e) {
      debugPrint('[apply] showCards error: $e');
    }
    if (!mounted) return;
    await MobileController.instance.moveToBackground();
    debugPrint('[apply] moveToBackground done');
  }

  /// 悬浮窗引擎回传卡片位置（拖动后）→ 保存并同步到内存。
  void _onOverlayCardsUpdated(List<VocabCard> cards) {
    if (cards.isEmpty) return;
    setState(() => _cards = cards);
    _saveCards(cards);
  }

  /// 悬浮窗引擎就绪（握手）→ 回推当前卡片。
  ///
  /// 若当前正处于设置界面，则暂不推送可见卡片（只同步数据、保持隐藏），
  /// 避免与设置界面里的预览重复显示。
  Future<void> _onOverlayReady() async {
    if (!_isAndroid) return;
    if (_showSettings) {
      // 设置界面打开中：只把数据送进去、保持隐藏。
      await MobileController.instance.updateCards(_cards, visible: false);
      return;
    }
    await MobileController.instance.showCards(_cards);
  }

  /// 浮动提示（主界面没有 Scaffold，这里自带 Overlay 以适配任意界面）。
  void _showMessage(String text) {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 24,
        right: 24,
        bottom: 80,
        child: IgnorePointer(
          child: Material(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 3), entry.remove);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const ColoredBox(color: Colors.transparent);
    }

    if (_showSettings) {
      return SettingsScreen(
        initialCards: _cards,
        onApply: _applyFromSettings,
        onBack: _backToMain,
        onExit: _exitApp,
      );
    }

    return MainScreen(
      cards: _cards,
      onOpenSettings: _openSettings,
    );
  }
}


