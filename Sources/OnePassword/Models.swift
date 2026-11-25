import Foundation

// The types have the fields of onepassword-sdk-go v0.4.1's JSON that signd reads.
// Their coding keys are the SDK's key names, and other keys are ignored.

/// The SDK's category of an item. A category that is not listed here still decodes.
public struct ItemCategory: RawRepresentable, Codable, Hashable, Sendable {
    /// The SDK's text for the category.
    public let rawValue: String

    /// Creates a category from the SDK's text, whether or not this type lists it.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The category of a login item.
    public static let login = ItemCategory(rawValue: "Login")
    /// The category of a secure note item.
    public static let secureNote = ItemCategory(rawValue: "SecureNote")
    /// The category of a credit card item.
    public static let creditCard = ItemCategory(rawValue: "CreditCard")
    /// The category of a crypto wallet item.
    public static let cryptoWallet = ItemCategory(rawValue: "CryptoWallet")
    /// The category of an identity item.
    public static let identity = ItemCategory(rawValue: "Identity")
    /// The category of a password item.
    public static let password = ItemCategory(rawValue: "Password")
    /// The category of a document item.
    public static let document = ItemCategory(rawValue: "Document")
    /// The category of an API credentials item.
    public static let apiCredentials = ItemCategory(rawValue: "ApiCredentials")
    /// The category of a bank account item.
    public static let bankAccount = ItemCategory(rawValue: "BankAccount")
    /// The category of a database item.
    public static let database = ItemCategory(rawValue: "Database")
    /// The category of a driver license item.
    public static let driverLicense = ItemCategory(rawValue: "DriverLicense")
    /// The category of an email item.
    public static let email = ItemCategory(rawValue: "Email")
    /// The category of a medical record item.
    public static let medicalRecord = ItemCategory(rawValue: "MedicalRecord")
    /// The category of a membership item.
    public static let membership = ItemCategory(rawValue: "Membership")
    /// The category of an outdoor license item.
    public static let outdoorLicense = ItemCategory(rawValue: "OutdoorLicense")
    /// The category of a passport item.
    public static let passport = ItemCategory(rawValue: "Passport")
    /// The category of a rewards item.
    public static let rewards = ItemCategory(rawValue: "Rewards")
    /// The category of a router item.
    public static let router = ItemCategory(rawValue: "Router")
    /// The category of a server item.
    public static let server = ItemCategory(rawValue: "Server")
    /// The category of an SSH key item.
    public static let sshKey = ItemCategory(rawValue: "SshKey")
    /// The category of a social security number item.
    public static let socialSecurityNumber = ItemCategory(rawValue: "SocialSecurityNumber")
    /// The category of a software license item.
    public static let softwareLicense = ItemCategory(rawValue: "SoftwareLicense")
    /// The category of a person item.
    public static let person = ItemCategory(rawValue: "Person")
    /// The category of an unsupported item.
    public static let unsupported = ItemCategory(rawValue: "Unsupported")
}

/// Whether an item is in regular view or in the archive. A state that is not listed here still decodes.
public struct ItemState: RawRepresentable, Codable, Hashable, Sendable {
    /// The SDK's text for the state.
    public let rawValue: String

    /// Creates a state from the SDK's text, whether or not this type lists it.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The item is in regular view.
    public static let active = ItemState(rawValue: "active")
    /// The item is in the archive.
    public static let archived = ItemState(rawValue: "archived")
}

/// The SDK's type of an item field. A type that is not listed here still decodes.
public struct FieldType: RawRepresentable, Codable, Hashable, Sendable {
    /// The SDK's text for the field type.
    public let rawValue: String

