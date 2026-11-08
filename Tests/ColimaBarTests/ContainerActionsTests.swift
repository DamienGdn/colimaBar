import Foundation
import ColimaBarCore

private func makeManager(_ args: [String], output: String = "", error: String = "", exitCode: Int32 = 0) -> (ColimaManager, MockShellRunner) {
    let mock = MockShellRunner()
    mock.responses[makeKey(_dockerPath, args)] = (output: output, error: error, exitCode: exitCode)
    return (ColimaManager(shell: mock, colimaPath: _colimaPath, dockerPath: _dockerPath), mock)
}

func test_removeContainer_usesRm() {
    let (mgr, mock) = makeManager(["rm", "web"])
    var result: Result<Void, Error>?
    mgr.removeContainer("web", force: false) { result = $0 }
    waitUntil { result != nil }
    checkEqual(mock.calls.first?.args, ["rm", "web"], "rm args")
    if case .success? = result { check(true, "rm succeeds") } else { check(false, "rm succeeds") }
}

func test_removeContainer_force_usesDashF() {
    let (mgr, mock) = makeManager(["rm", "-f", "web"])
    var result: Result<Void, Error>?
    mgr.removeContainer("web", force: true) { result = $0 }
    waitUntil { result != nil }
    checkEqual(mock.calls.first?.args, ["rm", "-f", "web"], "rm -f args")
    if case .success? = result { check(true, "rm -f succeeds") } else { check(false, "rm -f succeeds") }
}

func test_removeContainer_failure_propagatesMessage() {
    let (mgr, _) = makeManager(["rm", "web"], error: "conflict", exitCode: 1)
    var result: Result<Void, Error>?
    mgr.removeContainer("web", force: false) { result = $0 }
    waitUntil { result != nil }
    if case .failure(let e)? = result {
        checkEqual(e.localizedDescription, "conflict", "error message propagated")
    } else { check(false, "expected failure") }
}

func test_pruneImages_args() {
    let (mgr, mock) = makeManager(["image", "prune", "-f"], output: "Total reclaimed space: 0B")
    var result: Result<String, Error>?
    mgr.pruneImages { result = $0 }
    waitUntil { result != nil }
    checkEqual(mock.calls.first?.args, ["image", "prune", "-f"], "prune args")
    if case .success(let out)? = result { checkEqual(out, "Total reclaimed space: 0B", "prune output") }
    else { check(false, "prune succeeds") }
}

func test_inspectContainer_returnsJSON() {
    let json = "[{\"Id\":\"abc\"}]"
    let (mgr, mock) = makeManager(["inspect", "web"], output: json)
    var result: Result<String, Error>?
    mgr.inspectContainer("web") { result = $0 }
    waitUntil { result != nil }
    checkEqual(mock.calls.first?.args, ["inspect", "web"], "inspect args")
    if case .success(let out)? = result { checkEqual(out, json, "inspect JSON") }
    else { check(false, "inspect succeeds") }
}

func test_statePolicy_inFlight_ignoresPolledRunning() {
    check(!StateUpdatePolicy.shouldApplyPolled(operationInFlight: true, colima: .running), "running ignored")
    check(!StateUpdatePolicy.shouldApplyPolled(operationInFlight: true, colima: .stopped), "stopped ignored")
}

func test_statePolicy_inFlight_appliesTransitioning() {
    check(StateUpdatePolicy.shouldApplyPolled(operationInFlight: true, colima: .transitioning("Starting")), "transitioning applied")
}

func test_statePolicy_notInFlight_appliesPolled() {
    check(StateUpdatePolicy.shouldApplyPolled(operationInFlight: false, colima: .running), "running applied")
    check(StateUpdatePolicy.shouldApplyPolled(operationInFlight: false, colima: .stopped), "stopped applied")
}
