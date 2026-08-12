import SwiftUI
import UIKit

struct CustomSourceSheet: View {
    let sourceID: String?

    @EnvironmentObject private var store: ConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var source: CustomPaymentSource?
    @State private var fields: [WebhookField] = []
    @State private var eventReceivedAt: Date?
    @State private var mapping = WebhookFieldMapping(
        paymentIdPath: "",
        amountPath: "",
        amountUnit: "major",
        currencyPath: nil
    )
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var copiedItem: CopiedItem?
    @State private var confirmRegenerate = false
    @State private var saveConfirmation: String?

    var body: some View {
        NavigationStack {
            Form {
                if let source {
                    if source.status == .setup {
                        setupSections(source)
                    } else {
                        managementSections(source)
                    }
                } else {
                    newSourceSections
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(source?.name ?? "Another payment source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .disabled(isBusy)
            .overlay { if isBusy { ProgressView().controlSize(.large) } }
            .task { await loadExistingSource() }
            .alert("Regenerate webhook URL?", isPresented: $confirmRegenerate) {
                Button("Cancel", role: .cancel) {}
                Button("Regenerate", role: .destructive) { Task { await regenerateURL() } }
            } message: {
                Text("The current URL will stop working immediately. You'll need to replace it wherever payments are sent from.")
            }
        }
    }

    private var newSourceSections: some View {
        Group {
            Section("Name this source") {
                TextField("Example: SERP Store", text: $name)
                    .textInputAutocapitalization(.words)
                Text("Use a name you'll recognize when a payment arrives.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                actionButton("Create webhook", systemImage: "link.badge.plus") {
                    await createSource()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func setupSections(_ source: CustomPaymentSource) -> some View {
        Section("1. Connect your store") {
            Text(source.webhookUrl.absoluteString)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            copyURLButton(source)
            copyDeveloperPromptButton(source)
            Text("Add this private URL to your store's successful-payment event. It stays the same through normal Cha-Ching updates.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("2. Confirm the connection") {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.connectionState.title)
                        .fontWeight(.semibold)
                    if source.connectionState == .eventReceived, let eventReceivedAt {
                        Text("Received \(eventReceivedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: source.connectionState == .eventReceived ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(source.connectionState == .eventReceived ? Theme.accent : .secondary)
            }

            Text(source.connectionState == .eventReceived
                 ? "Cha-Ching found \(fields.count) fields and is ready for notification setup."
                 : "Ask your developer to send the first real payment event to the webhook URL above.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            actionButton(source.connectionState == .eventReceived ? "Check for a new event" : "Check for event", systemImage: "arrow.clockwise") {
                await checkConnection()
            }

            Text("The first event configures this source. It does not create a Dashboard payment or send a notification.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if !fields.isEmpty {
            Section("Next") {
                NavigationLink {
                    CustomNotificationSettingsView(
                        source: source,
                        fields: fields,
                        mapping: $mapping,
                        onActivated: { activatedSource in
                            self.source = activatedSource
                        }
                    )
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Customize notifications")
                                .fontWeight(.semibold)
                            Text("Choose what appears when you get paid")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func managementSections(_ source: CustomPaymentSource) -> some View {
        Section("Status") {
            Toggle("Receive payments", isOn: Binding(
                get: { source.status == .active },
                set: { active in Task { await setActive(active) } }
            ))
            Text(source.status == .active
                 ? "New payments appear on your Dashboard and send notifications."
                 : "Paused. Your setup and existing payments are kept, but new events are ignored.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if let health = source.health {
            Section("Connection health") {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(health.statusTitle)
                            .fontWeight(.semibold)
                        Text(health.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: health.status == .needsAttention
                          ? "exclamationmark.triangle.fill"
                          : health.status == .receiving
                            ? "wave.3.right.circle.fill"
                            : "clock")
                        .foregroundStyle(health.status == .needsAttention ? Theme.gold : Theme.accent)
                }

                if let lastEvent = health.lastEventDate {
                    LabeledContent("Last webhook request") {
                        Text(lastEvent.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let lastPayment = health.lastPaymentDate {
                    LabeledContent("Last accepted payment") {
                        Text(lastPayment.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Text("Active means Cha-Ching is ready to receive events. Health reflects the requests that actually reached this URL.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                actionButton("Refresh connection health", systemImage: "arrow.clockwise") {
                    await checkConnection()
                }
            }
        }

        Section("Notifications") {
            NavigationLink {
                CustomNotificationSettingsView(
                    source: source,
                    fields: [],
                    mapping: $mapping,
                    onActivated: { _ in },
                    onSaved: { saveConfirmation = $0 }
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Customize notifications").fontWeight(.semibold)
                        Text("Rename, show, hide, or reorder future payment details")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge").foregroundStyle(Theme.accent)
                }
            }
            if let saveConfirmation {
                Label(saveConfirmation, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
        }

        Section("Webhook URL") {
            Text(source.webhookUrl.absoluteString)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            copyURLButton(source)
            copyDeveloperPromptButton(source)
            Text("The developer instructions contain this private URL. Share them only with someone you trust to configure the payment sender.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Regenerate URL", role: .destructive) { confirmRegenerate = true }
        }
    }

    private func copyURLButton(_ source: CustomPaymentSource) -> some View {
        Button(
            copiedItem == .webhookURL ? "Webhook URL copied" : "Copy webhook URL",
            systemImage: copiedItem == .webhookURL ? "checkmark" : "doc.on.doc"
        ) {
            UIPasteboard.general.string = source.webhookUrl.absoluteString
            copiedItem = .webhookURL
        }
        .accessibilityHint("Copies the private webhook URL to the clipboard.")
    }

    private func copyDeveloperPromptButton(_ source: CustomPaymentSource) -> some View {
        Button(
            copiedItem == .developerPrompt ? "Developer instructions copied" : "Copy instructions for developer",
            systemImage: copiedItem == .developerPrompt ? "checkmark" : "text.badge.plus"
        ) {
            UIPasteboard.general.string = CustomWebhookDeveloperPrompt.make(
                sourceName: source.name,
                webhookURL: source.webhookUrl
            )
            copiedItem = .developerPrompt
        }
        .fontWeight(.semibold)
        .accessibilityHint("Copies setup instructions and the private webhook URL to the clipboard.")
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button(title, systemImage: systemImage) { Task { await action() } }
            .fontWeight(.semibold)
    }

    private func run(_ operation: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await operation() }
        catch { errorMessage = error.localizedDescription }
    }

    private func createSource() async {
        await run {
            source = try await store.createCustomSource(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func loadExistingSource() async {
        guard let sourceID else { return }
        await run {
            apply(try await store.customSourceDetail(id: sourceID))
        }
    }

    private func checkConnection() async {
        guard let id = source?.id else { return }
        await run { apply(try await store.customSourceDetail(id: id)) }
    }

    private func apply(_ detail: CustomSourceDetail) {
        source = detail.source
        fields = detail.sample?.fields ?? []
        eventReceivedAt = detail.connectionPresentation.receivedAt

        if let saved = detail.mapping {
            mapping = saved
            mapping.refreshUntouchedDefaults(from: fields)
        } else if let suggestions = detail.sample?.suggestions {
            mapping.paymentIdPath = suggestions.paymentIdPath ?? mapping.paymentIdPath
            if let amountPath = suggestions.amountPath {
                mapping.amountPath = amountPath
                mapping.amountUnit = WebhookFieldMapping.inferredAmountUnit(for: amountPath)
            }
            mapping.currencyPath = suggestions.currencyPath ?? mapping.currencyPath
            mapping.occurredAtPath = suggestions.occurredAtPath
            mapping.productPath = suggestions.productPath
            mapping.planPath = suggestions.planPath
            mapping.saleTypePath = suggestions.saleTypePath
            mapping.notificationFields = WebhookNotificationField.defaults(from: fields)
        } else if !fields.isEmpty && mapping.notificationFields.isEmpty {
            mapping.notificationFields = WebhookNotificationField.defaults(from: fields)
        }

        if let sampleError = detail.sample?.error {
            errorMessage = sampleError
        }
    }

    private func setActive(_ active: Bool) async {
        guard let id = source?.id else { return }
        await run { source = try await store.setCustomSource(id: id, active: active) }
    }

    private func regenerateURL() async {
        guard let id = source?.id else { return }
        await run { source = try await store.regenerateCustomSourceURL(id: id) }
    }
}

private enum CopiedItem {
    case webhookURL
    case developerPrompt
}
