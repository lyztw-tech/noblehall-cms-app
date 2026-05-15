import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("帳號", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                    SecureField("密碼", text: $password)
                        .textContentType(.password)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                }
                Section {
                    Button(action: submit) {
                        if isLoading { ProgressView() } else { Text("登入") }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isLoading)
                }
                Section {
                    LabeledContent("環境") {
                        Text(AppConfiguration.developerFacingAPIStatusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .dismissKeyboardOnScroll()
            .keyboardDoneToolbar()
            .navigationTitle("Noblehall")
        }
        .dismissKeyboardOnTapOutside()
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
