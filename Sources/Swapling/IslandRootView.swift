import IslandCore
import SwiftUI

private enum Palette {
    static let primary = Pixel.text
    static let secondary = Pixel.muted
    static let card = Pixel.card
}

extension AppModel {
    /// The character for the panel and the notch, chosen among all providers in panel order.
    func mascotChoice(now: Date) -> MascotChoice? {
        let prefs = self.prefs
        // Nil when the setting is off (see updateActiveAgent).
        return MascotPicker.pick(orderedProviders, thresholds: prefs.thresholds, now: now, activeProviderID: activeProviderID) { provider in
            QuotaOverview.status(of: provider, thresholds: prefs.thresholds, refreshInterval: prefs.refreshInterval, now: now)
        }
    }

    func mascotSentence(_ choice: MascotChoice, now: Date) -> String {
        let prefs = self.prefs
        return MascotPicker.sentence(
            for: choice, providers: orderedProviders, thresholds: prefs.thresholds, now: now, money: prefs.money
        ) { provider in
            QuotaOverview.status(of: provider, thresholds: prefs.thresholds, refreshInterval: prefs.refreshInterval, now: now)
        }
    }
}

struct IslandRootView: View {
    let model: AppModel
    let geometry: NotchGeometry

    /// Widest ear content as laid out, reported by `CollapsedView`.
    @State private var earContentWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Grows out of the notch, or just fades in with Reduce Motion on.
    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var island: some View {
        content
            .frame(width: islandWidth, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: bottomRadius, style: .continuous))
            .background(
                IslandShape(topExtension: shoulder, bottomRadius: bottomRadius)
                    .fill(model.surface == .expanded ? Pixel.background : Color.black)
            )
            // Measured directly: a size preference read from the VStack got the Spacer's default
            // (zero) instead, which made every hover point miss.
            .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { size in
                model.islandSize = size
            }
            // Hover follows the visible outline: the padding makes room for the shoulders, and
            // the transparent area cut away by the bottom corners doesn't count.
            .padding(.horizontal, shoulder)
            .contentShape(Rectangle())
            // A click on the collapsed island or a pop-up opens the panel and keeps it open; inside
            // the open panel, clicks belong to its controls.
            .simultaneousGesture(TapGesture().onEnded {
                if model.surface != .expanded { model.openByClick() }
            }, including: model.surface == .expanded ? .subviews : .all)
            .onContinuousHover { phase in
                guard case let .active(point) = phase else {
                    model.pointerMoved(to: nil, inside: false)
                    return
                }
                // The width is the one laid out, not the measured one: a measurement can lag a
                // quick change of width and leave part of the island dead to the pointer.
                let size = CGSize(width: islandWidth, height: model.islandSize.height)
                let inside = IslandOutline.hoverContains(
                    point, islandSize: size, topExtension: shoulder, bottomRadius: bottomRadius
                )
                model.pointerMoved(to: point, inside: inside)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.surface {
        case .collapsed:
            CollapsedView(model: model, geometry: geometry, earWidth: earWidth) { width in
                guard abs(width - earContentWidth) > 0.5 else { return }
                withAnimation(IslandAnimation.close) { earContentWidth = width }
            }
                .transition(.opacity)
        case let .alert(group):
            AlertView(model: model, group: group, geometry: geometry)
                .transition(panelTransition)
        case .expanded:
            ExpandedView(model: model, geometry: geometry)
                .transition(panelTransition)
        }
    }

    // MARK: Metrics

    /// Width of each "ear" beside the physical notch: the wider side's content plus padding, so
    /// the notch stays centred and the island never grows past what it shows.
    private var earWidth: CGFloat {
        earContentWidth > 0 ? earContentWidth + 16 : 0
    }

    private var islandWidth: CGFloat {
        switch model.surface {
        case .collapsed: return geometry.notchWidth + earWidth * 2
        case .alert: return max(geometry.notchWidth + 180, 400)
        case .expanded: return max(geometry.notchWidth + 160, 470)
        }
    }

    private var shoulder: CGFloat { model.surface.isCollapsed ? 6 : 14 }
    private var bottomRadius: CGFloat {
        switch model.surface {
        case .collapsed: return 10
        case .alert: return 22
        case .expanded: return 26
        }
    }
}

// MARK: - Collapsed

/// How the pinned providers are drawn beside the notch, from Settings.
private struct EarStyle {
    var showRemaining: Bool
    var compact: Bool
    /// Colours and the glow; the same lines the pop-up alerts use.
    var thresholds: QuotaThresholds
    var money: MoneyDisplay

    @MainActor
    init(prefs: Preferences) {
        showRemaining = prefs.showRemaining
        compact = prefs.compactEars
        thresholds = prefs.thresholds
        money = prefs.money
    }
}

private struct CollapsedView: View {
    let model: AppModel
    let geometry: NotchGeometry
    let earWidth: CGFloat
    let onMeasureEars: (CGFloat) -> Void

    /// Nil until that side has been laid out.
    @State private var leftWidth: CGFloat?
    @State private var rightWidth: CGFloat?

