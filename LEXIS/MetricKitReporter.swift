import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

// MARK: - MetricKit crash & performance reporting
//
// Apple's on-device MetricKit gives us daily performance metrics plus
// crash/hang diagnostics with ZERO third-party SDK and no PII — a
// privacy-clean alternative to Crashlytics/Sentry. Crashes and hangs are
// summarised into the analytics stream so post-launch stability is visible
// without shipping anyone else's code. Register once at launch.
//
// Payloads arrive at most once per day (and on next launch after a crash),
// so this is for trend visibility, not real-time alerting.

#if canImport(MetricKit)
final class MetricKitReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitReporter()

    func start() {
        MXMetricManager.shared.add(self)
    }

    // Daily rolled-up performance metrics arrive here too. We don't unpack
    // the histograms (their generic Obj-C unit types are awkward to read at
    // runtime, and the full payload is already in Xcode Organizer); we just
    // note that a payload landed, so "app is being used and reporting" is
    // itself a visible signal.
    func didReceive(_ payloads: [MXMetricPayload]) {
        guard !payloads.isEmpty else { return }
        Task { @MainActor in
            Analytics.shared.track(.init("metrickit_perf", ["payloads": "\(payloads.count)"]))
        }
    }

    // Crash & hang diagnostics (iOS 14+). Summarised as counts — no stack
    // traces are exfiltrated, keeping this PII-free.
    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let cpuExceptions = payload.cpuExceptionDiagnostics?.count ?? 0
            guard crashes + hangs + cpuExceptions > 0 else { continue }
            Task { @MainActor in
                Analytics.shared.track(.init("metrickit_diagnostic", [
                    "crashes": "\(crashes)", "hangs": "\(hangs)", "cpu": "\(cpuExceptions)"
                ]))
            }
        }
    }
}
#else
// Non-Apple platforms: a no-op so call sites don't need to be conditional.
final class MetricKitReporter {
    static let shared = MetricKitReporter()
    func start() {}
}
#endif
