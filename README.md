# Swapling

把 AI 平台的额度和余额放进 MacBook 刘海的灵动岛。数据由内置的 [CodexBar](https://github.com/steipete/CodexBar) 命令行工具读取，**不需要另外安装 CodexBar**。当前版本只显示 Codex（ChatGPT）、Claude 和 DeepSeek 三个平台

## 功能
- **刘海两侧常驻**：只显示你在设置里勾选的平台（最多 4 个），圆环和百分比表示已用额度。
- **快到上限自动弹出**：已用达到 80%、95%（可调）时，灵动岛像 iPhone 实时活动一样弹出提醒，5 秒后收回。
- **用完显示倒计时**：额度用完后，刘海旁显示距离重置的时间；重置后再弹一次。
- **悬停展开**：鼠标移到灵动岛上，列出所有已开启的平台：5 小时/每周等额度、余额、今日花费、近 7 天趋势。
- 没有刘海的 Mac 会在菜单栏中间显示一个黑色胶囊。
- **看板娘随额度变化**：展开面板顶部站着 Claude、Codex 或 DeepSeek 的二创像素角色，随额度或余额状态切换表情，并在平台用尽时交接给可用平台。也可以放入你自己的形象，见 [角色资源与状态规则](Resources/Characters/README.md)。

## 安装
只支持 Apple 芯片（M 系列）的 Mac，需要 macOS 14 或更高版本。

1. 在 [Releases](https://github.com/AmakitaCastle/swapling/releases) 下载最新的 `Swapling-<版本>-arm64.zip`，解压后把 `Swapling.app` 拖进「应用程序」文件夹。
2. 目前的版本没有经过 Apple 公证，第一次打开时 macOS 会提示无法打开。点「完成」，然后到 系统设置 → 隐私与安全性，在页面下方点「仍要打开」，再确认一次即可。之后正常打开。
   如果提示「已损坏」或找不到「仍要打开」，在终端运行 `xattr -dr com.apple.quarantine /Applications/Swapling.app` 后再打开。

## 开始使用
1. 打开 Swapling，在菜单栏岛灵图标 → 设置… →「平台与 API Key」里开启要监控的平台。
2. DeepSeek 点「填 API Key」粘贴保存，保存后会自动开启。
3. Codex、Claude 这类登录型平台会沿用本机已有的登录（例如 `codex login`、Claude 命令行或浏览器登录）。

如果 app 里自带的命令行工具被删除，启动时会弹窗提醒：可以从 [CodexBar Releases](https://github.com/steipete/CodexBar/releases/latest) 手动下载 `CodexBarCLI-…-macos-arm64.tar.gz`，解压后在 设置 → 备用 CLI 路径 填入其中 `CodexBarCLI` 的位置，或者直接重新安装 Swapling。

设置保存在 `~/Library/Application Support/Swapling/codexbar-config.json`。如果你装过 CodexBar，第一次启动时会把它的配置（`~/.config/codexbar/config.json`）复制过来作为起点；之后两边互不影响，Swapling 不会改动 CodexBar 的配置。

## 编译运行
只支持 Apple 芯片（M 系列）的 Mac。需要 macOS 14+（目前只在 macOS 15 上实测过）和 Xcode 15+（或 Swift 5.9+ 工具链）。

```bash
swift test                 # 跑数据解析和提醒逻辑的测试
swift run Swapling         # 直接运行（开发用）
./scripts/install.sh       # 打包并安装到 ~/Applications/Swapling.app，然后启动
```

日常使用请用 `install.sh` 装到 `~/Applications` 再打开，不要直接打开 `dist/Swapling.app`：项目在「文稿」文件夹里，macOS 会要求「访问文稿文件夹」的权限，而每次重新打包都是新的 ad-hoc 签名，系统会忘掉上次的授权，于是反复弹窗。只想打包不安装时用 `./scripts/bundle.sh`。

菜单栏会出现一个岛灵图标，可以从这里刷新、打开设置和退出。图标资源及导出方式见 [品牌资源](Resources/Brand/README.md)。



## 许可
本项目代码以 [MIT 许可证](LICENSE) 发布。`Resources/Characters/` 中的角色图是非商用二创，不在 MIT 范围内，见 [角色图声明](Resources/Characters/NOTICE.md)。

灵动岛轮廓和动画参数改编自 [CodeIsland](https://github.com/wxtsky/CodeIsland)（MIT）。app 内附带 [CodexBar](https://github.com/steipete/CodexBar) 的命令行工具（MIT）。面板使用的 Fusion Pixel 字体为 SIL OFL 1.1。详见 `THIRD_PARTY_NOTICES.md`。

本项目与 OpenAI、Anthropic、DeepSeek 等平台无关，平台名称和图标仅用于标明数据来源。
