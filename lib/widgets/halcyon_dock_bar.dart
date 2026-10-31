// Halcyon 液态玻璃悬浮底栏（Flutter 移植版）。
// 蓝本：Halcyon (Kotlin Compose) ui/components/FloatingBottomBar.kt +
// ui/animation/DampedDragAnimation.kt 的可见行为子集（行号见注释）：
//   - 玻璃面板：BackdropFilter 模糊 + 半透明底 + 内缘高光（Compose 端的
//     lens 折射/陀螺仪光源 Flutter 无对应 shader 管线，用高光描边 + pill
//     顶部光泽渐变近似；玻璃色参数照抄 GlassPill.kt:38-45 LiquidGlass 档）。
//   - pill 指示器：primary 15% 实底（FloatingBottomBar.kt:569 accent 0.15），
//     拖动跟手、松手 spring 回弹（同文件 328：dampingRatio 1 / stiffness 300）。
//   - 拖动滑切：手指横向拖动连续扫过 tab（DampedDragAnimation 语义），
//     位移超 touchSlop 且落点 tab 变化才提交切换（同文件 322）。
//   - 橡皮筋：拖动面板整体位移 ≤4dp EaseOut（同文件 279-289、345）。
//   - 按压形变：面板 scale 1→1+16dp/width（同文件 444）、pill 速度拉伸
//     （同文件 537-539：横向 /(1-0.75v)、纵向 ×(1-0.25v)，clamp ±0.2）。
// 与 MD3Music 的融合边界：导航提交/震动/TV 焦点包装/labelBehavior 三档
// 由调用方（responsive_layout）注入，本组件只管视觉与手势。
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart'
    show SpringDescription, SpringSimulation;

/// 底栏玻璃配色（GlassPill.kt:38-45 LiquidGlass 档：亮 white@0.34 / 暗 #111114@0.38）。
const double kHalcyonDockLightAlpha = 0.34;
const double kHalcyonDockDarkAlpha = 0.38;
const Color kHalcyonDockDarkTint = Color(0xFF111114);

/// pill 指示器底色 alpha（FloatingBottomBar.kt:569 accent 0.15）。
const double kHalcyonDockPillAlpha = 0.15;

/// 橡皮筋最大位移（同上 279 rubberBandPx = 4.dp）。
const double kHalcyonDockRubberBandDp = 4.0;

/// 按压时面板膨胀的等效值（同上 444：1 + 16.dp/width）。
const double kHalcyonDockPressBulgeDp = 16.0;

/// pill/面板回弹弹簧（同上 328 spring(1f, 300f, 0.5f)）。
const double kHalcyonDockSpringDampingRatio = 1.0;
const double kHalcyonDockSpringStiffness = 300.0;

/// pill 高 56 = 面板 64 - 上下 4 padding（同上 465-466、502）。
const double kHalcyonDockPanelHeightDp = 64.0;
const double kHalcyonDockEdgeInsetDp = 4.0;

double _easeOut(double t) {
  final double c = t.clamp(0.0, 1.0);
  return 1.0 - (1.0 - c) * (1.0 - c);
}

/// 标签显隐三档（对应 MD3 NavigationDestinationLabelBehavior）。
enum HalcyonDockLabelMode { none, activeOnly, always }

/// Halcyon 风格悬浮玻璃底栏：拖动滑切 + pill 指示器 + 按压/速度形变。
///
/// [itemBuilder] 返回每个 tab 的内容（图标/文字由调用方组装，便于挂
/// TV 焦点包装与 _CapsuleBounce 回弹）；[onItemTap] 在点击/拖动提交时
/// 回调目标 index。
class HalcyonDockBar extends StatefulWidget {
  const HalcyonDockBar({
    super.key,
    required this.selectedIndex,
    required this.tabCount,
    required this.itemBuilder,
    required this.onItemTap,
    this.height = kHalcyonDockPanelHeightDp,
    this.labelMode = HalcyonDockLabelMode.none,
  });

  final int selectedIndex;
  final int tabCount;
  final double height;
  final HalcyonDockLabelMode labelMode;

  /// (context, index, selected) → tab 内容。
  final Widget Function(BuildContext, int, bool) itemBuilder;

