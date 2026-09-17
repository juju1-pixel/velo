import SwiftUI

@main
struct VeloApp: App {
    @StateObject private var speedometer = Speedometer()
    @StateObject private var webRouter = WebDestinationRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Normalize removed unit values before either AppStorage-backed picker appears.
        let defaults = UserDefaults.standard
        if let savedUnit = defaults.string(forKey: "speedUnit"),
           SpeedUnit(rawValue: savedUnit) == nil {
            defaults.set(SpeedUnit.kilometersPerHour.rawValue, forKey: "speedUnit")
        }
    }

    var body: some Scene {
        WindowGroup {
            LaunchContainerView(speedometer: speedometer)
                .environmentObject(webRouter)
                .preferredColorScheme(.light)
                .tint(VeloTheme.accent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { speedometer.handleBackground() }
                }
        }
    }
}
