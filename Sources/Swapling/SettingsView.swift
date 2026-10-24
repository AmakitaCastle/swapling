import AppKit
import IslandCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        EditMenu.install()
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Swapling 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, prefs: model.prefs))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let model: AppModel
    @Bindable var prefs: Preferences

    private var providerIDs: [String] {
        var ids = model.providers.map(\.id)
        for id in prefs.pinnedProviderIDs where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }

    var body: some View {
        TabView(selection: Binding(get: { model.settingsTab }, set: { model.settingsTab = $0 })) {
            displaySettings
                .tabItem { Text("显示") }
                .tag(SettingsTab.display)
            ProviderSettingsView(model: model)
                .tabItem { Text("平台与 API Key") }
                .tag(SettingsTab.providers)
            SystemSettingsView(prefs: prefs)
                .tabItem { Text("系统") }
                .tag(SettingsTab.system)
        }
        .padding(.top, 8)
        .frame(width: 500, height: 620)
    }

    private var displaySettings: some View {
        Form {
            Section {
                if providerIDs.isEmpty {
                    Text("还没有读到平台。到「平台与 API Key」里开启要监控的平台。")
                        .foregroundStyle(.secondary)
                }
                ForEach(providerIDs, id: \.self) { id in
                    Toggle(isOn: Binding(
                        get: { prefs.isPinned(id) },
                        set: { prefs.setPinned(id, $0) }
                    )) {
                        Text(ProviderCatalog.displayName(for: id))
                    }
                    .disabled(!prefs.isPinned(id) && prefs.pinnedProviderIDs.count >= Preferences.maxPinned)
                }
            } header: {
                Text("刘海旁显示的平台")
            } footer: {
                Text("最多 \(Preferences.maxPinned) 个。鼠标悬停在灵动岛上时，会列出所有已开启的平台。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if prefs.pinnedProviderIDs.count > 1 {
                Section("刘海旁的顺序（从左到右）") {
                    ForEach(Array(prefs.pinnedProviderIDs.enumerated()), id: \.element) { index, id in
                        HStack {
                            Text("\(index + 1). \(ProviderCatalog.displayName(for: id))")
                            Spacer()
                            Button {
                                prefs.movePinned(id, by: -1)
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .disabled(index == 0)
                            .help("往左移")
                            Button {
                                prefs.movePinned(id, by: 1)
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .disabled(index == prefs.pinnedProviderIDs.count - 1)
                            .help("往右移")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section {
                Picker("数字显示", selection: $prefs.showRemaining) {
                    Text("已用").tag(false)
                    Text("剩余").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("展开面板排序", selection: Binding(
                    get: { prefs.panelOrder },
                    set: { prefs.panelOrder = $0; model.snapshotPanelOrder() }
                )) {
                    Text("优先关注（受限、接近上限在前）").tag(PanelOrderMode.attention)
                    Text("固定顺序（与平台列表一致）").tag(PanelOrderMode.fixed)
                }
                Toggle("紧凑模式：只显示图标和圆环", isOn: $prefs.compactEars)
                Picker("同时显示", selection: $prefs.earItemLimit) {
                    Text("2 个").tag(2)
                    Text("4 个").tag(4)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("刘海旁的样式")
            } footer: {
                Text("刘海旁默认显示 5 小时额度，周额度已过第一条提醒线且比 5 小时更紧、或已用完时改为显示周额度；数字旁总会标出是哪个额度（5h / 周）。「数字显示」同时用于刘海、菜单栏和展开面板；提醒文案会同时写出已用和剩余。钉住的平台比「同时显示」多时，会每 \(Int(CollapsedDisplay.rotationPeriod)) 秒轮换一次；用量超过第一次提醒线的平台会一直显示。某个平台的数据超过两个刷新周期没更新、或本次读取失败时，只有这个平台会变暗。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("鼠标悬停时展开面板", isOn: $prefs.hoverToExpand)
                Picker("悬停延迟", selection: $prefs.hoverDelay) {
                    ForEach(HoverDelay.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .disabled(!prefs.hoverToExpand)
                Picker("展开快捷键", selection: $prefs.expandShortcut) {
                    ForEach(ExpandShortcut.allCases) { Text($0.label).tag($0) }
                }
                if model.shortcutRegistrationFailed {
                    Text("这个快捷键已被其他应用占用，请换一个。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("展开方式")
            } footer: {
                Text("鼠标需要在刘海上停稳一会儿才展开，只是划过不会打开；停留时持续移动会重新计时。点击刘海会立即展开并保持展开，按 Esc、点收起按钮或关掉「保持展开」后收起。关闭悬停展开后，只有点击、快捷键或菜单栏「显示额度面板」会打开面板。快捷键再按一次收起，不需要辅助功能权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("看板娘跟随正在使用的 AI", isOn: $prefs.mascotFollowsActiveAgent)
                    .onChange(of: prefs.mascotFollowsActiveAgent) { model.updateActiveAgent() }
            } header: {
                Text("看板娘")
            } footer: {
                Text("打开面板时，看板娘换成你正在用的 AI：前台是 Claude 就是 Claude，前台是 ChatGPT / Codex 就是 Codex；前台是终端或编辑器时，看 10 分钟内最近写过的 Claude Code 或 Codex CLI 会话记录（只看修改时间，不读内容）。它的额度用完时，照常换成下一个还能用的平台。关闭后按额度最紧急的平台显示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("提醒") {
                Toggle("快到上限时弹出灵动岛提醒", isOn: $prefs.popupEnabled)
                // Each line bounds the other, so the first warning always stays below the second.
                Stepper(
                    "第一次提醒：已用 \(prefs.warnLevel1)%",
                    value: $prefs.warnLevel1,
                    in: QuotaThresholds.range.lowerBound...(prefs.warnLevel2 - 1),
                    step: 5
                )
                Stepper(
                    "第二次提醒：已用 \(prefs.warnLevel2)%",
                    value: $prefs.warnLevel2,
                    in: (prefs.warnLevel1 + 1)...QuotaThresholds.range.upperBound,
                    step: 1
                )
                Toggle("提醒时播放提示音", isOn: $prefs.alertSound)
                Toggle("同时发送系统通知（全屏或看不到刘海时有用）", isOn: $prefs.systemNotification)
                    .onChange(of: prefs.systemNotification) { _, enabled in
                        if enabled { AlertNotifier.requestPermission() }
                    }
                Text("刘海和面板的颜色也用这两条线：低于第一条为绿色（正常），到第一条为橙色（紧张），到第二条为红色并开始呼吸光效（接近上限）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("额度用完时会显示重置倒计时，重置后再弹一次。同一平台同时触发的提醒合并成一条；鼠标移到提醒上会展开面板并标出该平台；展开面板时到来的提醒会在收起后补弹。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("数据") {
                Picker("刷新间隔", selection: $prefs.refreshInterval) {
                    Text("1 分钟").tag(60.0)
                    Text("2 分钟").tag(120.0)
                    Text("5 分钟").tag(300.0)
                    Text("10 分钟").tag(600.0)
                }
                Picker("金额显示", selection: $prefs.displayCurrency) {
                    ForEach(DisplayCurrency.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if prefs.displayCurrency == .cny {
                    TextField(
                        "汇率（1 美元 = ? 人民币）",
                        value: Binding(get: { prefs.usdToCNY }, set: { if $0 > 0 { prefs.usdToCNY = $0 } }),
                        format: .number.precision(.fractionLength(0...4))
                    )
                    .textFieldStyle(.roundedBorder)
                }
                TextField("备用 CLI 路径（仅在内置数据组件缺失时使用）", text: $prefs.cliPath)
                    .textFieldStyle(.roundedBorder)
                cliStatus
                Button("立即刷新") {
                    Task { await model.refresh() }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var cliStatus: some View {
        if let found = model.client.resolvedCLI() {
            Label(found.source == .bundled ? "数据组件：内置" : "数据组件：\(found.path)", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Label(CodexBarClientError.cliNotFound.localizedDescription, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            Link("前往下载 CodexBar 命令行工具", destination: CodexBarCLILocator.manualDownloadURL)
                .font(.caption)
        }
        if let error = model.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

/// Login item, which display the island uses, when it hides, and the menu-bar fallback.
private struct SystemSettingsView: View {
    @Bindable var prefs: Preferences

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    /// Connected displays, plus the saved one when it is unplugged right now.
    private var screenNames: [String] {
        var names = NSScreen.screens.map(\.localizedName)
        if !["auto", "main"].contains(prefs.screenChoice), !names.contains(prefs.screenChoice) {
            names.append(prefs.screenChoice)
        }
        return names
    }

    var body: some View {
        Form {
            Section {
                Toggle("登录 Mac 时自动打开 Swapling", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        launchError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("启动")
            } footer: {
                Text("Mac 从睡眠中唤醒后，会自动刷新一次额度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("显示位置") {
                Picker("显示在", selection: $prefs.screenChoice) {
                    Text("自动（有刘海的屏幕）").tag("auto")
                    Text("主显示器（有菜单栏的屏幕）").tag("main")
                    ForEach(screenNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Toggle("有 App 全屏时隐藏灵动岛", isOn: $prefs.hideInFullScreen)
                Toggle("屏幕共享和录屏时不显示灵动岛", isOn: $prefs.hideFromScreenSharing)
            }

            Section {
                Toggle("菜单栏图标旁显示用量最高平台的百分比", isOn: $prefs.menuBarPercent)
            } header: {
                Text("菜单栏")
            } footer: {
                Text("灵动岛被挡住、隐藏，或在用外接显示器时，可以从这里看。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
