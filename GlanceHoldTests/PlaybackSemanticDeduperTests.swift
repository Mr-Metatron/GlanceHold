import XCTest
@testable import GlanceHold

final class PlaybackSemanticDeduperTests: XCTestCase {
    func testFirstFacingInMonitoringSessionEmitsAndRepeatedFacingSuppresses() {
        var deduper = PlaybackSemanticDeduper()
        deduper.startSession(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)

        XCTAssertTrue(deduper.shouldEmit(.facing))
        XCTAssertFalse(deduper.shouldEmit(.facing))
        XCTAssertFalse(deduper.shouldEmit(.facing))
    }

    func testRecoveringChainEmitsOncePerSemanticTransition() {
        var deduper = PlaybackSemanticDeduper()
        deduper.startSession(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)

        XCTAssertTrue(deduper.shouldEmit(.lookingAway))
        XCTAssertFalse(deduper.shouldEmit(.lookingAway))
        XCTAssertTrue(deduper.shouldEmit(.recovering))
        XCTAssertFalse(deduper.shouldEmit(.recovering))
        XCTAssertTrue(deduper.shouldEmit(.facing))
        XCTAssertFalse(deduper.shouldEmit(.facing))
    }

    func testNewMonitoringSessionAllowsSameSemanticStateAgain() {
        var deduper = PlaybackSemanticDeduper()
        deduper.startSession(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)

        XCTAssertTrue(deduper.shouldEmit(.facing))
        XCTAssertFalse(deduper.shouldEmit(.facing))

        deduper.startSession(UUID(uuidString: "44444444-4444-4444-4444-444444444444")!)

        XCTAssertTrue(deduper.shouldEmit(.facing))
        XCTAssertFalse(deduper.shouldEmit(.facing))
    }

    func testEndingMonitoringClearsStateAndSuppressesUntilNewSessionStarts() {
        var deduper = PlaybackSemanticDeduper()
        deduper.startSession(UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)

        XCTAssertTrue(deduper.shouldEmit(.lookingAway))

        deduper.endSession()

        XCTAssertFalse(deduper.shouldEmit(.facing))
        XCTAssertFalse(deduper.shouldEmit(.lookingAway))

        deduper.startSession(UUID(uuidString: "66666666-6666-6666-6666-666666666666")!)

        XCTAssertTrue(deduper.shouldEmit(.lookingAway))
    }

    func testModeOrSettingsStyleCallsDoNotReemitWithoutNewSession() {
        var deduper = PlaybackSemanticDeduper()
        deduper.startSession(UUID(uuidString: "77777777-7777-7777-7777-777777777777")!)

        XCTAssertTrue(deduper.shouldEmit(.facing))

        XCTAssertFalse(deduper.shouldEmit(.facing))
        XCTAssertFalse(deduper.shouldEmit(.facing))
    }

    func testRepeatedStableSuppressionExposesNoCommandReason() {
        var deduper = PlaybackSemanticDeduper()
        deduper.startSession(UUID(uuidString: "88888888-8888-8888-8888-888888888888")!)

        XCTAssertTrue(deduper.shouldEmit(.facing))
        XCTAssertFalse(deduper.shouldEmit(.facing))
        XCTAssertEqual(deduper.suppressionReason(for: .facing), .repeatedStableStateNoCommand)
    }

    func testSuppressionWithoutMonitoringSessionDoesNotLookLikeRepeatedStableState() {
        let deduper = PlaybackSemanticDeduper()

        XCTAssertEqual(deduper.suppressionReason(for: .facing), .noActiveSession)
    }
}
