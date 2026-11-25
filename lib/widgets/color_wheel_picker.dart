import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// RGB + 透明度圆盘取色器。
///
/// 交互模型（不依赖任何第三方依赖）：
///  * 外圈：色相环（Hue，0~360°），点击 / 拖动选择色相；
///  * 内圆：饱和度 × 明度三角（Saturation / Value），点击 / 拖动选择具体颜色；
///  * 底部：透明度（Alpha）滑条，控制颜色的不透明度。
///
/// 结果通过 `HSVColor.toColor()` 得到 ARGB 颜色（含 Alpha），
/// 即“RGB 外加透明度”。
class ColorWheelPicker extends StatefulWidget {
  /// 初始颜色。
  final Color initialColor;

  /// 颜色变化回调（拖动过程中持续触发）。
  final ValueChanged<Color> onChanged;

  /// 圆盘整体尺寸。
  final double size;

  const ColorWheelPicker({
    super.key,
    required this.initialColor,
    required this.onChanged,
    this.size = 200,
  });

  @override
  State<ColorWheelPicker> createState() => _ColorWheelPickerState();
}

class _ColorWheelPickerState extends State<ColorWheelPicker> {
  late HSVColor _hsv;

  /// 透明度单独保存，避免在“色相 / 饱和度均为 0”时丢失用户选择的 Alpha。
  late double _alpha;

  @override
  void initState() {
    super.initState();
    final color = widget.initialColor;
    _hsv = HSVColor.fromColor(
      Color.from(alpha: 1, red: color.r, green: color.g, blue: color.b),
    );
    _alpha = color.a;
  }

  Color get _currentColor {
    final c = _hsv.toColor();
    return c.withValues(alpha: _alpha);
  }

  void _emit() => widget.onChanged(_currentColor);

