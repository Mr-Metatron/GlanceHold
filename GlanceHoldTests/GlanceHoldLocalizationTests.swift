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
            GlanceHoldStrings.text(.privacyPermissionExplanation, localeIdentifier: "en"),
            "GlanceHold uses the camera to calibrate your facing-screen pose."
        )
        XCTAssertEqual(
            GlanceHoldStrings.text(.privacyPermissionExplanation, localeIdentifier: "zh-Hans"),
            "GlanceHold 使用摄像头校准你正对屏幕的姿态。"
        )

        XCTAssertEqual(
            GlanceHoldStrings.format(.menuLastActionFormat, "Held speed at 1x", localeIdentifier: "en"),
            "Last Action: Held speed at 1x"
        )
        XCTAssertEqual(
            GlanceHoldStrings.format(.menuLastActionFormat, "已将速度保持在 1x", localeIdentifier: "zh-Hans"),
            "上次操作：已将速度保持在 1x"
        )
        XCTAssertEqual(GlanceHoldStrings.text(.menuDiagnosticMode, localeIdentifier: "en"), "Diagnostic Mode")
        XCTAssertEqual(GlanceHoldStrings.text(.menuDiagnosticMode, localeIdentifier: "zh-Hans"), "诊断模式")
        XCTAssertEqual(
            GlanceHoldStrings.format(.lastActionRestoredSpeed, "2x", localeIdentifier: "en"),
            "Restored speed to 2x"
        )
        XCTAssertEqual(
            GlanceHoldStrings.format(.lastActionRestoredSpeed, "2x", localeIdentifier: "zh-Hans"),
            "已恢复速度到 2x"
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
        XCTAssertTrue(english.contains("uses the camera to detect whether you are facing the screen"))
        XCTAssertFalse(english.contains("processed only on this Mac"))
        XCTAssertFalse(english.contains("not saved"))
        XCTAssertFalse(english.contains("uploaded"))
        XCTAssertTrue(simplifiedChinese.contains("NSCameraUsageDescription"))
        XCTAssertTrue(simplifiedChinese.contains("使用摄像头判断你是否正对屏幕"))
        XCTAssertFalse(simplifiedChinese.contains("仅在本机处理"))
        XCTAssertFalse(simplifiedChinese.contains("不会保存"))
        XCTAssertFalse(simplifiedChinese.contains("不会上传"))
    }

    func testPlayerDetailCopyDoesNotRepeatNoCommandAssurances() {
        let details = [
            GlanceHoldStrings.text(.playerIdleDetail, localeIdentifier: "en"),
            GlanceHoldStrings.text(.playerNotControllableDetail, localeIdentifier: "en"),
            GlanceHoldStrings.text(.playerIdleDetail, localeIdentifier: "zh-Hans"),
            GlanceHoldStrings.text(.playerNotControllableDetail, localeIdentifier: "zh-Hans")
        ]

        XCTAssertFalse(details.contains { $0.contains("No playback command will be sent") })
        XCTAssertFalse(details.contains { $0.contains("不会发送播放命令") })
    }

    func testAppSurfacePrivacyCopyStaysPurposeFocused() {
        let visibleAppSurfaceStrings = [
            GlanceHoldStrings.text(.privacyPermissionExplanation, localeIdentifier: "en"),
            GlanceHoldStrings.text(.privacyNote, localeIdentifier: "en"),
            GlanceHoldStrings.text(.aboutPrivacyBody, localeIdentifier: "en"),
            GlanceHoldStrings.text(.privacyPermissionExplanation, localeIdentifier: "zh-Hans"),
            GlanceHoldStrings.text(.privacyNote, localeIdentifier: "zh-Hans"),
            GlanceHoldStrings.text(.aboutPrivacyBody, localeIdentifier: "zh-Hans")
        ]

        XCTAssertTrue(visibleAppSurfaceStrings.contains { $0.contains("camera") || $0.contains("摄像头") })
        XCTAssertNoRedundantPrivacyAssurance(in: visibleAppSurfaceStrings)
    }

    func testIINAPluginUsesLocalizedShortcutLabelAndNoTokenBridgeMetadata() throws {
        let source = try String(contentsOf: projectFileURL("IINAPlugin/GlanceHoldBridge.iinaplugin/main.js"), encoding: .utf8)
        let infoData = try Data(contentsOf: projectFileURL("IINAPlugin/GlanceHoldBridge.iinaplugin/Info.json"))
        let pluginInfo = try XCTUnwrap(try JSONSerialization.jsonObject(with: infoData) as? [String: Any])
        let preferenceDefaults = pluginInfo["preferenceDefaults"] as? [String: Any]
        let preferencesPageURL = projectFileURL("IINAPlugin/GlanceHoldBridge.iinaplugin/preferences.html")

        XCTAssertTrue(source.contains(#""zh-Hans": "切换 GlanceHold 监控""#))
        XCTAssertTrue(source.contains("localizedToggleMonitoringTitle()"))
        XCTAssertFalse(source.contains("menu.item(\n  \"Toggle GlanceHold Monitoring\""))
        XCTAssertTrue(source.contains("executeBridgeCommand"))
        XCTAssertTrue(source.contains(#""snapshot""#))
        XCTAssertTrue(source.contains(#""setSpeed""#))
        XCTAssertTrue(source.contains(#""pause""#))
        XCTAssertTrue(source.contains(#""resume""#))
        XCTAssertFalse(source.contains("bridgeTokenPreferenceKey"))
        XCTAssertFalse(source.contains(#"preferences.get("bridgeToken")"#))
        XCTAssertFalse(source.contains("request.token"))
        XCTAssertFalse(source.contains(#""unauthorized""#))
        XCTAssertNil(pluginInfo["preferencesPage"])
        XCTAssertNil(preferenceDefaults?["bridgeToken"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferencesPageURL.path))
    }

    func testBridgeDocsAvoidManualTokenSetupAndDescribeUpdateNeededGuidance() throws {
        let pluginReadme = try String(contentsOf: projectFileURL("IINAPlugin/README.md"), encoding: .utf8)
        let topLevelReadme = try String(contentsOf: projectFileURL("README.md"), encoding: .utf8)
        let docs = [pluginReadme, topLevelReadme]

        XCTAssertTrue(pluginReadme.contains("No request token is required."))
        XCTAssertTrue(pluginReadme.contains("Do not copy or paste a bridge token."))
        XCTAssertTrue(pluginReadme.contains("There is no remote host configuration."))
        XCTAssertTrue(pluginReadme.contains("Phase 11 inherits this no-token local loopback trust model."))
        XCTAssertTrue(
            docs.allSatisfy {
                $0.contains("Update or reinstall the GlanceHold IINA plugin, then restart IINA.")
            }
        )

        for doc in docs {
            XCTAssertFalse(doc.contains("Bridge Token"))
            XCTAssertFalse(doc.contains("iinaPluginBridgeToken"))
            XCTAssertFalse(doc.contains("defaults read"))
            XCTAssertFalse(doc.contains("plugin preference token"))
            XCTAssertFalse(doc.contains("token preference"))
            XCTAssertFalse(doc.contains("preferencesPage"))
            XCTAssertFalse(doc.contains(#"data-pref-key="bridgeToken""#))
        }
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

    private func XCTAssertNoRedundantPrivacyAssurance(
        in strings: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let redundantPhrases = [
            "processed only on this Mac",
            "not saved",
            "uploaded",
            "仅在本机处理",
            "不会保存",
            "不会上传"
        ]

        for string in strings {
            for phrase in redundantPhrases {
                XCTAssertFalse(string.contains(phrase), "\(phrase) should not appear in \(string)", file: file, line: line)
            }
        }
    }
}
