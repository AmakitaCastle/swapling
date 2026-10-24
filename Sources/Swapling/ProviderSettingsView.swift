import IslandCore
import Observation
import SwiftUI

/// Provider toggles and API keys, edited through the bundled CodexBar CLI so the
/// config file stays in the format CodexBar expects.
@Observable
@MainActor
final class ProviderSettingsModel {
    private let appModel: AppModel
    var providers: [ProviderConfig] = []
    var isLoading = false
    var busyID: String?
    var error: String?
    var notice: String?

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            providers = try await appModel.client.providerConfigs()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool, for id: String) async {
        await perform(id) {
            try await self.appModel.client.setEnabled(enabled, provider: id)
        }
    }

    /// Returns true when the key was saved, so the view can clear its field.
    func saveKey(_ key: String, for id: String) async -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        let saved = await perform(id) {
            try await self.appModel.client.setAPIKey(key, provider: id)
        }
        if saved {
            let name = providers.first { $0.id == id }?.displayName ?? id
            notice = "已保存 \(name) 的 API Key，并已开启。"
        }
        return saved
    }

    @discardableResult
    private func perform(_ id: String, _ action: @escaping () async throws -> Void) async -> Bool {
        busyID = id
        defer { busyID = nil }
        notice = nil
        do {
            try await action()
            error = nil
        } catch {
            self.error = error.localizedDescription
            await load()
            return false
        }
        await load()
        await appModel.refresh()
        return true
    }
}

struct ProviderSettingsView: View {
    @State private var settings: ProviderSettingsModel
    @State private var search = ""
    @State private var keyEditorID: String?
    @State private var keyDraft = ""

    init(model: AppModel) {
        _settings = State(initialValue: ProviderSettingsModel(appModel: model))
    }

    private var filtered: [ProviderConfig] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return settings.providers }
        return settings.providers.filter {
            $0.displayName.lowercased().contains(query) || $0.id.contains(query)
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("搜索平台", text: $search)
                    .textFieldStyle(.roundedBorder)
                if let error = settings.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notice = settings.notice {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("这些设置只保存在 Swapling 自己的配置里，不会改动 CodexBar.app。Codex、Claude 会沿用本机已有的登录（命令行登录或浏览器）；DeepSeek 填 platform.deepseek.com 里创建的 API Key，用来读余额。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let enabled = filtered.filter(\.enabled)
            let others = filtered.filter { !$0.enabled }
            if !enabled.isEmpty {
                Section("已开启") {
                    ForEach(enabled) { row($0) }
                }
            }
            Section(settings.isLoading && settings.providers.isEmpty ? "正在读取…" : "其他平台") {
                ForEach(others) { row($0) }
            }
        }
        .formStyle(.grouped)
        .task { await settings.load() }
    }

    @ViewBuilder
    private func row(_ provider: ProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(isOn: Binding(
                    get: { provider.enabled },
                    set: { newValue in Task { await settings.setEnabled(newValue, for: provider.id) } }
                )) {
                    HStack(spacing: 6) {
                        Text(provider.displayName)
                        if provider.hasAPIKey {
                            Image(systemName: "key.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("已保存 API Key")
                        }
                    }
                }
                if settings.busyID == provider.id {
                    ProgressView().controlSize(.small)
                }
                if provider.supportsAPIKey {
                    Button(keyEditorID == provider.id ? "取消" : (provider.hasAPIKey ? "更换 Key" : "填 API Key")) {
                        keyDraft = ""
                        keyEditorID = keyEditorID == provider.id ? nil : provider.id
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .disabled(settings.busyID != nil)

            if keyEditorID == provider.id {
                HStack {
                    SecureField("\(provider.displayName) API Key", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveKey)
                    Button("保存", action: saveKey)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty || settings.busyID != nil)
                }
            }
        }
    }

    private func saveKey() {
        guard let id = keyEditorID else { return }
        let key = keyDraft
        Task {
            if await settings.saveKey(key, for: id) {
                keyDraft = ""
                keyEditorID = nil
            }
        }
    }
}
