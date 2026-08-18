import XCTest
@testable import OpenWisprLib

final class PermissionCoordinatorTests: XCTestCase {
    func testRepairPlanOrdersEveryMissingCapability() {
        let snapshot = LocalVoicePermissionSnapshot(
            microphone: false,
            accessibility: false,
            inputMonitoring: false
        )
        let coordinator = PermissionCoordinator(
            snapshotProvider: { snapshot },
            signingModeProvider: { .stable }
        )

        let plan = coordinator.repairPlan(for: snapshot)

        XCTAssertEqual(
            plan.missingCapabilities,
            [.inputMonitoring, .microphone, .accessibility]
        )
        XCTAssertEqual(plan.primaryCapability, .inputMonitoring)
        XCTAssertEqual(
            plan.primaryAction,
            .openSettings(.inputMonitoring)
        )
        XCTAssertTrue(plan.instruction?.contains("Step 1 of 3") == true)
        XCTAssertTrue(
            plan.instruction?.contains("not Automic Vault") == true
        )
        XCTAssertTrue(
            plan.instruction?.contains("Drag ~/Applications/Local Voice.app") == true
        )
        XCTAssertTrue(
            plan.instruction?.contains("click minus") == true
        )
        XCTAssertTrue(
            plan.instruction?.contains("advance automatically") == true
        )
        XCTAssertNil(plan.signingWarning)
        XCTAssertFalse(plan.isComplete)
    }

    func testPostEventWithoutFullAXCompletesInsertRepair() {
        let snapshot = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: false,
            inputMonitoring: true,
            postEvent: true
        )
        let coordinator = PermissionCoordinator(
            snapshotProvider: { snapshot },
            signingModeProvider: { .stable }
        )

        let plan = coordinator.repairPlan(for: snapshot)

