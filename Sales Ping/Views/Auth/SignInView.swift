import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        ZStack {
            Theme.heroGradient.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                iconMark
                VStack(spacing: 8) {
                    Text("Sales Ping")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Cha-ching, every sale.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                VStack(spacing: 14) {
                    if let message = auth.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    SignInWithAppleButton(.signIn, onRequest: configure, onCompletion: auth.handleAppleAuthorization)
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 28)
                    Text("Your account keeps provider connections and sale history in sync securely.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.bottom, 40)
            }
        }
    }

    private var iconMark: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 120, height: 120)
            Image(systemName: "bolt.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = auth.prepareAppleRequest()
    }
}

#Preview {
    SignInView().environmentObject(AuthManager())
}
