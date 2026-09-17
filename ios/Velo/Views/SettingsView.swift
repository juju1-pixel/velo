import SwiftUI

struct SettingsView: View {
    @ObservedObject var speedometer: Speedometer
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedUnit") private var selectedUnit = SpeedUnit.kilometersPerHour.rawValue
    @AppStorage("speedReminderEnabled") private var reminderEnabled = true
    @AppStorage("speedReminderKph") private var reminderKph = 80.0
    private var unit: SpeedUnit { SpeedUnit(rawValue: selectedUnit) ?? .kilometersPerHour }

    var body: some View {
        NavigationStack {
            Form {
                Section("显示单位") {
                    Picker("速度单位", selection: $selectedUnit) {
                        ForEach(SpeedUnit.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("settingsUnitPicker")
                }
                Section {
                    Toggle("速度提醒", isOn: $reminderEnabled)
                    if reminderEnabled {
                        Picker("提醒速度", selection: $reminderKph) {
                            ForEach([30.0, 50, 60, 80, 100, 120], id: \.self) { value in
                                Text("\(Int(unit.speed(from: value / 3.6).rounded())) \(unit.rawValue)").tag(value)
                            }
                        }
                    }
                } header: { Text("速度提醒") } footer: {
                    Text("超过你设定的速度时，仪表盘会高亮。此设置不代表道路限速。")
                }
                Section {
                    Toggle("演示模式", isOn: Binding(get: { speedometer.isDemo }, set: { speedometer.setDemo($0) }))
                        .accessibilityIdentifier("demoToggle")
                } footer: {
                    Text("开启后使用明确标注的模拟数据，方便在模拟器中体验。切换模式会重置本次行程。")
                }
                Section("定位与离线使用") {
                    Label("GPS 测速无需网络连接", systemImage: "wifi.slash")
                    Label("位置数据仅在本机处理", systemImage: "lock.shield")
                    Button("打开系统定位设置") { openAppSettings() }
                    Text("需要允许“使用 App 期间”访问位置，并开启“精确位置”。室内、隧道和高楼之间可能没有有效速度读数。")
                        .font(.footnote).foregroundStyle(VeloTheme.secondary)
                }
                Section("关于") {
                    NavigationLink {
                        AboutAppView()
                    } label: {
                        HStack {
                            Label("关于 VELO", systemImage: "info.circle")
                            Spacer()
                            Text(AppInformation.version)
                                .font(.subheadline).foregroundStyle(VeloTheme.secondary)
                        }
                    }.accessibilityIdentifier("aboutAppLink")
                }
            }
            .scrollContentBackground(.hidden).background(VeloTheme.background)
            .tint(VeloTheme.accent)
            .navigationTitle("测速设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.accessibilityIdentifier("settingsDone") } }
        }.preferredColorScheme(.light)
    }
}