    var body: some View {
        // Ticks drive rotation through extra pins and re-check staleness.
        TimelineView(.periodic(from: .now, by: CollapsedDisplay.rotationPeriod)) { context in
            row(now: context.date)
        }
        // Both sides read from state here, not from one side's closure: there the other side's
        // width could be stale, and a wider side would spill under the camera (the lone
        // provider's icon went missing that way).
        // Waits for both sides: reporting the unmeasured zero shrank the island for a moment on
        // every collapse, and the hover zone kept that narrow width, so the right side never opened.
        .onChange(of: earsWidth, initial: true) { _, width in
            if let width { onMeasureEars(width) }
        }
    }

    private var earsWidth: CGFloat? {
        guard let leftWidth, let rightWidth else { return nil }
        return max(leftWidth, rightWidth)
    }

    private func row(now: Date) -> some View {
        let prefs = model.prefs
        let pinned = model.pinnedProviders
        let page = Int(now.timeIntervalSince1970 / CollapsedDisplay.rotationPeriod)
        let rotating = CollapsedDisplay.visibleProviders(
            pinned,
            limit: max(prefs.earItemLimit, 1),
            urgentPercent: Double(prefs.thresholds.warn1),
            page: page
        )
        // The AI in use stays on show (in place of a non-urgent item) so its bar can be marked.
        let visible = CollapsedDisplay.withActive(
            rotating,
            candidates: pinned + model.orderedProviders.filter { !prefs.isPinned($0.id) },
            activeProviderID: model.activeProviderID,
            limit: max(prefs.earItemLimit, 1),
            urgentPercent: Double(prefs.thresholds.warn1)
        )
        let activeID = CollapsedDisplay.activeID(in: visible, activeProviderID: model.activeProviderID)
        let badges = ProviderCatalog.badges(for: pinned.map(\.id) + visible.map(\.id).filter { !prefs.isPinned($0) })
        let style = EarStyle(prefs: prefs)
        // Judged per provider: one provider's old numbers grey out only that provider.
        let staleIDs = Set(visible.filter { provider in
            Freshness.of(provider, refreshInterval: prefs.refreshInterval, now: now)?.isStale ?? false
        }.map(\.id))

        return HStack(spacing: 0) {
            ear(alignment: .leading, measure: $leftWidth) {
                if visible.count == 1 {
                    if !style.compact {
                        EarLabel(provider: visible[0], style: style)
                            .modifier(StaleDimming(stale: staleIDs.contains(visible[0].id)))
                    }
                } else if pinned.isEmpty, model.providers.isEmpty, model.lastError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                } else {
                    ForEach(leftHalf(visible)) {
                        EarItem(provider: $0, badge: badges[$0.id] ?? "", style: style, stale: staleIDs.contains($0.id),
                                isActive: $0.id == activeID, sweeps: model.islandOnScreen)
                    }
                }
            }
            Color.clear.frame(width: geometry.notchWidth)
            ear(alignment: .trailing, measure: $rightWidth) {
                if visible.count == 1 {
                    HStack(spacing: 5) {
                        ProviderIcon(providerID: visible[0].id, size: 11, fallback: badges[visible[0].id] ?? "")
                            .foregroundStyle(Palette.secondary)
                        EarBar(provider: visible[0], style: style, cells: 8,
                               isActive: visible[0].id == activeID, sweeps: model.islandOnScreen)
                    }
                    .modifier(StaleDimming(stale: staleIDs.contains(visible[0].id)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(EarAccessibility.label(for: visible[0], style: style, stale: staleIDs.contains(visible[0].id))
                        + (visible[0].id == activeID ? "，正在使用" : ""))
                } else {
                    ForEach(rightHalf(visible)) {
                        EarItem(provider: $0, badge: badges[$0.id] ?? "", style: style, stale: staleIDs.contains($0.id),
                                isActive: $0.id == activeID, sweeps: model.islandOnScreen)
                    }
                }
            }
        }
        .frame(height: geometry.notchHeight)
        .animation(.easeInOut(duration: 0.35), value: visible.map(\.id))
        .animation(.easeInOut(duration: 0.35), value: staleIDs)
    }

    private func ear<Content: View>(
        alignment: Alignment,
        measure: Binding<CGFloat?>,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        HStack(spacing: 8) { content() }
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width } action: { width in
                measure.wrappedValue = width
            }
            .padding(.horizontal, earWidth > 0 ? 8 : 0)
            .frame(width: earWidth, height: geometry.notchHeight, alignment: alignment)
            .clipped()
    }

    private func leftHalf(_ items: [ProviderUsage]) -> [ProviderUsage] {
        Array(items.prefix((items.count + 1) / 2))
    }

    private func rightHalf(_ items: [ProviderUsage]) -> [ProviderUsage] {
        Array(items.dropFirst((items.count + 1) / 2))
    }
}

