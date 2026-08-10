import SwiftUI

struct ConnectSheet: View {
    let processor: Processor
    let isConnected: Bool

    @EnvironmentObject private var connectStore: ConnectStore
    @Environment(\.dismiss) private var dismiss

    @State private var accountLabel = ""
    @State private var apiKey = ""
    @State private var webhookSecret = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: processor.symbol)
                            .foregroundStyle(processor.color)
                            .font(.title3)
                        Text(processor.setupHint)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink.opacity(0.7))
                    }
                }
                Section("Account label (optional)") {
                    TextField("e.g. My SaaS — Live", text: $accountLabel)
                        .textInputAutocapitalization(.words)
                }
                Section("API key") {
                    SecureField("Paste your key here", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if processor.needsWebhookSecret {
                    Section("Webhook signing secret") {
                        SecureField("Paste your webhook secret", text: $webhookSecret)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                if let error = connectStore.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                if isConnected {
                    Section {
                        Button("Disconnect \(processor.title)", role: .destructive) {
                            Task {
                                await connectStore.disconnect(provider: processor)
                                dismiss()
                            }
                        }
                    }
                }
                Section {
                    Text("Keys are sent straight to Sales Ping's secure backend and are never stored on this device or visible again in the app.")
                        .font(.caption2)
                        .foregroundStyle(Theme.ink.opacity(0.5))
                }
            }
            .navigationTitle(processor.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || connectStore.isBusy)
                }
            }
        }
    }

    private func save() async {
        let success = await connectStore.connect(
            provider: processor,
            apiKey: apiKey,
            webhookSecret: webhookSecret.isEmpty ? nil : webhookSecret,
            accountLabel: accountLabel.isEmpty ? nil : accountLabel
        )
        if success { dismiss() }
    }
}
