import Foundation

struct DiagnosticSettings: Equatable, Codable {
    static let currentSchemaVersion = 1
    static let disabled = DiagnosticSettings()

    var schemaVersion: Int
    var isEnabled: Bool

    init(schemaVersion: Int = currentSchemaVersion, isEnabled: Bool = false) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
    }

    var diagnosticMode: DiagnosticMode {
        isEnabled ? .diagnostic : .default
    }
}

protocol DiagnosticSettingsStoring: AnyObject {
    func load() -> DiagnosticSettings
    func save(_ settings: DiagnosticSettings) throws
}

final class UserDefaultsDiagnosticSettingsStore: DiagnosticSettingsStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        key: String = "com.metatron.GlanceHold.diagnosticSettings.v1",
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.defaults = defaults
        self.key = key
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() -> DiagnosticSettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? decoder.decode(DiagnosticSettings.self, from: data),
            settings.schemaVersion == DiagnosticSettings.currentSchemaVersion
        else {
            return .disabled
        }

        return settings
    }

    func save(_ settings: DiagnosticSettings) throws {
        let data = try encoder.encode(settings)
        defaults.set(data, forKey: key)
    }
}
