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
                    Text("Cha-Ching")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Know the moment you get paid.")
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
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: 132, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Theme.gold.opacity(0.35), radius: 24, x: 0, y: 12)
    }

    private func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = auth.prepareAppleRequest()
    }
}

#Preview {
    SignInView().environmentObject(AuthManager())
}
