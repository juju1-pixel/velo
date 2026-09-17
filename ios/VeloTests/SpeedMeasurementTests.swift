import XCTest
import CoreLocation
@testable import Velo

final class SpeedMeasurementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func location(speed: Double = 10, horizontal: Double = 5, speedAccuracy: Double = 1, age: Double = 0) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 22.3, longitude: 114.2), altitude: 0,
                   horizontalAccuracy: horizontal, verticalAccuracy: 10,
                   course: 0, courseAccuracy: 1, speed: speed, speedAccuracy: speedAccuracy,
                   timestamp: now.addingTimeInterval(-age))
    }

    func testValidStationaryReadingIsZeroWhileMissingSpeedIsUnavailable() {
        XCTAssertEqual(SpeedSample(location: location(speed: 0), now: now)?.metersPerSecond, 0)
        XCTAssertNil(SpeedSample(location: location(speed: -1), now: now))
        XCTAssertNil(SpeedSample(location: location(speed: .nan), now: now))
    }

    func testStaleFutureAndUncertainFixesAreRejected() {
        XCTAssertNil(SpeedSample(location: location(age: 6), now: now))
        XCTAssertNil(SpeedSample(location: location(age: -2), now: now))
        XCTAssertNil(SpeedSample(location: location(horizontal: 51), now: now))
        XCTAssertNil(SpeedSample(location: location(horizontal: -1), now: now))
        XCTAssertNil(SpeedSample(location: location(speedAccuracy: -1), now: now))
        XCTAssertNil(SpeedSample(location: location(speedAccuracy: 6), now: now))
    }

    func testSixtySecondsAtTenMetersPerSecondMeasuresSixHundredMeters() {
        var trip = TripRecorder()
        for second in 0...60 { trip.ingest(SpeedSample(metersPerSecond: 10, timestamp: now.addingTimeInterval(Double(second)))) }
        XCTAssertEqual(trip.distanceMeters, 600, accuracy: 0.0001)
        XCTAssertEqual(trip.measuredSeconds, 60)
        XCTAssertEqual(trip.averageSpeed, 10)
        XCTAssertEqual(trip.maximumSpeed, 10)
    }

    func testAccelerationUsesAverageOfConsecutiveSpeeds() {
        var trip = TripRecorder()
        trip.ingest(SpeedSample(metersPerSecond: 0, timestamp: now))
        trip.ingest(SpeedSample(metersPerSecond: 20, timestamp: now.addingTimeInterval(2)))
        XCTAssertEqual(trip.distanceMeters, 20)
        XCTAssertEqual(trip.averageSpeed, 10)
    }

    func testGPSGapsAndPausesDoNotInventDistance() {
        var trip = TripRecorder()
        trip.ingest(SpeedSample(metersPerSecond: 20, timestamp: now))
        trip.ingest(SpeedSample(metersPerSecond: 20, timestamp: now.addingTimeInterval(10)))
        XCTAssertEqual(trip.distanceMeters, 0)
        XCTAssertNil(trip.averageSpeed)
        trip.breakContinuity()
        trip.ingest(SpeedSample(metersPerSecond: 20, timestamp: now.addingTimeInterval(11)))
        XCTAssertEqual(trip.distanceMeters, 0)
    }

    func testDuplicateOutOfOrderAndInvalidSamplesDoNotChangeTrip() {
        var trip = TripRecorder()
        trip.ingest(SpeedSample(metersPerSecond: 10, timestamp: now))
        XCTAssertFalse(trip.ingest(SpeedSample(metersPerSecond: 100, timestamp: now)))
        XCTAssertFalse(trip.ingest(SpeedSample(metersPerSecond: 100, timestamp: now.addingTimeInterval(-1))))
        XCTAssertFalse(trip.ingest(SpeedSample(metersPerSecond: -.infinity, timestamp: now.addingTimeInterval(1))))
        XCTAssertEqual(trip.maximumSpeed, 10)
        XCTAssertEqual(trip.distanceMeters, 0)
    }

    func testSpeedAndDistanceUnitsAreConsistent() {
        XCTAssertEqual(SpeedUnit.kilometersPerHour.speed(from: 10), 36, accuracy: 0.001)
        XCTAssertEqual(SpeedUnit.milesPerHour.speed(from: 10), 22.36936, accuracy: 0.0001)
        XCTAssertEqual(SpeedUnit.milesPerHour.distance(from: 1609.344), 1, accuracy: 0.0001)
    }

    func testHighSpeedGPSReadingsAndTripStatisticsAreNotClipped() throws {
        let first = try XCTUnwrap(SpeedSample(location: location(speed: 500 / 3.6), now: now))
        let secondTime = now.addingTimeInterval(1)
        let second = try XCTUnwrap(SpeedSample(location: location(speed: 600 / 3.6, age: -1), now: secondTime))
        XCTAssertEqual(SpeedUnit.kilometersPerHour.speed(from: first.metersPerSecond), 500, accuracy: 0.001)
        XCTAssertEqual(SpeedUnit.milesPerHour.speed(from: first.metersPerSecond), 310.685596, accuracy: 0.001)
        var trip = TripRecorder()
        XCTAssertTrue(trip.ingest(first))
        XCTAssertTrue(trip.ingest(second))
        XCTAssertEqual(try XCTUnwrap(trip.maximumSpeed) * 3.6, 600, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(trip.averageSpeed) * 3.6, 550, accuracy: 0.001)
        XCTAssertEqual(trip.distanceMeters, 550 / 3.6, accuracy: 0.001)
    }

    func testDurationHandlesHourBoundariesAndLongSessions() {
        XCTAssertEqual(DurationFormatter.string(seconds: 59.9), "00:00:59")
        XCTAssertEqual(DurationFormatter.string(seconds: 3600), "01:00:00")
        XCTAssertEqual(DurationFormatter.string(seconds: 90000), "25:00:00")
    }
}