    /// Creates a field type from the SDK's text, whether or not this type lists it.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The type of a text field.
    public static let text = FieldType(rawValue: "Text")
    /// The type of a concealed text field.
    public static let concealed = FieldType(rawValue: "Concealed")
    /// The type of a field for a credit card type.
    public static let creditCardType = FieldType(rawValue: "CreditCardType")
    /// The type of a field for a credit card number.
    public static let creditCardNumber = FieldType(rawValue: "CreditCardNumber")
    /// The type of a phone number field.
    public static let phone = FieldType(rawValue: "Phone")
    /// The type of an URL field.
    public static let url = FieldType(rawValue: "Url")
    /// The type of an one-time password (TOTP) field.
    public static let totp = FieldType(rawValue: "Totp")
    /// The type of an email address field.
    public static let email = FieldType(rawValue: "Email")
    /// The type of a reference field.
    public static let reference = FieldType(rawValue: "Reference")
    /// The type of an SSH key field.
    public static let sshKey = FieldType(rawValue: "SshKey")
    /// The type of a menu field.
    public static let menu = FieldType(rawValue: "Menu")
    /// The type of a month and year field.
    public static let monthYear = FieldType(rawValue: "MonthYear")
    /// The type of an address field.
    public static let address = FieldType(rawValue: "Address")
    /// The type of a date field.
    public static let date = FieldType(rawValue: "Date")
    /// The type of an unsupported field.
    public static let unsupported = FieldType(rawValue: "Unsupported")
}

/// How the SDK names the failure of an item in a batch. A type that is not listed here still decodes.
public struct ItemFailure: RawRepresentable, Codable, Hashable, Sendable {
    /// The SDK's text for the failure.
    public let rawValue: String

    /// Creates a failure from the SDK's text, whether or not this type lists it.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The item failed the SDK's validation.
    public static let validationError = ItemFailure(rawValue: "itemValidationError")
    /// The token has no permission for the item.
    public static let permissionError = ItemFailure(rawValue: "itemStatusPermissionError")
    /// The version of the item is not the current one.
    public static let incorrectVersion = ItemFailure(rawValue: "itemStatusIncorrectItemVersion")
    /// A file the item refers to was not found.
    public static let fileNotFound = ItemFailure(rawValue: "itemStatusFileNotFound")
    /// The item is too big.
    public static let tooBig = ItemFailure(rawValue: "itemStatusTooBig")
    /// The item was not found.
    public static let notFound = ItemFailure(rawValue: "itemNotFound")
    /// The SDK reported an internal error.
    public static let internalError = ItemFailure(rawValue: "internal")
}

/// A vault that the token reads, with its title and content version.
public struct VaultOverview: Codable, Sendable, Hashable, Identifiable {
    /// The ID of the vault.
    public let id: String
    /// The title of the vault.
    public let title: String
    /// Rises whenever the vault's contents change.
    public let contentVersion: UInt32
    /// When the vault last changed.
    public let updatedAt: Date

    /// Creates a vault overview.
    public init(id: String, title: String, contentVersion: UInt32, updatedAt: Date) {
        self.id = id
        self.title = title
        self.contentVersion = contentVersion
        self.updatedAt = updatedAt
    }
}

/// An item as a vault lists it, without its fields.
public struct ItemOverview: Codable, Sendable, Hashable, Identifiable {
    /// The ID of the item.
    public let id: String
    /// The title of the item.
    public let title: String
    /// The category of the item.
    public let category: ItemCategory
    /// The ID of the vault that contains the item.
    public let vaultID: String
    /// The tags of the item, empty when it has none.
    public let tags: [String]
    /// When the item last changed.
    public let updatedAt: Date
    /// Whether the item is in regular view or in the archive.
    public let state: ItemState

    /// Creates an item overview.
    public init(
        id: String, title: String, category: ItemCategory, vaultID: String, tags: [String] = [], updatedAt: Date,
        state: ItemState
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.vaultID = vaultID
        self.tags = tags
        self.updatedAt = updatedAt
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, tags, updatedAt, state
        case vaultID = "vaultId"
    }

