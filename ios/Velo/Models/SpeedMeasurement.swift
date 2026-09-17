import Foundation
import CoreLocation

enum SpeedUnit: String, CaseIterable, Identifiable {
    case kilometersPerHour = "km/h"
    case milesPerHour = "mph"

    var id: String { rawValue }
    var speedMultiplier: Double {
        switch self {
        case .kilometersPerHour: return 3.6
        case .milesPerHour: return 2.2369362921
        }
    }
    var distanceUnit: String {
        switch self {
        case .kilometersPerHour: return "km"
        case .milesPerHour: return "mi"
        }
    }
    func speed(from metersPerSecond: Double) -> Double { metersPerSecond * speedMultiplier }
    func distance(from meters: Double) -> Double { meters * speedMultiplier / 3600 }
}

struct SpeedSample {
    let metersPerSecond: Double
    let timestamp: Date

    static let maximumAge: TimeInterval = 5

    /// Invalid or uncertain readings remain unavailable; they must never become zero.
    init?(location: CLLocation, now: Date) {
        let age = now.timeIntervalSince(location.timestamp)
        guard age.isFinite, age >= -1, age <= Self.maximumAge,
              location.speed.isFinite, location.speed >= 0,
              location.horizontalAccuracy.isFinite,
              (0...50).contains(location.horizontalAccuracy),
              location.speedAccuracy.isFinite,
              (0...5).contains(location.speedAccuracy) else { return nil }
        metersPerSecond = location.speed
        timestamp = location.timestamp
    }

    init(metersPerSecond: Double, timestamp: Date) {
        self.metersPerSecond = metersPerSecond
        self.timestamp = timestamp
    }
}

struct TripRecorder {
    private(set) var distanceMeters: Double = 0
    private(set) var measuredSeconds: TimeInterval = 0
    private(set) var maximumSpeed: Double?
    private(set) var lastSample: SpeedSample?

    var averageSpeed: Double? {
        measuredSeconds > 0 ? distanceMeters / measuredSeconds : nil
    }

    @discardableResult
    mutating func ingest(_ sample: SpeedSample) -> Bool {
        guard sample.metersPerSecond.isFinite, sample.metersPerSecond >= 0,
              sample.timestamp.timeIntervalSince1970.isFinite else { return false }
        if let last = lastSample {
            let delta = sample.timestamp.timeIntervalSince(last.timestamp)
            guard delta > 0 else { return false }
            if delta <= SpeedSample.maximumAge {
                distanceMeters += (last.metersPerSecond + sample.metersPerSecond) / 2 * delta
                measuredSeconds += delta
            }
        }
        maximumSpeed = max(maximumSpeed ?? 0, sample.metersPerSecond)
        lastSample = sample
        return true
    }

    mutating func breakContinuity() { lastSample = nil }
}

struct SpeedHistoryPoint: Identifiable {
    let timestamp: Date
    let metersPerSecond: Double?
    let segment: Int
    var id: Date { timestamp }
}

enum DurationFormatter {
    static func string(seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00:00" }
        let total = Int(max(0, seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}