  /// 处理色环选择：根据点击位置相对圆心的角度得到色相。
  ///
  /// 只有点在外圈色环上才生效（内圈归饱和度 / 明度三角处理）。
  void _handleHue(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final v = localPosition - center;
    final distance = v.distance;
    final outerRadius = widget.size / 2;
    final ringWidth = widget.size * 0.14;
    // 内圈：不处理（交给三角）。
    if (distance < outerRadius - ringWidth) return;
    // atan2 返回弧度，转换为角度并归一化到 0~360。
    final angle = math.atan2(v.dy, v.dx) * 180 / math.pi;
    final hue = (angle + 360) % 360;
    setState(() => _hsv = _hsv.withHue(hue));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final outerRadius = size / 2;
    // 色环厚度。
    final ringWidth = size * 0.14;
    // 内三角外接圆半径（略小于色环内边界）。
    final triangleRadius = outerRadius - ringWidth - 6;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 色相环：本身用 SweepGradient 绘制，外围用 GestureDetector 捕获
              // 指针位置，避免自定义排布。
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (d) => _handleHue(d.localPosition),
                  onPanUpdate: (d) => _handleHue(d.localPosition),
                  child: CustomPaint(
                    painter: _HueRingPainter(
                      ringWidth: ringWidth,
                      selectedHue: _hsv.hue,
                    ),
                  ),
                ),
              ),
              // 内部饱和度 / 明度三角。
              Transform.translate(
                // 三角整体下移一点，让重心居中。
                offset: const Offset(0, 0),
                child: _SvTriangle(
                  radius: triangleRadius,
                  hsv: _hsv,
                  onChanged: (s, v) {
                    setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
                    _emit();
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 透明度滑条。
        Row(
          children: [
            const SizedBox(
              width: 44,
              child: Text('透明度', style: TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: SizedBox(
                height: 28,
                child: _AlphaSlider(
                  alpha: _alpha,
                  hue: _hsv.hue,
                  saturation: _hsv.saturation,
                  value: _hsv.value,
                  onChanged: (a) {
                    setState(() => _alpha = a);
                    _emit();
                  },
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${(_alpha * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 当前颜色预览。
        Row(
          children: [
            const SizedBox(
              width: 44,
              child: Text('预览', style: TextStyle(fontSize: 12)),
            ),
            Container(
              width: 60,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black26),
                // 棋盘格底，便于观察透明度。
                color: Colors.white,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(color: _currentColor),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _hexLabel(_currentColor),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
      ],
    );
  }

  static String _hexLabel(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    final a = (c.a * 255).round();
    String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${h(a)}${h(r)}${h(g)}${h(b)}';
  }
}

/// 色相环绘制：SweepGradient 圆环 + 当前色相指示点。
class _HueRingPainter extends CustomPainter {
  final double ringWidth;
  final double selectedHue;

  _HueRingPainter({required this.ringWidth, required this.selectedHue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 圆环本体：用不同半径的两个圆做差集，并把 SweepGradient 填进圆环。
    final ringRect = Rect.fromCircle(center: center, radius: radius - 0);
    final innerRect = Rect.fromCircle(
      center: center,
      radius: radius - ringWidth,
    );

    final gradient = SweepGradient(
      colors: [
        for (var h = 0; h <= 360; h += 60)
          HSVColor.fromAHSV(
            1,
            h % 360 == 360 ? 359.9 : h.toDouble(),
            1,
            1,
          ).toColor(),
      ],
    );

    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addOval(ringRect),
        Path()..addOval(innerRect),
      ),
    );
    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    canvas.drawCircle(center, radius, paint);
    canvas.restore();

    // 选中色相的指示点。
    final angle = selectedHue * math.pi / 180;
    final pointRadius = radius - ringWidth / 2;
    final indicator =
        center +
        Offset(math.cos(angle) * pointRadius, math.sin(angle) * pointRadius);
    canvas.drawCircle(
      indicator,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      indicator,
      4,
      Paint()..color = HSVColor.fromAHSV(1, selectedHue, 1, 1).toColor(),
    );
  }

  @override
  bool shouldRepaint(covariant _HueRingPainter oldDelegate) =>
      oldDelegate.selectedHue != selectedHue ||
      oldDelegate.ringWidth != ringWidth;
}

/// 饱和度 / 明度三角。
///
/// 三角形三个顶点：
///  * 顶部：饱和度为 0、明度为 1（白色方向）；
///  * 右下：饱和度为 1、明度为 1（纯色）；
///  * 左下：明度为 0（黑色）。
class _SvTriangle extends StatelessWidget {
  final double radius;
  final HSVColor hsv;
  final void Function(double saturation, double value) onChanged;

  const _SvTriangle({
    required this.radius,
    required this.hsv,
    required this.onChanged,
  });

  /// 三个顶点的位置（相对圆心）。
  static const double _sqrt3 = 1.7320508075688772;

  List<Offset> _vertices() {
    // 等边三角形，顶部顶点朝上。
    final top = Offset(0, -radius);
    final bottomRight = Offset(radius * _sqrt3 / 2, radius / 2);
    final bottomLeft = Offset(-radius * _sqrt3 / 2, radius / 2);
    return [top, bottomRight, bottomLeft];
  }

  /// 把三角形内的点映射为 (saturation, value)。
  ///
  /// 用重心坐标反解；若点在三角形外则夹到边界。
  (double, double) _svFromLocal(Offset p) {
    final v = _vertices();
    // 重心坐标 (a, b, c) 分别对应 顶 / 右下 / 左下。
    final p0 = v[0];
    final p1 = v[1];
    final p2 = v[2];
    final denom =
        (p1.dy - p2.dy) * (p0.dx - p2.dx) + (p2.dx - p1.dx) * (p0.dy - p2.dy);
    var a =
        ((p1.dy - p2.dy) * (p.dx - p2.dx) + (p2.dx - p1.dx) * (p.dy - p2.dy)) /
        denom;
    var b =
        ((p2.dy - p0.dy) * (p.dx - p2.dx) + (p0.dx - p2.dx) * (p.dy - p2.dy)) /
        denom;
    var c = 1 - a - b;

    // 夹到三角形内部（负值统一夹 0，然后重新归一化）。
    a = a.clamp(0.0, 1.0);
    b = b.clamp(0.0, 1.0);
    c = c.clamp(0.0, 1.0);
    final sum = a + b + c;
    if (sum <= 0) return (0, 1);
    a /= sum;
    b /= sum;

    // value = a + b（顶与右下都是明度 1，左下是 0）。
    final value = (a + b).clamp(0.0, 1.0);
    // saturation = b / (a + b)（白点饱和度为 0，纯色点为 1）。
    final saturation = (a + b) <= 1e-6 ? 0.0 : (b / (a + b)).clamp(0.0, 1.0);
    return (saturation, value);
  }

  @override
  Widget build(BuildContext context) {
    final vertices = _vertices();
    final size = radius * 2 + 4;
    final center = size / 2;
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();

    // 当前选中点在三角形里的位置。
    final sv = hsv.withSaturation(hsv.saturation).withValue(hsv.value);
    final selS = sv.saturation;
    final selV = sv.value;
    // 由 (s, v) 反推重心坐标并计算位置。
    final b = selS * selV;
    final a = selV - b;
    final c = 1 - a - b;
    final selected = Offset(
      vertices[0].dx * a + vertices[1].dx * b + vertices[2].dx * c + center,
      vertices[0].dy * a + vertices[1].dy * b + vertices[2].dy * c + center,
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) {
                final local = d.localPosition - Offset(center, center);
                final (s, v) = _svFromLocal(local);
                onChanged(s, v);
              },
              onPanUpdate: (d) {
                final local = d.localPosition - Offset(center, center);
                final (s, v) = _svFromLocal(local);
                onChanged(s, v);
              },
              child: CustomPaint(
                painter: _SvTrianglePainter(
                  center: Offset(center, center),
                  vertices: vertices,
                  hueColor: hueColor,
                  selected: selected,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SvTrianglePainter extends CustomPainter {
  final Offset center;
  final List<Offset> vertices;
  final Color hueColor;
  final Offset selected;

  _SvTrianglePainter({
    required this.center,
    required this.vertices,
    required this.hueColor,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(vertices[0].dx + center.dx, vertices[0].dy + center.dy)
      ..lineTo(vertices[1].dx + center.dx, vertices[1].dy + center.dy)
      ..lineTo(vertices[2].dx + center.dx, vertices[2].dy + center.dy)
      ..close();

    // 底色：纯色（饱和度 1、明度 1）。
    canvas.drawPath(path, Paint()..color = hueColor);

    // 叠加白色渐变（顶部白 → 透明），实现“饱和度 0”。
    final whiteGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white, Colors.white.withValues(alpha: 0)],
    );
    canvas.save();
    canvas.clipPath(path);
    final rect = path.getBounds();
    canvas.drawRect(rect, Paint()..shader = whiteGradient.createShader(rect));
    // 叠加黑色渐变（底部黑 → 透明），实现“明度 0”。
    final blackGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.black.withValues(alpha: 0), Colors.black],
    );
    canvas.drawRect(rect, Paint()..shader = blackGradient.createShader(rect));
    canvas.restore();

    // 三角形边框。
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 选中点。
    canvas.drawCircle(
      selected,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(selected, 4, Paint()..color = Colors.black26);
  }

  @override
  bool shouldRepaint(covariant _SvTrianglePainter oldDelegate) =>
      oldDelegate.hueColor != hueColor ||
      oldDelegate.selected != selected ||
      oldDelegate.vertices != vertices;
}

/// 透明度滑条：从透明到不透明的当前颜色渐变。
class _AlphaSlider extends StatelessWidget {
  final double alpha;
  final double hue;
  final double saturation;
  final double value;
  final ValueChanged<double> onChanged;

  const _AlphaSlider({
    required this.alpha,
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final base = HSVColor.fromAHSV(1, hue, saturation, value).toColor();

    void update(double dx, double width) {
      if (width <= 0) return;
      onChanged((dx / width).clamp(0.0, 1.0));
    }

    // 注意：这里**不能**用 LayoutBuilder。
    //
    // AlertDialog 会把 content 包进 IntrinsicWidth（按 intrinsic width 布局），
    // 而 LayoutBuilder 不支持返回 intrinsic 尺寸，会抛：
    //   “LayoutBuilder does not support returning intrinsic dimensions.”
    // 该异常发生在 performLayout 阶段，导致整个对话框布局失败——结果就是
    // 只看到模态遮罩（屏幕整体变灰），圆盘和滑条一个都显示不出来。
    //
    // 因此改用 Builder：在手势回调里读取实际渲染宽度（手势发生在布局之后，
    // 此时 context.size 一定可用）；滑块的横向位置用 Align 的比例对齐表示
    // （无需在 build 期知道像素宽度），全程不请求 intrinsic 尺寸。
    return Builder(
      builder: (context) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) =>
              update(d.localPosition.dx, context.size?.width ?? 0),
          onPanUpdate: (d) =>
              update(d.localPosition.dx, context.size?.width ?? 0),
          child: Stack(
            children: [
              // 棋盘格（体现透明度）。
              Positioned.fill(
                top: 8,
                bottom: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CustomPaint(painter: _CheckerPainter()),
                ),
              ),
              // 渐变条。
              Positioned.fill(
                top: 8,
                bottom: 8,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black26),
                    gradient: LinearGradient(
                      colors: [
                        base.withValues(alpha: 0),
                        base.withValues(alpha: 1),
                      ],
                    ),
                  ),
                ),
              ),
              // 滑块：用比例对齐定位，避免在布局期依赖具体像素宽度。
              Align(
                alignment: Alignment(alpha * 2 - 1, 0),
                child: Container(
                  width: 14,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.black38),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final light = Paint()..color = Colors.white;
    final dark = Paint()..color = const Color(0xFFDDDDDD);
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final isEven = ((x / cell).floor() + (y / cell).floor()) % 2 == 0;
        if (isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) => false;
}
