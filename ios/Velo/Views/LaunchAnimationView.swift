import SwiftUI

/// Keep the first frame identical to LaunchScreen.storyboard, then animate once per launch.
struct LaunchContainerView: View {
    @ObservedObject var speedometer: Speedometer
    @EnvironmentObject private var webRouter: WebDestinationRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsIntro = true

    private var isShowingIntro: Bool { showsIntro && !reduceMotion }

    var body: some View {
        ZStack {
            Group {
                if let url = webRouter.destinationURL {
                    FeedbackWebView(url: url) { await webRouter.refreshDestination() }
                } else {
                    DashboardView(speedometer: speedometer)
                }
            }
            .allowsHitTesting(!isShowingIntro)
            .accessibilityHidden(isShowingIntro)

            if isShowingIntro {
                LaunchAnimationView {
                    withAnimation(.easeOut(duration: 0.16)) { showsIntro = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .task {
            if reduceMotion { showsIntro = false }
        }
        .onChange(of: webRouter.destinationURL) { _, url in
            if url != nil, speedometer.isRunning || speedometer.isRequestingPermission {
                speedometer.pause()
            }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { showsIntro = false }
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning from the background must never replay or resume the intro.
            if phase == .background { showsIntro = false }
        }
    }
}

private struct LaunchAnimationView: View {
    let onFinished: @MainActor () -> Void
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Color.white
            LaunchSpeedArtwork(progress: progress)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 0.64)) { progress = 1 }
            do {
                try await Task.sleep(for: .milliseconds(640))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}

private struct LaunchSpeedArtwork: View, Animatable {
    nonisolated var progress: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private var surge: CGFloat { sin(progress * .pi) }

    var body: some View {
        ZStack {
            ForEach(0..<5) { index in
                SpeedStreak(index: index, progress: progress)
            }
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 144, height: 144)
                .scaleEffect(1 + 0.045 * surge)
                .offset(x: 8 * surge)
        }
        .frame(width: 300, height: 180)
    }
}

private struct SpeedStreak: View {
    let index: Int
    let progress: CGFloat

    private var phase: CGFloat {
        min(1, max(0, (progress - CGFloat(index) * 0.045) / 0.76))
    }

    var body: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [.clear, VeloTheme.accent.opacity(0.2), VeloTheme.accent.opacity(0.65)],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .frame(width: index.isMultiple(of: 2) ? 84 : 116, height: 2)
            .opacity(sin(Double(phase) * .pi))
            .offset(x: 185 - 390 * phase, y: CGFloat(index - 2) * 25)
    }
}
