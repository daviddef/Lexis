import SwiftUI

// MARK: - Splash / branded intro
//
// A brief, classy launch moment shown once per cold launch: the LEXIS
// letters drop in as bevelled tiles (the same tactile look as the app icon
// and the in-game tiles), the wordmark glows, the tagline fades in, then the
// whole thing dissolves to the menu. Tap anywhere to skip; honors Reduce
// Motion (holds a static frame instead of animating).
struct SplashView: View {
    let onFinish: () -> Void

    @ObservedObject private var settings = GameSettings.shared
    private let letters = ["L", "E", "X", "I", "S"]

    @State private var dropped = false
    @State private var glow = false
    @State private var taglineIn = false
    @State private var finished = false

    private var reduceMotion: Bool { settings.motionReduced }

    var body: some View {
        ZStack {
            // Same ground as the menu, so the dissolve into it is seamless.
            Color.lexisBg.ignoresSafeArea()
            RadialGradient(
                colors: [Color.lexisAccent.opacity(0.12), .clear],
                center: .center, startRadius: 4, endRadius: 340
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 20) {
                HStack(spacing: 9) {
                    ForEach(0..<letters.count, id: \.self) { i in
                        SplashTile(letter: letters[i])
                            .offset(y: dropped ? 0 : -240)
                            .opacity(dropped ? 1 : 0)
                            .animation(
                                reduceMotion ? nil
                                : .spring(response: 0.5, dampingFraction: 0.6).delay(Double(i) * 0.08),
                                value: dropped
                            )
                    }
                }
                .shadow(color: Color.lexisAccent.opacity(glow ? 0.7 : 0.25), radius: glow ? 28 : 10)

                Text("ONE LETTER · ONE WORD · ONE LIFE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.lexisMid)
                    .tracking(3)
                    .opacity(taglineIn ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }        // tap to skip
        .onAppear(perform: run)
    }

    private func run() {
        if reduceMotion {
            dropped = true; glow = true; taglineIn = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { finish() }
            return
        }
        Haptics.light()
        dropped = true
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.6)) { taglineIn = true }
        // Hold on the finished wordmark, then dissolve.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

/// A bevelled LEXIS tile in the app-icon style (bright mint face, dark letter,
/// top-left highlight / bottom-right shade), so the splash reads as the same
/// object as the icon the player just tapped.
private struct SplashTile: View {
    let letter: String
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.42, green: 0.95, blue: 0.76),
                            Color(red: 0.20, green: 0.68, blue: 0.54)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 2)
                .offset(x: -0.5, y: -0.5)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.28), lineWidth: 2)
                .offset(x: 0.5, y: 0.5)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center))
                .padding(3)
            Text(letter)
                .font(.system(size: size * 0.55, weight: .black, design: .rounded))
                .foregroundColor(.lexisBg)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: 7, y: 4)
    }
}
