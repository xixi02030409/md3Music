# Halcyon UI for MD3Music

把 **Halcyon**（Kifranei/Halcyon，MIUI/HyperOS 风格播放器）的玻璃视觉体系移植给
**MD3Music**（zzyoxml/md3Music，Flutter + Rust 酷狗第三方客户端）。

**单一成品补丁**：`halcyon-ui-final.patch`（包含全部阶段，`git apply --3way` 一次应用）。
历史分段补丁（base/stage2/stage3/stage4）在 `archive/` 仅作存档，不再使用。

## 效果清单

- **底部导航栏** → 悬浮胶囊 dock：左右 12dp / 下 10dp 悬浮、全圆角、
  高斯模糊（sigma 18）+ 半透明磨砂底（暗 `#111114@0.42` / 亮 `white@0.38`）
  + 顶部高光渐变 + 内缘 1px 描边（近似液态玻璃边缘反光）
- **迷你播放条** → **悬浮胶囊形态**（Halcyon Floating 签名视觉）：玻璃只包
  内容行（全圆角 20），悬在底栏胶囊顶沿上方 8dp，与底栏之间的缝透出列表
  内容（只被底栏玻璃模糊）；左右 12dp 与底栏对齐；底栏收起时随同一条动画
  落为贴边屏底形态（横向圆角避让自动接管）
- **全局卡片玻璃化**（背景图模式下）：`surfaceContainer` 五档全部带 alpha
  （0.40~0.66，越浮起越实）+ `cardTheme` 半透明零阴影——所有卡片透出
  AppBackground 预模糊壁纸，即 Halcyon 截图「卡片透出模糊壁纸」的效果；
  纯色 alpha 零渲染开销
- **文字底模糊衬**：`HalcyonGlassCard`（真 BackdropFilter 大卡 + footer
  副文本底衬槽：更亮更糊的一条带）与独立 `HalcyonGlassFooterStrip`；示范
  落在听歌统计页概览卡 hint
- **底栏滚动隐藏**：主页面列表上滑收底栏让位内容、下滑回看升起（复用既有
  收起动画，横向翻页/二级页面/TV 自动豁免），总开关
  `kHalcyonScrollHideChrome`
- **横屏玻璃 rail**：侧边导航栏同款悬浮玻璃胶囊（全圆角 28，rail 底色透明）
- **保留**：MD3Music 的**播放进度环绕播放条描边**效果（进度 painter、
  胶囊形变槽位、封面形变、点卡交互全部未动，只换底色材质层）
- 图标、选中胶囊回弹（`_CapsuleBounce`）、底栏文字三档设置全部原样

## 改动面（6 文件）

| 文件 | 改动 |
|---|---|
| `lib/widgets/halcyon_glass.dart` | **新增**：自包含毛玻璃容器/玻璃卡/footer 底衬/常量组/总闸 |
| `lib/core/layout/responsive_layout.dart` | `extendBody: true`；底栏悬浮胶囊玻璃容器；`BottomChromeScope` 下发槽位高；滚动隐藏驱动；横屏 rail 玻璃化；**slotHeight 勘误**（+`kBottomBarDockBottomInset`，见下） |
| `lib/modules/player/mini_player.dart` | 迷你条悬浮胶囊形态（净空带移玻璃外 + 锚点反解修正）；**坞位端点勘误**（`slotHeight + kMiniPlayerDockLift(8)`，见下） |
| `lib/core/layout/bottom_chrome_scope.dart` | `BottomChromeScope` + `slotHeight` 字段 |
| `lib/app.dart` | `_applyBackgroundOverrides`：surface 五档带 alpha + cardTheme 玻璃化（仅背景图模式） |
| `lib/modules/user/listen_stats_page.dart` | 概览卡 hint 条件化套 `HalcyonGlassFooterStrip`（示范，关闭背景图时零痕迹） |

## 几何勘误（2026-10-31，随成品补丁修正）

此前分段补丁里有两处**未编译就上线的几何错误**，成品补丁已修正：

