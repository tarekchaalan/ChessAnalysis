import SwiftUI

struct LoginView: View {
    @ObservedObject var settings: AppSettings
    var onConnect: () -> Void
    @State private var usernameDraft: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Connect your Chess.com account")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.caption)
                TextField("Chess.com username", text: $usernameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            Button("Connect") {
                settings.username = usernameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                onConnect()
            }
            .buttonStyle(.borderedProminent)

            Text("Not affiliated with Chess.com. Games are fetched from public endpoints; no local caching unless you download a game.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .onAppear {
            if usernameDraft.isEmpty {
                usernameDraft = settings.username
            }
        }
    }
}
