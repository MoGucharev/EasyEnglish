// ignore_for_file: deprecated_member_use

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/legacy.dart';

import 'models/vocab_card.dart';
import 'screens/main_screen.dart';
import 'screens/settings_screen.dart';
import 'services/overlay_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowManager.instance.ensureInitialized();
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
    // 首帧渲染后再次确认窗口铺满屏幕：
    // 初始化阶段的 setBounds 可能发生在窗口尚未显示 / 无边框切换之前，
    // 系统有机会把窗口“约束”回默认大小。这里在真正显示后再贴合一次，
    // 保证主界面 / 调整界面都能覆盖整块屏幕，卡片可放到任意位置。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OverlayService.instance.ensureCoverScreen();
    });
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
    if (cards.isEmpty) return cards;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return cards;
    final view = views.first;
    final dpr = view.devicePixelRatio;
    if (dpr <= 1.0) return cards;
    final logical = view.physicalSize / dpr;
    if (logical.width <= 0 || logical.height <= 0) return cards;

    // 只要有一张卡片的坐标超出逻辑屏幕，就认为整批是旧的物理像素数据。
    final anyOutOfBounds = cards.any(
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
  }

  Future<void> _backToMain() async {
    // 从设置界面返回主界面（不保存输入框内容，除非点了“应用”）。
    setState(() => _showSettings = false);
    await OverlayService.instance.setClickThrough(true);
    await OverlayService.instance.setAlwaysOnTop(true);
  }

  Future<void> _applyFromSettings(List<VocabCard> cards) async {
    // 应用：更新主界面卡片、保存，返回主界面。
    setState(() {
      _cards = cards;
      _showSettings = false;
    });
    await _saveCards(cards);
    await OverlayService.instance.setClickThrough(true);
    await OverlayService.instance.setAlwaysOnTop(true);
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
      );
    }

    return MainScreen(
      cards: _cards,
      onOpenSettings: _openSettings,
    );
  }
}