        XCTAssertTrue(plan.isComplete)
        XCTAssertTrue(snapshot.canInsert)
        XCTAssertTrue(snapshot.runtimeReady(hotkeyMonitorReady: true))
        XCTAssertNil(snapshot.blockingSummary)
    }

    func testCompletePlanHasNoRepairAction() {
        let snapshot = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: true,
            inputMonitoring: true
        )
        let coordinator = PermissionCoordinator(
            snapshotProvider: { snapshot },
            signingModeProvider: { .stable }
        )

        let plan = coordinator.repairPlan(for: snapshot)

        XCTAssertTrue(plan.isComplete)
        XCTAssertNil(plan.primaryCapability)
        XCTAssertNil(plan.primaryAction)
        XCTAssertNil(plan.instruction)
    }

    func testAdhocBuildMakesPermissionChurnExplicit() {
        let snapshot = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: false,
            inputMonitoring: true
        )
        let coordinator = PermissionCoordinator(
            snapshotProvider: { snapshot },
            signingModeProvider: { .adhoc }
        )

        let plan = coordinator.repairPlan(for: snapshot)

        XCTAssertEqual(plan.primaryCapability, .accessibility)
        XCTAssertEqual(
            plan.primaryAction,
            .openSettings(.accessibility)
        )
        XCTAssertTrue(
            plan.instruction?.contains("not Automic Vault")
                == true
        )
        XCTAssertTrue(
            plan.instruction?.contains("Drag ~/Applications/Local Voice.app")
                == true
        )
        XCTAssertTrue(
            plan.instruction?.contains("verify text insertion automatically")
                == true
        )
        XCTAssertTrue(
            plan.signingWarning?.contains("ad-hoc signed") == true
        )
    }

    func testRepairOpensAccessibilityWhenFnTapIsAlreadyRunning() {
        let snapshot = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: false,
            inputMonitoring: false
        )
        let coordinator = PermissionCoordinator(
            snapshotProvider: { snapshot },
            signingModeProvider: { .stable }
        )
        coordinator.updateHotkeyMonitorReady(true)

        let plan = coordinator.repairPlan(for: snapshot)

        XCTAssertEqual(plan.primaryCapability, .accessibility)
        XCTAssertEqual(
            plan.primaryAction,
            .openSettings(.accessibility)
        )
        XCTAssertTrue(
            plan.missingCapabilities.contains(.inputMonitoring)
        )
        XCTAssertFalse(plan.isComplete)
        XCTAssertTrue(
            plan.instruction?.contains("not Automic Vault") == true
        )
    }

    func testMicrophoneRepairRequestsPermissionWithoutBlockingSettingsFlow() {
        let snapshot = LocalVoicePermissionSnapshot(
            microphone: false,
            accessibility: true,
            inputMonitoring: true
        )
        let coordinator = PermissionCoordinator(
            snapshotProvider: { snapshot }
        )

        let plan = coordinator.repairPlan(for: snapshot)

        XCTAssertEqual(plan.primaryCapability, .microphone)
        XCTAssertEqual(plan.primaryAction, .requestMicrophone)
    }

    func testRefreshReportsInputMonitoringTransition() {
        var snapshots = [
            LocalVoicePermissionSnapshot(
                microphone: true,
                accessibility: true,
                inputMonitoring: false
            ),
            LocalVoicePermissionSnapshot(
                microphone: true,
                accessibility: true,
                inputMonitoring: true
            ),
        ]
        let coordinator = PermissionCoordinator(
            snapshotProvider: { snapshots.removeFirst() }
        )

        let first = coordinator.refresh()
        let second = coordinator.refresh()

        XCTAssertFalse(first.inputMonitoringChanged)
        XCTAssertTrue(second.inputMonitoringChanged)
        XCTAssertTrue(second.changed)
    }

    func testRuntimeReadyRequiresPermissionsAndLiveHotkeyMonitor() {
        let granted = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: true,
            inputMonitoring: true
        )
        let missingAccessibility = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: false,
            inputMonitoring: true
        )

        XCTAssertFalse(
            granted.runtimeReady(hotkeyMonitorReady: false)
        )
        XCTAssertFalse(
            missingAccessibility.runtimeReady(hotkeyMonitorReady: true)
        )
        XCTAssertTrue(
            granted.runtimeReady(hotkeyMonitorReady: true)
        )
    }

    func testCoordinatorOwnsCombinedRuntimeReadiness() {
        let granted = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: true,
            inputMonitoring: true
        )
        let coordinator = PermissionCoordinator(
            snapshotProvider: { granted }
        )

        coordinator.refresh()
        XCTAssertFalse(coordinator.runtimeReady)

        coordinator.updateHotkeyMonitorReady(true)
        XCTAssertTrue(coordinator.runtimeReady)
    }

    func testEveryPermissionCombinationProducesConsistentPlanAndReadiness() {
        for bits in 0..<8 {
            let snapshot = LocalVoicePermissionSnapshot(
                microphone: bits & 0b001 != 0,
                accessibility: bits & 0b010 != 0,
                inputMonitoring: bits & 0b100 != 0
            )
            let coordinator = PermissionCoordinator(
                snapshotProvider: { snapshot },
                signingModeProvider: { .stable }
            )

            coordinator.refresh()
            coordinator.updateHotkeyMonitorReady(true)
            let plan = coordinator.repairPlan(for: snapshot)

            XCTAssertEqual(plan.isComplete, bits == 0b111)
            XCTAssertEqual(coordinator.runtimeReady, bits == 0b111)
        }
    }

    func testRepeatedIdenticalRefreshDoesNotReportAChange() {
        let snapshot = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: true,
            inputMonitoring: true
        )
        let coordinator = PermissionCoordinator(
            snapshotProvider: { snapshot }
        )

        coordinator.refresh()
        let second = coordinator.refresh()

        XCTAssertFalse(second.changed)
        XCTAssertFalse(second.inputMonitoringChanged)
    }

    func testApplyingPermissionsCannotLeaveAFalseReadyState() {
        var runtime = LocalVoiceRuntimeSnapshot(
            state: .ready,
            engineName: "Test",
            modelName: "Test",
            languageName: "English",
            statusDetail: "Ready",
            privacyVerified: true,
            whisperReady: true,
            accessibilityReady: true,
            microphoneReady: true,
            inputMonitoringReady: true,
            hotkeyReady: true
        )
        let missingInputMonitoring = LocalVoicePermissionSnapshot(
            microphone: true,
            accessibility: true,
            inputMonitoring: false
        )

        runtime.applyPermissionReadiness(
            missingInputMonitoring,
            hotkeyMonitorReady: false,
            hotkeySummary: "fn"
        )

        XCTAssertEqual(runtime.state, .error)
        XCTAssertFalse(runtime.hotkeyReady)
        XCTAssertEqual(
            runtime.statusDetail,
            "Input Monitoring is required for the recording shortcut"
        )
    }
}
