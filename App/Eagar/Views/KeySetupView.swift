import EagarAI
import SwiftUI

/// BYOK onboarding (FR-AI-07, FR-AI-10, BD-07): workspace guidance, key entry, test key.
struct KeySetupView: View {
    let model: AppModel
    @State private var keyEntry = ""

    var body: some View {
        Form {
            Section {
                Text("Eagar uses your own Claude API key for personal data you choose to send to Claude. College data never leaves your devices.")
                    .accessibilityIdentifier("key.intro")
                Text("Create a dedicated workspace for Eagar with a monthly spend limit, then create a key in it that expires. Use a separate key on each device, so you can revoke one without affecting the others.")
                Link("How to set up a workspace and spend limit", destination: URL(string: "https://platform.claude.com/docs/en/manage-claude/workspaces")!)
                Link("How to create an API key", destination: URL(string: "https://platform.claude.com/docs/en/manage-claude/authentication")!)
            } header: {
                Text("Before you start")
            }

            Section {
                if let masked = model.maskedKey {
                    LabeledContent("Stored key", value: masked)
                        .accessibilityLabel(Text("Stored key, ending \(String(masked.suffix(4)))"))
                    Button("Remove key from this device", role: .destructive) { model.removeKey() }
                } else {
                    SecureField("Paste your API key", text: $keyEntry)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button("Save key to this device") {
                        model.saveKey(keyEntry)
                        keyEntry = ""
                    }
                    .disabled(keyEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Your key")
            } footer: {
                Text("The key is kept in this device's Keychain only. It is never synced, logged or exported, and is sent only to Anthropic.")
            }

            Section {
                Button {
                    Task { await model.testKey() }
                } label: {
                    if model.keyTestState == .running {
                        ProgressView().accessibilityLabel(Text("Testing key"))
                    } else {
                        Text("Test key")
                    }
                }
                .disabled(!model.hasKey || model.keyTestState == .running)
                .accessibilityIdentifier("key.test")
                KeyTestResultView(state: model.keyTestState)
            } footer: {
                Text("The test sends one short fixed message to Claude Haiku 5.5 and records the call in the privacy ledger, with its exact payload and cost.")
            }

            Section {
                Text("Requests are processed by Anthropic using your key, in the US or globally. Anthropic stores workspace data in the US.")
            } header: {
                Text("Where your data goes")
            }
        }
        .navigationTitle(Text("Claude key"))
    }
}

private struct KeyTestResultView: View {
    let state: AppModel.KeyTestState

    var body: some View {
        switch state {
        case .idle, .running:
            EmptyView()
        case let .finished(outcome):
            switch outcome {
            case let .valid(model, cost):
                Label {
                    Text("Key works with \(model.rawValue). Cost: \(MicroUSD.text(cost ?? 0)).")
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            case .invalidKey:
                Label("Claude rejected this key. Check it has not expired or been revoked.", systemImage: "xmark.octagon")
            case .noKey:
                Label("No key is stored on this device.", systemImage: "key.slash")
            case .failed:
                Label("The test could not reach Claude. Check your connection and try again.", systemImage: "wifi.exclamationmark")
            }
        }
    }
}

/// Formats millionths of a US dollar. API usage is billed in USD.
enum MicroUSD {
    static func text(_ micro: Int64) -> String {
        let dollars = Decimal(micro) / 1_000_000
        return dollars.formatted(.currency(code: "USD").precision(.fractionLength(2...6)))
    }
}
