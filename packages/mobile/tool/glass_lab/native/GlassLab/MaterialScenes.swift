import SwiftUI

enum MaterialScenes {
    static let all: [String: () -> AnyView] = [
        "material.regular": { AnyView(RegularScene()) },
        "material.clear": { AnyView(ClearScene()) },
        "material.tinted": { AnyView(TintedScene()) },
        "material.interactive": { AnyView(InteractiveScene()) },
        "material.flip": { AnyView(FlipScene()) },
        "material.materialize": { AnyView(MaterializeScene()) },
        "material.materialize.snappy": { AnyView(MaterializeScene(animation: .snappy)) },
        "material.materialize.bouncy": { AnyView(MaterializeScene(animation: .bouncy)) },
        "material.press.circle58": { AnyView(PressScene(width: 58, height: 58, circle: true)) },
        "material.press.138x53": { AnyView(PressScene(width: 138, height: 53)) },
        "material.press.250x44": { AnyView(PressScene(width: 250, height: 44)) },
        "material.press.300x120": { AnyView(PressScene(width: 300, height: 120)) },
        "material.press.360x200": { AnyView(PressScene(width: 360, height: 200, cornerRadius: 32)) },
        "material.spacing.default.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: nil)) },
        "material.spacing.default.b": { AnyView(SpacingScene(gaps: [16, 20, 24, 32], spacing: nil)) },
        "material.spacing.default.c": { AnyView(SpacingScene(gaps: [40, 48, 60], spacing: nil)) },
        "material.spacing.40.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 40)) },
        "material.spacing.40.b": { AnyView(SpacingScene(gaps: [16, 20, 24, 32], spacing: 40)) },
        "material.spacing.40.c": { AnyView(SpacingScene(gaps: [40, 48, 60], spacing: 40)) },
        "material.spacing.4.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 4)) },
        "material.spacing.6.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 6)) },
        "material.spacing.8.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 8)) },
        "material.spacing.10.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 10)) },
        "material.spacing.12.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 12)) },
        "material.spacing.16.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 16)) },
        "material.spacing.20.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 20)) },
        "material.spacing.80.a": { AnyView(SpacingScene(gaps: [0, 4, 8, 12], spacing: 80)) },
        "material.spacing.default.d": { AnyView(SpacingScene(gaps: [2, 5, 6, 7], spacing: nil)) },
        "material.spacing.20.b": { AnyView(SpacingScene(gaps: [9, 10, 11, 14], spacing: 20)) },
        "material.spacing.20.c": { AnyView(SpacingScene(gaps: [16, 18, 24, 32], spacing: 20)) },
        "material.spacing.40.d": { AnyView(SpacingScene(gaps: [18, 19, 21, 22], spacing: 40)) },
        "material.spacing.40.e": { AnyView(SpacingScene(gaps: [28, 36, 44, 52], spacing: 40)) },
        "material.spacing.80.b": { AnyView(SpacingScene(gaps: [16, 24, 32, 36], spacing: 80)) },
        "material.spacing.80.c": { AnyView(SpacingScene(gaps: [38, 40, 42, 44], spacing: 80)) },
        "material.spacing.80.d": { AnyView(SpacingScene(gaps: [48, 56, 64, 72], spacing: 80)) },
        "material.spacing.80.e": { AnyView(SpacingScene(gaps: [80, 88, 96], spacing: 80)) },
        "material.merge": { AnyView(MergeScene()) },
        "material.union": { AnyView(UnionScene()) },
        "material.morph": { AnyView(MorphScene()) },
        "material.morph.plain": { AnyView(MorphScene(interactive: false)) },
        "material.tap": { AnyView(TapScene()) },
        "material.shapes": { AnyView(ShapesScene()) },
        "material.edge.soft": { AnyView(EdgeScene(style: .soft)) },
        "material.edge.hard": { AnyView(EdgeScene(style: .hard)) },
        "material.edge.automatic": { AnyView(EdgeScene(style: .automatic)) },
        "material.content": { AnyView(ContentMaterialsScene()) },
    ]
}

struct RegularScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 48) {
                GlassBlock(width: 150, height: 44)
                GlassBlock(width: 250, height: 88)
                GlassBlock(width: 360, height: 200)
            }
        }
    }
}

struct ClearScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 64) {
                GlassBlock(width: 250, height: 88, glass: .clear)
                ZStack {
                    Capsule().fill(.black.opacity(0.35)).frame(width: 250, height: 88)
                    GlassBlock(width: 250, height: 88, glass: .clear)
                }
            }
        }
    }
}

struct TintedScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 48) {
                GlassBlock(width: 250, height: 88, glass: .regular.tint(Lab.accent))
                Button {} label: { Label("Run", systemImage: "play.fill") }
                    .buttonStyle(.glassProminent)
                    .tint(Lab.accent)
                    .accessibilityIdentifier("tinted.run")
            }
        }
    }
}

struct InteractiveScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            Color.white.opacity(0.001)
                .frame(width: 250, height: 88)
                .glassEffect(.regular.interactive())
                .accessibilityElement()
                .accessibilityIdentifier("glass")
        }
    }
}

struct PressScene: View {
    let width: CGFloat
    let height: CGFloat
    var circle = false
    var cornerRadius: CGFloat?

    var body: some View {
        ZStack {
            Backdrop()
            Group {
                if circle {
                    Color.white.opacity(0.001).frame(width: width, height: height).glassEffect(.regular.interactive(), in: .circle)
                } else if let cornerRadius {
                    Color.white.opacity(0.001).frame(width: width, height: height).glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                } else {
                    Color.white.opacity(0.001).frame(width: width, height: height).glassEffect(.regular.interactive())
                }
            }
            .accessibilityElement()
            .accessibilityIdentifier("glass")
        }
    }
}