/// The collapsed gauge: a short block bar of what's used (or what's left); grey when unknown.
/// The AI in use gets one bright cell stepping slowly across it (流光), or a still underline with
/// Reduce Motion; the bar's size never changes.
private struct EarBar: View {
    let provider: ProviderUsage
    let style: EarStyle
    var cells = 5
    var isActive = false
    /// False while the island is off screen, which removes (stops) the sweep.
    var sweeps = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let filled = filledCells
        bar
            .overlay {
                if isActive, !reduceMotion, sweeps {
                    SweepLayer(cells: cells, filled: filled)
                }
            }
            .overlay(alignment: .bottom) {
                if isActive, reduceMotion {
                    // Still marker: a 1pt bright line just under the bar (an overlay, so nothing moves).
                    Rectangle().fill(Pixel.text).frame(height: 1).offset(y: 2)
                }
            }
    }

    private var shownPercent: Double {
        window.map { CollapsedDisplay.shownPercent(for: $0, showRemaining: style.showRemaining) } ?? 0
    }

    private var window: QuotaWindow? {
        provider.error == nil ? QuotaOverview.displayWindow(of: provider, thresholds: style.thresholds) : nil
    }

    private var filledCells: Int {
        SegmentedBar.litCells(percent: shownPercent, cells: cells)
    }

    private var bar: some View {
        SegmentedBar(
            percent: shownPercent,
            color: window.map { QuotaColor.color(forUsed: $0.usedPercent, style.thresholds) } ?? Pixel.muted,
            cells: cells,
            cellHeight: 8,
            gap: 2
        )
        .frame(width: CGFloat(cells) * 4 + CGFloat(cells - 1) * 2)
    }
}

/// Percent (with its quota window), the reset countdown once a window is exhausted, or a warning.
private struct EarLabel: View {
    let provider: ProviderUsage
    let style: EarStyle

    var body: some View {
        if provider.error != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.orange)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                label(now: context.date)
            }
        }
    }

    private func label(now: Date) -> some View {
        // 5h by default; the weekly window only when it needs attention (see displayWindow).
        let window = QuotaOverview.displayWindow(of: provider, thresholds: style.thresholds)
        let shown = window.map { CollapsedDisplay.shownPercent(for: $0, showRemaining: style.showRemaining) } ?? 0
        let text: String
        if let window, window.isExhausted, let resetsAt = window.resetsAt, resetsAt > now {
            text = IslandFormat.shortCountdown(to: resetsAt, now: now)
        } else if let window, window.isBalanceGauge, let balance = provider.balance {
            // The bar already shows the share left; the amount says more than a second percent.
            text = style.money.format(balance.amount, from: balance.currencyCode)
        } else if window != nil {
            text = IslandFormat.percent(shown)
        } else if let balance = provider.balance {
            // Pay-as-you-go: no percent exists, so the amount stands in for it.
            text = style.money.format(balance.amount, from: balance.currencyCode)
        } else {
            text = "–"
        }
        let color = window.map { QuotaColor.color(forUsed: $0.usedPercent, style.thresholds) }
            ?? (provider.balance != nil ? Palette.primary : QuotaColor.color(for: .unknown))
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(text)
                .font(PixelFont.font())
                .foregroundStyle(color)
                .contentTransition(.numericText(value: shown))
            // Always named: the shown window can change, so the number never stands alone.
            if let tag = window?.shortLabel {
                Text(tag)
                    .font(PixelFont.font())
                    .foregroundStyle(Palette.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .animation(.snappy, value: text)
    }
}

/// Out-of-date numbers turn grey instead of pretending to be current.
private struct StaleDimming: ViewModifier {
    let stale: Bool

    func body(content: Content) -> some View {
        content
            .saturation(stale ? 0 : 1)
            .opacity(stale ? 0.5 : 1)
    }
}

private struct EarItem: View {
    let provider: ProviderUsage
    let badge: String
    let style: EarStyle
    var stale = false
    var isActive = false
    var sweeps = true

    var body: some View {
        HStack(spacing: 3) {
            ProviderIcon(providerID: provider.id, size: 11, fallback: badge)
                .foregroundStyle(Palette.secondary)
            EarBar(provider: provider, style: style, isActive: isActive, sweeps: sweeps)
            if !style.compact {
                EarLabel(provider: provider, style: style)
            }
        }
        .modifier(StaleDimming(stale: stale))
        .help(stale ? "\(provider.displayName)：数据已过期" : provider.displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EarAccessibility.label(for: provider, style: style, stale: stale) + (isActive ? "，正在使用" : ""))
        .transition(.opacity)
    }
}

// MARK: - Alert (Live Activity style pop-up)

private struct AlertView: View {
    let model: AppModel
    let group: AlertGroup
    let geometry: NotchGeometry

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.notchHeight)
            HStack(spacing: 12) {
                ZStack {
                    QuotaRing(
                        usedPercent: window.usedPercent,
                        thresholds: thresholds,
                        lineWidth: 4,
                        showsRemaining: model.prefs.showRemaining
                    )
                    Text(IslandFormat.percent(
                        CollapsedDisplay.shownPercent(for: window, showRemaining: model.prefs.showRemaining)
                    ))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.primary)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        ProviderIcon(providerID: group.providerID, size: 12)
                            .foregroundStyle(Palette.primary)
                        Text(group.title)
                            .font(PixelFont.font())
                            .foregroundStyle(Palette.primary)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(group.subtitle(now: context.date))
                            .font(PixelFont.font())
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
    }

    private var window: QuotaWindow { group.primary.window }
    private var thresholds: QuotaThresholds { model.prefs.thresholds }

    private var icon: String {
        switch group.primary {
        case .threshold: return "exclamationmark.circle.fill"
        case .exhausted: return "hourglass"
        case .reset: return "checkmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch group.primary {
        case .threshold: return QuotaColor.color(forUsed: window.usedPercent, thresholds)
        case .exhausted: return QuotaColor.color(for: .exhausted)
        case .reset: return QuotaColor.color(for: .normal)
        }
    }
}

