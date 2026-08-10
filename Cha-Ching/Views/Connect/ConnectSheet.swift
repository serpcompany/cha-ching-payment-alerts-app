import SwiftUI

struct ConnectSheet: View {
    let processor: Processor
    let isConnected: Bool

    @EnvironmentObject private var connectStore: ConnectStore
    @Environment(\.dismiss) private var dismiss

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

                if !isConnected {
                    Section {
                        Button {
                            Task { await connect() }
                        } label: {
                            HStack {
                                Spacer()
                                if connectStore.isBusy {
                                    ProgressView()
                                } else {
                                    Text("Connect with \(processor.title)")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(
                            connectStore.isBusy ||
                            !connectStore.isEntitled(to: processor) ||
                            !connectStore.isAvailable(processor)
                        )
                    }
                    if !connectStore.isEntitled(to: processor) {
                        Section {
                            Text("Your current plan doesn't include this connection.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    } else if !connectStore.isAvailable(processor) {
                        Section {
                            Text("We're finishing \(processor.title) setup. This connection will become available without an app update.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
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
                        .disabled(connectStore.isBusy)
                    }
                }

                Section {
                    Text("Authorization happens on \(processor.title). Access tokens are encrypted by Cha-Ching's backend and are never stored on this device.")
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
            }
        }
    }

    private func connect() async {
        let success = await connectStore.connect(provider: processor)
        if success { dismiss() }
    }
}
