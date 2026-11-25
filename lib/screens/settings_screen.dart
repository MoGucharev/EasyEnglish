import 'package:material_ui/material_ui.dart';

import '../models/card_style.dart';
import '../models/vocab_card.dart';
import '../services/overlay_service.dart';
import '../widgets/color_wheel_picker.dart';
import '../widgets/vocab_card_view.dart';
import 'adjust_screen.dart';

/// 设置界面：
///  * 进入时先清空所有输入卡片；
///  * 根据已有词汇卡数量与内容，重建对应数量的输入卡片并填入内容；
///  * “样式”：切换词汇卡整体外观（有边框 / 无边框仅字体）；
///  * “创建词汇”：新增一张空的输入卡片；
///  * 每张输入卡片可单独设置“字体颜色”（RGB + 透明度圆盘）与“字体大小”；
///  * “调整词汇位置”（位于“应用”之上）：进入调整界面；
///  * “应用”：把输入卡片内容提交为新词汇卡列表，返回主界面。
class SettingsScreen extends StatefulWidget {
  /// 设置界面关闭时的回调（移动端用于让悬浮窗恢复显示）。
  static VoidCallback? onClosed;

  /// 进入设置时的初始词汇卡（主界面当前显示的内容）。
  final List<VocabCard> initialCards;

  /// 进入设置时当前的词汇卡整体样式。
  final CardStyle initialStyle;

  /// 点击“应用”：提交卡片与当前样式。
  final void Function(List<VocabCard> cards, CardStyle style) onApply;

  final VoidCallback onBack;

  /// 点击右下角“退出”按钮时调用（保存后退出应用），参数为当前输入内容与样式。
  final void Function(List<VocabCard> cards, CardStyle style)? onExit;

  const SettingsScreen({
    super.key,
    required this.initialCards,
    required this.onApply,
    required this.onBack,
    this.initialStyle = CardStyle.bordered,
    this.onExit,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// 每张卡片对应一组输入控制器。base 用于保存位置 / 尺寸等元信息。
  final List<_CardEntry> _entries = [];

  final ScrollController _scrollController = ScrollController();

  /// 当前词汇卡整体样式。
  late CardStyle _style;

  @override
  void initState() {
    super.initState();
    _style = widget.initialStyle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 设置界面需要正常交互：关闭穿透、取消置顶。
      OverlayService.instance.setClickThrough(false);
      OverlayService.instance.setAlwaysOnTop(false);
    });
    _rebuildFromCards(widget.initialCards);
  }

  void _rebuildFromCards(List<VocabCard> cards) {
    // 先删除所有输入卡片（释放旧的控制器）。
    for (final e in _entries) {
      e.dispose();
    }
    _entries.clear();

    // 根据词汇卡数量、英文、中文，重建输入卡片并填入。
    for (final c in cards) {
      _entries.add(_CardEntry.fromCard(c));
    }
    setState(() {});
  }

