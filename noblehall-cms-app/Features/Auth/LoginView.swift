import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var account = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    loginContent
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
            .nobleHallScreen()
            .dismissKeyboardOnScroll()
            .toolbar(.hidden, for: .navigationBar)
        }
        .dismissKeyboardOnTapOutside()
    }

    private var loginContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            brandMark

            VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("帳號")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NobleHallTheme.ink)
                            TextField("請輸入帳號", text: $account)
                                .textContentType(.username)
                                .keyboardType(.default)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NobleHallTheme.hairline, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("密碼")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NobleHallTheme.ink)
                            SecureField("請輸入密碼", text: $password)
                                .textContentType(.password)
                                .padding(14)
                                .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NobleHallTheme.hairline, lineWidth: 1))
                        }

                        if let errorMessage {
                            Label {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .textSelection(.enabled)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .foregroundStyle(.red)
                            .padding(12)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        Button(action: submit) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.right.circle.fill")
                                    Text("登入")
                                }
                            }
                        }
                        .buttonStyle(NobleHallPrimaryButtonStyle())
                        .disabled(account.isEmpty || password.isEmpty || isLoading)
                        .opacity(account.isEmpty || password.isEmpty ? 0.55 : 1)
                    }
                    .padding(20)
                    .nobleHallCard()

                    DisclosureGroup {
                        Text(AppConfiguration.developerFacingAPIStatusLine)
                            .font(.caption)
                            .foregroundStyle(NobleHallTheme.secondaryInk)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } label: {
                        Label("環境與連線資訊", systemImage: "network")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(NobleHallTheme.secondaryInk)
                    }
                    .padding(16)
                    .nobleHallCard(cornerRadius: 18)
        }
    }

    private var brandMark: some View {
        Image("NobleHallLogo")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 168)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("育堂建設 Noble Hall")
    }

    private func submit() {
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                let response = try await AuthAPI.login(account: account, password: password)
                await MainActor.run {
                    password = ""
                    session.applyLoginResponse(response)
                }
            } catch {
                errorMessage = error.userFacingMessage
            }
        }
    }
}
