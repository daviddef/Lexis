import SwiftUI

// MARK: - Launch Screen
// This is the TRUE system launch screen — shown for a brief instant during
// cold app launch, before SwiftUI's full view hierarchy (and any @State,
// @StateObject, or game logic) is ready. It must stay static and near-
// instant: no animations that depend on data, no network/UserDefaults
// reads, nothing that could delay first paint. Registered via
// UILaunchScreen in Info.plist (see README/CLAUDE.md for the exact Xcode
// setup step), NOT shown as a regular SwiftUI view in the app's navigation
// flow — MenuView is the real "first interactive screen" with live high
// scores and difficulty selection.
struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Color.lexisBg.ignoresSafeArea()
            
            VStack(spacing: 12) {
                // A static rendition of the hero tile from the app icon, so
                // the launch screen and icon feel like the same object
                // continuing into the app. Carries the same bevel depth as
                // the in-game tiles (bright top-left / dark bottom-right
                // strokes + inner sheen + drop shadow) so it reads as the
                // same chunky, tactile block the player steers, not a flatter
                // one-off.
                ZStack {
                    // Drop shadow
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 100, height: 100)
                        .offset(y: 4)
                        .blur(radius: 8)

                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.27, green: 0.92, blue: 0.72),
                                    Color(red: 0.11, green: 0.49, blue: 0.41)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 100, height: 100)

                    // Bevel: dark bottom-right, bright top-left
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Color.black.opacity(0.3), lineWidth: 3)
                        .offset(x: 1, y: 1)
                        .frame(width: 100, height: 100)
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 3)
                        .offset(x: -1, y: -1)
                        .frame(width: 100, height: 100)
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Color.lexisAccent, lineWidth: 3)
                        .frame(width: 100, height: 100)

                    // Inner top sheen
                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(width: 100, height: 100)
                        .padding(4)

                    Text("L")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundColor(Color.lexisBg)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                }
                .shadow(color: Color.lexisAccent.opacity(0.35), radius: 20)
                
                Text("LEXIS")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.lexisAccent)
                    .tracking(8)
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}