1. **底栏胶囊悬浮边距被裁**：底栏本体真实总高 = 胶囊下边距 10 + 玻璃容器高
   （栏高 + NavigationBar 内部 SafeArea 补的手势条净空），而旧 `slotHeight`
   公式漏了下边距——`BottomChromeSlot` 的 `Clip.hardEdge` 按 slotHeight 裁切，
   把胶囊悬浮在屏底上方的 10dp 整段裁掉（悬浮从未真正生效）。新口径：
   `slotHeight = barHeight + padding.bottom + kBottomBarDockBottomInset(10)`，
   收起滑动距离/面板下沉几何同步归位
2. **迷你条被玻璃底栏盖住**：旧坞位端点 `slotHeight − alone.bottom + 18` 多减
   了 `alone.bottom`（手势机上 ≈ 手势条 inset 48px+），内容行沉进胶囊内
   40px+。新口径：`slotHeight + kMiniPlayerDockLift(8)`——胶囊顶沿之上纯
   视觉间距 8dp

## 自动同步 + 自动编译（GitHub Actions）

`.github/workflows/halcyon-ui.yml`：

1. 每 6 小时检查上游 `zzyoxml/md3Music` main 最新提交
2. 新提交 → 检出上游树 → 自动 `git apply --3way halcyon-ui-final.patch`
3. 编译 arm64 APK（JDK17 + Flutter stable，与上游官方 CI 同链路）
4. 自动发 Release：`halcyon-ui-<上游短SHA>`（同一上游提交只构建一次）
5. 上游改动导致补丁打不上时 → 自动开 issue 提醒

### 启用步骤（一次性，约 2 分钟）

1. 在 GitHub 上 **fork** `zzyoxml/md3Music`（保持默认 fork main）
2. 把本目录的 `.github/workflows/halcyon-ui.yml` 和 `halcyon-ui/` 目录
   **原样复制/推送到你 fork 的 main 分支**（两个路径都要；`archive/` 可不上传）
3. fork 页面 → Actions 标签 → 启用 workflow（首次手动跑一次验证：
   Run workflow 按钮）
4. 之后每 6 小时自动跟踪上游，新版本自动出 APK

### 手动本地打补丁（不用 Actions 时）

```bash
git clone https://github.com/zzyoxml/md3Music.git
cd md3Music
git apply --3way halcyon-ui-final.patch
flutter build apk --release --flavor standard --split-per-abi --target-platform android-arm64
```

## 已知取舍

- **全局玻璃卡只在背景图模式下生效**（玻璃的本质是透出预模糊壁纸，没有
  壁纸就没有玻璃的意义）；透明度五档常量在 `halcyon_glass.dart` 的
  `kHalcyonGlassSurface*Alpha`，真机嫌透/嫌实整组微调。底栏/迷你条/rail
  玻璃（BackdropFilter 真模糊）不受此开关限制
- 输入框（TextField fill 取 surfaceContainerHighest）在玻璃档下变半透明，
  深壁纸上的可读性是首跑验收点；不行就把 Highest 档 alpha 往上提
- Halcyon 的「液态玻璃折射」（Miuix lens 着色器）在 Flutter 无对应 API，
  用「顶部高光渐变 + 内缘描边」近似；真机观感如需更强可在
  `halcyon_glass.dart` 调 `highlightAlpha` / `blurSigma`
- 迷你条悬浮形态的形变起点矩形已按可见胶囊反解（`_visualBottomInset`），
  但形变浮层的**宽度**端点仍按全宽解析——展开瞬间胶囊两侧 12dp 有轻微
  跳变，真机明显再修
- 横屏 rail 玻璃胶囊按 `kNavigationRailDefaultWidth=112` 恒定档布局
  （OverflowBox 强制 + `_MeasureWidth` 回填同值），形态交棒浮层的 rail
  端点有 ±16dp 口径差，真机明显再调
- 毛玻璃依赖 `extendBody: true`：个别自带底部避让的页面（Zen 沉浸、
  车机、TV）走独立布局分支，不受影响
