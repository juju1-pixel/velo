import SwiftUI

/// Version labels follow the installed bundle, including future TestFlight builds.
enum AppInformation {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var versionDescription: String {
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return "版本 \(version) (\(build))"
        }
        return "版本 \(version)"
    }
}

struct AboutAppView: View {
    @State private var showFeedback = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                appIdentity
                Button { showFeedback = true } label: {
                    Label("留言", systemImage: "square.and.pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity).frame(minHeight: 48)
                        .foregroundStyle(VeloTheme.onAccent)
                        .background(VeloTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityIdentifier("feedbackButton")
                VStack(alignment: .leading, spacing: 20) {
                    Text("专注此刻的速度").font(.headline)
                    detail("离线 GPS 测速", symbol: "satellite.fill",
                           text: "通过 iPhone 定位测量当前速度。测速功能无需 Wi-Fi 或移动数据；网页内容需要联网。")
                    Divider().overlay(VeloTheme.border)
                    detail("按你的习惯显示", symbol: "gauge.with.dots.needle.33percent",
                           text: "支持 km/h 与 mph，并显示本次行程的时长、距离、平均速度和最高速度。")
                }.frame(maxWidth: .infinity, alignment: .leading).veloPanel()
                VStack(alignment: .leading, spacing: 20) {
                    Label("数据与隐私", systemImage: "lock.shield")
                        .font(.headline).foregroundStyle(VeloTheme.accent)
                    detail("位置留在本机", symbol: "iphone",
                           text: "VELO 不向服务器上传位置或行程数据，也不加入广告跟踪。")
                    detail("本机保存", symbol: "slider.horizontal.3",
                           text: "显示单位和速度提醒设置保存在本机。本次行程仅保留在内存中，退出应用后不保留。")
                }.frame(maxWidth: .infinity, alignment: .leading).veloPanel()
                VStack(alignment: .leading, spacing: 20) {
                    Text("使用说明").font(.headline)
                    detail("在开阔处使用", symbol: "location.circle",
                           text: "请允许使用期间访问位置，并开启精确位置。室内、隧道或高楼遮挡可能影响定位；尚无有效读数时，仪表显示 0 和当前定位状态，此时的 0 不代表实际静止。")
                    detail("专注当前行程", symbol: "pause.circle",
                           text: "测速时保持屏幕常亮。切到后台或锁屏时自动暂停，返回后可继续。暂停和信号中断期间不累计距离。")
                    detail("了解行程统计", symbol: "waveform.path",
                           text: "距离由有效速度读数估算，平均速度只统计有效读数之间的时间。速度提醒由你自行设定，不代表道路限速。")
                    detail("演示数据有明确标记", symbol: "play.circle",
                           text: "演示模式用于体验界面，显示的是模拟速度。实际测速前，请在设置中关闭演示模式。")
                }.frame(maxWidth: .infinity, alignment: .leading).veloPanel()
                Text("保持专注，安全出行。")
                    .font(.footnote).foregroundStyle(VeloTheme.secondary)
                    .padding(.top, 4).padding(.bottom, 12)
            }
            .padding(.horizontal, 20).padding(.vertical, 20)
        }
        .foregroundStyle(VeloTheme.foreground)
        .background(VeloTheme.background)
        .navigationTitle("关于 VELO")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("aboutAppPage")
        .sheet(isPresented: $showFeedback) { FeedbackView() }
    }

    private var appIdentity: some View {
        VStack(spacing: 12) {
            Image("BrandIcon")
                .resizable().scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(VeloTheme.accent.opacity(0.2), lineWidth: 1))
                .accessibilityHidden(true)
            Text("velo.").font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-2)
            Text("时速 · 离线 GPS 测速")
                .font(.subheadline).foregroundStyle(VeloTheme.secondary)
            Text(AppInformation.versionDescription)
                .font(.footnote.monospacedDigit()).foregroundStyle(VeloTheme.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(VeloTheme.surface, in: Capsule())
                .accessibilityIdentifier("aboutAppVersion")
        }
        .frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 12)
    }

    private func detail(_ title: String, symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.body)
                .foregroundStyle(VeloTheme.accent).frame(width: 22).padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(VeloTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }
}
