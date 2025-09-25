import SwiftUI
import UIKit
import RealTimeOddsPackage

struct ContentView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ListViewControllerWrapper()
                .edgesIgnoringSafeArea(.all)
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashView()
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}

private struct SplashView: View {
    private var logo: Image {
        if let uiImage = UIImage(named: "AppIcon") {
            return Image(uiImage: uiImage)
        } else {
            return Image(systemName: "sparkles.rectangle.stack.fill")
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.systemBackground).opacity(0.85)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 6)

                Text("歡迎來到 RealTimeOdds！賠率跑得比球員還快。")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(.horizontal, 32)
            }
        }
    }
}

#Preview {
    ContentView()
}
