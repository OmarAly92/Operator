import SwiftUI

enum MaterialScenes {
    static let all: [String: () -> AnyView] = [
        "material.regular": { AnyView(RegularScene()) },
        "material.clear": { AnyView(ClearScene()) },
        "material.tinted": { AnyView(TintedScene()) },
        "material.interactive": { AnyView(InteractiveScene()) },
        "material.flip": { AnyView(FlipScene()) },
        "material.materialize": { AnyView(MaterializeScene()) },
        "material.merge": { AnyView(MergeScene()) },
        "material.union": { AnyView(UnionScene()) },
        "material.morph": { AnyView(MorphScene()) },
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
            GlassBlock(width: 250, height: 88, glass: .regular.interactive())
                .accessibilityElement()
                .accessibilityIdentifier("glass")
        }
    }
}

struct FlipScene: View {
    var body: some View {
        ZStack {
            ScrollBackdrop()
            VStack {
                GlassBlock(width: 150, height: 44).padding(.top, 180)
                Spacer()
                GlassBlock(width: 360, height: 200).padding(.bottom, 180)
            }
            .allowsHitTesting(false)
        }
    }
}

struct MaterializeScene: View {
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
                    withAnimation { shown.toggle() }
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
                    .glassEffect(.regular.interactive())
                    .glassEffectID("toggle", in: namespace)
                    .accessibilityIdentifier("morph")
                }
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
    let style: ScrollEdgeEffectStyle

    var body: some View {
        NavigationStack {
            ScrollView {
                if let image = Lab.image("scroll") {
                    Image(uiImage: image).resizable().aspectRatio(image.size, contentMode: .fit)
                }
            }
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
