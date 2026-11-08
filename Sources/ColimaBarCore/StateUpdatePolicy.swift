import Foundation

public enum StateUpdatePolicy {
    /// A polled/refreshed state is applied unless a Start/Stop/Restart is in flight and the
    /// polled state is not itself `.transitioning` (it would cancel the operation's UI state).
    public static func shouldApplyPolled(operationInFlight: Bool, colima: ColimaRunningState) -> Bool {
        guard operationInFlight else { return true }
        if case .transitioning = colima { return true }
        return false
    }
}
