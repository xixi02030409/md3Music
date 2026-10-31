/// Halcyon 风格毛玻璃容器（液态玻璃/高斯模糊/磨砂底）。
///
/// 视觉规范逐项取自 Halcyon（Kifranei/Halcyon）的底栏玻璃体系
/// `ui/components/GlassEffect.kt`：
///  - 磨砂底色：亮色 White@0.38 / 暗色 #111114@0.42（LiquidGlass 档）
///  - 内缘高光：亮色 alpha 0.18 / 暗色 alpha 0.10（玻璃上沿反光）
///  - 模糊：高斯 sigma 默认 18（Halcyon 的 blurRadiusDp=6 是 RenderEffect
///    的半径口径，与 Flutter ImageFilter.blur 的 sigma 不是一个量纲；18 在
///    Flutter 侧的观感与其 6dp 接近，可后续按真机微调）
///  - 「液态玻璃」的边缘折射：Flutter 无 Miuix lens 着色器，这里用
///    **上缘高光渐变 + 内描边**近似（顶部亮、往下衰减 + 1px 内描边，
///    观感接近 iOS 液态玻璃的边缘反光）
///
/// 设计目标：**自包含**（只依赖 Flutter SDK 的 widgets/dart:ui），上游
/// md3Music 任何文件都不 import 它，只有我们钩子处的 2~3 行引用——上游
/// 更新时补丁冲突面最小。
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';

/// 背景图模式下的**全局卡片玻璃**分档透明度（app.dart 的
/// `_applyBackgroundOverrides` 按档注入 colorScheme.surfaceContainer 族）。
///
/// 为什么是主题层而不是逐卡 BackdropFilter：壁纸已由 AppBackground 全局
/// 预模糊（ImageFiltered），半透明卡片透出的就是毛玻璃背景——列表里几十
/// 张卡都套 BackdropFilter 的开销不可接受，纯色 alpha 则零开销。
/// 分档沿用 M3 surface 族语义：越浮起（High/Highest）越实，保证弹层、
/// 菜单等悬浮件的可读性；对齐 Halcyon `frostedCardColor` 的 defaultAlpha
/// 0.42 量级（中间档 0.52），真机观感可整组微调。
const double kHalcyonGlassSurfaceLowestAlpha = 0.40;
const double kHalcyonGlassSurfaceLowAlpha = 0.46;
const double kHalcyonGlassSurfaceAlpha = 0.52;
const double kHalcyonGlassSurfaceHighAlpha = 0.58;
const double kHalcyonGlassSurfaceHighestAlpha = 0.66;

/// 底栏「滚动隐藏」总开关：主页面列表下滑浏览（手指上滑）时玻璃底栏下沉
/// 让位内容，下滑回看时升起（Halcyon / YouTube Music 同款行为）。
/// false 时恢复上游行为（底栏常驻，仅二级页面 route 驱动收起）。
const bool kHalcyonScrollHideChrome = true;

/// 背景图模式开启才渲染玻璃效果；关闭时原样返回 [child]（零痕迹）。
///
/// 玻璃的本质是「透出预模糊壁纸」——壁纸不存在时玻璃只剩一层怪异的
/// 半透明色斑，因此以背景图开关作为总闸，调用方无需各自判断。
bool halcyonGlassEnabled(BuildContext context) =>
    context.watch<ThemeProvider>().useBackgroundImage;

/// 玻璃档位：磨砂（毛玻璃）/ 液态玻璃（磨砂 + 更强边缘反光）。
enum HalcyonGlassStyle { frosted, liquid }

class HalcyonGlassContainer extends StatelessWidget {
  const HalcyonGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.blurSigma = 18.0,
    this.style = HalcyonGlassStyle.liquid,
    this.fallbackColor,
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// 高斯模糊 sigma（BackdropFilter/ImageFilter.blur）。
  final double blurSigma;

  final HalcyonGlassStyle style;

  /// BackdropFilter 在部分低端机/旧 WebView 场景可能被禁用（EngineFlags），
  /// 届时退化为纯色容器，保证可用性。
  final Color? fallbackColor;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Halcyon GlassEffect.kt bottomBarGlassContainerColor：
    // LiquidGlass 档 亮 0.38 / 暗 0.42；底色亮白 / 暗 #111114。
    final tint = isDark
        ? const Color(0xFF111114).withValues(alpha: 0.42)
        : Colors.white.withValues(alpha: 0.38);
    // bottomBarGlassHighlightAlpha：LiquidGlass 档 亮 0.18 / 暗 0.10。
    final highlightAlpha = isDark ? 0.10 : 0.18;
    final effectiveTint = fallbackColor ?? tint;

