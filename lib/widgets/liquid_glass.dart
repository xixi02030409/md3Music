// 液态玻璃折射镜片（Kyant0/AndroidLiquidGlass Lens 的 Flutter 移植件）。
//
// Halcyon 蓝本（Kotlin Compose）的 alpha0 内容折射层 + GlassPill lens 用的是
// Compose layerBackdrop/RenderEffect 管线，Flutter 无对应 API；这里用
// dart:ui ImageFilter.shader（Impeller 专有，FragmentProgram 运行时编译）
// 实现同款边缘折射 + 色散 + 双光源高光。非 Impeller 后端（Skia/软件渲染）
// 或 shader 加载失败时自动退化为透明（露出下层实底 pill），绝不崩。
//
// 用法：画在被折射内容的【上层】（Stack 最后），必须包 IgnorePointer。
// shader 源码：shaders/liquid_glass.frag（uniform 槽位契约见该文件头）。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const String kLiquidGlassShaderAsset = 'shaders/liquid_glass.frag';

/// 默认参数（GlassPill lens 10×progress 口径换算 + 实机调校余量；dp 值由
/// widget 侧 ×dpr 换算成物理 px 再喂 shader）。
const double kLensThicknessDp = 22.0;
const double kLensRefract = 0.85;
const double kLensBlurDp = 1.5;
const double kLensChromaDp = 1.4;
const double kLensSpecular = 0.40;
const double kLensEdgeDp = 3.0;

ui.FragmentProgram? _program;
bool _loadStarted = false;

/// 预热：发起 shader 加载（幂等）。加载失败按永久退化处理（与
/// FlowingBackground 的 shaderUnavailable 同口径）。
Future<void> ensureLiquidGlassShader() async {
  if (_loadStarted) return;
  _loadStarted = true;
  try {
    _program = await ui.FragmentProgram.fromAsset(kLiquidGlassShaderAsset);
  } catch (_) {
    _program = null;
  }
}

/// 当前是否走真折射镜片（Impeller + shader 加载成功）。
bool get liquidGlassSupported =>
    ui.ImageFilter.isShaderFilterSupported && _program != null;

/// 折射镜片：占据可用空间，把背后内容做边缘折射 + 色散 + 高光。
class LiquidGlassLens extends StatefulWidget {
  const LiquidGlassLens({
    super.key,
    required this.radius,
    this.thickness = kLensThicknessDp,
    this.refract = kLensRefract,
    this.blur = kLensBlurDp,
    this.chroma = kLensChromaDp,
    this.specular = kLensSpecular,
    this.edge = kLensEdgeDp,
  });

  final double radius;
  final double thickness;
  final double refract;
  final double blur;
  final double chroma;
  final double specular;
  final double edge;

  @override
  State<LiquidGlassLens> createState() => _LiquidGlassLensState();
}

class _LiquidGlassLensState extends State<LiquidGlassLens> {
  /// FragmentShader 实例只建一次（每帧 program.fragmentShader() + 滤镜对象
  /// 重建是 depth_shader_cover 实证过的跟手卡顿主因）；float 每帧更新很便宜。
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    ensureLiquidGlassShader().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui.FragmentProgram? program = _program;
    if (program == null || !ui.ImageFilter.isShaderFilterSupported) {
      // Skia/软件渲染/加载失败：退化路径（实底 pill 由调用方下层兜底）。
      return const SizedBox.expand();
    }
    final ui.FragmentShader shader = _shader ??= program.fragmentShader();
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        // float 槽 0-1 是 u_size（引擎注入），从 2 开始（契约见 .frag 头注释）。
        shader.setFloat(2, widget.radius * dpr);
        shader.setFloat(3, widget.thickness * dpr);
        shader.setFloat(4, widget.refract);
        shader.setFloat(5, widget.blur * dpr);
        shader.setFloat(6, widget.chroma * dpr);
        shader.setFloat(7, widget.specular);
        shader.setFloat(8, widget.edge * dpr);
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.shader(shader),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}
