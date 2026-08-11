import SwiftUI

struct CustomNotificationSettingsView: View {
    let source: CustomPaymentSource
    let fields: [WebhookField]
    @Binding var mapping: WebhookFieldMapping
    let onActivated: (CustomPaymentSource) -> Void

    @EnvironmentObject private var store: ConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var preview: CustomPaymentPreview?
    @State private var previewedMapping: WebhookFieldMapping?
    @State private var editingField: WebhookNotificationField?
    @State private var showingPreview = false
    @State private var testResultMessage: String?
    @State private var showingTestResult = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                sourceSummary
                previewButton
                testNotificationButton
            }

            paymentMatchingSection

            Section {
                ForEach(mapping.notificationFields) { field in
                    notificationFieldRow(field)
                }
                .onMove(perform: moveNotificationFields)
            } header: {
                HStack {
                    Text("Notification contents")
                    Spacer()
                    Text("\(includedFieldCount) of \(mapping.notificationFields.count) on")
                        .textCase(nil)
                }
            } footer: {
                Text("All details found in the test payment are listed. Each enabled detail appears on its own “Label: Value” line.")
            }

            Section {
                Label("Enabled details may appear on the iPhone lock screen.", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Notification settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .disabled(isBusy)
        .overlay { if isBusy && !showingPreview { ProgressView().controlSize(.large) } }
        .onChange(of: mapping) { _, _ in
            preview = nil
            previewedMapping = nil
        }
        .sheet(item: $editingField) { field in
            WebhookNotificationFieldEditor(
                field: field,
                fields: fields,
                canMoveEarlier: notificationFieldIndex(id: field.id) != 0,
                canMoveLater: notificationFieldIndex(id: field.id).map {
                    $0 < mapping.notificationFields.count - 1
                } ?? false,
                onSave: updateNotificationField,
                onMove: moveNotificationField
            )
        }
        .sheet(isPresented: $showingPreview) {
            if let preview {
                CustomNotificationPreviewSheet(
                    sourceName: source.name,
                    notificationBody: preview.notificationBody ?? legacyPreviewBody(preview),
                    isActivating: isBusy,
                    errorMessage: errorMessage,
                    onActivate: { Task { await activate() } }
                )
            }
        }
        .alert("Test notification", isPresented: $showingTestResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testResultMessage ?? "The test notification was sent.")
        }
    }

    private var sourceSummary: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name)
                    .fontWeight(.semibold)
                Text("Webhook connected")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
        }
    }

    private var previewButton: some View {
        Button {
            Task { await previewMapping() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preview notification")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("Cha-ching! · \(includedFieldCount) details")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .disabled(!mappingIsComplete)
        .accessibilityHint("Shows the exact notification and lets you activate this source.")
    }

    private var testNotificationButton: some View {
        Button {
            Task { await sendTestNotification() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(Theme.gold)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Test notification")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("Send this sample to your iPhone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .disabled(!mappingIsComplete)
        .accessibilityHint("Sends the current sample as a real notification without creating a payment.")
    }

    private var paymentMatchingSection: some View {
        Section {
            DisclosureGroup {
                WebhookFieldPicker(title: "Payment ID", fields: fields, selection: $mapping.paymentIdPath)
                WebhookFieldPicker(title: "Amount", fields: fields, selection: $mapping.amountPath)
                Picker("Amount format", selection: $mapping.amountUnit) {
                    Text("27.00").tag("major")
                    Text("2700 cents").tag("minor")
                }
                WebhookFieldPicker(
                    title: "Currency",
                    fields: fields,
                    selection: requiredBinding($mapping.currencyPath)
                )
                WebhookFieldPicker(
                    title: "Time",
                    fields: fields,
                    selection: optionalBinding($mapping.occurredAtPath),
                    allowsNone: true
                )
                WebhookFieldPicker(
                    title: "Product",
                    fields: fields,
                    selection: optionalBinding($mapping.productPath),
                    allowsNone: true
                )
                WebhookFieldPicker(
                    title: "Plan",
                    fields: fields,
                    selection: optionalBinding($mapping.planPath),
                    allowsNone: true
                )
                WebhookFieldPicker(
                    title: "Sale type",
                    fields: fields,
                    selection: optionalBinding($mapping.saleTypePath),
                    allowsNone: true
                )
            } label: {
                Label(
                    paymentMappingIsComplete ? "Payment matching ready" : "Finish payment matching",
                    systemImage: paymentMappingIsComplete ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(paymentMappingIsComplete ? Theme.accent : Theme.gold)
            }
        } header: {
            Text("Payment matching")
        } footer: {
            Text("Confirm which sample fields contain the payment ID, amount, and currency. Optional fields improve payment details.")
        }
    }

    private func notificationFieldRow(_ field: WebhookNotificationField) -> some View {
        HStack(spacing: 12) {
            Button {
                editingField = field
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.label.isEmpty ? "Unnamed detail" : field.label)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text(sampleValue(path: field.path))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(
                "Include \(field.label)",
                isOn: notificationFieldEnabledBinding(id: field.id)
            )
            .labelsHidden()
        }
    }

    private var includedFieldCount: Int {
        mapping.notificationFields.count(where: \.enabled)
    }

    private var mappingIsComplete: Bool {
        paymentMappingIsComplete
            && mapping.notificationFields.contains(where: \.enabled)
            && mapping.notificationFields.allSatisfy {
                !$0.enabled || (
                    !$0.path.isEmpty
                        && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
    }

    private var paymentMappingIsComplete: Bool {
        !mapping.paymentIdPath.isEmpty
            && !mapping.amountPath.isEmpty
            && !(mapping.currencyPath ?? "").isEmpty
    }

    private func requiredBinding(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0 })
    }

    private func optionalBinding(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func sampleValue(path: String) -> String {
        fields.first { $0.path == path }?.value.displayValue ?? "No sample value"
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

    private func moveNotificationFields(from offsets: IndexSet, to destination: Int) {
        mapping.notificationFields.move(fromOffsets: offsets, toOffset: destination)
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

    private func run(_ operation: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await operation() }
        catch { errorMessage = error.localizedDescription }
    }

    private func previewMapping() async {
        guard mappingIsComplete else {
            errorMessage = "Turn on at least one complete notification detail before previewing."
            return
        }

        await run {
            preview = try await store.previewCustomSource(id: source.id, mapping: mapping)
            previewedMapping = mapping
            showingPreview = true
        }
    }

    private func sendTestNotification() async {
        guard mappingIsComplete else {
            errorMessage = "Finish payment matching and turn on at least one notification detail before testing."
            return
        }
        await NotificationManager.shared.requestPermissionAndRegister()
        await run {
            preview = try await store.previewCustomSource(id: source.id, mapping: mapping)
            previewedMapping = mapping
            let sent = try await store.testCustomSourceNotification(id: source.id, mapping: mapping)
            testResultMessage = sent == 1
                ? "Sent to your registered iPhone. Lock the screen or leave Cha-Ching open to check both presentation styles."
                : "Sent to \(sent) registered iPhones."
            showingTestResult = true
        }
    }

    private func activate() async {
        guard previewedMapping == mapping else {
            showingPreview = false
            errorMessage = "Your choices changed. Preview the current notification before activating."
            return
        }

        await run {
            let activatedSource = try await store.activateCustomSource(id: source.id, mapping: mapping)
            await NotificationManager.shared.requestPermissionAndRegister()
            onActivated(activatedSource)
            showingPreview = false
            dismiss()
        }
    }
}

private struct WebhookFieldPicker: View {
    let title: String
    let fields: [WebhookField]
    @Binding var selection: String
    var allowsNone = false

    var body: some View {
        Picker(title, selection: $selection) {
            if allowsNone { Text("Don't save").tag("") }
            if !allowsNone && selection.isEmpty { Text("Choose a field").tag("") }
            ForEach(fields) { field in
                Text("\(field.label): \(field.value.displayValue.prefix(30))")
                    .tag(field.path)
            }
        }
    }
}

private struct WebhookNotificationFieldEditor: View {
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
                    Toggle("Show in notification", isOn: $draft.enabled)
                    TextField("Display name", text: $draft.label)
                        .textInputAutocapitalization(.words)
                }

                Section("Payment data") {
                    Picker("Use field", selection: $draft.path) {
                        ForEach(fields) { option in
                            Text("\(option.label): \(option.value.displayValue.prefix(30))")
                                .tag(option.path)
                        }
                    }
                    LabeledContent("Example", value: selectedSample?.value.displayValue ?? "—")
                    if let selectedSample {
                        Text(selectedSample.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section("Order") {
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
                    Text("You can also tap Edit on the Notification settings screen and drag rows.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Line preview") {
                    Text("\(draft.label.isEmpty ? "Unnamed detail" : draft.label): \(selectedSample?.value.displayValue ?? "—")")
                }
            }
            .navigationTitle("Edit detail")
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

private struct CustomNotificationPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sourceName: String
    let notificationBody: String
    let isActivating: Bool
    let errorMessage: String?
    let onActivate: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(Theme.accent)
                            Text("CHA-CHING")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("now")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Cha-ching!")
                            .font(.headline)
                        Text(notificationBody)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                    Text("This is the exact field order and wording Cha-Ching will use for \(sourceName).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button(action: onActivate) {
                        HStack {
                            Spacer()
                            if isActivating { ProgressView().tint(.white) }
                            Text(isActivating ? "Activating…" : "Activate payment source")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isActivating)
                }
                .padding()
            }
            .navigationTitle("Notification preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
