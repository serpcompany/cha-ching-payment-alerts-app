import AuthenticationServices
import SwiftUI

enum ChaChingLink {
    static let manageSubscription = URL(string: "https://apps.apple.com/account/subscriptions")!
    static let support = URL(string: "https://cha-ching-api.serpcompany.workers.dev/support")!
    static let privacy = URL(string: "https://cha-ching-api.serpcompany.workers.dev/privacy")!
    static let terms = URL(string: "https://cha-ching-api.serpcompany.workers.dev/terms")!
}

enum AccountSheet: String, Identifiable {
    case deletion
    var id: String { rawValue }
}

struct AccountDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Deleting your Cha-Ching account permanently removes your connections, private webhook URLs, payment history, notification registrations, and account data.")
                    Text("Deleting Cha-Ching does not cancel your Apple subscription. Manage or cancel it with Apple before deleting if you do not want it to renew.")
                } header: {
                    Text("Before you delete")
                }

                Section {
                    Link("Manage Subscription", destination: ChaChingLink.manageSubscription)
                }

                Section {
                    Text("Continue with the same Apple Account to confirm your identity. Deletion is immediate and cannot be undone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = []
                        request.nonce = auth.prepareAppleRequest()
                    } onCompletion: { result in
                        auth.handleAccountDeletionAuthorization(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                    .disabled(auth.isDeletingAccount)

                    if auth.isDeletingAccount {
                        HStack {
                            ProgressView()
                            Text("Deleting account…")
                        }
                    }
                    if let error = auth.accountDeletionError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Permanently delete account")
                }

                Section("Help and legal") {
                    Link("Support", destination: ChaChingLink.support)
                    Link("Privacy Policy", destination: ChaChingLink.privacy)
                    Link("Terms of Use", destination: ChaChingLink.terms)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(auth.isDeletingAccount)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(auth.isDeletingAccount)
                }
            }
        }
    }
}
