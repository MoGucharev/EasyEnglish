import 'package:material_ui/material_ui.dart';

import '../models/vocab_card.dart';
import '../services/overlay_service.dart';
import '../widgets/vocab_card_view.dart';
import 'adjust_screen.dart';

/// 设置界面：
///  * 进入时先清空所有输入卡片；
///  * 根据已有词汇卡数量与内容，重建对应数量的输入卡片并填入内容；
///  * “创建词汇”：新增一张空的输入卡片；
///  * “调整词汇位置”（位于“应用”之上）：进入调整界面；
///  * “应用”：把输入卡片内容提交为新词汇卡列表，返回主界面。
class SettingsScreen extends StatefulWidget {
  /// 进入设置时的初始词汇卡（主界面当前显示的内容）。
  final List<VocabCard> initialCards;

  final void Function(List<VocabCard> cards) onApply;
  final VoidCallback onBack;

  /// 点击右下角“退出”按钮时调用（保存后退出应用），参数为当前输入内容。
  final void Function(List<VocabCard> cards)? onExit;

  const SettingsScreen({
    super.key,
    required this.initialCards,
    required this.onApply,
    required this.onBack,
    this.onExit,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// 每张卡片对应一组输入控制器。base 用于保存位置 / 尺寸等元信息。
  final List<_CardEntry> _entries = [];

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
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

    // 根据词汇卡数量、英文、中文重建输入卡片并填入。
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
      );
    }).toList();
  }

  Future<void> _openAdjust() async {
    // 进入调整界面前先提交当前输入内容，让调整界面显示最新文字。
    final cards = _collectCards();

    final result = await Navigator.of(context).push<List<VocabCard>>(
      MaterialPageRoute(
        builder: (_) => AdjustScreen(initialCards: cards),
        fullscreenDialog: true,
      ),
    );

    // 调整完成后：回到设置界面并保持正常交互。
    await OverlayService.instance.setClickThrough(false);
    await OverlayService.instance.setAlwaysOnTop(false);

    if (result != null) {
      // “完成”：用调整后的位置更新输入卡片（保留输入框文字）。
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
    final cards = _collectCards();
    widget.onApply(cards);
  }

  void _exit() {
    // 退出前先收集当前输入内容，交给外部先保存再退出。
    final cards = _collectCards();
    final onExit = widget.onExit;
    if (onExit != null) {
      onExit(cards);
      return;
    }
    // 未提供退出回调时，直接关闭应用。
    OverlayService.instance.closeApp();
  }

  @override
  void dispose() {
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
            // 预览当前卡片效果。
            Align(
              alignment: Alignment.centerLeft,
              child: _PreviewChip(entry: entry),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  final _CardEntry entry;

  const _PreviewChip({required this.entry});

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
            );
            return Opacity(
              opacity: 0.9,
              child: VocabCardView(card: preview),
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

  _CardEntry({
    required this.base,
    required this.englishController,
    required this.chineseController,
  });

  factory _CardEntry.fromCard(VocabCard card) {
    return _CardEntry(
      base: card,
      englishController: TextEditingController(text: card.english),
      chineseController: TextEditingController(text: card.chinese),
    );
  }

  void dispose() {
    englishController.dispose();
    chineseController.dispose();
  }
}
