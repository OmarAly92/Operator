import SwiftUI

enum SceneRegistry {
    static let all: [String: () -> AnyView] = MaterialScenes.all

    static let ids: [String] = all.keys.sorted()
}
