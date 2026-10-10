<p align="center">
  <img src="docs/app-icon.png" alt="TH11 iOS 应用图标" width="180" height="180">
</p>

# TH11 iOS Port

《東方地霊殿 ～ Subterranean Animism》1.00a 的原生 iOS 移植，基于 [YomotsuHisami/th11](https://github.com/YomotsuHisami/th11) 的 C++ 行为重建源码，使用 UIKit、SDL3 和 OpenGL ES 3。

本仓库保存 b3 版本的主要源码、资源准备工具、构建脚本与原生测试。游戏逻辑在设备上直接执行 C++；原版 Windows 程序只作为本地资源准备的输入。游戏内容为日文，触控设置为简体中文。

## Vibe Coding 声明

本项目的 iOS 移植采用 **Vibe Coding（AI 辅助开发）**：由用户提出需求，使用 **OpenAI Codex** 辅助完成移植实现、触控与设置功能、问题修复、构建验证及文档整理。

游戏的 C++ 行为重建源码来自 [YomotsuHisami/th11](https://github.com/YomotsuHisami/th11)，原作及图标来自 Team Shanghai Alice / ZUN；各来源的署名与组件授权均保留。测试覆盖与尚未验证的内容见下方“验证与已知限制”及 [ios/VALIDATION.md](ios/VALIDATION.md)。

## 功能

- ARM64 iPhone / iPad，最低部署版本 **iOS 14.0**。
- 横竖屏铺满屏幕。竖屏战斗参考 TH06 的布局，将原右侧的积分、残机、火力等信息移至顶部，384 × 448 游戏区映射到下方剩余空间；横屏及菜单使用全屏画布。
- 虚拟摇杆、Z / X / S 按钮和游戏区拖拽；摇杆从区域内按下后，滑出区域仍持续追踪，抬手才释放。死区可在设置中调整为 0–40%。
- 混合、拖拽、摇杆三种操作模式，自动射击、低速、按键保持、灵敏度、透明度、控件大小、左右手布局、触感和手势设置。
- 控件布局可拖动编辑，横屏和竖屏位置分别保存；切后台、旋转、打开设置时暂停并释放输入。
- **拖拽限速开关**：默认遵循原作移动速度；关闭后立即跟随相对拖拽。修复灵梦＋文的重复位移、移动残影和僚机动画位置重叠。
- **开发者功能开关**：战斗中显示可拖动悬浮按钮，提供无敌、最高分数、资源补满、满火力、满残机与 Bomb 能量、全部补满，以及清除弹幕和激光。
- **一键解锁**：设置 → 开发者与解锁 → 输入作弊码，输入 `ymgjdsh` 并确认，永久解锁六条 Extra 路线、全部练习关卡与 Music Room 的 17 首曲目；保留已有成绩。
- **自动 Bomb 开关**：默认关闭；实际中弹时在死亡效果之前释放原作 Bomb，扣除对应角色一次 Bomb 的火力。擦弹、无敌、Bomb 已生效、对话和回放不触发，火力不足时正常受击。
- 修复作弊码输入首个字符后键盘自动收回的问题，支持连续输入、删除和粘贴。构建时自动为 SDL 3.4.2 应用限定输入来源的 UIKit 修补。
- 30 / 60 FPS 显示选项，游戏逻辑目标保持 60 Hz；设置、成绩及录像保存在应用沙盒，本机诊断日志可通过系统分享导出。

## 构建

### 依赖

- macOS、Xcode 14 或兼容的 iOS SDK。已验证环境为 Xcode 14.0 / iOS 16 SDK，部署目标为 iOS 14.0。
- CMake 3.20+、Python 3.10+、Git。
- Windows 和 Node.js 20+：仅用于离线生成 Windows GDI 字形；需安装原版所用的日文字体 `ＭＳ ゴシック` / `ＭＳ 明朝`。
- SDL 3.4.2；依赖获取脚本固定版本并校验下载内容。

先克隆仓库：

```sh
git clone https://github.com/Ymgjdsh/th11-ios-port.git
cd th11-ios-port
```

### 私有资源

从自己有权使用的日文 **TH11 1.00a** 安装准备 `th11.exe`、`th11.dat` 和 `thbgm.dat`。游戏数据、音乐、字体和用于构建的完整图标目录需在本地准备；仓库中的 `docs/app-icon.png` 仅用于 README 展示。

在 Windows 的仓库根目录运行：

```powershell
py -3 -m pip install -r ios/tools/requirements-assets.txt
npm --prefix th11_web/scripts ci
node th11_web/scripts/prepare-fonts.mjs
py -3 ios/tools/prepare_th11_assets.py --original "<原版游戏目录>"
py -3 ios/tools/prepare_icon.py --exe "<原版游戏目录>/th11.exe" --group IDI_ICON3
```

随后将源码以及生成的 `.local/assets/`、`.local/app-icon/Assets.xcassets/` 复制到 Mac 的同一项目目录。`.local` 是私有构建输入，不要提交。资源版本、字体要求、音乐转换方式和图标说明见 [ios/ASSETS.md](ios/ASSETS.md) 与 [ios/ICON.md](ios/ICON.md)。

### iOS 设备包

在 Mac 的仓库根目录运行：

```sh
bash ios/tools/fetch_dependencies.sh
bash ios/tools/native_checks.sh
TH11_SDK=iphoneos TH11_DIAGNOSTICS=OFF TH11_BUILD_NUMBER=3 bash ios/build_ios.sh
python3 ios/tools/package_ipa.py \
  .local/build-iphoneos/RelWithDebInfo-iphoneos/th11.app \
  dist/TH11-iOS14-Native-b3.ipa
```

`TH11_BUILD_JOBS` 设置编译并发数，默认 3；`TH11_BUILD_DIR`、`TH11_ASSETS`、`TH11_DEPENDENCIES` 和 `TH11_BUILD_NUMBER` 可覆盖默认值。模拟器构建及检查入口见 [ios/README.md](ios/README.md)。

打包工具校验 ARM64 设备架构、最低系统版本、图标、资源哈希及签名，并生成 IPA 和校验清单。IPA 使用 **ad-hoc 签名，供已有 TrollStore 的设备安装**。普通未配置安装环境的 iOS 不能直接点击 IPA 安装；本脚本不生成 App Store 或 Apple 开发者描述文件签名包。

## 操作

| 控件或手势 | 功能 |
| --- | --- |
| 摇杆 | 移动；菜单选择 |
| Z | 射击；确认 |
| X | Bomb；返回 |
| S | 低速移动 |
| 暂停按钮 | 暂停游戏 |
| 齿轮按钮 | 打开中文设置 |
| 游戏区拖拽 | 相对移动，是否限速由设置决定 |
| 双指按住 | 低速，可在设置中开关 |
| 双击游戏区 | Bomb，可在设置中开关 |
| 四指触摸 | 暂停 |
| 菜单滑动 / 轻点 | 选择 / 确认 |
| 对话轻点 | 继续对话 |

TH11 的 Bomb 消耗火力，因此开发者菜单中的 Bomb 能量通过补满火力恢复。开发者菜单打开时暂停战斗；关闭开发者功能会同时关闭无敌。录像回放和演示不启用作弊。解锁码在确认后写入存档，输入错误或取消不会修改解锁状态。

## 源码结构

| 目录 | 内容 |
| --- | --- |
| `ios/` | UIKit 入口、中文设置、摇杆、生命周期、诊断、构建及打包工具 |
| `ios/tests/` | 触控、暂停、ECL 和原生游戏集成检查 |
| `th11_web/cpp/game/` | C++ 游戏行为重建：关卡、脚本、自机、弹幕、菜单、存档及录像 |
| `th11_web/cpp/sdl/` | 游戏与原生显示、声音、资源及输入的连接层 |
| `portable/` | 共享渲染器、触控策略及第三方源码 |
| `th11_web/scripts/` | 离线字体生成工具及固定依赖 |

保留 `th11_web` 路径是为了保持源码引用一致。本仓库主要交付原生 iOS 目标，未收录网页启动器、旧项目工具链或原版对照样本。

## 验证与已知限制

原生回归覆盖四份内置演示、七关 × 六自机、Bomb、暂停以及成绩 / 录像读写，累计 43,253 个更新 tick。b2 另验证六种自机各 90 次不限速往返拖拽、限速边界、开发者动作、错误 / 正确解锁码和持久化。iOS 16 模拟器检查了实际设置、悬浮按钮、菜单暂停恢复、画面与声音；设备 IPA 的架构、最低版本、资源、签名和 ZIP CRC 已校验。详见 [ios/VALIDATION.md](ios/VALIDATION.md)。

- **尚未完成 iOS 14 真机安装与性能验收**；最低部署版本及模拟器结果不能证明真机所有场景稳定 60 FPS。
- 行为重建和固定样本检查不等于原版 EXE 的所有行为完全一致。
- 战斗作弊动作及自动 Bomb 触发没有记录进录像，使用这些功能后生成的录像可能无法复现该局；回放不根据当前开关自动补触发。
- 游戏资源为日文，未附加 TH11 汉化补丁。

## 致谢

- [YomotsuHisami/th11](https://github.com/YomotsuHisami/th11)：TH11 1.00a 的 C++ 行为重建及共享平台源码；上游参考提交 [`8255f484d0c1cff0ef9af9f19bb159328adda69f`](https://github.com/YomotsuHisami/th11/tree/8255f484d0c1cff0ef9af9f19bb159328adda69f)。
- Team Shanghai Alice / ZUN：《東方地霊殿 ～ Subterranean Animism》原作。
- TH10 iOS 项目的原生工具链与渲染经验，以及 TH06 的竖屏布局和 TH08 的开发者菜单参考。
- SDL、miniaudio、stb 与 eagler-th07 的共享触控策略。

## 资源与授权

本仓库收录一张用于 README 展示的应用图标预览 `docs/app-icon.png`，与 IPA 使用的图标一致，源自原版 `th11.exe` 的 `IDI_ICON3` 资源，原图版权归 Team Shanghai Alice / ZUN。

原版 EXE、游戏数据、音乐、字体、完整 AppIcon 构建目录、存档、录像、IPA 和私有工具链均在本地准备。可运行的安装包需从有权使用的资源在本地构建。

授权按组件保留，不对整个项目或原版资源声明统一许可证。上游的 `LICENSE-launcher.txt` 针对网页启动器；该启动器未收录到本原生仓库，不能据此推定全部游戏重建源码的授权。第三方声明见 [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt)、[ios/licenses](ios/licenses) 与 `portable/sdl/third_party` 中各组件的原始声明。
