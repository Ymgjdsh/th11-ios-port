# TH11 图标

从原版 th11.exe 的 Windows RT_GROUP_ICON 资源 IDI_ICON3 提取图标，保留原图像，缩放到 Apple AppIcon 所需尺寸。
准备输出位于 .local/app-icon/Assets.xcassets；Xcode 编译为 Assets.car 及 iPhone / iPad 图标条目。
在仓库根目录运行 `python ios/tools/prepare_icon.py --exe "<原版游戏目录>/th11.exe" --group IDI_ICON3`。
准备工具为 ios/tools/prepare_icon.py，使用 Pillow 与 pefile，仅将 exe 作为数据读取；依赖列在 ios/tools/requirements-assets.txt 中。
图标为私有原版资源，不进入公开源码传输。
