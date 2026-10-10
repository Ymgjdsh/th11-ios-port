# TH11 私有资源准备

资源必须来自自己有权使用的日文 TH11 1.00a 安装。需要 `th11.exe`、`th11.dat`、`thbgm.dat`；原版 EXE 仅作为数据校验版本和提取图标，不会执行，也不进入 IPA。

资源准备工具要求原版 EXE 的 SHA-256 为：

```text
2978b17f6184d100d249d4311348dd30c5c32ec75c014b667a525b797d3d8813
```

## Windows 准备步骤

在仓库根目录运行，需要 Python 3.10+ 和 Node.js 20+：

```powershell
py -3 -m pip install -r ios/tools/requirements-assets.txt
npm --prefix th11_web/scripts ci
node th11_web/scripts/prepare-fonts.mjs
py -3 ios/tools/prepare_th11_assets.py --original "<原版游戏目录>"
py -3 ios/tools/prepare_icon.py --exe "<原版游戏目录>/th11.exe" --group IDI_ICON3
```

字体工具通过 Windows GDI 离线生成四套字形，要求系统安装原作使用的日文字体 `ＭＳ ゴシック` / `ＭＳ 明朝`（通常为 `msgothic.ttc` / `msmincho.ttc`）。缺少字体时先安装 Windows 的日文字体组件；替代字体会改变字形和布局。字体栅格数据是私有构建输入，不上传到仓库。

生成字体先写入 `th11_web/assets/sdl-native/fonts/`，随后资源工具复制到 `.local/assets/fonts/`。应用读取离线栅格数据，不依赖设备上的 Windows 字体或 GDI。

## 生成内容

- `.local/assets/game/th11.dat`：原始 THA1 游戏数据。
- `.local/assets/music/`：由 `thbgm.fmt` 指定的 18 个音乐条目转换出的 OGG Vorbis 文件。这里包括游戏使用的音乐资源，Music Room 可选曲目为 17 首。
- `.local/assets/fonts/`：四套字形、CP932 查表及像素混合表。
- `.local/assets/music-verification.json`：原始 PCM 的帧数、循环点与转换文件校验值。
- `.local/assets/manifest.json`：所有资源文件的大小和 SHA-256。
- `.local/app-icon/Assets.xcassets/`：原版图标生成的 Apple 图标目录，详见 [ICON.md](ICON.md)。

音乐转换为有损 Vorbis，核对解码采样帧数和循环位置；不宣称音频 PCM 无损一致。打包时逐项核对资源清单，不嵌入用户成绩或录像。

将源码以及 `.local/assets/`、`.local/app-icon/Assets.xcassets/` 复制到 Mac 的同一项目目录后，按 [README.md](README.md) 构建。不要复制或提交连接配置、SSH 密钥或其他私有工具链。

原版资源、字体和图标的准备输出不得随公开源码发布，仓库的忽略规则和源码打包工具均排除这些文件。
