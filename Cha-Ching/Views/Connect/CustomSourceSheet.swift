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
    @State private var notificationFilter = NotificationFieldFilter.all
    @State private var notificationSearch = ""
    @State private var editingNotificationField: WebhookNotificationField?

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
            .sheet(item: $editingNotificationField) { field in
                WebhookNotificationFieldDetailEditor(
                    field: field,
                    fields: fields,
                    canMoveEarlier: notificationFieldIndex(id: field.id) != 0,
                    canMoveLater: notificationFieldIndex(id: field.id).map { $0 < mapping.notificationFields.count - 1 } ?? false,
                    onSave: updateNotificationField,
                    onMove: moveNotificationField
                )
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
                 : "Connected — Cha-Ching found \(fields.count) fields in this sample.")
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(includedNotificationFieldCount) of \(mapping.notificationFields.count) included")
                        .font(.headline)
                    Text("Every field in the test sample starts on. Tap a row to rename it, remap it, or change its order.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Picker("Fields", selection: $notificationFilter) {
                    ForEach(NotificationFieldFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Find a field", text: $notificationSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !notificationSearch.isEmpty {
                        Button("Clear", systemImage: "xmark.circle.fill") { notificationSearch = "" }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Show all") { setAllNotificationFields(enabled: true) }
                        .buttonStyle(.borderless)
                    Spacer()
                    Button("Hide all") { setAllNotificationFields(enabled: false) }
                        .buttonStyle(.borderless)
                }

                if visibleNotificationFields.isEmpty {
                    ContentUnavailableView(
                        "No matching fields",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try another filter or search.")
                    )
                } else {
                    ForEach(visibleNotificationFields) { notificationField in
                        HStack(spacing: 12) {
                            Toggle(
                                "Include \(notificationField.label)",
                                isOn: notificationFieldEnabledBinding(id: notificationField.id)
                            )
                            .labelsHidden()

                            Button {
                                editingNotificationField = notificationField
                            } label: {
                                WebhookNotificationFieldRow(
                                    field: notificationField,
                                    sample: sampleField(path: notificationField.path)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("Included values are saved with the payment and may appear on the lock screen. Each one is shown on its own “Label: Value” line, in this order.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("5. Preview and activate") {
                actionButton("Preview notification", systemImage: "bell.badge") {
                    await previewMapping()
                }
                .disabled(!mappingIsComplete)
                if let preview {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cha-ching!")
                            .font(.headline)
                        Text(preview.notificationBody ?? legacyPreviewBody(preview))
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
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

    private var includedNotificationFieldCount: Int {
        mapping.notificationFields.count(where: \.enabled)
    }

    private var visibleNotificationFields: [WebhookNotificationField] {
        let query = notificationSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return mapping.notificationFields.filter { field in
            let matchesFilter = switch notificationFilter {
            case .all: true
            case .included: field.enabled
            case .hidden: !field.enabled
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            let sample = sampleField(path: field.path)?.value.displayValue ?? ""
            return field.label.lowercased().contains(query)
                || field.path.lowercased().contains(query)
                || sample.lowercased().contains(query)
        }
    }

    private func sampleField(path: String) -> WebhookField? {
        fields.first { $0.path == path }
    }

    private func notificationFieldIndex(id: String) -> Int? {
        mapping.notificationFields.firstIndex { $0.id == id }
    }

    private func notificationFieldEnabledBinding(id: String) -> Binding<Bool> {
        Binding(
            get: { mapping.notificationFields.first(where: { $0.id == id })?.enabled ?? false },
            set: { enabled in
                guard let index = notificationFieldIndex(id: id) else { return }
                mapping.notificationFields[index].enabled = enabled
            }
        )
    }

    private func updateNotificationField(_ field: WebhookNotificationField) {
        guard let index = notificationFieldIndex(id: field.id) else { return }
        mapping.notificationFields[index] = field
    }

    private func moveNotificationField(_ field: WebhookNotificationField, by offset: Int) {
        updateNotificationField(field)
        mapping.moveNotificationField(id: field.id, by: offset)
    }

    private func legacyPreviewBody(_ preview: CustomPaymentPreview) -> String {
        [
            "Amount: \(preview.formattedAmount)",
            "Product: \(preview.productLabel)",
            preview.plan.map { "Plan: \($0)" },
            preview.saleType.map { "Sale Event: \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
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

private struct WebhookNotificationFieldRow: View {
    let field: WebhookNotificationField
    let sample: WebhookField?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label.isEmpty ? "Unnamed field" : field.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                if let sample {
                    Text(sample.value.displayValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(field.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct WebhookNotificationFieldDetailEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WebhookNotificationField
    let fields: [WebhookField]
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let onSave: (WebhookNotificationField) -> Void
    let onMove: (WebhookNotificationField, Int) -> Void

    init(
        field: WebhookNotificationField,
        fields: [WebhookField],
        canMoveEarlier: Bool,
        canMoveLater: Bool,
        onSave: @escaping (WebhookNotificationField) -> Void,
        onMove: @escaping (WebhookNotificationField, Int) -> Void
    ) {
        _draft = State(initialValue: field)
        self.fields = fields
        self.canMoveEarlier = canMoveEarlier
        self.canMoveLater = canMoveLater
        self.onSave = onSave
        self.onMove = onMove
    }

    private var selectedSample: WebhookField? {
        fields.first { $0.path == draft.path }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Notification line") {
                    Toggle("Include in notification", isOn: $draft.enabled)
                    TextField("Display name", text: $draft.label)
                        .textInputAutocapitalization(.words)
                }

                Section("Data source") {
                    Picker("Field", selection: $draft.path) {
                        ForEach(fields) { option in
                            Text("\(option.label): \(option.value.displayValue.prefix(30))")
                                .tag(option.path)
                        }
                    }
                    if let selectedSample {
                        LabeledContent("Example", value: selectedSample.value.displayValue)
                        Text(selectedSample.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Display order") {
                    Button("Move earlier", systemImage: "arrow.up") {
                        onMove(draft, -1)
                        dismiss()
                    }
                    .disabled(!canMoveEarlier)
                    Button("Move later", systemImage: "arrow.down") {
                        onMove(draft, 1)
                        dismiss()
                    }
                    .disabled(!canMoveLater)
                    Text("Notification lines appear from top to bottom in this order.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Preview") {
                    Text("\(draft.label.isEmpty ? "Unnamed field" : draft.label): \(selectedSample?.value.displayValue ?? "—")")
                }
            }
            .navigationTitle("Edit field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private enum NotificationFieldFilter: String, CaseIterable, Identifiable {
    case all, included, hidden

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All"
        case .included: "Included"
        case .hidden: "Hidden"
        }
    }
}

#if DEBUG
struct WebhookNotificationDesignerReviewView: View {
    private let fields: [WebhookField]
    @State private var notificationFields: [WebhookNotificationField]
    @State private var filter = NotificationFieldFilter.all
    @State private var search = ""
    @State private var editingField: WebhookNotificationField?

    init() {
        let sample = Self.sampleFields
        fields = sample
        _notificationFields = State(initialValue: WebhookNotificationField.defaults(from: sample))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Choose notification fields") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(notificationFields.count(where: \.enabled)) of \(notificationFields.count) included")
                            .font(.headline)
                        Text("Every field in the test sample starts on. Tap a row to rename it, remap it, or change its order.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Fields", selection: $filter) {
                        ForEach(NotificationFieldFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Find a field", text: $search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Button("Show all") { setAll(true) }
                            .buttonStyle(.borderless)
                        Spacer()
                        Button("Hide all") { setAll(false) }
                            .buttonStyle(.borderless)
                    }

                    ForEach(visibleFields) { field in
                        HStack(spacing: 12) {
                            Toggle("Include \(field.label)", isOn: enabledBinding(id: field.id))
                                .labelsHidden()
                            Button {
                                editingField = field
                            } label: {
                                WebhookNotificationFieldRow(
                                    field: field,
                                    sample: fields.first { $0.path == field.path }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Notification preview") {
                    Text("Cha-ching!")
                        .font(.headline)
                    Text(previewBody)
                        .font(.subheadline)
                }
            }
            .navigationTitle("SERP Store")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingField) { field in
                WebhookNotificationFieldDetailEditor(
                    field: field,
                    fields: fields,
                    canMoveEarlier: index(id: field.id) != 0,
                    canMoveLater: index(id: field.id).map { $0 < notificationFields.count - 1 } ?? false,
                    onSave: update,
                    onMove: move
                )
            }
        }
        .tint(Theme.accent)
    }

    private var visibleFields: [WebhookNotificationField] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return notificationFields.filter { field in
            let filterMatches = switch filter {
            case .all: true
            case .included: field.enabled
            case .hidden: !field.enabled
            }
            guard filterMatches else { return false }
            guard !query.isEmpty else { return true }
            let value = fields.first { $0.path == field.path }?.value.displayValue ?? ""
            return field.label.lowercased().contains(query)
                || field.path.lowercased().contains(query)
                || value.lowercased().contains(query)
        }
    }

    private var previewBody: String {
        notificationFields.compactMap { field in
            guard field.enabled,
                  let value = fields.first(where: { $0.path == field.path })?.value.displayValue
            else { return nil }
            return "\(field.label): \(value)"
        }.joined(separator: "\n")
    }

    private func index(id: String) -> Int? {
        notificationFields.firstIndex { $0.id == id }
    }

    private func enabledBinding(id: String) -> Binding<Bool> {
        Binding(
            get: { notificationFields.first(where: { $0.id == id })?.enabled ?? false },
            set: { enabled in
                guard let index = index(id: id) else { return }
                notificationFields[index].enabled = enabled
            }
        )
    }

    private func setAll(_ enabled: Bool) {
        for index in notificationFields.indices { notificationFields[index].enabled = enabled }
    }

    private func update(_ field: WebhookNotificationField) {
        guard let index = index(id: field.id) else { return }
        notificationFields[index] = field
    }

    private func move(_ field: WebhookNotificationField, by offset: Int) {
        update(field)
        var mapping = WebhookFieldMapping(
            paymentIdPath: "/payment/id",
            amountPath: "/payment/amount_minor",
            amountUnit: "minor",
            currencyPath: "/payment/currency",
            notificationFields: notificationFields
        )
        mapping.moveNotificationField(id: field.id, by: offset)
        notificationFields = mapping.notificationFields
    }

    private static let sampleFields = [
        WebhookField(path: "/buyer/email", value: .string("buyer@example.com"), valueType: "string"),
        WebhookField(path: "/buyer/checkout_country_ip", value: .string("JP"), valueType: "string"),
        WebhookField(path: "/purchase/product", value: .string("Circle Video Downloader"), valueType: "string"),
        WebhookField(path: "/purchase/entitlement", value: .string("circle-video-downloader"), valueType: "string"),
        WebhookField(path: "/purchase/purchase_type", value: .string("subscription"), valueType: "string"),
        WebhookField(path: "/purchase/sale_event", value: .string("new_sale"), valueType: "string"),
        WebhookField(path: "/payment/amount_minor", value: .number(900), valueType: "number"),
        WebhookField(path: "/attribution/dub_affiliate_id", value: .string("pn_hasanul"), valueType: "string"),
        WebhookField(path: "/attribution/utm_source", value: .string("dub"), valueType: "string"),
        WebhookField(path: "/attribution/utm_medium", value: .string("affiliate"), valueType: "string"),
        WebhookField(path: "/attribution/utm_campaign", value: .string("summer-launch"), valueType: "string"),
        WebhookField(path: "/attribution/utm_term", value: .string("video downloader"), valueType: "string"),
        WebhookField(path: "/attribution/utm_content", value: .string("pricing-page"), valueType: "string"),
        WebhookField(path: "/payment/occurred_at", value: .string("2026-08-11T08:27:14Z"), valueType: "string"),
        WebhookField(path: "/source/store", value: .string("serp.store"), valueType: "string"),
        WebhookField(path: "/payment/id", value: .string("cs_live_123"), valueType: "string"),
        WebhookField(path: "/payment/currency", value: .string("USD"), valueType: "string")
    ]
}
#endif

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
