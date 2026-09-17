import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
final class Speedometer: NSObject, ObservableObject, @MainActor CLLocationManagerDelegate {
    @Published private(set) var isRunning = false
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var isDemo = false
    @Published private(set) var speed: Double?
    @Published private(set) var trip = TripRecorder()
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var history: [SpeedHistoryPoint] = []
    @Published private(set) var horizontalAccuracy: Double?
    @Published private(set) var speedAccuracy: Double?
    @Published private(set) var status = "准备就绪"
    @Published private(set) var message: String?
    @Published private(set) var needsSettings = false

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var runStartedAt: Date?
    private var runStartedUptime: TimeInterval?
    private var accumulatedElapsed: TimeInterval = 0
    private var lastValidSample: SpeedSample?
    private var lastHistoryTime: Date?
    private var historySegment = 0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        // Foreground-only MVP. No Always authorization or background location entitlement.
        locationManager.allowsBackgroundLocationUpdates = false
    }

    func start() {
        guard !isRunning, !isRequestingPermission else { return }
        message = nil
        needsSettings = false
        if isDemo { beginSession(); return }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            isRequestingPermission = true
            status = "等待定位授权"
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginAuthorizedSession()
        case .denied, .restricted:
            showPermissionFailure()
        @unknown default:
            status = "定位暂不可用"
            message = "暂时无法确定定位权限，请稍后重试。"
        }
    }

    func pause() {
        updateElapsed()
        accumulatedElapsed = elapsed
        isRunning = false
        isRequestingPermission = false
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        runStartedUptime = nil
        runStartedAt = nil
        clearReading()
        status = "已暂停"
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func reset() {
        pause()
        trip = TripRecorder()
        elapsed = 0
        accumulatedElapsed = 0
        history = []
        lastHistoryTime = nil
        historySegment = 0
        horizontalAccuracy = nil
        speedAccuracy = nil
        status = "准备就绪"
        message = nil
    }

    func setDemo(_ enabled: Bool) {
        guard enabled != isDemo else { return }
        reset()
        isDemo = enabled
        needsSettings = false
        status = enabled ? "演示模式" : "准备就绪"
    }

    func handleBackground() {
        guard isRunning || isRequestingPermission else { return }
        pause()
        message = "应用已进入后台，测速已暂停。返回后可继续本次行程。"
    }

    private func beginAuthorizedSession() {
        isRequestingPermission = false
        guard locationManager.accuracyAuthorization == .fullAccuracy else {
            status = "需要精确位置"
            message = "请在系统设置中为 VELO 开启“精确位置”，以获取可靠的速度。"
            needsSettings = true
            return
        }
        beginSession()
    }

    private func beginSession() {
        guard !isRunning else { return }
        trip.breakContinuity()
        lastValidSample = nil
        historySegment += 1
        runStartedAt = Date()
        runStartedUptime = ProcessInfo.processInfo.systemUptime
        isRunning = true
        status = isDemo ? "模拟行驶中" : "正在寻找 GPS"
        UIApplication.shared.isIdleTimerDisabled = true
        if isDemo { updateDemo(at: Date()) }
        else { locationManager.startUpdatingLocation() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard isRunning else { return }
        let now = Date()
        updateElapsed()
        if isDemo { updateDemo(at: now) }
        else if let last = lastValidSample, now.timeIntervalSince(last.timestamp) > SpeedSample.maximumAge {
            clearReading()
            status = "GPS 信号中断"
            message = "速度读数已过期，正在等待新的定位信号。"
        } else if lastValidSample == nil, message == nil,
                  let started = runStartedAt, now.timeIntervalSince(started) > 12 {
            message = "首次定位可能需要一些时间，请在开阔的室外使用。"
        }
        if lastHistoryTime == nil || now.timeIntervalSince(lastHistoryTime!) >= 1 {
            history.append(SpeedHistoryPoint(timestamp: now, metersPerSecond: speed, segment: historySegment))
            lastHistoryTime = now
        }
        history.removeAll { now.timeIntervalSince($0.timestamp) > 60 }
    }

    private func updateElapsed() {
        if let started = runStartedUptime {
            elapsed = accumulatedElapsed + max(0, ProcessInfo.processInfo.systemUptime - started)
        }
    }

    private func updateDemo(at date: Date) {
        let kph = 64.8 + 12 * sin(elapsed / 8) + 3 * sin(elapsed / 2.5)
        accept(SpeedSample(metersPerSecond: kph / 3.6, timestamp: date))
    }

    private func accept(_ sample: SpeedSample) {
        guard trip.ingest(sample) else { return }
        lastValidSample = sample
        speed = sample.metersPerSecond
        status = isDemo ? "模拟行驶中" : sample.metersPerSecond < 0.3 ? "静止中" : "实时测速中"
        message = nil
    }

    private func clearReading() {
        speed = nil
        lastValidSample = nil
        speedAccuracy = nil
        horizontalAccuracy = nil
        trip.breakContinuity()
        historySegment += 1
    }

    private func showPermissionFailure() {
        pause()
        status = "定位未授权"
        message = "请在系统设置中允许 VELO 在使用期间访问位置，并开启精确位置。"
        needsSettings = true
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !isDemo else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if isRequestingPermission { beginAuthorizedSession() }
            else if isRunning && manager.accuracyAuthorization != .fullAccuracy {
                pause()
                status = "需要精确位置"
                needsSettings = true
                message = "精确位置已关闭，测速已暂停。请在设置中重新开启。"
            }
        case .denied, .restricted:
            showPermissionFailure()
        case .notDetermined: break
        @unknown default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning, !isDemo, let started = runStartedAt else { return }
        let now = Date()
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard location.timestamp >= started else { continue }
            // Late and duplicate callbacks cannot replace a newer, valid fix.
            if let last = lastValidSample, location.timestamp <= last.timestamp { continue }
            guard let sample = SpeedSample(location: location, now: now) else {
                clearReading()
                status = "等待可靠读数"
                message = "定位信号或速度精度不足。请到开阔处，应用会自动继续尝试。"
                continue
            }
            horizontalAccuracy = location.horizontalAccuracy
            speedAccuracy = location.speedAccuracy
            accept(sample)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isRunning, !isDemo else { return }
        if let locationError = error as? CLError, locationError.code == .denied {
            showPermissionFailure()
        } else {
            clearReading()
            status = "定位暂不可用"
            message = "暂时无法获得定位，正在继续尝试。请确认系统定位已开启。"
        }
    }
}
