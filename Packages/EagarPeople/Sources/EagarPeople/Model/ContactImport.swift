import Foundation

/// What the app hands over after Mark picks a contact with the limited-access picker or
/// `ContactAccessButton` (FR-PEOPLE-01, BD-26).
///
/// It has no notes field on purpose: Eagar never reads contact notes. The package does not
/// import Contacts; the app fills this from `CNContact` identifier, name, email addresses and
/// birthday components only.
public struct ContactImport: Sendable, Hashable {
    /// `CNContact.identifier`.
    public let contactIdentifier: String
    public let displayName: String
    /// Email addresses, used to match calendar attendees and personal-lane mail.
    public let emailAddresses: [String]
    public let birthday: Birthday?

    public init(contactIdentifier: String, displayName: String, emailAddresses: [String] = [], birthday: Birthday? = nil) {
        self.contactIdentifier = contactIdentifier
        self.displayName = displayName
        self.emailAddresses = emailAddresses
        self.birthday = birthday
    }

    /// Convenience for the app: birthday from Contacts-style date components.
    public init(contactIdentifier: String, displayName: String, emailAddresses: [String] = [], birthdayComponents: DateComponents?) {
        self.init(
            contactIdentifier: contactIdentifier, displayName: displayName, emailAddresses: emailAddresses,
            birthday: birthdayComponents.flatMap(Birthday.init(components:))
        )
    }
}

/// Lower-cases and trims addresses, dropping empties and duplicates, keeping first-seen order.
func normalisedEmails(_ addresses: [String]) -> [String] {
    var seen = Set<String>()
    return addresses.compactMap { raw in
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard address.contains("@"), seen.insert(address).inserted else { return nil }
        return address
    }
}
