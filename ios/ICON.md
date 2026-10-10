# TH11 图标

从原版 th11.exe 的 Windows RT_GROUP_ICON 资源 IDI_ICON3 提取图标，保留原图像，缩放到 Apple AppIcon 所需尺寸。
准备输出位于 .local/app-icon/Assets.xcassets；Xcode 编译为 Assets.car 及 iPhone / iPad 图标条目。
在仓库根目录运行 `python ios/tools/prepare_icon.py --exe "<原版游戏目录>/th11.exe" --group IDI_ICON3`。
准备工具为 ios/tools/prepare_icon.py，使用 Pillow 与 pefile，仅将 exe 作为数据读取；依赖列在 ios/tools/requirements-assets.txt 中。
完整 AppIcon 构建目录保留在 `.local/app-icon/`，由本地资源准备工具生成。

仓库仅收录 `docs/app-icon.png`，供 README 展示。这张 180 × 180 PNG 与 IPA 使用的 `AppIcon-180.png` 一致，原图来自上述 `IDI_ICON3` 资源，版权归 Team Shanghai Alice / ZUN。源码导出工具仅允许这一张文档预览图；构建仍需按上述步骤生成完整图标目录。