    // 高光渐变：顶部最强、快速衰减到底部（玻璃上缘反光）。liquid 档更亮。
    // 注意：BoxDecoration 的 color 与 gradient 互斥（assert），因此高光
    // 不走第二层，而是把顶部颜色往白色插值 highlightAlpha 后做成两段
    // gradient —— 顶部=带高光的 tint，底部=纯 tint。
    final Widget content = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );

    // 顶部色 = tint 向白混合 highlightAlpha（模拟玻璃上缘反光叠在底色上）
    final topColor =
        Color.lerp(effectiveTint, Colors.white, highlightAlpha)!;
    final bottomColor = effectiveTint;

    return ClipRRect(
      borderRadius: borderRadius,
      // 描边画在模糊层之上：DecoratedBox(foreground) 顺序 = blur → tint → stroke
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
          tileMode: TileMode.mirror,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            // 液态玻璃：顶部高光渐变（融合进 tint），frosted 档无渐变纯 tint。
            gradient: style == HalcyonGlassStyle.liquid
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [topColor, bottomColor],
                    stops: const [0.0, 1.0],
                  )
                : null,
            color: style == HalcyonGlassStyle.liquid ? null : effectiveTint,
            border: Border.all(
              color: Colors.white.withValues(
                alpha: style == HalcyonGlassStyle.liquid
                    ? highlightAlpha * 0.9
                    : highlightAlpha * 0.5,
              ),
              width: 1.0,
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Halcyon 仪表盘 tile 同构的**真模糊玻璃卡**（对应 Halcyon
/// `frostedCardModifier`：Miuix textureBlur 72f/64f + 模糊开启时卡体
/// Color.Transparent）。与 [HalcyonGlassContainer] 的区别：卡片档 tint
/// 更淡（模糊感为主）、自带 [footer] 副文本底衬槽。
///
/// [footer] 是 Halcyon tile 的「文字底模糊底层效果」：副文本所在的一条
/// 独立横带，比卡体更亮、更糊（内部再叠一层 BackdropFilter 与卡体模糊
/// 累加），上缘一条内缘高光分隔线。结构与截图 tile 一致：标题内容在
/// 卡体，副文本落在 footer 带。
///
/// 适用场景：屏幕上数量有限的大卡（入口 tile / 概览卡）。长列表行卡请
/// 走主题层的全局半透明（见 kHalcyonGlassSurface*Alpha），不要逐行套
/// BackdropFilter。
class HalcyonGlassCard extends StatelessWidget {
  const HalcyonGlassCard({
    super.key,
    required this.child,
    this.footer,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.blurSigma = 30.0,
    this.padding = const EdgeInsets.all(16),
    this.footerPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 10,
    ),
  });

  final Widget child;

  /// 底部副文本槽：自动获得「更亮更糊」的底衬条。
  final Widget? footer;

  final BorderRadius borderRadius;

  /// 卡体模糊 sigma。Halcyon 卡片档 textureBlur 72f（暗）观感比底栏
  /// （6dp/18sigma）强得多，Flutter 侧取 30 起步，真机微调。
  final double blurSigma;

  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry footerPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 卡片档 tint：Halcyon 模糊开启时卡体全透（靠 blend 混色），Flutter
    // 无对应混合着色器，用淡 tint 保底色相；比底栏档（0.42）更透。
    final tint = isDark
        ? const Color(0xFF111114).withValues(alpha: 0.30)
        : Colors.white.withValues(alpha: 0.30);
    // footer 比 card 体更亮：暗色往白提（发白磨砂带），亮色往白再提一点。
    final footerTint = isDark
        ? const Color(0xFF111114).withValues(alpha: 0.30 + 0.10)
        : Colors.white.withValues(alpha: 0.30 + 0.14);
    final highlightAlpha = isDark ? 0.10 : 0.18;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
          tileMode: TileMode.mirror,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: highlightAlpha * 0.9),
              width: 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 卡体：顶部高光渐变（同 HalcyonGlassContainer 的 liquid 观感）
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      Color.lerp(tint, Colors.white, highlightAlpha)!,
                      tint,
                    ],
                  ),
                ),
                padding: padding,
                child: child,
              ),
              if (footer != null)
                // footer 底衬：更亮 tint + 再叠一层模糊（与卡体累加 → 更糊）
                Container(
                  decoration: BoxDecoration(
                    color: footerTint,
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(
                          alpha: highlightAlpha * 0.9,
                        ),
                        width: 1.0,
                      ),
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: blurSigma * 1.3,
                      sigmaY: blurSigma * 1.3,
                      tileMode: TileMode.mirror,
                    ),
                    child: Padding(
                      padding: footerPadding,
                      child: footer!,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 独立的「文字底模糊底层」横带：可单独套在任意卡片内副文本（hint/
/// summary）的下面，不需要整卡换成 [HalcyonGlassCard]。
///
/// 关闭背景图模式时直接返回 [child]（halcyonGlassEnabled 总闸）。
/// 底衬材质：暗色白纱 / 亮色白提亮，自带水平内边距归零（由调用方控制
/// 外形，条带本身铺满父级给的宽度）。
class HalcyonGlassFooterStrip extends StatelessWidget {
  const HalcyonGlassFooterStrip({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!halcyonGlassEnabled(context)) return child;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.35);
    final result = Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: borderRadius,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 24,
          sigmaY: 24,
          tileMode: TileMode.mirror,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (borderRadius == null) return result;
    return ClipRRect(borderRadius: borderRadius!, child: result);
  }
}
