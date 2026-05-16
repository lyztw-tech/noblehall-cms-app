import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        brandMark
                        NobleHallSectionHeader(
                            eyebrow: "Noble Hall CMS",
                            title: "育堂建設品質工作台",
                            subtitle: "築出品味，也守護每一項現場細節。請登入後選擇專案，開始管理任務與平面圖。",
                            systemImage: "building.2.crop.circle"
                        )
                    }
                    .padding(.top, 28)

                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("帳號")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NobleHallTheme.ink)
                            TextField("請輸入帳號", text: $username)
                                .textContentType(.username)
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
                                    Text("登入工作台")
                                }
                            }
                        }
                        .buttonStyle(NobleHallPrimaryButtonStyle())
                        .disabled(username.isEmpty || password.isEmpty || isLoading)
                        .opacity(username.isEmpty || password.isEmpty ? 0.55 : 1)
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
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .nobleHallScreen()
            .dismissKeyboardOnScroll()
            .keyboardDoneToolbar()
            .navigationTitle("登入")
            .navigationBarTitleDisplayMode(.inline)
        }
        .dismissKeyboardOnTapOutside()
    }

    private var brandMark: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NobleHallTheme.brandGold.opacity(0.12))
                Image(systemName: "house.and.flag.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(NobleHallTheme.brandGold)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("育堂建設")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(NobleHallTheme.ink)
                Text("NOBLE HALL")
                    .font(.caption.weight(.semibold))
                    .tracking(2.4)
                    .foregroundStyle(NobleHallTheme.brandGold)
            }
        }
    }

    private func submit() {
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                let user = try await AuthAPI.login(username: username, password: password)
                let spaceAfterApply = await MainActor.run { () -> String? in
                    password = ""
                    session.applyLoginResponse(user)
                    if session.spaceId == nil, let first = user.spaceIds?.first {
                        session.setSpaceId(first)
                    }
                    return session.spaceId
                }
                if let sid = spaceAfterApply {
                    let full = try await AuthAPI.fetchMe(spaceId: sid)
                    await MainActor.run {
                        session.applyLoginResponse(full)
                    }
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
