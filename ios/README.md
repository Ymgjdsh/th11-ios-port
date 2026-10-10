# TH11 原生 iOS 移植

目标系统为 iOS 14.0 及以上，ARM64 iPhone / iPad，Bundle ID 为 org.th11.native。
行为重建游戏由 C++ 直接执行，UIKit 提供中文触控与设置，SDL3/OpenGL ES 提供原生显示和声音。
原版游戏资源为日文；没有附加汉化补丁。

## 操作

摇杆：移动或菜单选择；Z：射击 / 确认；X：Bomb / 返回；S：低速；暂停图标：游戏暂停。
摇杆从内部按下后，手指滑到外部仍持续移动，抬手或取消才释放；死区可在设置中调整为 0–40%，即时生效并保存。
游戏区支持相对拖动、双指按住低速、双击 Bomb、四指暂停。菜单滑动选择、轻点确认，对话轻点继续。
齿轮设置支持混合 / 拖动 / 摇杆模式、自动射击、低速、点击保持 Z / S、隐藏操作控件、灵敏度、死区、透明度、大小、左手布局及触感。
横竖屏固定铺满屏幕。竖屏战斗按 TH06 的比例将原右侧信息板移到顶部，384×448 战斗区域铺满下方剩余空间；菜单与横屏铺满完整画布。横竖屏按键位置分别保存。
30 FPS 设置限制显示提交，游戏逻辑目标维持 60 Hz。切后台、旋转及进入设置释放触摸与保持按键。
设置中的“拖拽限速”默认开启，遵循原版各角色的速度；关闭后立即跟随相对拖动。不限速拖拽不会再被灵梦＋文的加速重复放大，也不会生成文的速度残影，僚机随角色同步平移。
打开“开发者功能”后，自己的战斗中显示可拖动的“开发”按钮，横竖屏位置分别保存。点开后游戏暂停，可切换无敌、最高分数、补满资源、满火力、满残机与 Bomb 能量、全部补满及清除弹幕和激光。TH11 的 Bomb 消耗火力。关闭开发者功能会关闭无敌；回放及演示不启用作弊。
设置 → 开发者与解锁 → 输入作弊码，输入 ymgjdsh 并确认，永久解锁六种角色／搭档的 Extra、四个难度下的全部练习关卡，以及 Music Room 的全部 17 首曲目。输入错误或取消不会解锁。保留既有成绩，重启和恢复触控默认设置不会撤销解锁。
“自动 Bomb”默认关闭，开启后在实际碰撞造成中弹、死亡效果出现之前使用原作 Bomb，按当前角色的正常火力消耗扣费。擦弹、无敌、已有 Bomb、对话、回放及演示不触发；火力不足则正常受击。河城荷取的护盾会吸收触发自动 Bomb 的这次碰撞，沿用原作的护盾消耗和效果。
SDL 3.4.2 的字体通知处理会误抢原生输入框的焦点；构建工具自动应用 ios/tools/patch_sdl_uikit.py，限定只处理 SDL 自己的输入框变化。作弊码支持连续输入、删除、粘贴后确认。
成绩、设置、录像写入应用沙盒。诊断日志保存在本机，可以在设置内使用系统分享导出。

## 本地构建

先按 [ASSETS.md](ASSETS.md) 在 Windows 准备私有游戏资源、字体和图标，并将源码与 `.local` 中的资源输出复制到 Mac。
需要 CMake 3.20+、Python 3.10+、Git 和 Xcode。已验证工具链为 Xcode 14.0 / iOS 16 SDK，deployment target 为 14.0。

在 Mac 的仓库根目录运行：

```sh
bash ios/tools/fetch_dependencies.sh
bash ios/tools/native_checks.sh
TH11_SDK=iphoneos TH11_DIAGNOSTICS=OFF TH11_BUILD_NUMBER=3 bash ios/build_ios.sh
python3 ios/tools/package_ipa.py \
  .local/build-iphoneos/RelWithDebInfo-iphoneos/th11.app \
  dist/TH11-iOS14-Native-b3.ipa
```

依赖脚本固定 SDL 3.4.2，并获取旧工具链配套的 SDL_ttf 3.2.2 / FreeType；本原生目标实际链接 SDL3，字体由离线栅格数据提供。
`TH11_BUILD_JOBS` 默认 3；`TH11_BUILD_DIR`、`TH11_DEPENDENCIES`、`TH11_ASSETS`、`TH11_BUILD_NUMBER` 可覆盖默认值。

签名为 ad-hoc，供已有 TrollStore 的设备安装。普通系统直接点击 IPA 不能完成安装。打包工具拒绝模拟器或诊断版本，并校验资源、设备架构、最低系统版本、图标及签名；输出文件已存在时需选择新文件名。

## 模拟器与检查

```sh
# 不需要游戏数据的输入、生命周期及 ECL 检查
bash ios/tools/native_checks.sh --policy-only

# 完整原生检查需要 .local/assets/game/th11.dat
bash ios/tools/native_checks.sh

# 模拟器架构由当前 Mac 决定；请记录实际安装的模拟器系统版本
TH11_SDK=iphonesimulator TH11_DIAGNOSTICS=ON \
  TH11_BUILD_DIR="$PWD/.local/build-simulator-diagnostics" bash ios/build_ios.sh
```

诊断版本用于模拟器自动操作，不作为设备安装包。显示、触控和性能的验证范围见 [VALIDATION.md](VALIDATION.md) 与 [PERFORMANCE.md](PERFORMANCE.md)。战斗作弊动作及自动 Bomb 触发未记录进录像，使用这些功能后生成的录像可能无法复现该局。

## 源码导出

```sh
python3 ios/tools/package_source.py --output dist/TH11-native-source.tar.gz
```

导出原生源码、字体准备脚本、文档、组件授权说明，以及供 README 展示的 `docs/app-icon.png`。游戏资源、完整 AppIcon 构建目录、依赖安装目录、编译输出和本机配置仍由本地准备。

私有构建输入保留在本地。文档图标的来源见 [ICON.md](ICON.md)，源码及验证范围见 [VALIDATION.md](VALIDATION.md)。
