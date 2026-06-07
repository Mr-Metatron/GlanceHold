import XCTest
@testable import GlanceHold

final class GlanceHoldLocalizationTests: XCTestCase {
    private let requiredKeyFamilies = [
        "app.",
        "menu.",
        "action.",
        "status.monitoring.",
        "status.player.",
        "detail.monitoring.",
        "detail.player.",
        "tuning.",
        "alert.",
        "shortcut.",
        "about.",
        "privacy.",
        "accessibility.",
        "format.delay.seconds"
    ]

    func testLocalizableCatalogContainsRequiredFamiliesInEnglishAndSimplifiedChinese() throws {
        let catalog = try localizationCatalog()
        let keys = Set(catalog.keys)

        for family in requiredKeyFamilies {
            XCTAssertTrue(
                keys.contains { $0.hasPrefix(family) || $0 == family },
                "Missing localization key family \(family)"
            )
        }

        for key in keys where requiredKeyFamilies.contains(where: { key.hasPrefix($0) || key == $0 }) {
            let localizations = try XCTUnwrap(catalog[key] as? [String: Any], "Missing entry for \(key)")["localizations"] as? [String: Any]
            XCTAssertNotNil(localizations?["en"], "Missing English localization for \(key)")
            XCTAssertNotNil(localizations?["zh-Hans"], "Missing Simplified Chinese localization for \(key)")
        }
    }

    func testRepresentativeStringsResolveInEnglishAndSimplifiedChinese() {
        XCTAssertEqual(GlanceHoldStrings.text(.appName, localeIdentifier: "en"), "GlanceHold")
        XCTAssertEqual(GlanceHoldStrings.text(.appName, localeIdentifier: "zh-Hans"), "GlanceHold")

        XCTAssertEqual(GlanceHoldStrings.text(.shortcutToggleMonitoring, localeIdentifier: "en"), "Toggle GlanceHold Monitoring")
        XCTAssertEqual(GlanceHoldStrings.text(.shortcutToggleMonitoring, localeIdentifier: "zh-Hans"), "切换 GlanceHold 监控")

        XCTAssertEqual(GlanceHoldStrings.text(.playerSetupNeededTitle, localeIdentifier: "en"), "IINA Bridge Waiting")
        XCTAssertEqual(GlanceHoldStrings.text(.playerSetupNeededTitle, localeIdentifier: "zh-Hans"), "IINA 桥接等待中")

        XCTAssertEqual(
            GlanceHoldStrings.text(.privacyNote, localeIdentifier: "zh-Hans"),
            "摄像头画面仅在本机处理，不会保存或上传。"
        )
    }

    func testCompactDelayFormattingIsLocalized() {
        XCTAssertEqual(GlanceHoldStrings.delaySeconds(0.8, localeIdentifier: "en"), "0.8s")
        XCTAssertEqual(GlanceHoldStrings.delaySeconds(0.8, localeIdentifier: "zh-Hans"), "0.8秒")
    }

    func testEnumBackedVisibleCopyUsesLocalizationHelper() {
        XCTAssertEqual(MonitoringStatus.off.visibleTitle, GlanceHoldStrings.text(.monitoringOffTitle))
        XCTAssertEqual(PlayerControlStatus.setupNeeded.visibleTitle, GlanceHoldStrings.text(.playerSetupNeededTitle))
        XCTAssertEqual(MonitoringMode.speedControl.displayName, GlanceHoldStrings.text(.modeSpeedControl))
        XCTAssertEqual(AttentionSensitivity.balanced.displayName, GlanceHoldStrings.text(.sensitivityBalanced))
    }

    func testInfoPlistCameraPromptIsLocalizedInEnglishAndSimplifiedChinese() throws {
        let english = try String(contentsOf: infoPlistStringsURL(language: "en"), encoding: .utf8)
        let simplifiedChinese = try String(contentsOf: infoPlistStringsURL(language: "zh-Hans"), encoding: .utf8)

        XCTAssertTrue(english.contains("NSCameraUsageDescription"))
        XCTAssertTrue(english.contains("processed only on this Mac"))
        XCTAssertTrue(simplifiedChinese.contains("NSCameraUsageDescription"))
        XCTAssertTrue(simplifiedChinese.contains("仅在本机处理"))
    }

    func testIINAPluginUsesLocalizedShortcutLabelAndRejectsUnauthenticatedRequests() throws {
        let source = try String(contentsOf: projectFileURL("IINAPlugin/GlanceHoldBridge.iinaplugin/main.js"), encoding: .utf8)

        XCTAssertTrue(source.contains(#""zh-Hans": "切换 GlanceHold 监控""#))
        XCTAssertTrue(source.contains("localizedToggleMonitoringTitle()"))
        XCTAssertTrue(source.contains(#""unauthorized""#))
        XCTAssertFalse(source.contains("menu.item(\n  \"Toggle GlanceHold Monitoring\""))
    }

    private func localizationCatalog() throws -> [String: Any] {
        let data = try Data(contentsOf: projectFileURL("GlanceHold/Localizable.xcstrings"))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try XCTUnwrap(root?["strings"] as? [String: Any])
    }

    private func infoPlistStringsURL(language: String) -> URL {
        projectFileURL("GlanceHold/\(language).lproj/InfoPlist.strings")
    }

    private func projectFileURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
