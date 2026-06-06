import Foundation

protocol AttentionSettingsStoring {
    func load() -> AttentionSettings
    func save(_ settings: AttentionSettings) throws
    func reset() throws
}

struct UserDefaultsAttentionSettingsStore: AttentionSettingsStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        key: String = "com.metatron.GlanceHold.attentionSettings.v1",
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.defaults = defaults
        self.key = key
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() -> AttentionSettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? decoder.decode(AttentionSettings.self, from: data),
            settings.schemaVersion == AttentionSettings.currentSchemaVersion
        else {
            return .defaults
        }

        return settings
    }

    func save(_ settings: AttentionSettings) throws {
        let data = try encoder.encode(settings)
        defaults.set(data, forKey: key)
    }

    func reset() throws {
        defaults.removeObject(forKey: key)
    }
}
