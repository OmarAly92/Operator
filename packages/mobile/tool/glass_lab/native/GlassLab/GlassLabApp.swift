import SwiftUI

@main
struct GlassLabApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        if let id = Lab.sceneID {
            SceneHost(id: id)
        } else {
            CatalogIndex()
        }
    }
}

struct SceneHost: View {
    let id: String

    var body: some View {
        Group {
            if Lab.bare {
                Backdrop()
            } else if let make = SceneRegistry.all[id] {
                make()
            } else {
                ZStack {
                    Backdrop()
                    Text("unknown scene: \(id)").font(.headline).padding().background(.white)
                }
            }
        }
        .overlay(alignment: .topLeading) { ReadyMarker() }
        .overlay(alignment: .bottomLeading) {
            if Lab.marker {
                TouchMarker().frame(width: 18, height: 18).padding(.leading, 16).padding(.bottom, 160)
            }
        }
    }
}

struct CatalogIndex: View {
    @State private var selected: String?

    var body: some View {
        NavigationStack {
            List(SceneRegistry.ids, id: \.self) { id in
                NavigationLink(id, value: id)
            }
            .navigationTitle("Glass Lab")
            .navigationDestination(for: String.self) { id in
                SceneHost(id: id).toolbar(.hidden, for: .navigationBar)
            }
        }
    }
}
