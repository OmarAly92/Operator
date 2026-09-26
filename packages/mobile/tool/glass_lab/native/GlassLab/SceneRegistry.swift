import SwiftUI

enum SceneRegistry {
    static let all: [String: () -> AnyView] = MaterialScenes.all
        .merging(NavigationScenes.all) { first, _ in first }
        .merging(PresentationScenes.all) { first, _ in first }
        .merging(ControlScenes.all) { first, _ in first }

    static let ids: [String] = all.keys.sorted()
}
