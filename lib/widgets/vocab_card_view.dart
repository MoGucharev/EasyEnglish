import 'package:material_ui/material_ui.dart';

import '../models/vocab_card.dart';

/// 词汇卡样式组件：上方英文，下方中文。
///
/// 外观为「透明背景 + 黑色边框」：背景完全透明，仅保留一圈描边，
/// 不遮挡下层应用；文字使用浅色并带描边阴影，保证在各种背景上都清晰可读。
///
/// [highlight] 用于调整界面中给出“可拖动”的视觉提示（更亮的边框与描边）。
/// [overlay] 可叠加一层子组件（例如拖动处理层）。
class VocabCardView extends StatelessWidget {
  final VocabCard card;
  final bool highlight;
  final Widget? overlay;

  const VocabCardView({
    super.key,
    required this.card,
    this.highlight = false,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    // 描边颜色：平时为黑色；调整界面高亮时用更亮的强调色，方便识别。
    final borderColor = highlight
        ? const Color(0xFF1E88E5)
        : Colors.black.withValues(alpha: 0.85);

    return Container(
      width: card.width,
      height: card.height,
      decoration: BoxDecoration(
        // 透明背景：不填充，只保留黑框。
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: highlight ? 2.0 : 1.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                card.english,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  // 文字描边阴影：透明背景下保证可读。
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 3),
                    Shadow(color: Colors.black, blurRadius: 3),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 1,
                color: Colors.white70,
              ),
              const SizedBox(height: 4),
              Text(
                card.chinese,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 3),
                    Shadow(color: Colors.black, blurRadius: 3),
                  ],
                ),
              ),
            ],
          ),
          if (overlay != null) Positioned.fill(child: overlay!),
        ],
      ),
    );
  }
}
