import DogearCore
import SwiftUI

struct SignInView: View {
    let model: AppModel

    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: SignInError?
    @State private var isSigningIn = false

    private var canSubmit: Bool {
        !isSigningIn && !address.isEmpty && !username.isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://grimmory.example", text: $address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server address")
                }

                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Grimmory account")
                }

                if let error {
                    Section {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        if isSigningIn {
                            ProgressView()
                        } else {
                            Text("Sign In")
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Dogear")
            .onSubmit { Task { await signIn() } }
        }
        .frame(maxWidth: 600)
    }

    private func signIn() async {
        guard canSubmit else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await model.signIn(address: address, username: username, password: password)
        } catch {
            self.error = error
        }
    }
}