struct SpacingScene: View {
    let gaps: [CGFloat]
    let spacing: CGFloat?

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 100) {
                ForEach(gaps, id: \.self) { gap in
                    pair(gap)
                }
            }
        }
    }

    @ViewBuilder
    private func pair(_ gap: CGFloat) -> some View {
        let circles = HStack(spacing: gap) {
            Color.clear.frame(width: 80, height: 80).glassEffect(.regular, in: .circle)
            Color.clear.frame(width: 80, height: 80).glassEffect(.regular, in: .circle)
        }
        if let spacing {
            GlassEffectContainer(spacing: spacing) { circles }
        } else {
            GlassEffectContainer { circles }
        }
    }
}

struct FlipScene: View {
    var body: some View {
        ZStack {
            ScrollBackdrop()
            VStack(spacing: 0) {
                GlassBlock(width: 150, height: 44).padding(.top, 180)
                Spacer()
                GlassBlock(width: 360, height: 200).padding(.bottom, 96)
                GlassBlock(width: 150, height: 44).padding(.bottom, 40)
            }
            .allowsHitTesting(false)
        }
    }
}

struct MaterializeScene: View {
    var animation: Animation?
    @State private var shown = true

    var body: some View {
        ZStack {
            Backdrop()
            GlassEffectContainer {
                if shown {
                    GlassBlock(width: 250, height: 88).glassEffectTransition(.materialize)
                }
            }
            VStack {
                Spacer()
                LabButton(title: "Toggle", id: "toggle") {
                    if let animation {
                        withAnimation(animation) { shown.toggle() }
                    } else {
                        withAnimation { shown.toggle() }
                    }
                }
                .padding(.bottom, 120)
            }
        }
    }
}

struct MergeScene: View {
    @State private var merged = false

    var body: some View {
        ZStack {
            Backdrop()
            GlassEffectContainer(spacing: 40) {
                HStack(spacing: merged ? 0 : 80) {
                    Color.clear.frame(width: 80, height: 80).glassEffect(.regular, in: .circle)
                    Color.clear.frame(width: 80, height: 80).glassEffect(.regular, in: .circle)
                }
            }
            VStack {
                Spacer()
                HStack(spacing: 24) {
                    LabButton(title: "Merge", id: "merge") { withAnimation { merged = true } }
                    LabButton(title: "Split", id: "split") { withAnimation { merged = false } }
                }
                .padding(.bottom, 120)
            }
        }
    }
}

struct UnionScene: View {
    @Namespace private var namespace
    private let symbols = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill"]

    var body: some View {
        ZStack {
            Backdrop()
            GlassEffectContainer {
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { index in
                        Image(systemName: symbols[index])
                            .font(.system(size: 24))
                            .frame(width: 64, height: 64)
                            .glassEffect()
                            .glassEffectUnion(id: index < 2 ? "first" : "second", namespace: namespace)
                    }
                }
            }
        }
    }
}

struct MorphScene: View {
    var interactive = true
    @Namespace private var namespace
    @State private var expanded = false
    private let badges = ["star.fill", "heart.fill", "bolt.fill"]

    var body: some View {
        ZStack {
            Backdrop()
            GlassEffectContainer(spacing: 20) {
                VStack(spacing: 16) {
                    if expanded {
                        ForEach(badges, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.system(size: 22))
                                .frame(width: 56, height: 56)
                                .glassEffect()
                                .glassEffectID(symbol, in: namespace)
                        }
                    }
                    Button {
                        withAnimation { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "xmark" : "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(interactive ? .regular.interactive() : .regular)
                    .glassEffectID("toggle", in: namespace)
                    .accessibilityIdentifier("morph")
                }
            }
        }
    }
}

struct TapScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            GlassEffectContainer(spacing: 20) {
                Button {} label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive())
                .accessibilityIdentifier("glass")
            }
        }
    }
}

struct ShapesScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 40) {
                Color.clear.frame(width: 250, height: 60).glassEffect(.regular, in: .capsule)
                Color.clear.frame(width: 250, height: 88).glassEffect(.regular, in: .rect(cornerRadius: 16))
                Color.clear
                    .frame(width: 300, height: 180)
                    .overlay {
                        Color.clear
                            .glassEffect(.regular, in: ConcentricRectangle())
                            .padding(12)
                    }
                    .background(.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .containerShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            }
        }
    }
}

struct EdgeScene: View {
    static let offset: CGFloat = 300

    let style: ScrollEdgeEffectStyle
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        NavigationStack {
            ScrollView {
                if let image = Lab.image("scroll") {
                    Image(uiImage: image).resizable().aspectRatio(image.size, contentMode: .fit)
                }
            }
            .scrollPosition($position)
            .onAppear { position.scrollTo(y: EdgeScene.offset) }
            .accessibilityIdentifier("scroll.content")
            .scrollEdgeEffectStyle(style, for: .all)
            .navigationTitle("Edge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Edit") {} }
            }
        }
    }
}

struct ContentMaterialsScene: View {
    private let materials: [(String, Material)] = [
        ("Ultra thin", .ultraThinMaterial),
        ("Thin", .thinMaterial),
        ("Regular", .regularMaterial),
        ("Thick", .thickMaterial),
    ]

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 16) {
                ForEach(materials, id: \.0) { name, material in
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 340, height: 80)
                        .background(material, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }
}
