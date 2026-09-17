import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var speedometer: Speedometer
    @AppStorage("speedUnit") private var selectedUnit = SpeedUnit.kilometersPerHour.rawValue
    @AppStorage("speedReminderEnabled") private var reminderEnabled = true
    @AppStorage("speedReminderKph") private var reminderKph = 80.0
    @State private var showSettings = false
    @State private var showReset = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var unit: SpeedUnit { SpeedUnit(rawValue: selectedUnit) ?? .kilometersPerHour }
    private var overLimit: Bool { reminderEnabled && (speedometer.speed ?? 0) * 3.6 > reminderKph }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("实时测速").font(.system(size: 28, weight: .semibold))
                        Text("专注此刻的速度").font(.subheadline).foregroundStyle(VeloTheme.secondary)
                    }
                    Spacer()
                    Label("离线可用", systemImage: "wifi.slash")
                        .font(.caption).foregroundStyle(VeloTheme.accent)
                        .padding(10).background(VeloTheme.accent.opacity(0.07), in: Capsule())
                }
                .padding(.vertical, 5)
                meterPanel
                if let message = speedometer.message { messagePanel(message) }
                tripPanel
                trendPanel
                offlinePanel
                Text("位置数据仅在本机处理 · VELO 1.0")
                    .font(.caption).foregroundStyle(VeloTheme.secondary).padding(.vertical, 10)
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)
        }
        .foregroundStyle(VeloTheme.foreground)
        .background(VeloTheme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .sheet(isPresented: $showSettings) { SettingsView(speedometer: speedometer) }
        .confirmationDialog("重置本次行程？", isPresented: $showReset, titleVisibility: .visible) {
            Button("重置行程", role: .destructive) { speedometer.reset() }
            Button("取消", role: .cancel) {}
        } message: { Text("本次时长、距离和速度统计将被清空。") }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("BrandIcon").resizable().scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            Text("velo.").font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-2)
            Rectangle().fill(VeloTheme.border).frame(width: 1, height: 20).padding(.horizontal, 6)
            Text("时速").font(.subheadline).foregroundStyle(VeloTheme.secondary)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
            }.tint(VeloTheme.secondary).accessibilityLabel("测速设置").accessibilityIdentifier("settingsButton")
        }
    }

    private var meterPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(speedometer.isRunning ? VeloTheme.accent : VeloTheme.secondary).frame(width: 6, height: 6)
                Text(speedometer.isDemo ? "演示模式 · 模拟数据" : speedometer.status)
                    .font(.caption).foregroundStyle(VeloTheme.secondary)
                Spacer(minLength: 4)
                Menu {
                    ForEach(SpeedUnit.allCases) { option in
                        Button { selectedUnit = option.rawValue } label: {
                            if option == unit { Label(option.rawValue, systemImage: "checkmark") }
                            else { Text(option.rawValue) }
                        }
                    }
                } label: {
                    HStack(spacing: 5) { Text(unit.rawValue); Image(systemName: "chevron.down").font(.caption2) }
                        .font(.subheadline.monospaced()).padding(.horizontal, 11).frame(minHeight: 44)
                        .foregroundStyle(VeloTheme.accent)
                        .background(VeloTheme.background, in: RoundedRectangle(cornerRadius: 10))
                }.tint(VeloTheme.accent).accessibilityLabel("速度单位").accessibilityIdentifier("unitPicker")
            }
            SpeedDial(speed: speedometer.speed, unit: unit, status: speedometer.status, isOverLimit: overLimit)
                .frame(maxWidth: 340)
                .frame(maxWidth: .infinity)
            Divider().overlay(VeloTheme.border)
            HStack {
                Label(speedometer.isDemo ? "模拟信号" : accuracyLabel, systemImage: "satellite.fill")
                    .font(.caption).foregroundStyle(VeloTheme.secondary)
                Spacer()
                if reminderEnabled {
                    Button { showSettings = true } label: {
                        Label("提醒 \(Int(unit.speed(from: reminderKph / 3.6))) \(unit.rawValue)", systemImage: "bell")
                            .font(.caption).foregroundStyle(VeloTheme.secondary).frame(minHeight: 38)
                    }.accessibilityLabel("设置速度提醒")
                }
            }
        }.padding(.vertical, 4)
    }

    private var accuracyLabel: String {
        guard let accuracy = speedometer.horizontalAccuracy else { return "等待定位" }
        return "定位 ±\(Int(accuracy.rounded())) m"
    }

    private func messagePanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "info.circle")
                .font(.subheadline).foregroundStyle(VeloTheme.secondary).fixedSize(horizontal: false, vertical: true)
            if speedometer.needsSettings {
                Button("打开系统设置") { openAppSettings() }.tint(VeloTheme.accent)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).veloPanel()
    }

    private var tripPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("本次行程").font(.headline)
                Spacer()
                Text(speedometer.isDemo ? "模拟数据" : "GPS 数据").font(.caption).foregroundStyle(VeloTheme.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 23) {
                metric("行驶时长", symbol: "clock", value: DurationFormatter.string(seconds: speedometer.elapsed), suffix: nil, identifier: "tripDuration")
                metric("行驶距离", symbol: "point.topleft.down.to.point.bottomright.curvepath", value: String(format: "%.2f", unit.distance(from: speedometer.trip.distanceMeters)), suffix: unit.distanceUnit, identifier: "tripDistance")
                metric("平均速度", symbol: "waveform.path", value: formatted(speedometer.trip.averageSpeed), suffix: unit.rawValue, identifier: "averageSpeed")
                metric("最高速度", symbol: "arrow.up.right", value: formatted(speedometer.trip.maximumSpeed), suffix: unit.rawValue, identifier: "maximumSpeed")
            }
        }.veloPanel()
    }

    private func formatted(_ speed: Double?) -> String {
        speed.map { String(format: "%.1f", unit.speed(from: $0)) } ?? "—"
    }

    private func metric(_ title: String, symbol: String, value: String, suffix: String?, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(VeloTheme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 26, weight: .regular, design: .rounded)).monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                    .accessibilityIdentifier(identifier)
                if let suffix { Text(suffix).font(.caption).foregroundStyle(VeloTheme.secondary) }
            }
        }.accessibilityElement(children: .combine)
    }

    private var trendPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("速度趋势").font(.headline)
                Spacer()
                Text("最近 60 秒 · \(unit.rawValue)").font(.caption).foregroundStyle(VeloTheme.secondary)
            }
            let end = speedometer.history.last?.timestamp ?? Date()
            let maxValue = max(100 * unit.speedMultiplier / 3.6, (speedometer.history.compactMap(\.metersPerSecond).max() ?? 0) * unit.speedMultiplier * 1.15)
            Chart(speedometer.history) { point in
                if let speed = point.metersPerSecond {
                    LineMark(x: .value("时间", point.timestamp), y: .value("速度", unit.speed(from: speed)), series: .value("连续读数", point.segment))
                        .foregroundStyle(VeloTheme.accent).lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartXScale(domain: end.addingTimeInterval(-60)...end)
            .chartYScale(domain: 0...maxValue)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .second, count: 15)) { _ in
                    AxisGridLine().foregroundStyle(VeloTheme.track)
                    AxisValueLabel(format: .dateTime.minute().second()).foregroundStyle(VeloTheme.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(dash: [3, 4])).foregroundStyle(VeloTheme.border)
                    AxisValueLabel().foregroundStyle(VeloTheme.secondary)
                }
            }
            .frame(height: 120)
            .overlay {
                if !speedometer.history.contains(where: { $0.metersPerSecond != nil }) {
                    Text("开始测速后，记录每一次速度变化")
                        .font(.caption).foregroundStyle(VeloTheme.secondary).multilineTextAlignment(.center)
                }
            }
            .accessibilityLabel("最近一分钟的速度曲线")
        }.veloPanel()
    }

    private var offlinePanel: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "wifi.slash").font(.title2).foregroundStyle(VeloTheme.accent)
            VStack(alignment: .leading, spacing: 8) {
                Text("没有网络，也能测速。").font(.headline)
                Text("直接接收 GPS 卫星信号，无需 Wi-Fi 或移动数据。请在开阔的室外使用。")
                    .font(.subheadline).foregroundStyle(VeloTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).veloPanel()
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { showReset = true } label: {
                Image(systemName: "arrow.counterclockwise").font(.title3).frame(width: 52, height: 54)
                    .background(VeloTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            }.tint(VeloTheme.secondary).accessibilityLabel("重置行程").accessibilityIdentifier("resetButton")
            Button {
                if speedometer.isRunning { speedometer.pause() } else { speedometer.start() }
            } label: {
                HStack(spacing: 10) {
                    if speedometer.isRequestingPermission { ProgressView().tint(VeloTheme.onAccent) }
                    else { Image(systemName: speedometer.isRunning ? "pause.fill" : "play.fill") }
                    Text(speedometer.isRequestingPermission ? "等待定位授权" : speedometer.isRunning ? "暂停测速" : speedometer.elapsed > 0 ? "继续测速" : "开始测速")
                        .font(.headline)
                }.foregroundStyle(VeloTheme.onAccent)
                    .frame(maxWidth: .infinity).frame(minHeight: 54)
                    .background(VeloTheme.accent, in: RoundedRectangle(cornerRadius: 16))
            }.tint(VeloTheme.onAccent).disabled(speedometer.isRequestingPermission).accessibilityIdentifier("startPauseButton")
        }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            .background(VeloTheme.background.opacity(0.97))
    }
}

@MainActor
func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}
