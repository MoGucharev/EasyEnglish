import 'package:material_ui/material_ui.dart';

import '../models/card_style.dart';
import '../models/vocab_card.dart';

/// 词汇卡样式组件：上方英文，下方中文。
///
/// 两种外观（由 [style] 决定）：
///  * [CardStyle.bordered]：透明背景 + 黑色圆角边框（只保留一圈描边，不遮挡
///    下层应用）；
///  * [CardStyle.borderless]：只有字体，无边框无背景。
///
/// 文字颜色取自卡片的 [VocabCard.fontColor]（可含透明度），
/// 字号取自 [VocabCard.fontSize]；并带描边阴影，保证在各种背景上都清晰可读。
///
/// [highlight] 用于调整界面中给出“可拖动”的视觉提示（更亮的边框与描边）。
/// [overlay] 可叠加一层子组件（例如拖动处理层）。
class VocabCardView extends StatelessWidget {
  final VocabCard card;
  final CardStyle style;
  final bool highlight;
  final Widget? overlay;

  const VocabCardView({
    super.key,
    required this.card,
    this.style = CardStyle.bordered,
    this.highlight = false,
    this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    // 描边颜色：平时为黑色；调整界面高亮时用更亮的强调色，方便识别。
    final borderColor = highlight
        ? const Color(0xFF1E88E5)
        : Colors.black.withValues(alpha: 0.85);

    final showBorder = style == CardStyle.bordered;

    // 文字描边阴影：透明背景下保证可读。
    final textShadows = <Shadow>[
      const Shadow(color: Colors.black, blurRadius: 3),
      const Shadow(color: Colors.black, blurRadius: 3),
    ];

    final textColor = card.fontColor;

    return Container(
      width: card.width,
      height: card.height,
      decoration: showBorder
          ? BoxDecoration(
              // 透明背景：不填充，只保留描边。
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: highlight ? 2.0 : 1.5,
              ),
            )
          // 无边框样式：只有字体，不画任何背景 / 边框。
          : null,
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
                style: TextStyle(
                  fontSize: card.fontSize,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  shadows: textShadows,
                ),
              ),
              const SizedBox(height: 4),
              if (showBorder) ...[
                Container(height: 1, color: Colors.white70),
                const SizedBox(height: 4),
              ],
              Text(
                card.chinese,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: card.chineseFontSize,
                  color: textColor,
                  shadows: textShadows,
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
