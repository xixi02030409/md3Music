#version 460 core

#include <flutter/runtime_effect.glsl>

// 液态玻璃折射镜片（Kyant0/AndroidLiquidGlass Lens 的 Flutter shader 移植）。
//
// 【管线契约（dart:ui ImageFilter.shader）】
//   - 第一个 float uniform 必须是 vec2：引擎注入输入纹理尺寸（占 float 槽
//     0-1，Dart 侧不得写）；
//   - 第一个 sampler2D 由引擎绑定为滤镜输入（BackdropFilter 的背景层）；
//   - GLES 后端 y 轴反向：所有采样坐标经 uv2tex() 翻转（偏移量随仿射自动
//     保持方向：1-(u+o) = (1-u)-o）；
//   - 本项目约定：sampler uniform 声明在所有 float uniform 之后
//     （见 shaders/depth_parallax.frag:45）。
//
// 【算法（与 Kyant0 Lens 同构）】
//   圆角盒 SDF d：d>0 形外原样透传；d<0 内部按「凸缘高度剖面」折射——
//   边带内 h = sqrt(1-(depth/thickness)^2)（外缘 1 → 带内缘 0），采样点
//   向内偏移 -n·h·strength，RGB 三通道偏移量错开 = 边缘色散；内部整体
//   3% 放大造透镜感；BloomStroke 双光源（左上主光 + 右下副光）沿法线在
//   环带上加白。
uniform vec2 u_size;        // float 槽 0-1（引擎注入，勿写）
uniform float u_radius;     // 2: 圆角半径（物理 px）
uniform float u_thickness;  // 3: 折射边带厚度（物理 px）
uniform float u_refract;    // 4: 折射强度 0-1
uniform float u_blur;       // 5: 内部模糊 sigma（物理 px）
uniform float u_chroma;     // 6: 色散强度（物理 px）
uniform float u_specular;   // 7: 高光强度 0-1
uniform float u_edge;       // 8: 高光环带宽度（物理 px）

// 约定：sampler 声明在所有 float uniform 之后
uniform sampler2D u_backdrop; // 槽 0：引擎绑定为滤镜输入

out vec4 fragColor;

float sdRoundBox(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + r;
  return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

vec2 uv2tex(vec2 uv) {
#ifdef IMPELLER_TARGET_OPENGLES
  return vec2(uv.x, 1.0 - uv.y);
#else
  return uv;
#endif
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 uv = fc / u_size;
  vec2 halfSize = u_size * 0.5;
  vec2 p = fc - halfSize;
  float d = sdRoundBox(p, halfSize, u_radius);

  // 形外：原样透传（BackdropFilter 边界内未被镜片覆盖处不改变背景）
  if (d > 0.0) {
    fragColor = texture(u_backdrop, uv2tex(uv));
    return;
  }

  // SDF 中心差分 = 外法线（max 防 0 向量 NaN）
  float e = 1.0;
  vec2 grad = vec2(
    sdRoundBox(p + vec2(e, 0.0), halfSize, u_radius) -
        sdRoundBox(p - vec2(e, 0.0), halfSize, u_radius),
    sdRoundBox(p + vec2(0.0, e), halfSize, u_radius) -
        sdRoundBox(p - vec2(0.0, e), halfSize, u_radius)
  );
  vec2 n = grad / max(length(grad), 1e-4);

  float depth = -d;
  float band = 1.0 - clamp(depth / u_thickness, 0.0, 1.0); // 1 在外缘
  float h = sqrt(max(1.0 - (1.0 - band) * (1.0 - band), 0.0)); // 凸缘剖面

  // 折射位移（uv 空间）：边带内向内拉采样，外缘最强；色散分通道错开。
  // 量纲红线（真机彩虹漩涡教训）：amt 峰值 = refract×0.5×thickness_px
  // （24dp 边带下 rim 位移 ≈16px，读感是"透镜弯"而不是"把别处内容吸进来"）；
  // 色散是【像素级】错位，直接 chroma_px/width，绝不能再乘 thickness/width。
  float scale = u_thickness / max(u_size.x, 1.0);
  float amt = u_refract * 0.5 * h * scale;
  float ca = u_chroma * h / max(u_size.x, 1.0);
  vec2 offR = -n * (amt + ca);
  vec2 offG = -n * amt;
  vec2 offB = -n * max(amt - ca, 0.0);

  // 内部 3% 放大（透镜感）
  vec2 mag = (halfSize + p * 0.97) / u_size;

  // 9 tap 近似模糊（u_blur=0 退化为单点）；采样坐标 clamp 防边缘拖影
  vec2 px = vec2(1.0) / u_size;
  vec3 col = vec3(0.0);
  float wsum = 0.0;
  for (int i = -1; i <= 1; i++) {
    for (int j = -1; j <= 1; j++) {
      vec2 o = vec2(float(i), float(j)) * u_blur * px;
      float w = (i == 0 && j == 0) ? 2.0 : 1.0;
      col.r += texture(u_backdrop, uv2tex(clamp(mag + o + offR, vec2(0.002), vec2(0.998)))).r * w;
      col.g += texture(u_backdrop, uv2tex(clamp(mag + o + offG, vec2(0.002), vec2(0.998)))).g * w;
      col.b += texture(u_backdrop, uv2tex(clamp(mag + o + offB, vec2(0.002), vec2(0.998)))).b * w;
      wsum += w;
    }
  }
  col /= wsum;

  // BloomStroke 双光源高光：左上主光(-45°) + 右下副光，沿外法线在环带加白
  float rim = 1.0 - smoothstep(0.0, u_edge, depth);
  vec2 l1 = normalize(vec2(-0.6, -0.8));
  vec2 l2 = normalize(vec2(0.7, 0.7));
  float s1 = pow(max(dot(n, l1), 0.0), 3.0) * rim * u_specular;
  float s2 = pow(max(dot(n, l2), 0.0), 4.0) * rim * u_specular * 0.55;
  col += vec3(s1 + s2);

  fragColor = vec4(col, 1.0);
}
