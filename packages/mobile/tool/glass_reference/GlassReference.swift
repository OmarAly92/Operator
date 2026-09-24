import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct Palette {
    let bg: Color
    let surface: Color
    let text: Color
    let secondary: Color
    let accent: Color

    static func of(_ scheme: ColorScheme) -> Palette {
        if scheme == .dark {
            return Palette(bg: Color(hex: 0x18171C), surface: Color(hex: 0x1F1E24), text: Color(hex: 0xFFFFFF), secondary: Color(hex: 0xA09EA8), accent: Color(hex: 0x1ACB64))
        }
        return Palette(bg: Color(hex: 0xFAF7F2), surface: Color(hex: 0xFFFFFF), text: Color(hex: 0x1A1612), secondary: Color(hex: 0x6B6354), accent: Color(hex: 0x1ACB64))
    }
}

let stripeColors: [UInt32] = [0xE5484D, 0xE89527, 0xF0B45C, 0x1ACB64, 0x47BFFF, 0x8E6CF0]

struct Stripes: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(stripeColors, id: \.self) { Color(hex: $0) }
        }
    }
}

struct Card: View {
    let p: Palette
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Session \(index + 1)").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
            Text("feat/branch-\(index + 1)").font(.system(size: 12)).foregroundStyle(p.secondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .leading)
        .background(p.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SceneContent: View {
    let p: Palette

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Stripes().frame(height: 182)
                    VStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { Card(p: p, index: $0) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    Spacer(minLength: 0)
                    Stripes().frame(height: 180)
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .background(p.bg)
        .ignoresSafeArea()
    }
}

struct AgentsScreen: View {
    let p: Palette

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                SceneContent(p: p)
                Button {} label: { Label("Run", systemImage: "play.fill") }
                    .buttonStyle(.glassProminent)
                    .tint(p.accent)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
            .navigationTitle("Agents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {} label: { Image(systemName: "chevron.left") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {}
                }
            }
        }
    }
}

struct RootView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var showSheet = ProcessInfo.processInfo.environment["GLASS_LAB_SCENE"] == "sheet"

    var body: some View {
        let p = Palette.of(scheme)
        TabView {
            Tab("Agents", systemImage: "square.stack.3d.up") { AgentsScreen(p: p) }
            Tab("PRs", systemImage: "arrow.triangle.merge") { p.bg.ignoresSafeArea() }
            Tab("Settings", systemImage: "gearshape") { p.bg.ignoresSafeArea() }
        }
        .tint(p.accent)
        .sheet(isPresented: $showSheet) {
            Text("Sheet")
                .font(.headline)
                .presentationDetents([.medium])
        }
    }
}

@main
struct GlassReferenceApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}
