import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The share extension's entry point (FR-TRIAL-03): hosts ``ShareView`` and runs the import.
#if os(iOS)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareRoot(context: extensionContext))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
#else
final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSHostingView(rootView: ShareRoot(context: extensionContext))
        preferredContentSize = NSSize(width: 360, height: 220)
    }
}
#endif

/// Runs the import once and shows the outcome.
struct ShareRoot: View {
    let context: NSExtensionContext?
    @State private var state = ShareImportState.reading

    var body: some View {
        ShareView(state: state) { context?.completeRequest(returningItems: nil) }
            .task {
                let attachments = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
                state = await ShareImport.run(attachments)
            }
    }
}

struct ShareView: View {
    let state: ShareImportState
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Label("Add to Eagar", systemImage: "creditcard")
                .font(.headline)
            Group {
                switch state {
                case .reading:
                    ProgressView { Text("Reading on this device…") }
                case let .saved(service?):
                    Text("Eagar will ask you to confirm \(service) the next time you open it.")
                case .saved(nil):
                    Text("Eagar will ask you to confirm the subscription the next time you open it.")
                case .noContainer:
                    Text("This build of Eagar can't receive shared items. Add the subscription in Eagar instead.")
                case .nothingFound:
                    Text("Eagar found no subscription details in this item.")
                case .failed:
                    Text("Eagar could not save this item. Try again, or add it in Eagar.")
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            Button(action: onDone) {
                Text("Done").frame(minWidth: 88, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state == .reading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