// MARK: - Expanded (hover)

private struct ExpandedView: View {
    let model: AppModel
    let geometry: NotchGeometry

    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: max(geometry.notchHeight - 6, 0))
            header
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let choice = model.mascotChoice(now: context.date) {
                    MascotHero(choice: choice, sentence: model.mascotSentence(choice, now: context.date))
                }
            }
            if let error = model.lastError {
                // With cards below, their numbers are from earlier reads and say how old they are.
                IssueView(
                    issue: model.lastIssue ?? .other,
                    detail: error,
                    title: model.providers.isEmpty ? nil : "刷新失败，下面是之前读到的数据",
                    providerID: nil,
                    model: model
                )
                .padding(10)
                .pixelBox(fill: Palette.card, border: Pixel.warn)
            } else if model.providers.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("正在读取额度数据…")
                }
                .font(PixelFont.font())
                .foregroundStyle(Palette.secondary)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
            list
            footer
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("额度与余额")
                .font(PixelFont.font())
                .foregroundStyle(Pixel.frame)
            // Says what every percent below means; same setting as the notch and the menu bar.
            PixelTag(
                text: "百分比 = \(CollapsedDisplay.modeLabel(showRemaining: model.prefs.showRemaining))",
                color: Pixel.button,
                textColor: Palette.secondary
            )
                .help("刘海、菜单栏和这里的百分比都按设置 → 显示 → 数字显示 的选择，当前为「\(CollapsedDisplay.modeLabel(showRemaining: model.prefs.showRemaining))」")
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            Menu {
                Picker("排序", selection: Binding(
                    get: { model.prefs.panelOrder },
                    set: { model.prefs.panelOrder = $0; model.snapshotPanelOrder() }
                )) {
                    Text(PanelOrderMode.attention.label).tag(PanelOrderMode.attention)
                    Text(PanelOrderMode.fixed.label).tag(PanelOrderMode.fixed)
                }
                .pickerStyle(.inline)
            } label: {
                Text(model.prefs.panelOrder.label)
                    .font(PixelFont.font())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("卡片排序。面板打开期间顺序不变，下次打开再按最新状态排序。")
            .accessibilityLabel("排序：\(model.prefs.panelOrder.label)")
            // 保持展开 keeps this panel open; the pin on each card is 常驻刘海, a different thing.
            Button {
                model.togglePanelPinned()
            } label: {
                HeaderIcon(systemName: model.isPanelPinned ? "lock.fill" : "lock.open")
                    .foregroundStyle(model.isPanelPinned ? Palette.primary : Palette.secondary)
            }
            .help(model.isPanelPinned ? "保持展开：已开启，点击后鼠标移开会收起" : "保持展开：鼠标移开也不收起")
            .accessibilityLabel(model.isPanelPinned ? "取消保持展开" : "保持展开")
            Button {
                Task { await model.refresh() }
            } label: {
                HeaderIcon(systemName: "arrow.clockwise")
            }
            .disabled(model.isRefreshing)
            .help("立即刷新")
            .accessibilityLabel("立即刷新")
            Button {
                model.openSettings()
            } label: {
                HeaderIcon(systemName: "gearshape")
            }
            .help("设置")
            .accessibilityLabel("打开设置")
            Button {
                model.collapsePanel()
            } label: {
                HeaderIcon(systemName: "xmark")
            }
            .help("收起面板（Esc）")
            .accessibilityLabel("收起面板")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Palette.secondary)
    }

    /// Room left for cards below the header and above the footer.
    private var listMaxHeight: CGFloat {
        max(geometry.panelHeight - geometry.notchHeight - 120, 200)
    }

    private var list: some View {
        let cards = VStack(spacing: 8) {
            ForEach(model.orderedProviders) { provider in
                ProviderCard(
                    provider: provider,
                    isPinned: model.prefs.isPinned(provider.id),
                    isHighlighted: model.highlightedProviderID == provider.id,
                    model: model
                )
                .id(provider.id)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.height } action: { height in
            model.listContentHeight = height
        }
        // Until measured, guess from the card count so the first opening doesn't jump.
        let measured = model.listContentHeight > 0
            ? model.listContentHeight
            : CGFloat(model.providers.count) * 110
        let overflows = measured > listMaxHeight
        return ScrollViewReader { reader in
            // Short lists take exactly their height; long ones scroll inside what the screen allows.
            ScrollView { cards }
                .scrollIndicators(.never)
                .scrollDisabled(!overflows)
                .frame(height: min(measured, listMaxHeight))
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, overflows ? .clear : .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 18)
                    }
                }
                .onAppear {
                    // Opened from a pop-up: bring that provider's card into view.
                    if let id = model.highlightedProviderID {
                        reader.scrollTo(id, anchor: .center)
                    }
                }
        }
    }

    private var footer: some View {
        // The last refresh as a whole; each card says how old its own numbers are.
        let refreshed = model.lastRefresh.map {
            "上次刷新 \($0.formatted(date: .omitted, time: .shortened))\(model.lastError == nil ? "" : "，之后的刷新失败")"
        }
        let source = AppModel.isDemo ? "演示数据（--demo），不是真实额度" : "数据来自 CodexBar"
        return ViewThatFits(in: .horizontal) {
            HStack {
                if let refreshed { Text(refreshed) }
                Spacer()
                Text(source)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let refreshed { Text(refreshed) }
                Text(source)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(PixelFont.font())
        .lineLimit(1)
        .foregroundStyle(Palette.secondary)
    }
}

private struct ProviderCard: View {
    let provider: ProviderUsage
    let isPinned: Bool
    var isHighlighted = false
    let model: AppModel

    @ViewBuilder
    private var browserImport: some View {
        HStack(spacing: 6) {
            Button {
                Task { await model.importBrowserLogin(provider: provider.id) }
            } label: {
                PixelButtonLabel(title: model.isImportingCookies ? "正在导入…" : "从浏览器导入登录")
            }
            .buttonStyle(.plain)
            .disabled(model.isImportingCookies)
            .help("读取 Chrome / Edge 里 claude.ai 的登录。macOS 可能会问一次是否允许访问钥匙串，选「始终允许」以后就不会再问。")
            if model.isImportingCookies {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            }
        }
        if let message = model.cookieImportMessage {
            Text(message)
                .font(PixelFont.font())
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    /// The provider's own message, selectable so it can be copied into a bug report.
    private func errorDetail(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(error)
                .font(PixelFont.font())
                .foregroundStyle(Palette.primary)
            if let detail = provider.errorDetail {
                Text(detail)
                    .font(PixelFont.font())
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .padding(7)
        .background(Pixel.background)
    }

    private var costHelp: String {
        let basis = provider.costIsEstimate ? "按本机日志里的 token 数和公开价格估算，不是账单金额" : "来自本机日志"
        return "\(basis)；包含这台 Mac 上该平台所有账号的用量，不能用于预算判断。"
    }

    private var status: ProviderStatus {
        QuotaOverview.status(
            of: provider, thresholds: model.prefs.thresholds, refreshInterval: model.prefs.refreshInterval, now: Date()
        )
    }

    private var showsDetails: Bool { model.expandedCardIDs.contains(provider.id) }

    private func freshness(now: Date) -> DataFreshness? {
        Freshness.of(provider, refreshInterval: model.prefs.refreshInterval, now: now)
    }

    /// "OAuth · 更新于 3 分钟前": where the numbers came from and how fresh they are. "采集于" when
    /// the source gives no time of its own, so read time is never passed off as source time.
    private func metaText(now: Date) -> String {
        var parts: [String] = []
        if let source = PanelDisplay.sourceLabel(provider.source) { parts.append(source) }
        if let freshness = freshness(now: now) { parts.append(freshness.label(now: now)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        cardContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .pixelBox(fill: Palette.card, border: frameColor)
    }

    /// Dim while fine, yellow near the limit, red once used up; bright when a pop-up points here.
    private var frameColor: Color {
        switch status {
        case .limited(partial: false): return Pixel.bad
        case .limited(partial: true), .nearLimit: return Pixel.warn
        case .normal, .balance, .unconfirmed: return isHighlighted ? Pixel.frame : Pixel.frameDim
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            // First layer: who, state, the one quota that matters, and when it comes back.
            HStack(spacing: 8) {
                PixelIcon(providerID: provider.id)
                Text(provider.displayName)
                    .font(PixelFont.font())
                    .foregroundStyle(Palette.primary)
                    .lineLimit(1)
                StatusTag(status: status)
                Spacer(minLength: 4)
                // A balance is the headline only for pay-as-you-go providers; next to quota
                // windows (e.g. Codex credits) it is a detail.
                if provider.windows.isEmpty, let balance = provider.balance {
                    Text("余额 \(model.prefs.money.format(balance.amount, from: balance.currencyCode))")
                        .font(PixelFont.font())
                        .foregroundStyle(Palette.primary)
                }
                NotchPinToggle(providerID: provider.id, isPinned: isPinned, model: model)
                Button {
                    withAnimation(.snappy) { model.toggleCardDetails(provider.id) }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showsDetails ? 180 : 0))
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                        .foregroundStyle(Palette.secondary)
                }
                .buttonStyle(.plain)
                .help(showsDetails ? "收起详情" : "详情：全部额度、费用、来源与诊断")
                .accessibilityLabel(showsDetails ? "收起 \(provider.displayName) 详情" : "展开 \(provider.displayName) 详情")
            }

            // Re-evaluated on each refresh and on the cards' timers; a TimelineView here would
            // take up room even when there is no warning.
            if let warning = freshness(now: Date())?.warning {
                Label(warning, systemImage: "clock.badge.exclamationmark")
                    .font(PixelFont.font())
                    .foregroundStyle(Pixel.warn)
            }

            if let error = provider.error {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text(PanelDisplay.errorSummary(error))
                        .font(PixelFont.font())
                }
                .foregroundStyle(Pixel.warn)
                IssueActions(issue: DataIssue.classify(error), providerID: provider.id, model: model)
                if ClaudeFallback.offersBrowserImport(provider) {
                    browserImport
                }
            }

            if let key = QuotaOverview.keyWindow(of: provider, thresholds: model.prefs.thresholds) {
                KeyWindowView(provider: provider, window: key, model: model)
                    .modifier(StaleDimming(stale: freshness(now: Date())?.isStale ?? false))
            }

            if showsDetails {
                details
            }
        }
    }

    /// Second layer: every window, cost, trend, plan, source, freshness and raw errors.
    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle().fill(Pixel.frameDim).frame(height: 2)
            if provider.windows.count > 0 {
                Text("全部额度")
                    .font(PixelFont.font())
                    .foregroundStyle(Pixel.frame)
                ForEach(provider.windows) { window in
                    WindowRow(window: window, thresholds: model.prefs.thresholds, showRemaining: model.prefs.showRemaining)
                }
                .modifier(StaleDimming(stale: freshness(now: Date())?.isStale ?? false))
            }

            if provider.todayCost != nil || provider.dailyCosts.count > 1 {
                HStack(spacing: 8) {
                    if let today = provider.todayCost {
                        // Priced from this Mac's local logs at list prices: an estimate, not a bill,
                        // covering every account of the provider used on this Mac.
                        Text("今日\(provider.costIsEstimate ? "估算" : "花费") \(model.prefs.money.format(today))")
                            .font(PixelFont.font())
                            .foregroundStyle(Palette.secondary)
                            .help(costHelp)
                    }
                    Spacer()
                    if provider.dailyCosts.count > 1 {
                        Text(provider.costIsEstimate ? "近 7 天估算" : "近 7 天")
                            .font(PixelFont.font())
                            .foregroundStyle(Palette.secondary)
                        Sparkline(values: provider.dailyCosts.suffix(7).map(\.cost))
                            .frame(width: 90, height: 16)
                    }
                }
            }

            if let error = provider.error {
                errorDetail(error)
            }

            if let balance = provider.balance, !balance.parts.isEmpty {
                Text(balance.parts
                    .map { "\($0.label) \(model.prefs.money.format($0.amount, from: balance.currencyCode))" }
                    .joined(separator: " · "))
                    .font(PixelFont.font())
                    .foregroundStyle(Palette.secondary)
            }

            HStack(spacing: 6) {
                if !provider.windows.isEmpty, let balance = provider.balance {
                    Text("余额 \(model.prefs.money.format(balance.amount, from: balance.currencyCode))")
                        .font(PixelFont.font())
                        .foregroundStyle(Palette.secondary)
                }
                if let plan = provider.plan, !plan.isEmpty {
                    PixelTag(text: plan, color: Pixel.button, textColor: Palette.secondary)
                }
                if let url = PanelDisplay.usageURL(for: provider.id) {
                    Link(destination: url) {
                        Label("用量页面", systemImage: "arrow.up.right.square")
                            .font(PixelFont.font())
                            .foregroundStyle(Palette.secondary)
                    }
                    .help("在浏览器打开 \(provider.displayName) 的用量页面")
                    .accessibilityLabel("打开 \(provider.displayName) 用量页面")
                }
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(metaText(now: context.date))
                        .font(PixelFont.font())
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .transition(.opacity)
    }
}

/// The card's main line: the key window's percent and bar, then when quota comes back.
private struct KeyWindowView: View {
    let provider: ProviderUsage
    let window: QuotaWindow
    let model: AppModel

    var body: some View {
        let prefs = model.prefs
        let shown = CollapsedDisplay.shownPercent(for: window, showRemaining: prefs.showRemaining)
        VStack(alignment: .leading, spacing: 4) {
            // A balance bar leads with the money; the percent is only the share of the last top-up.
            let balance = window.isBalanceGauge ? provider.balance : nil
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(balance != nil
                    ? "\(window.title) · 上次充值后\(CollapsedDisplay.modeLabel(showRemaining: prefs.showRemaining)) \(IslandFormat.percent(shown))"
                    : "\(window.title) · \(CollapsedDisplay.modeLabel(showRemaining: prefs.showRemaining))")
                    .font(PixelFont.font())
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(balance.map { prefs.money.format($0.amount, from: $0.currencyCode) } ?? IslandFormat.percent(shown))
                    .font(PixelFont.font(PixelFont.large))
                    .foregroundStyle(QuotaColor.color(forUsed: window.usedPercent, prefs.thresholds))
                    .help(CollapsedDisplay.bothPercents(for: window))
            }
            SegmentedBar(percent: shown, color: QuotaColor.color(forUsed: window.usedPercent, prefs.thresholds))
            if balance != nil {
                if window.isExhausted {
                    Text("余额用完，充值后恢复")
                        .font(PixelFont.font())
                        .foregroundStyle(Palette.primary)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ResetLines(provider: provider, now: context.date)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "限制预计解除" when the used-up windows say so together; each window's own time when they
/// don't; otherwise "下一项额度重置".
private struct ResetLines: View {
    let provider: ProviderUsage
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch QuotaOverview.release(of: provider, now: now) {
            case let .expected(at):
                line("限制预计解除", value: "\(PanelDisplay.resetTime(at, now: now))（\(IslandFormat.relative(to: at, now: now))后）", strong: true)
            case let .perWindow(resets):
                ForEach(Array(resets.enumerated()), id: \.offset) { _, reset in
                    let scope = reset.window.isModelScoped ? "（仅此模型）" : ""
                    line(
                        "\(reset.window.title) 已用完\(scope)",
                        value: reset.resetsAt.map { "\(PanelDisplay.resetTime($0, now: now)) 重置" } ?? "重置时间未知",
                        strong: true
                    )
                }
                if resets.count > 1 || resets.contains(where: { $0.resetsAt == nil }) {
                    Text("各额度关系不明确，按各自时间分别显示，不推断整体何时恢复。")
                        .font(PixelFont.font())
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .notLimited:
                if let next = QuotaOverview.nextReset(of: provider, now: now), let at = next.resetsAt {
                    line("下一项额度重置", value: "\(next.window.title) · \(PanelDisplay.resetTime(at, now: now))", strong: false)
                }
            }
        }
    }

    private func line(_ title: String, value: String, strong: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 4)
            Text(value)
        }
        .font(PixelFont.font())
        .foregroundStyle(strong ? Palette.primary : Palette.secondary)
    }
}

/// "常驻刘海": whether this provider sits beside the notch. Not the panel's 保持展开.
private struct NotchPinToggle: View {
    let providerID: String
    let isPinned: Bool
    let model: AppModel

    var body: some View {
        let full = !isPinned && model.prefs.pinnedProviderIDs.count >= Preferences.maxPinned
        Button {
            model.prefs.setPinned(providerID, !isPinned)
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 10))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
                .foregroundStyle(isPinned ? Palette.primary : Palette.secondary)
        }
        .buttonStyle(.plain)
        .disabled(full)
        .help(full
            ? "常驻刘海最多 \(Preferences.maxPinned) 个，先取消一个"
            : (isPinned ? "常驻刘海：已显示在刘海旁，点击取消" : "常驻刘海：点击后显示在刘海旁"))
        .accessibilityLabel(isPinned ? "取消常驻刘海" : "常驻刘海")
    }
}

/// 正常 / 紧张 / 用完 / 待确认 / 按余额 as a solid pixel tag.
private struct StatusTag: View {
    let status: ProviderStatus

    static func color(for status: ProviderStatus) -> Color {
        switch status {
        case .normal: return Pixel.ok
        case .nearLimit, .limited(partial: true): return Pixel.warn
        case .limited(partial: false): return Pixel.bad
        case .unconfirmed: return Pixel.muted
        case .balance: return Pixel.frame
        }
    }

    static func shortLabel(for status: ProviderStatus) -> String {
        switch status {
        case .normal: return "正常"
        case .nearLimit: return "紧张"
        case .limited(partial: false): return "用完"
        case .limited(partial: true): return "部分用完"
        case .unconfirmed: return "待确认"
        case .balance: return "按余额"
        }
    }

    var body: some View {
        PixelTag(
            text: Self.shortLabel(for: status),
            color: Self.color(for: status),
            textColor: status == .limited(partial: false) ? Pixel.text : Pixel.background
        )
        .help(status.label)
        .accessibilityLabel("状态：\(status.label)")
    }
}

/// The provider's brand icon on a 16-pixel grid.
private struct PixelIcon: View {
    let providerID: String

    var body: some View {
        if let icon = PixelSprite.icon(for: providerID, pixels: 16) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.none)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        } else {
            ProviderIcon(providerID: providerID, size: 14, fallback: String(ProviderCatalog.shortName(for: providerID).prefix(1)))
                .foregroundStyle(Palette.primary)
        }
    }
}