    // Reading the category and the state as strings costs fewer allocations than decoding each
    // through its own single value container.
    // Go writes the tags of an item without any as null, which reads as empty.
    /// Reads an overview from the core's JSON. A null or missing `tags` reads as empty.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        category = ItemCategory(rawValue: try values.decode(String.self, forKey: .category))
        vaultID = try values.decode(String.self, forKey: .vaultID)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        state = ItemState(rawValue: try values.decode(String.self, forKey: .state))
    }
}

/// An item of a vault, with its fields, sections, notes and tags.
public struct Item: Codable, Sendable, Hashable, Identifiable {
    /// A field of an item.
    public struct Field: Codable, Sendable, Hashable, Identifiable {
        /// The ID of the field.
        public let id: String
        /// The title of the field.
        public let title: String
        /// The type of the field.
        public let type: FieldType
        /// The value of the field, as text.
        public let value: String
        /// The ID of the section that contains the field, or nil when it has none.
        public let sectionID: String?
        /// The public key of an `SshKey` field, from the SDK's `details.content.publicKey`.
        /// It is nil when the field has no details, or the details have no public key.
        public let publicKey: String?
        /// The fingerprint of an `SshKey` field's key, from the SDK's `details.content.fingerprint`.
        /// It is nil when the field has no details, or the details have no fingerprint.
        public let fingerprint: String?
        /// The kind of an `SshKey` field's key, from the SDK's `details.content.keyType`: `Ed25519`, or `RSA, {length}-bit`.
        /// It is nil when the field has no details, or the details have no key type.
        public let keyType: String?

        /// Creates a field.
        /// The public key, fingerprint and key type are for an `SshKey` field, and default to nil.
        public init(
            id: String, title: String, type: FieldType, value: String, sectionID: String? = nil,
            publicKey: String? = nil, fingerprint: String? = nil, keyType: String? = nil
        ) {
            self.id = id
            self.title = title
            self.type = type
            self.value = value
            self.sectionID = sectionID
            self.publicKey = publicKey
            self.fingerprint = fingerprint
            self.keyType = keyType
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
            case publicKey, fingerprint, keyType
        }

        // Go writes the details of a field as {"type": ..., "content": {...}}.
        // It writes the content of an SshKey field as null when the field has none.
        // Only an SshKey field's details are read, so a field of another type costs nothing extra.
        /// Reads a field from the core's JSON.
        /// Only an `SshKey` field has its details read.
        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            title = try values.decode(String.self, forKey: .title)
            type = FieldType(rawValue: try values.decode(String.self, forKey: .type))
            value = try values.decode(String.self, forKey: .value)
            sectionID = try values.decodeIfPresent(String.self, forKey: .sectionID)
            var publicKey: String?
            var fingerprint: String?
            var keyType: String?
            if type == .sshKey, values.contains(.details), try !values.decodeNil(forKey: .details) {
                let details = try values.nestedContainer(keyedBy: DetailsKeys.self, forKey: .details)
                if details.contains(.content), try !details.decodeNil(forKey: .content) {
                    let content = try details.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
                    publicKey = try content.decodeIfPresent(String.self, forKey: .publicKey)
                    fingerprint = try content.decodeIfPresent(String.self, forKey: .fingerprint)
                    keyType = try content.decodeIfPresent(String.self, forKey: .keyType)
                }
            }
            self.publicKey = publicKey
            self.fingerprint = fingerprint
            self.keyType = keyType
        }

