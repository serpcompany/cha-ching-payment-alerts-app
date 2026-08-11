import SwiftUI
import UIKit

struct CustomSourceSheet: View {
    let sourceID: String?

    @EnvironmentObject private var store: ConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var source: CustomPaymentSource?
    @State private var fields: [WebhookField] = []
    @State private var mapping = WebhookFieldMapping(
        paymentIdPath: "",
        amountPath: "",
        amountUnit: "major",
        currencyPath: nil
    )
    @State private var preview: CustomPaymentPreview?
    @State private var previewedMapping: WebhookFieldMapping?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var copiedItem: CopiedItem?
    @State private var confirmRegenerate = false

    var body: some View {
        NavigationStack {
            Form {
                if let source {
                    if source.status == .setup { setupSections(source) }
                    else { managementSections(source) }
                } else {
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

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
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
            .onChange(of: mapping) { _, _ in
                preview = nil
                previewedMapping = nil
            }
            .alert("Regenerate webhook URL?", isPresented: $confirmRegenerate) {
                Button("Cancel", role: .cancel) {}
                Button("Regenerate", role: .destructive) { Task { await regenerateURL() } }
            } message: {
                Text("The current URL will stop working immediately. You'll need to replace it wherever payments are sent from.")
            }
        }
    }

    @ViewBuilder
    private func setupSections(_ source: CustomPaymentSource) -> some View {
        Section("1. Add this URL to your store") {
            Text(source.webhookUrl.absoluteString)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            copyURLButton(source)
            copyDeveloperPromptButton(source)
            Text("Choose your store's successful-payment event. This URL stays the same through normal Cha-Ching updates.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("The developer prompt includes this private URL. Send it only to a trusted developer or AI agent working in the payment sender.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("2. Send one test payment") {
            Text(fields.isEmpty
                 ? "Use your store's Send test button, then come back here. A real event received during setup is treated only as a sample."
                 : "Connected — Cha-Ching found \(fields.count) available fields.")
                .font(.footnote)
                .foregroundStyle(fields.isEmpty ? .secondary : Theme.accent)
            actionButton(fields.isEmpty ? "Check connection" : "Check again", systemImage: "arrow.clockwise") {
                await checkConnection()
            }
        }

        if !fields.isEmpty {
            Section("3. Match payment details") {
                WebhookFieldPicker(title: "Payment ID", fields: fields, selection: $mapping.paymentIdPath)
                WebhookFieldPicker(title: "Amount", fields: fields, selection: $mapping.amountPath)
                Picker("Amount format", selection: $mapping.amountUnit) {
                    Text("27.00").tag("major")
                    Text("2700 cents").tag("minor")
                }
                WebhookFieldPicker(title: "Currency", fields: fields, selection: requiredBinding($mapping.currencyPath))
                WebhookFieldPicker(title: "Time (optional)", fields: fields, selection: optionalBinding($mapping.occurredAtPath), allowsNone: true)
                WebhookFieldPicker(title: "Product (optional)", fields: fields, selection: optionalBinding($mapping.productPath), allowsNone: true)
                WebhookFieldPicker(title: "Plan (optional)", fields: fields, selection: optionalBinding($mapping.planPath), allowsNone: true)
                WebhookFieldPicker(title: "Sale type (optional)", fields: fields, selection: optionalBinding($mapping.saleTypePath), allowsNone: true)
            }

            Section("4. Choose notification fields") {
                Text("Every field is shown by default. Turn off anything you don't want on your lock screen, rename its label, or choose a different data field.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Show all") { setAllNotificationFields(enabled: true) }
                        .buttonStyle(.borderless)
                    Spacer()
                    Button("Hide all") { setAllNotificationFields(enabled: false) }
                        .buttonStyle(.borderless)
                }
                ForEach($mapping.notificationFields) { $notificationField in
                    WebhookNotificationFieldEditor(
                        field: $notificationField,
                        fields: fields
                    )
                }
                Text("Enabled values are saved with the payment and may appear on the lock screen. Avoid customer, card, or other private fields.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("5. Preview and activate") {
                actionButton("Preview notification", systemImage: "bell.badge") {
                    await previewMapping()
                }
                .disabled(!mappingIsComplete)
                if let preview {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cha-ching!")
                            .font(.headline)
                        Text(preview.notificationBody ?? legacyPreviewBody(preview))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button("Activate payment source") { Task { await activate() } }
                        .fontWeight(.semibold)
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
                 ? "New payments create history and notifications."
                 : "Paused. Your setup and history are kept, but new events are ignored.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Section("Webhook URL") {
            Text(source.webhookUrl.absoluteString)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            copyURLButton(source)
            copyDeveloperPromptButton(source)
            Text("The developer prompt contains this private URL. Share it only with someone you trust to configure the payment sender.")
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
            copiedItem == .developerPrompt ? "Developer prompt copied" : "Copy prompt for AI agent / developer",
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

    private var mappingIsComplete: Bool {
        !mapping.paymentIdPath.isEmpty
            && !mapping.amountPath.isEmpty
            && !(mapping.currencyPath ?? "").isEmpty
            && mapping.notificationFields.allSatisfy {
                !$0.enabled || (!$0.path.isEmpty && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
    }

    private func setAllNotificationFields(enabled: Bool) {
        for index in mapping.notificationFields.indices {
            mapping.notificationFields[index].enabled = enabled
        }
    }

    private func legacyPreviewBody(_ preview: CustomPaymentPreview) -> String {
        let details = [preview.productLabel, preview.plan, preview.saleType]
            .compactMap { $0 }
            .joined(separator: " · ")
        return "You received \(preview.formattedAmount)\(details.isEmpty ? "." : " for \(details).")"
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () async -> Void) -> some View {
        Button(title, systemImage: systemImage) { Task { await action() } }
            .fontWeight(.semibold)
    }

    private func requiredBinding(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0 })
    }

    private func optionalBinding(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
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
        if let saved = detail.mapping {
            mapping = saved
            if mapping.notificationFields.isEmpty && !fields.isEmpty {
                mapping.notificationFields = WebhookNotificationField.defaults(from: fields)
            }
        }
        else if let suggestions = detail.sample?.suggestions {
            mapping.paymentIdPath = suggestions.paymentIdPath ?? mapping.paymentIdPath
            mapping.amountPath = suggestions.amountPath ?? mapping.amountPath
            mapping.currencyPath = suggestions.currencyPath ?? mapping.currencyPath
            mapping.occurredAtPath = suggestions.occurredAtPath
            mapping.productPath = suggestions.productPath
            mapping.planPath = suggestions.planPath
            mapping.saleTypePath = suggestions.saleTypePath
            mapping.notificationFields = WebhookNotificationField.defaults(from: fields)
        } else if !fields.isEmpty && mapping.notificationFields.isEmpty {
            mapping.notificationFields = WebhookNotificationField.defaults(from: fields)
        }
        if let sampleError = detail.sample?.error { errorMessage = sampleError }
    }

    private func previewMapping() async {
        guard let id = source?.id else { return }
        await run {
            preview = try await store.previewCustomSource(id: id, mapping: mapping)
            previewedMapping = mapping
        }
    }

    private func activate() async {
        guard let id = source?.id, previewedMapping == mapping else {
            errorMessage = "Preview your current field choices before activating."
            return
        }
        await run {
            source = try await store.activateCustomSource(id: id, mapping: mapping)
            await NotificationManager.shared.requestPermissionAndRegister()
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

private struct WebhookNotificationFieldEditor: View {
    @Binding var field: WebhookNotificationField
    let fields: [WebhookField]

    private var selectedSample: WebhookField? {
        fields.first { $0.path == field.path }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $field.enabled) {
                Text(field.label.isEmpty ? "Unnamed field" : field.label)
                    .fontWeight(.semibold)
            }
            TextField("Display name", text: $field.label)
            Picker("Data field", selection: $field.path) {
                ForEach(fields) { option in
                    Text("\(option.label): \(option.value.displayValue.prefix(30))")
                        .tag(option.path)
                }
            }
            if let selectedSample {
                Text("Sample: \(selectedSample.value.displayValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

private enum CopiedItem {
    case webhookURL
    case developerPrompt
}

private struct WebhookFieldPicker: View {
    let title: String
    let fields: [WebhookField]
    @Binding var selection: String
    var allowsNone = false

    var body: some View {
        Picker(title, selection: $selection) {
            if allowsNone { Text("Don't show").tag("") }
            if !allowsNone && selection.isEmpty { Text("Choose a field").tag("") }
            ForEach(fields) { field in
                Text("\(field.label): \(field.value.displayValue.prefix(30))")
                    .tag(field.path)
            }
        }
    }
}
