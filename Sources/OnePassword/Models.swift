import Foundation

// The types hold the fields of onepassword-sdk-go v0.4.1's JSON that signd reads, under the SDK's
// key names. Other keys are ignored.

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
    /// The SDK's category name, such as `SshKey` or `SecureNote`.
    public let category: String
    public let vaultId: String
    public let updatedAt: Date
    /// `active` or `archived`.
    public let state: String

    public init(id: String, title: String, category: String, vaultId: String, updatedAt: Date, state: String) {
        self.id = id
        self.title = title
        self.category = category
        self.vaultId = vaultId
        self.updatedAt = updatedAt
        self.state = state
    }
}

public struct Item: Codable, Sendable, Hashable, Identifiable {
    public struct Field: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        /// The SDK's field type name, such as `Text`, `Concealed` or `SshKey`.
        public let fieldType: String
        public let value: String
        public let sectionId: String?
        /// The public key of an `SshKey` field, from the SDK's `details.content.publicKey`; nil when the
        /// field has no details or they hold no public key.
        public let publicKey: String?

        public init(
            id: String, title: String, fieldType: String, value: String, sectionId: String? = nil,
            publicKey: String? = nil
        ) {
            self.id = id
            self.title = title
            self.fieldType = fieldType
            self.value = value
            self.sectionId = sectionId
            self.publicKey = publicKey
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, fieldType, value, sectionId, details
        }

        private enum DetailsKeys: String, CodingKey {
            case type, content
        }

        private enum ContentKeys: String, CodingKey {
            case publicKey
        }

        // Go writes the details of a field as {"type": ..., "content": {...}}, and the content of
        // an SshKey field as null when it holds nothing. Only an SshKey field's details are read,
        // so a field of another type costs nothing extra.
        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            title = try values.decode(String.self, forKey: .title)
            fieldType = try values.decode(String.self, forKey: .fieldType)
            value = try values.decode(String.self, forKey: .value)
            sectionId = try values.decodeIfPresent(String.self, forKey: .sectionId)
            if fieldType == "SshKey", values.contains(.details), try !values.decodeNil(forKey: .details) {
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
            try values.encode(fieldType, forKey: .fieldType)
            try values.encode(value, forKey: .value)
            try values.encodeIfPresent(sectionId, forKey: .sectionId)
            if let publicKey {
                var details = values.nestedContainer(keyedBy: DetailsKeys.self, forKey: .details)
                try details.encode(fieldType, forKey: .type)
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
    public let category: String
    public let vaultId: String
    public let fields: [Field]
    public let sections: [Section]
    public let notes: String
    public let version: UInt32
    public let updatedAt: Date

    public init(
        id: String, title: String, category: String, vaultId: String,
        fields: [Field], sections: [Section], notes: String, version: UInt32, updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.vaultId = vaultId
        self.fields = fields
        self.sections = sections
        self.notes = notes
        self.version = version
        self.updatedAt = updatedAt
    }

    // Go encodes a nil slice as null, so an item without sections or fields reads as empty.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        category = try values.decode(String.self, forKey: .category)
        vaultId = try values.decode(String.self, forKey: .vaultId)
        fields = try values.decodeIfPresent([Field].self, forKey: .fields) ?? []
        sections = try values.decodeIfPresent([Section].self, forKey: .sections) ?? []
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        version = try values.decode(UInt32.self, forKey: .version)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}
