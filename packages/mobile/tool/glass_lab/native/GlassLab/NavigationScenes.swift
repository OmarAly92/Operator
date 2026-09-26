import SwiftUI

enum NavigationScenes {
    static let all: [String: () -> AnyView] = [
        "tabbar.rest": { AnyView(LabTabView()) },
        "tabbar.press": { AnyView(LabTabView()) },
        "tabbar.drag": { AnyView(LabTabView()) },
        "tabbar.badge": { AnyView(LabTabView(badge: true)) },
        "tabbar.prominent": { AnyView(LabTabView(prominent: true)) },
        "tabbar.minimize": { AnyView(LabTabView(scrolls: true, minimizes: true)) },
        "tabbar.accessory": { AnyView(LabTabView(scrolls: true, minimizes: true, accessory: true)) },
        "tabbar.search": { AnyView(LabTabView()) },
        "navbar.inline": { AnyView(InlineNavScene()) },
        "navbar.large": { AnyView(LargeTitleScene()) },
        "navbar.groups": { AnyView(GroupsScene()) },
        "navbar.minimize": { AnyView(LargeTitleScene(minimizes: true)) },
        "navbar.push": { AnyView(PushScene()) },
        "navbar.badge": { AnyView(BadgeNavScene()) },
        "toolbar.bottom": { AnyView(BottomToolbarScene()) },
        "search.bottom": { AnyView(SearchScene()) },
        "search.minimized": { AnyView(SearchScene(minimized: true)) },
        "search.scopes": { AnyView(SearchScene(scoped: true)) },
    ]
}

enum LabTab: Hashable {
    case agents, prs, settings, run, search
}

struct LabTabView: View {
    var badge = false
    var prominent = false
    var scrolls = false
    var minimizes = false
    var accessory = false
    @State private var selection: LabTab = .agents
    @State private var query = ""

    var body: some View {
        TabView(selection: $selection) {
            Tab("Agents", systemImage: "square.stack.3d.up", value: .agents) { page }
            Tab("PRs", systemImage: "arrow.triangle.merge", value: .prs) { page }
                .badge(badge ? 3 : 0)
            Tab("Settings", systemImage: "gearshape", value: .settings) { page }
            if prominent {
                Tab("Run", systemImage: "play.fill", value: .run, role: .prominent) { page }
            }
            Tab(value: .search, role: .search) {
                NavigationStack { Backdrop().searchable(text: $query) }
            }
        }
        .tint(Lab.accent)
        .tabBarMinimizeBehavior(minimizes ? .onScrollDown : .automatic)
        .tabViewBottomAccessory(isEnabled: accessory) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                Text("Agent working")
                Spacer()
                Image(systemName: "stop.fill")
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private var page: some View {
        if scrolls {
            ScrollBackdrop()
        } else {
            Backdrop()
        }
    }
}

struct DetailPage: View {
    let title: String

    var body: some View {
        Backdrop()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct InlineNavScene: View {
    @State private var path = [1]

    var body: some View {
        NavigationStack(path: $path) {
            Backdrop()
                .navigationTitle("Sessions")
                .navigationDestination(for: Int.self) { _ in
                    Backdrop()
                        .navigationTitle("Agents")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                Button {} label: { Image(systemName: "bell") }
                                Button {} label: { Image(systemName: "ellipsis") }
                            }
                        }
                }
        }
    }
}

struct LargeTitleScene: View {
    var minimizes = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let image = Lab.image("scroll") {
                    Image(uiImage: image).resizable().aspectRatio(image.size, contentMode: .fit)
                }
            }
            .accessibilityIdentifier("scroll.content")
            .navigationTitle("Agents")
            .navigationSubtitle("3 running")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {} label: { Image(systemName: "plus") }
                }
            }
            .toolbarMinimizationBehavior(minimizes ? .onScrollDown : .automatic, for: .navigationBar)
        }
    }
}

struct GroupsScene: View {
    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Agents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Edit") {} }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {} label: { Image(systemName: "bell") }.accessibilityIdentifier("nav.bell")
                        Button {} label: { Image(systemName: "tray") }.accessibilityIdentifier("nav.tray")
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {}.buttonStyle(.glassProminent).tint(Lab.accent)
                    }
                }
        }
    }
}

struct PushScene: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop()
                VStack(spacing: 12) {
                    ForEach(1...3, id: \.self) { index in
                        NavigationLink(value: index) { Card(title: "Session \(index)") }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("row.\(index)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("Agents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {} label: { Image(systemName: "bell") }
                }
            }
            .navigationDestination(for: Int.self) { index in
                Backdrop()
                    .navigationTitle("Session \(index)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {} label: { Image(systemName: "bell") }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {} label: { Image(systemName: "square.and.arrow.up") }
                        }
                    }
            }
        }
    }
}

struct BadgeNavScene: View {
    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Agents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {} label: { Image(systemName: "bell") }
                            .badge(3)
                    }
                }
        }
    }
}

struct BottomToolbarScene: View {
    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Files")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {} label: { Image(systemName: "trash") }
                        Button {} label: { Image(systemName: "folder") }
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button {} label: { Image(systemName: "square.and.pencil") }
                    }
                }
        }
    }
}

struct SearchScene: View {
    var minimized = false
    var scoped = false
    @State private var query = ""
    @State private var scope = 0

    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query)
                .searchToolbarBehavior(minimized ? .minimize : .automatic)
                .searchScopes($scope, activation: .onSearchPresentation) {
                    if scoped {
                        Text("All").tag(0)
                        Text("Running").tag(1)
                        Text("Done").tag(2)
                    }
                }
        }
    }
}
