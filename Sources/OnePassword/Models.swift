import Foundation

// The types have the fields of onepassword-sdk-go v0.4.1's JSON that signd reads.
// Their coding keys are the SDK's key names, and other keys are ignored.

/// The SDK's category of an item. A category that is not listed here still decodes.
public struct ItemCategory: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let login = ItemCategory(rawValue: "Login")
    public static let secureNote = ItemCategory(rawValue: "SecureNote")
    public static let creditCard = ItemCategory(rawValue: "CreditCard")
    public static let cryptoWallet = ItemCategory(rawValue: "CryptoWallet")
    public static let identity = ItemCategory(rawValue: "Identity")
    public static let password = ItemCategory(rawValue: "Password")
    public static let document = ItemCategory(rawValue: "Document")
    public static let apiCredentials = ItemCategory(rawValue: "ApiCredentials")
    public static let bankAccount = ItemCategory(rawValue: "BankAccount")
    public static let database = ItemCategory(rawValue: "Database")
    public static let driverLicense = ItemCategory(rawValue: "DriverLicense")
    public static let email = ItemCategory(rawValue: "Email")
    public static let medicalRecord = ItemCategory(rawValue: "MedicalRecord")
    public static let membership = ItemCategory(rawValue: "Membership")
    public static let outdoorLicense = ItemCategory(rawValue: "OutdoorLicense")
    public static let passport = ItemCategory(rawValue: "Passport")
    public static let rewards = ItemCategory(rawValue: "Rewards")
    public static let router = ItemCategory(rawValue: "Router")
    public static let server = ItemCategory(rawValue: "Server")
    public static let sshKey = ItemCategory(rawValue: "SshKey")
    public static let socialSecurityNumber = ItemCategory(rawValue: "SocialSecurityNumber")
    public static let softwareLicense = ItemCategory(rawValue: "SoftwareLicense")
    public static let person = ItemCategory(rawValue: "Person")
    public static let unsupported = ItemCategory(rawValue: "Unsupported")
}

/// Whether an item is in regular view or in the archive. A state that is not listed here still decodes.
public struct ItemState: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let active = ItemState(rawValue: "active")
    public static let archived = ItemState(rawValue: "archived")
}

/// The SDK's type of an item field. A type that is not listed here still decodes.
public struct FieldType: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let text = FieldType(rawValue: "Text")
    public static let concealed = FieldType(rawValue: "Concealed")
    public static let creditCardType = FieldType(rawValue: "CreditCardType")
    public static let creditCardNumber = FieldType(rawValue: "CreditCardNumber")
    public static let phone = FieldType(rawValue: "Phone")
    public static let url = FieldType(rawValue: "Url")
    public static let totp = FieldType(rawValue: "Totp")
    public static let email = FieldType(rawValue: "Email")
    public static let reference = FieldType(rawValue: "Reference")
    public static let sshKey = FieldType(rawValue: "SshKey")
    public static let menu = FieldType(rawValue: "Menu")
    public static let monthYear = FieldType(rawValue: "MonthYear")
    public static let address = FieldType(rawValue: "Address")
    public static let date = FieldType(rawValue: "Date")
    public static let unsupported = FieldType(rawValue: "Unsupported")
}

public struct VaultOverview: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// Rises whenever the vault's contents change.
    public let contentVersion: UInt32
    public let updatedAt: Date

    public init(id: String, title: String, contentVersion: UInt32, updatedAt: Date) {
        self.id = id
        self.title = title
        self.contentVersion = contentVersion
        self.updatedAt = updatedAt
    }
}

public struct ItemOverview: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let category: ItemCategory
    public let vaultID: String
    public let updatedAt: Date
    public let state: ItemState

    public init(id: String, title: String, category: ItemCategory, vaultID: String, updatedAt: Date, state: ItemState) {
        self.id = id
        self.title = title
        self.category = category
        self.vaultID = vaultID
        self.updatedAt = updatedAt
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, updatedAt, state
        case vaultID = "vaultId"
    }
}

public struct Item: Codable, Sendable, Hashable, Identifiable {
    public struct Field: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        public let type: FieldType
        public let value: String
        public let sectionID: String?
        /// The public key of an `SshKey` field, from the SDK's `details.content.publicKey`.
        /// It is nil when the field has no details, or the details have no public key.
        public let publicKey: String?

        public init(
            id: String, title: String, type: FieldType, value: String, sectionID: String? = nil,
            publicKey: String? = nil
        ) {
            self.id = id
            self.title = title
            self.type = type
            self.value = value
            self.sectionID = sectionID
            self.publicKey = publicKey
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, value, details
            case type = "fieldType"
            case sectionID = "sectionId"
        }

        private enum DetailsKeys: String, CodingKey {
            case type, content
        }

        private enum ContentKeys: String, CodingKey {
            case publicKey
        }

        // Go writes the details of a field as {"type": ..., "content": {...}}.
        // It writes the content of an SshKey field as null when the field has none.
        // Only an SshKey field's details are read, so a field of another type costs nothing extra.
        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            title = try values.decode(String.self, forKey: .title)
            type = FieldType(rawValue: try values.decode(String.self, forKey: .type))
            value = try values.decode(String.self, forKey: .value)
            sectionID = try values.decodeIfPresent(String.self, forKey: .sectionID)
            if type == .sshKey, values.contains(.details), try !values.decodeNil(forKey: .details) {
                let details = try values.nestedContainer(keyedBy: DetailsKeys.self, forKey: .details)
                if details.contains(.content), try !details.decodeNil(forKey: .content) {
                    let content = try details.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
                    publicKey = try content.decodeIfPresent(String.self, forKey: .publicKey)
                } else {
                    publicKey = nil
                }
            } else {
                publicKey = nil
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(id, forKey: .id)
            try values.encode(title, forKey: .title)
            try values.encode(type, forKey: .type)
            try values.encode(value, forKey: .value)
            try values.encodeIfPresent(sectionID, forKey: .sectionID)
            if let publicKey {
                var details = values.nestedContainer(keyedBy: DetailsKeys.self, forKey: .details)
                try details.encode(type, forKey: .type)
                var content = details.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
                try content.encode(publicKey, forKey: .publicKey)
            }
        }
    }

    public struct Section: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public let id: String
    public let title: String
    public let category: ItemCategory
    public let vaultID: String
    public let fields: [Field]
    public let sections: [Section]
    public let notes: String
    public let version: UInt32
    public let updatedAt: Date

    public init(
        id: String, title: String, category: ItemCategory, vaultID: String,
        fields: [Field], sections: [Section], notes: String, version: UInt32, updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.vaultID = vaultID
        self.fields = fields
        self.sections = sections
        self.notes = notes
        self.version = version
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, fields, sections, notes, version, updatedAt
        case vaultID = "vaultId"
    }

    // Go encodes a nil slice as null, so an item without sections or fields reads as empty.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        category = ItemCategory(rawValue: try values.decode(String.self, forKey: .category))
        vaultID = try values.decode(String.self, forKey: .vaultID)
        fields = try values.decodeIfPresent([Field].self, forKey: .fields) ?? []
        sections = try values.decodeIfPresent([Section].self, forKey: .sections) ?? []
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        version = try values.decode(UInt32.self, forKey: .version)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}
