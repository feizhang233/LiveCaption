import SwiftUI

struct ModelsView: View {
    @Bindable var session: SessionController
    @State private var deleting: WhisperModel?
    var body: some View {
        List {
            Section {
                LabeledContent("可用儲存空間", value: session.models.formattedAvailableSpace)
                LabeledContent("裝置記憶體", value: ByteCountFormatter.string(fromByteCount: Int64(session.models.physicalMemoryBytes), countStyle: .memory))
                Text("模型只在您選擇下載後安裝。檔案大小與執行記憶體需求不同；記憶體估計不是速度保證。")
                    .font(.callout).foregroundStyle(.secondary)
                if let error = session.models.storageError { Text(error).foregroundStyle(.orange) }
            }
            Section("多語言 Whisper 模型") {
                ForEach(session.models.models) { model in
                    ModelRow(model: model, session: session, delete: { deleting = model })
                }
            }
            Section {
                Text("模型來自 whisper.cpp 維護者的固定版本。下載完成後核對檔案大小與 SHA-256，通過才可使用。所有音訊辨識都在本機執行。")
                    .font(.caption).foregroundStyle(.secondary)
                StatusStrip(session: session)
            }
        }
        .onAppear { session.models.refreshStorage() }
        .confirmationDialog("刪除 \(deleting?.name ?? "") 模型？之後可重新下載。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("刪除模型", role: .destructive) {
                if let model = deleting {
                    do { try session.models.delete(model) } catch { session.report(error.localizedDescription) }
                }
                deleting = nil
            }
        }
    }
}

private struct ModelRow: View {
    let model: WhisperModel
    @Bindable var session: SessionController
    let delete: () -> Void
    var state: ModelInstallState { session.models.state(for: model) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveControls(horizontalSpacing: 8, verticalSpacing: 6, verticalAlignment: .firstTextBaseline) {
                modelName
                selectedBadge
                fileSize
            }
            Text("執行記憶體估計 \(model.formattedMemoryEstimate) · 建議裝置記憶體 \(model.formattedRecommendedRAM)")
                .font(.caption).foregroundStyle(.secondary)
            Text(model.recommendation(physicalMemory: session.models.physicalMemoryBytes)).font(.callout).foregroundStyle(.secondary)
            switch state {
            case .downloading(let progress):
                ProgressView(value: progress) { Text(state.statusText) }
                Button { session.models.cancel(model) } label: { actionLabel("取消下載") }
            case .verifying:
                HStack { ProgressView().controlSize(.small); Text("正在驗證完整性…").font(.callout) }
                if session.models.canCancel(model) {
                    Button { session.models.cancel(model) } label: { actionLabel("取消驗證") }
                }
            case .installed:
                AdaptiveControls(horizontalSpacing: 8, verticalSpacing: 10) {
                    verifiedLabel
                    installedActions
                }
            case .notInstalled:
                Button { session.models.download(model) } label: {
                    Label { actionLabel("下載 \(model.formattedFileSize)") } icon: { Image(systemName: "arrow.down.circle") }
                }
                .disabled(session.models.isBusy)
            case .failed(let error):
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                AdaptiveControls(horizontalSpacing: 8, verticalSpacing: 10) { retryActions }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.vertical, 12)
    }

    private var modelName: some View {
        Text(model.name).font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var selectedBadge: some View {
        if session.models.selectedID == model.id {
            Label("已選擇", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(CaptionTheme.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fileSize: some View {
        Text(model.formattedFileSize).font(.body.monospacedDigit())
    }

    private var verifiedLabel: some View {
        Label("已通過完整性校驗", systemImage: "checkmark.shield")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var installedActions: some View {
        AdaptiveControls(horizontalSpacing: 10, verticalSpacing: 10) { modelSelectionActions }
    }

    @ViewBuilder private var modelSelectionActions: some View {
        Button {
            Task { await session.selectModel(model) }
        } label: {
            actionLabel(session.models.activeModelID != nil && session.models.activeModelID != model.id ? "停止並切換" : "使用模型")
        }
        .disabled(session.models.selectedID == model.id || session.isBusy)
        Button(role: .destructive, action: delete) { actionLabel("刪除") }
            .disabled(session.models.activeModelID == model.id)
    }

    @ViewBuilder private var retryActions: some View {
        Button { session.models.download(model) } label: { actionLabel("重試下載") }
            .disabled(session.models.isBusy)
        if session.models.hasStoredFile(model) {
            Button(role: .destructive, action: delete) { actionLabel("刪除無效檔案") }
        }
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title)
            .fixedSize(horizontal: false, vertical: true)
            #if os(iOS)
            .frame(minHeight: 44)
            #endif
    }
}
