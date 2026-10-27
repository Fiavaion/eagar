import Contacts
import EagarPeople
import SwiftUI
#if os(iOS)
import ContactsUI
#else
import AppKit
import ContactsUI
#endif

/// Reads only what keep-in-touch needs from a picked contact: identifier, name, email
/// addresses and birthday (FR-PEOPLE-01). Never the note: `CNContactNoteKey` is not fetched,
/// so its value is not even available to the app.
enum ContactReader {
    static var keys: [any CNKeyDescriptor] {
        [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]
    }

    /// Fetches the contacts Mark shared with Eagar through the limited-access picker.
    @concurrent
    static func imports(identifiers: [String]) async throws -> [ContactImport] {
        guard !identifiers.isEmpty else { return [] }
        let contacts = try CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: identifiers), keysToFetch: keys)
        return contacts.map(makeImport)
    }

    /// Converts a contact, reading each key only if it was fetched or supplied by the picker.
    static func makeImport(_ contact: CNContact) -> ContactImport {
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        let emails = contact.isKeyAvailable(CNContactEmailAddressesKey) ? contact.emailAddresses.map { $0.value as String } : []
        let birthday = contact.isKeyAvailable(CNContactBirthdayKey) ? contact.birthday : nil
        return ContactImport(
            contactIdentifier: contact.identifier,
            displayName: name.isEmpty ? String(localized: "Unnamed contact") : name,
            emailAddresses: emails,
            birthdayComponents: birthday
        )
    }
}

#if os(iOS)
/// iOS: the limited-access contact picker and `ContactAccessButton` (FR-PEOPLE-01, BD-26).
/// Eagar sees only the contacts Mark chooses.
struct ContactPickerSection: View {
    let onPicked: ([ContactImport]) -> Void
    let onFailure: () -> Void
    @State private var status = CNContactStore.authorizationStatus(for: .contacts)
    @State private var showingPicker = false
    @State private var query = ""

    var body: some View {
        Section {
            switch status {
            case .notDetermined:
                Button("Choose people from Contacts") {
                    Task {
                        _ = try? await CNContactStore().requestAccess(for: .contacts)
                        status = CNContactStore.authorizationStatus(for: .contacts)
                        if status == .limited || status == .authorized { showingPicker = true }
                    }
                }
                .frame(minHeight: 44)
            case .limited, .authorized:
                Button("Choose people from Contacts") { showingPicker = true }
                    .frame(minHeight: 44)
                TextField("Search Contacts", text: $query)
                    .textInputAutocapitalization(.words)
                if !query.isEmpty {
                    ContactAccessButton(queryString: query) { identifiers in fetch(identifiers) }
                        .frame(minHeight: 44)
                }
            case .denied, .restricted:
                Text("Contacts access is off. You can turn it on in Settings, or add people by name.")
                    .foregroundStyle(.secondary)
            @unknown default:
                EmptyView()
            }
        } header: {
            Text("From Contacts")
        } footer: {
            Text("Eagar reads only the name, email addresses and birthday of the people you choose, never their notes.")
        }
        .contactAccessPicker(isPresented: $showingPicker) { identifiers in fetch(identifiers) }
    }

    private func fetch(_ identifiers: [String]) {
        Task {
            do {
                onPicked(try await ContactReader.imports(identifiers: identifiers))
            } catch {
                onFailure()
            }
        }
    }
}
#else
/// macOS: Apple's contact picker popover. It returns the chosen contact without Eagar having
/// access to the rest of Contacts (FR-PEOPLE-01).
struct ContactPickerSection: View {
    let onPicked: ([ContactImport]) -> Void
    let onFailure: () -> Void

    var body: some View {
        Section {
            ContactPickerButton(onPicked: onPicked)
                .frame(minHeight: 44)
        } header: {
            Text("From Contacts")
        } footer: {
            Text("Eagar reads only the name, email addresses and birthday of the people you choose, never their notes.")
        }
    }
}

/// A button that shows `CNContactPicker` relative to itself.
private struct ContactPickerButton: NSViewRepresentable {
    let onPicked: ([ContactImport]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: String(localized: "Choose someone from Contacts…"), target: context.coordinator, action: #selector(Coordinator.show(_:)))
        button.bezelStyle = .push
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.onPicked = onPicked
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency CNContactPickerDelegate {
        var onPicked: ([ContactImport]) -> Void
        private let picker = CNContactPicker()

        init(onPicked: @escaping ([ContactImport]) -> Void) {
            self.onPicked = onPicked
            super.init()
            picker.delegate = self
        }

        @objc func show(_ sender: NSButton) {
            picker.showRelative(to: sender.bounds, of: sender, preferredEdge: .maxY)
        }

        func contactPicker(_ picker: CNContactPicker, didSelect contact: CNContact) {
            onPicked([ContactReader.makeImport(contact)])
            picker.close()
        }
    }
}
#endif
