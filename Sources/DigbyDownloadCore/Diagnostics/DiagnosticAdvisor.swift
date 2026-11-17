import Foundation

/// Optional AI troubleshooting — designed for, not built (see ROADMAP). An advisor may only ever receive a
/// `DiagnosticReport` (already redacted: no links, cookies, tokens or user name) and may only return advice
/// in plain English. It can't run code, change settings or touch the engines; any engine change it suggests
/// still goes through the normal verified install (signatures, checksums, test run, rollback).
public protocol DiagnosticAdvisor: Sendable {
    /// A short name shown to the person ("Off" unless they choose one).
    var name: String { get }
    func advise(on report: String) async throws -> String
}

/// The default: no advisor; Digby works fully without one.
public struct NoAdvisor: DiagnosticAdvisor {
    public init() {}
    public var name: String { "Off" }
    public func advise(on report: String) async throws -> String { "" }
}