/// The 看板娘: the chosen provider's character with one sentence about what to use now.
private struct MascotHero: View {
    let choice: MascotChoice
    let sentence: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            MascotSprite(providerID: choice.providerID, mood: choice.mood, size: 96)
                .modifier(MoodMotion(mood: choice.mood, still: reduceMotion))
                .help("\(ProviderCatalog.displayName(for: choice.providerID))：\(choice.mood.label)")
            SpeechBubble(text: sentence, blinks: !reduceMotion)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, Pixel.line)
        .id(choice.providerID)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sentence)
    }
}

/// Fidgets sideways when worried, in whole-pixel steps; otherwise stands still (no bobbing).
private struct MoodMotion: ViewModifier {
    let mood: CharacterMood
    let still: Bool

    func body(content: Content) -> some View {
        if still || mood != .worried {
            content
        } else {
            content.phaseAnimator([false, true]) { view, right in
                view.offset(x: right ? 2 : -2)
            } animation: { _ in
                .linear(duration: 0.01).delay(0.25)
            }
        }
    }
}

/// Pixel speech bubble with a stepped tail pointing at the character and a blinking cursor.
private struct SpeechBubble: View {
    let text: String
    var blinks = true

    var body: some View {
        Group {
            if blinks {
                // The cursor sits right after the last word, so it blinks inside the text.
                Color.clear.frame(height: 0).phaseAnimator([true, false]) { _, on in
                    line(cursorOn: on)
                } animation: { _ in
                    .linear(duration: 0.01).delay(0.5)
                }
            } else {
                line(cursorOn: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBox(fill: Pixel.card, border: Pixel.frame)
        .overlay(alignment: .bottomLeading) {
            // Two stepped squares outside the left edge, like the mockup's tail.
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Pixel.frame).frame(width: 6, height: 6).offset(x: 3)
                Rectangle().fill(Pixel.frame).frame(width: 3, height: 3).offset(y: 6)
            }
            .frame(width: 9, height: 9, alignment: .topLeading)
            .offset(x: -9, y: -9)
        }
    }

    private func line(cursorOn: Bool) -> some View {
        (Text(text) + Text(" █").foregroundColor(cursorOn ? Pixel.text : .clear))
            .font(PixelFont.font())
            .foregroundStyle(Pixel.text)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A data problem in words, with what to do about it.
private struct IssueView: View {
    let issue: DataIssue
    let detail: String
    var title: String?
    let providerID: String?
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                Text(title ?? issue.summary).font(PixelFont.font())
            }
            .foregroundStyle(Pixel.warn)
            if title != nil {
                Text(issue.summary).font(PixelFont.font()).foregroundStyle(Palette.primary)
            }
            IssueActions(issue: issue, providerID: providerID, model: model)
            if issue == .other || issue == .cliMissing {
                Text(detail)
                    .font(PixelFont.font())
                    .foregroundStyle(Palette.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// The next step for a data problem: retry, settings, sign in, or get the CLI.
private struct IssueActions: View {
    let issue: DataIssue
    let providerID: String?
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(issue.hint)
                .font(PixelFont.font())
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(issue.actions, id: \.self) { action in
                    button(for: action)
                }
            }
        }
    }

    @ViewBuilder
    private func button(for action: DataIssue.Action) -> some View {
        switch action {
        case .retry:
            pill("重试", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                .disabled(model.isRefreshing)
        case .openSettings:
            pill("打开设置", systemImage: "gearshape") { model.openSettings(for: issue) }
        case .signIn:
            if let id = providerID, let url = PanelDisplay.usageURL(for: id) {
                pill("打开登录页", systemImage: "person.crop.circle") { NSWorkspace.shared.open(url) }
                    .help("在浏览器打开 \(ProviderCatalog.displayName(for: id)) 的页面，登录后回来点「重试」")
            }
        case .downloadCLI:
            pill("下载命令行工具", systemImage: "arrow.down.circle") {
                NSWorkspace.shared.open(CodexBarCLILocator.manualDownloadURL)
            }
        }
    }

    private func pill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PixelButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

private struct WindowRow: View {
    let window: QuotaWindow
    let thresholds: QuotaThresholds
    let showRemaining: Bool

    /// Hovering the row swaps the countdown for the clock time it resets at.
    @State private var isHovering = false

    /// Bar and number follow the used/remaining choice, like the ring beside the notch.
    private var shown: Double {
        CollapsedDisplay.shownPercent(for: window, showRemaining: showRemaining)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Wide enough for labels like "Claude/GPT weekly" so lanes stay distinguishable.
            Text(window.title)
                .font(PixelFont.font())
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 96, alignment: .leading)
                .help(window.title)
            SegmentedBar(
                percent: shown, color: QuotaColor.color(forUsed: window.usedPercent, thresholds),
                cells: 10, cellHeight: 6
            )
            Text(IslandFormat.percent(shown))
                .font(PixelFont.font())
                .foregroundStyle(Palette.primary)
                .frame(width: 36, alignment: .trailing)
                .help(CollapsedDisplay.bothPercents(for: window))
            Group {
                if let resetsAt = window.resetsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(isHovering
                            ? PanelDisplay.resetTime(resetsAt, now: context.date)
                            : IslandFormat.countdown(to: resetsAt, now: context.date))
                            .lineLimit(1)
                    }
                } else if let description = window.resetDescription {
                    Text(description).lineLimit(1)
                } else {
                    Text("")
                }
            }
            .font(PixelFont.font())
            .foregroundStyle(Palette.secondary)
            .frame(width: 88, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// "5 小时，已用 30%，剩余 70%，今天 18:40 重置".
    private var accessibilityText: String {
        var parts = [window.title, CollapsedDisplay.bothPercents(for: window)]
        if let resetsAt = window.resetsAt {
            parts.append("\(PanelDisplay.resetTime(resetsAt, now: Date())) 重置")
        } else if let description = window.resetDescription {
            parts.append(description)
        }
        return parts.joined(separator: "，")
    }
}

/// Header icon with a hit area larger than the glyph.
private struct HeaderIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
    }
}

/// What VoiceOver reads for a provider beside the notch.
private enum EarAccessibility {
    @MainActor
    static func label(for provider: ProviderUsage, style: EarStyle, stale: Bool) -> String {
        var parts = [provider.displayName]
        if provider.error != nil {
            parts.append("读取失败，额度未知")
        } else if let window = QuotaOverview.displayWindow(of: provider, thresholds: style.thresholds) {
            parts.append("\(window.title) \(CollapsedDisplay.bothPercents(for: window))")
            parts.append(style.thresholds.level(for: window).label)
        } else {
            parts.append("额度未知")
        }
        if stale { parts.append("数据已过期") }
        return parts.joined(separator: "，")
    }
}