        /// Writes the field as the core's JSON, with its SSH key details when it has any.
        public func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(id, forKey: .id)
            try values.encode(title, forKey: .title)
            try values.encode(type, forKey: .type)
            try values.encode(value, forKey: .value)
            try values.encodeIfPresent(sectionID, forKey: .sectionID)
            if publicKey != nil || fingerprint != nil || keyType != nil {
                var details = values.nestedContainer(keyedBy: DetailsKeys.self, forKey: .details)
                try details.encode(type, forKey: .type)
                var content = details.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
                try content.encodeIfPresent(publicKey, forKey: .publicKey)
                try content.encodeIfPresent(fingerprint, forKey: .fingerprint)
                try content.encodeIfPresent(keyType, forKey: .keyType)
            }
        }
    }

    /// A section of an item, which groups the fields that name its ID.
    public struct Section: Codable, Sendable, Hashable, Identifiable {
        /// The ID of the section.
        public let id: String
        /// The title of the section.
        public let title: String

        /// Creates a section.
        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    /// The ID of the item.
    public let id: String
    /// The title of the item.
    public let title: String
    /// The category of the item.
    public let category: ItemCategory
    /// The ID of the vault that contains the item.
    public let vaultID: String
    /// The fields of the item, empty when it has none.
    public let fields: [Field]
    /// The sections of the item, empty when it has none.
    public let sections: [Section]
    /// The notes of the item, empty when it has none.
    public let notes: String
    /// The tags of the item, empty when it has none.
    public let tags: [String]
    /// The version of the item's content.
    public let version: UInt32
    /// When the item last changed.
    public let updatedAt: Date

    /// Creates an item.
    public init(
        id: String, title: String, category: ItemCategory, vaultID: String,
        fields: [Field], sections: [Section], notes: String, tags: [String] = [], version: UInt32, updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.vaultID = vaultID
        self.fields = fields
        self.sections = sections
        self.notes = notes
        self.tags = tags
        self.version = version
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, fields, sections, notes, tags, version, updatedAt
        case vaultID = "vaultId"
    }

    // Go encodes a nil slice as null, so an item without sections, fields or tags reads as empty.
    /// Reads an item from the core's JSON.
    /// A null or missing list of fields, sections or tags, and missing notes, read as empty.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        category = ItemCategory(rawValue: try values.decode(String.self, forKey: .category))
        vaultID = try values.decode(String.self, forKey: .vaultID)
        fields = try values.decodeIfPresent([Field].self, forKey: .fields) ?? []
        sections = try values.decodeIfPresent([Section].self, forKey: .sections) ?? []
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        version = try values.decode(UInt32.self, forKey: .version)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}

/// What `Client.create(_:inVault:)` writes for a new item, and what `Client.update(_:inVault:to:)` sets on an
/// existing one: the title, fields, sections, notes and tags.
/// An update ignores the category and keeps the item's own.
public struct ItemContent: Encodable, Sendable, Hashable {
    /// The category of the new item. An update ignores it.
    public let category: ItemCategory
    /// The title of the item.
    public let title: String
    /// The fields of the item.
    public let fields: [Item.Field]
    /// The sections of the item.
    public let sections: [Item.Section]
    /// The notes of the item.
    public let notes: String
    /// The tags of the item.
    public let tags: [String]

    /// Creates the content of an item.
    public init(
        category: ItemCategory, title: String, fields: [Item.Field] = [], sections: [Item.Section] = [],
        notes: String = "", tags: [String] = []
    ) {
        self.category = category
        self.title = title
        self.fields = fields
        self.sections = sections
        self.notes = notes
        self.tags = tags
    }
}

/// The result for one item of a batch: the item, or the SDK's type of failure.
public enum ItemResult: Sendable, Hashable, Decodable {
    case item(Item)
    case failure(ItemFailure)

    private enum CodingKeys: String, CodingKey {
        case item, failure
    }

    // The core writes {"item": ...} or {"failure": "..."} for each item.
    /// Reads the result for one item from the core's JSON: an item, or a failure.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let item = try values.decodeIfPresent(Item.self, forKey: .item) {
            self = .item(item)
        } else if let failure = try values.decodeIfPresent(ItemFailure.self, forKey: .failure) {
            self = .failure(failure)
        } else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath, debugDescription: "an item result has neither an item nor a failure"
                )
            )
        }
    }
}