  /// 点击/拖动提交切换（与当前 index 相同不回调，由本组件保证）。
  final ValueChanged<int> onItemTap;

  @override
  State<HalcyonDockBar> createState() => HalcyonDockBarState();
}

class HalcyonDockBarState extends State<HalcyonDockBar>
    with TickerProviderStateMixin {
  /// pill 连续位置（0..tabCount-1 浮点）。
  double _pillValue = 0;

  /// 拖动速度 px/s（pill 速度形变用，FloatingBottomBar.kt:537）。
  double _velocity = 0;

  /// 橡皮筋积分位移 px（同上 345 snapTo(value + dx)）。
  double _rubberOffset = 0;

  /// 按压进度 0..1（拖动中 1，松手回落）。
  double _press = 0;

  bool _dragging = false;
  double _dragTravel = 0;
  Duration _lastMoveTime = Duration.zero;
  double _lastMoveX = 0;

  double _totalWidth = 0;
  double _tabWidth = 1;

  /// 松手/点击后 pill 的 spring 回弹。
  late final AnimationController _pillSpring =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void initState() {
    super.initState();
    _pillValue = widget.selectedIndex.toDouble();
  }

  @override
  void didUpdateWidget(covariant HalcyonDockBar old) {
    super.didUpdateWidget(old);
    // 外部 route 变化（返回键/深链）时 pill spring 跟随。
    if (old.selectedIndex != widget.selectedIndex && !_dragging) {
      _springPillTo(widget.selectedIndex.toDouble());
    }
  }

  @override
  void dispose() {
    _pillSpring.dispose();
    super.dispose();
  }

  SpringDescription get _springDesc => SpringDescription(
        mass: 1,
        stiffness: kHalcyonDockSpringStiffness,
        // damping = ratio × 2 × √(mass×stiffness)，ratio=1 无弹跳。
        damping: kHalcyonDockSpringDampingRatio *
            2 *
            math.sqrt(kHalcyonDockSpringStiffness),
      );

  void _springPillTo(double target) {
    _pillSpring.animateWith(
      SpringSimulation(_springDesc, _pillValue, target, 0),
    );
  }

  void _onDragStart(DragStartDetails d) {
    _dragging = true;
    _dragTravel = 0;
    _lastMoveTime = d.sourceTimeStamp ?? Duration.zero;
    _lastMoveX = d.localPosition.dx;
    _pillSpring.stop();
    setState(() => _press = 1);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging || _tabWidth <= 0) return;
    final double x = d.localPosition.dx;
    _dragTravel += d.delta.dx.abs();
    // pill 连续跟手（同上 340：delta/tabWidth 按位置直读）。
    _pillValue = ((x - kHalcyonDockEdgeInsetDp) / _tabWidth)
        .clamp(0.0, (widget.tabCount - 1).toDouble());
    // 速度估计 px/s（pill 速度形变，同上 537）。
    final double dtMs =
        ((d.sourceTimeStamp ?? Duration.zero) - _lastMoveTime).inMilliseconds.toDouble();
    if (dtMs > 1) {
      _velocity = ((x - _lastMoveX) / dtMs * 1000).clamp(-4000.0, 4000.0);
      _lastMoveTime = d.sourceTimeStamp ?? Duration.zero;
      _lastMoveX = x;
    }
    // 橡皮筋积分（同上 345）。
    _rubberOffset += d.delta.dx;
    setState(() {});
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    _velocity = d.velocity.pixelsPerSecond.dx.clamp(-4000.0, 4000.0);
    // 提交判定（同上 322）：位移超 touchSlop 且 round 后变 tab 才切。
    final double slop =
        MediaQuery.gestureSettingsOf(context).touchSlop ?? 18.0;
    final int target = _pillValue.round().clamp(0, widget.tabCount - 1);
    if (_dragTravel.abs() >= slop && target != widget.selectedIndex) {
      widget.onItemTap(target);
    }
    _springPillTo(widget.selectedIndex.toDouble());
    setState(() => _press = 0);
    // 速度形变随后续 spring 帧自然衰减（见 build 中每帧 ×0.86）。
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _springPillTo(widget.selectedIndex.toDouble());
    setState(() => _press = 0);
  }

  void _tapItem(int index) {
    if (index == widget.selectedIndex) return;
    _velocity = 0;
    widget.onItemTap(index);
    _springPillTo(index.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color panelColor = (isDark ? kHalcyonDockDarkTint : Colors.white)
        .withValues(
            alpha: isDark ? kHalcyonDockDarkAlpha : kHalcyonDockLightAlpha);
    final Color contentColor = cs.onSurface;
    final Color activeColor = cs.primary;

    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      _totalWidth = c.maxWidth;
      _tabWidth = ((_totalWidth - kHalcyonDockEdgeInsetDp * 2) / widget.tabCount)
          .clamp(1.0, double.infinity);
      final double radius = widget.height / 2;
      final double press = _press;
      final double pillLeft =
          kHalcyonDockEdgeInsetDp + _pillValue * _tabWidth;
      // 速度形变（同上 537-539）：v = velocity/10，clamp ±0.2（归一化口径
      // 与 Compose 的 px 值不同：这里 /1000 折算 dp 量级，实测再调）。
      final double v = (_velocity / 10 / 1000).clamp(-0.2, 0.2);
      final double pillScaleX = 1.0 / (1.0 - (v * 0.75));
      final double pillScaleY = 1.0 - (v * 0.25);
      // 橡皮筋（同上 285-287）：fraction×4dp×EaseOut(|fraction|)。
      final double f =
          (_rubberOffset / math.max(_totalWidth, 1)).clamp(-1.0, 1.0);
      final double panelShift =
          kHalcyonDockRubberBandDp * f.sign * _easeOut(f.abs());
      // 面板按压膨胀（同上 444：lerp(1, 1+16dp/width, press)）。
      final double bulge =
          1.0 + kHalcyonDockPressBulgeDp / math.max(_totalWidth, 1) * press;

      return GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragCancel,
        child: Transform.translate(
          offset: Offset(panelShift, 0),
          child: Transform.scale(
            scale: bulge,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: BackdropFilter(
                // LiquidGlass 档 blur 6dp（BottomBarLiquidGlassConfig 默认），
                // Flutter sigma 口径 ×2 ≈ 12；壁纸预模糊基建下开销可接受。
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: panelColor,
                    borderRadius: BorderRadius.circular(radius),
                    // 内缘高光近似 BloomStroke（同上 161-179 白 0.12）。
                    border: Border.all(
                      color: Colors.white
                          .withValues(alpha: isDark ? 0.10 : 0.18),
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: pillLeft,
                        top: 4,
                        bottom: 4,
                        width: _tabWidth,
                        child: Transform.scale(
                          scaleX: pillScaleX,
                          scaleY: pillScaleY,
                          alignment: Alignment.center,
                          child: Container(
                            decoration: BoxDecoration(
                              color: activeColor
                                  .withValues(alpha: kHalcyonDockPillAlpha),
                              borderRadius:
                                  BorderRadius.circular(radius - 4),
                              // pill 顶部光泽渐变（近似 lens 高光带）。
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.center,
                                colors: <Color>[
                                  Colors.white
                                      .withValues(alpha: isDark ? 0.08 : 0.14),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          for (int i = 0; i < widget.tabCount; i++)
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _tapItem(i),
                                child: Center(
                                  child: widget.itemBuilder(
                                    context,
                                    i,
                                    i == widget.selectedIndex,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// 供 responsive_layout 组装 tab 内容的默认排版（FloatingBottomBarItem：
/// Icon 26dp + label 11sp、垂直 1dp、选中 primary/未选中 onSurface）。
class HalcyonDockTabContent extends StatelessWidget {
  const HalcyonDockTabContent({
    super.key,
    required this.icon,
    this.label,
    required this.selected,
    required this.contentColor,
    required this.activeColor,
  });

  final Widget icon;
  final String? label;
  final bool selected;
  final Color contentColor;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? activeColor : contentColor;
    return IconTheme.merge(
      data: IconThemeData(color: color, size: 26),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 11,
          height: 1.0,
          color: color,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            icon,
            if (label != null && label!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 1),
              Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}
