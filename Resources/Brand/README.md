# 岛灵 / Island Spirit

2026-10-20 用户选定的正式方向：瓷白圆角底上的黑色悬浮小岛，两只椭圆眼睛、右上翘角和底部凹口构成角色特征。

## 正式资源

- `AppIcon-master.png`：内置 image_gen 根据用户选定概念图精修的透明背景母图，保留瓷白底和黑色角色的材质。
- `AppIcon.png`：1024 × 1024 应用图标。
- `AppIcon.icns` / `AppIcon.iconset/`：16–1024 px 的 macOS 图标资源。
- `mark.svg`：与代码相同的菜单栏矢量母版，24 × 20 坐标。
- `MenuBar.png` / `MenuBar@2x.png` / `MenuBar@3x.png`：22 × 18 pt 的透明单色导出。
- `preview.png`：正式应用图标及菜单栏浅色、深色、选中状态对照。

菜单栏标记由 `Sources/Swapling/BrandIcon.swift` 原生矢量绘制，不依赖运行时资源路径。眼睛是透明镂空，使用系统模板图像自动适配明暗和选中状态。相对材质图，菜单栏版本对曲线和眼孔作了小尺寸简化。

`Concepts/` 保留此前的探索；其中 `IslandSpirit/concept.png` 是用户选定的概念稿。正式图标生成提示见 `production-prompt.md`。

## 重新导出

在项目根目录运行（只做尺寸导出，无需重新调用图像生成）：

```sh
swiftc Sources/Swapling/BrandIcon.swift scripts/generate-brand-assets.swift -o /tmp/swapling-brand
/tmp/swapling-brand
iconutil -c icns Resources/Brand/AppIcon.iconset -o Resources/Brand/AppIcon.icns
./scripts/bundle.sh
```

修改菜单栏轮廓时同步更新 Swift 绘制源和 SVG。打包脚本将 ICNS 写入应用包，并通过 `CFBundleIconFile` 注册。