  void _addCard() {
    // 新建卡片给一个默认错开的初始位置。
    final index = _entries.length;
    final offset = 40.0 * index;
    final card = VocabCard(
      english: '',
      chinese: '',
      x: 60 + (offset % 400),
      y: 80 + (offset % 300),
    );
    setState(() => _entries.add(_CardEntry.fromCard(card)));
    // 滚动到底部展示新卡片。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 把当前输入内容收集成词汇卡列表。
  List<VocabCard> _collectCards() {
    return _entries.map((e) {
      return e.base.copyWith(
        english: e.englishController.text.trim(),
        chinese: e.chineseController.text.trim(),
        fontColor: e.fontColor,
        fontSize: e.fontSize,
      );
    }).toList();
  }

  Future<void> _openAdjust() async {
    // 进入调整界面前先提交当前输入内容，让调整界面显示最新文字。
    final cards = _collectCards();

    final result = await Navigator.of(context).push<List<VocabCard>>(
      MaterialPageRoute(
        builder: (_) => AdjustScreen(initialCards: cards, style: _style),
        fullscreenDialog: true,
      ),
    );

    // 调整完成后：回到设置界面并保持正常交互。
    await OverlayService.instance.setClickThrough(false);
    await OverlayService.instance.setAlwaysOnTop(false);

    if (result != null) {
      // “完成”：用调整后的位置更新输入卡片（保留输入框文字与样式）。
      _applyAdjustedPositions(result);
    }
    // result 为 null 表示“上一步”（取消调整），无需改动。
  }

  void _applyAdjustedPositions(List<VocabCard> adjusted) {
    // 调整界面里的卡片顺序与 _entries 一致（由 _collectCards 生成）。
    for (var i = 0; i < _entries.length && i < adjusted.length; i++) {
      _entries[i].base = _entries[i].base.copyWith(
        x: adjusted[i].x,
        y: adjusted[i].y,
        width: adjusted[i].width,
        height: adjusted[i].height,
      );
    }
    setState(() {});
  }

  void _apply() {
    // 立即收起键盘：避免输入法窗口在“返回主界面”时干扰界面切换。
    FocusManager.instance.primaryFocus?.unfocus();
    final cards = _collectCards();
    widget.onApply(cards, _style);
  }

  void _exit() {
    // 退出前先收集当前输入内容，交给外部先保存再退出。
    final cards = _collectCards();
    final onExit = widget.onExit;
    if (onExit != null) {
      onExit(cards, _style);
      return;
    }
    // 未提供退出回调时，直接关闭应用。
    OverlayService.instance.closeApp();
  }

  @override
  void dispose() {
    // 设置界面关闭：让悬浮窗恢复显示卡片（移动端）。
    SettingsScreen.onClosed?.call();
    for (final e in _entries) {
      e.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F6F8),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildToolbar(),
            _buildStyleSelector(),
            const Divider(height: 1),
            Expanded(
              child: _entries.isEmpty
                  ? _buildEmpty()
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _buildInputCard(index),
                    ),
            ),
            // “调整词汇位置”按钮位于右下角“应用”之上。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openAdjust,
                  icon: const Icon(Icons.open_with),
                  label: const Text('调整词汇位置'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.check),
                  label: const Text('应用'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            // “退出”按钮位于“应用”下方：保存后退出应用。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _exit,
                  icon: const Icon(Icons.exit_to_app, color: Colors.red),
                  label: const Text('退出', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
            tooltip: '返回',
          ),
          const Text(
            '设置',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          FilledButton.tonalIcon(
            onPressed: _addCard,
            icon: const Icon(Icons.add),
            label: const Text('创建词汇'),
          ),
          const SizedBox(width: 12),
          Text(
            '共 ${_entries.length} 张',
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  /// “样式”选项：切换全部词汇卡的外观（有边框 / 无边框仅字体）。
  Widget _buildStyleSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.palette_outlined, size: 18, color: Colors.black54),
          const SizedBox(width: 6),
          const Text(
            '样式',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SegmentedButton<CardStyle>(
              segments: const [
                ButtonSegment<CardStyle>(
                  value: CardStyle.borderless,
                  label: Text('无边框'),
                  icon: Icon(Icons.text_fields, size: 16),
                ),
                ButtonSegment<CardStyle>(
                  value: CardStyle.bordered,
                  label: Text('有边框'),
                  icon: Icon(Icons.crop_square, size: 16),
                ),
              ],
              selected: {_style},
              showSelectedIcon: false,
              onSelectionChanged: (sel) {
                if (sel.isEmpty) return;
                setState(() => _style = sel.first);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.style_outlined, size: 64, color: Colors.black26),
          SizedBox(height: 12),
          Text(
            '还没有词汇卡\n点击“创建词汇”开始添加',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black45, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard(int index) {
    final entry = _entries[index];
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '删除此卡',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      _entries.removeAt(index).dispose();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(
                  width: 84,
                  child: Text('请输入英语', style: TextStyle(fontSize: 14)),
                ),
                Expanded(
                  child: TextField(
                    controller: entry.englishController,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'English',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 84,
                  child: Text('请输入中文', style: TextStyle(fontSize: 14)),
                ),
                Expanded(
                  child: TextField(
                    controller: entry.chineseController,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '中文',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 字体颜色 + 字体大小。
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 84,
                      child: Text('字体颜色', style: TextStyle(fontSize: 14)),
                    ),
                    _ColorSwatchButton(
                      color: entry.fontColor,
                      onPressed: () => _openColorPicker(index),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('字体大小', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 76,
                      child: TextField(
                        controller: entry.fontSizeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          hintText: '${VocabCard.defaultFontSize.round()}',
                        ),
                        onChanged: (value) {
                          final parsed = double.tryParse(value.trim());
                          if (parsed == null) return;
                          entry.fontSize = parsed
                              .clamp(
                                VocabCard.minFontSize,
                                VocabCard.maxFontSize,
                              )
                              .toDouble();
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 预览当前卡片效果。
            Align(
              alignment: Alignment.centerLeft,
              child: _PreviewChip(entry: entry, style: _style),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开色盘对话框，调整此卡片对应词汇卡的字体颜色。
  Future<void> _openColorPicker(int index) async {
    final entry = _entries[index];
    // 打开前记录原颜色，取消时回滚。
    final original = entry.fontColor;
    var picked = original;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('字体颜色'),
          content: SingleChildScrollView(
            child: ColorWheelPicker(
              initialColor: original,
              size: 220,
              onChanged: (color) {
                picked = color;
                setState(() => entry.fontColor = color);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      // 取消：恢复到打开色盘前的颜色。
      setState(() => entry.fontColor = original);
    } else {
      setState(() => entry.fontColor = picked);
    }
  }
}

/// 显示当前颜色的方形色块按钮（点开色盘）。
class _ColorSwatchButton extends StatelessWidget {
  final Color color;
  final VoidCallback onPressed;

  const _ColorSwatchButton({required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black26),
          // 棋盘格底，便于观察透明度。
          color: Colors.white,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: color,
            alignment: Alignment.center,
            child: const Icon(Icons.colorize, size: 16, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  final _CardEntry entry;
  final CardStyle style;

  const _PreviewChip({required this.entry, required this.style});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: entry.englishController,
      builder: (context, enVal, _) {
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: entry.chineseController,
          builder: (context, zhVal, _) {
            final preview = entry.base.copyWith(
              english: enVal.text.trim(),
              chinese: zhVal.text.trim(),
              fontColor: entry.fontColor,
              fontSize: entry.fontSize,
            );
            return Container(
              decoration: BoxDecoration(
                // 预览时铺一层深色底，保证浅色 / 半透明字体也看得清。
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(14),
              ),
              child: VocabCardView(card: preview, style: style),
            );
          },
        );
      },
    );
  }
}

/// 单张输入卡片的状态封装。
class _CardEntry {
  VocabCard base; // 保存位置 / 尺寸等元信息
  final TextEditingController englishController;
  final TextEditingController chineseController;

  /// “字体大小”输入框的控制器。
  final TextEditingController fontSizeController;

  /// 字体颜色（含透明度）。
  Color fontColor;

  /// 字体大小（英文基础字号）。
  double fontSize;

  _CardEntry({
    required this.base,
    required this.englishController,
    required this.chineseController,
    required this.fontSizeController,
    required this.fontColor,
    required this.fontSize,
  });

  factory _CardEntry.fromCard(VocabCard card) {
    return _CardEntry(
      base: card,
      englishController: TextEditingController(text: card.english),
      chineseController: TextEditingController(text: card.chinese),
      // 输入框里预填当前字号（新卡片为默认值）。
      fontSizeController: TextEditingController(
        text: _formatFontSize(card.fontSize),
      ),
      fontColor: card.fontColor,
      fontSize: card.fontSize,
    );
  }

  static String _formatFontSize(double value) {
    // 整数不显示小数位，其余保留一位，便于阅读。
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  void dispose() {
    englishController.dispose();
    chineseController.dispose();
    fontSizeController.dispose();
  }
}
