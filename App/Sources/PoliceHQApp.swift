import SwiftUI
import PoliceHQCore

@main
struct PoliceHQApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { model.bootstrap() }
                .overlay {
                    // App-switcher privacy: cover content whenever the app is not active.
                    if scenePhase != .active {
                        PrivacyShieldView()
                    }
                }
        }
    }
}

struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Police HQ")
                    .font(.title2.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Police HQ is hidden while in the background")
    }
}
