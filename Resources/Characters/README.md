# 平台角色头像

内置三个平台的非官方二创角色，都是 96×96 的像素胸像，各有正常、紧张、休息三种表情：

- `claude/`：Claude 娘，参考二创设定图重绘为像素风，各表情的生成提示保存在同一目录；
- `codex/`：GPT 龙娘，原角色设计 ZipZipPipe，见 [Codex 角色说明](codex/README.md)；
- `deepseek/`：DeepSeek 鲸鱼女仆，见 [DeepSeek 角色说明](deepseek/README.md)。

**这些角色图不在本项目的 MIT 许可范围内**，版权归原作者，署名和使用条件见 [NOTICE.md](NOTICE.md)。

没有角色图的平台显示放大的像素化平台标志。想换成自己的形象，把 `normal.png`、`worried.png`、`exhausted.png` 放进 `~/Library/Application Support/Swapling/Characters/<providerID>/`，规则见下文。

## 看板娘与自动切换

展开面板顶部只站一个角色（约 96pt，最近邻缩放，透明度二值化后完全不透明），旁边的像素对话框用一句话说明现在该用哪个平台；角色站着不上下晃动，只有「紧张」时左右小幅抖动。刘海两侧不显示角色。选择规则在 `IslandCore/MascotPicker.swift`：

- 没有平台用完：显示最紧急的平台（状态优先级，其次关键额度已用比例，并列按面板顺序）。
- 有平台用完：换成仍可用平台（正常／接近上限／按余额）里关键额度用得最少的那个，表情跟它自己的状态走。
- 全部用完：显示最先恢复的平台，休息表情，对话框说明何时恢复。
- 没有角色图的平台用放大的像素化平台标志（带边框）代替，切换照样可见。

各平台自身表情：


| 文件 | 各平台的触发条件 | Claude 形象 |
| --- | --- | --- |
| `normal.png` | 可信数据且未达到第一条提醒线 | 微笑抱书 |
| `worried.png` | 任一额度达到第一条提醒线，默认已用 80% | 担心地握住领口 |
| `exhausted.png` | 任一额度用尽或部分模型受限 | 闭眼托腮休息 |

状态与面板标签共用 `QuotaOverview.status` 和用户设置的提醒线，切换「已用／剩余」显示方式不会改变角色状态。额度恢复后自动切回相应形象。数据过期或读取失败时显示低饱和度的正常头像，保留「待确认」文字，不依据旧数字显示用尽。

纯金额账户：可信余额 ≤ 0 时显示休息；正余额不套用统一货币阈值。要显示其他平台的角色，需要提供对应角色资源。

## 头像替换与回退

应用优先读取本机 `~/Library/Application Support/Swapling/Characters/<providerID>/` 中的同名图片，再读应用包内资源。账号会继承基础平台的头像（如 `claude:work` → `claude`），也支持账号专属覆盖。缺少状态图时回退到该角色的正常图，整个平台没有角色时显示原平台标志。

打包脚本自动复制 `Resources/Characters`。开发态如需直接运行，可把对应平台图片目录放进上述本机目录，或运行打包后的应用。

面板角色尺寸为 96 pt；图片所在目录带有 `pixel-art` 标记文件时，使用最近邻显示以保留像素边缘。自定义普通插画不带此标记，仍使用平滑缩放。

## 界面验收

```sh
./scripts/bundle.sh
dist/Swapling.app/Contents/MacOS/Swapling --demo --demo-characters
```

演示模式循环四个场景：Claude 正常、Codex 紧张、Claude 用完后由正常态 Codex 接班、全部用完后 Codex 休息。使用模拟额度，界面底部明确标记演示数据；加 `--demo-scene 2`、`3`、`4` 可分别固定查看 Codex 的紧张、正常、休息状态。
