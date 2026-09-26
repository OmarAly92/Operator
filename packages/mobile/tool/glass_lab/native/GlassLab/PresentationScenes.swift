import SwiftUI

enum PresentationScenes {
    static let all: [String: () -> AnyView] = [
        "sheet.detents": { AnyView(DetentSheetScene()) },
        "sheet.scroll": { AnyView(ScrollSheetScene()) },
        "sheet.zoom": { AnyView(ZoomSheetScene()) },
        "sheet.crossfade": { AnyView(CrossFadeSheetScene()) },
        "popover.bar": { AnyView(PopoverScene()) },
        "menu.bar": { AnyView(MenuScene()) },
        "menu.submenu": { AnyView(MenuScene()) },
        "menu.pressdrag": { AnyView(MenuScene()) },
        "contextmenu.card": { AnyView(ContextMenuScene()) },
        "alert.two": { AnyView(AlertScene(actions: 2)) },
        "alert.three": { AnyView(AlertScene(actions: 3)) },
        "confirm.source": { AnyView(ConfirmScene()) },
        "push.zoom": { AnyView(PushZoomScene()) },
    ]
}

struct SheetBody: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .accessibilityIdentifier("sheet.top")
            Spacer()
        }
    }
}

struct DetentSheetScene: View {
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        Backdrop()
            .sheet(isPresented: .constant(true)) {
                SheetBody(title: "Sheet")
                    .presentationDetents([.height(120), .medium, .large], selection: $detent)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(120)))
                    .interactiveDismissDisabled()
            }
    }
}

struct ScrollSheetScene: View {
    var body: some View {
        Backdrop()
            .sheet(isPresented: .constant(true)) {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(1...30, id: \.self) { index in
                            Card(title: "Row \(index)")
                        }
                    }
                    .padding(16)
                }
                .accessibilityIdentifier("sheet.scroll")
                .presentationDetents([.large])
                .interactiveDismissDisabled()
            }
    }
}

struct ZoomSheetScene: View {
    @Namespace private var namespace
    @State private var shown = false

    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Agents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { shown = true } label: { Image(systemName: "plus") }
                            .accessibilityIdentifier("zoom.source")
                    }
                    .matchedTransitionSource(id: "source", in: namespace)
                }
                .sheet(isPresented: $shown) {
                    SheetBody(title: "New agent")
                        .presentationDetents([.medium])
                        .navigationTransition(.zoom(sourceID: "source", in: namespace))
                }
        }
    }
}

struct CrossFadeSheetScene: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Backdrop()
            LabButton(title: "Present", id: "sheet.present") { shown = true }
        }
        .sheet(isPresented: $shown) {
            VStack {
                SheetBody(title: "Cross fade")
                LabButton(title: "Close", id: "sheet.close") { shown = false }
                Spacer()
            }
            .presentationDetents([.medium])
            .navigationTransition(.crossFade)
        }
    }
}

struct PopoverScene: View {
    @State private var shown = false

    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Agents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { shown = true } label: { Image(systemName: "info.circle") }
                            .accessibilityIdentifier("popover.source")
                            .popover(isPresented: $shown) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Session 1").font(.headline)
                                    Text("Running for 12 minutes").font(.subheadline)
                                }
                                .padding(20)
                                .presentationCompactAdaptation(.popover)
                            }
                    }
                }
        }
    }
}

struct MenuScene: View {
    var body: some View {
        NavigationStack {
            Backdrop()
                .navigationTitle("Reminders")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Show List Info", systemImage: "info.circle") {}
                            Button("Select Reminders", systemImage: "checkmark.circle") {}
                            Menu("Sort By", systemImage: "arrow.up.arrow.down") {
                                Button("Manual") {}
                                Button("Due Date") {}
                                Button("Title") {}
                            }
                            Button("Show Completed", systemImage: "eye") {}
                            Button("Print", systemImage: "printer") {}
                            Button("Delete List", systemImage: "trash", role: .destructive) {}
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityIdentifier("menu.button")
                    }
                }
        }
    }
}

struct ContextMenuScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            Card(title: "Session 1")
                .padding(.horizontal, 16)
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") {}
                    Button("Share", systemImage: "square.and.arrow.up") {}
                    Button("Kill", systemImage: "xmark.octagon", role: .destructive) {}
                }
                .accessibilityIdentifier("card")
        }
    }
}

struct AlertScene: View {
    let actions: Int
    @State private var shown = false

    var body: some View {
        ZStack {
            Backdrop()
            LabButton(title: "Show", id: "alert.show") { shown = true }
        }
        .alert("Kill session?", isPresented: $shown) {
            if actions == 3 {
                Button("Keep running") {}
            }
            Button("Kill", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The agent stops and its terminal closes.")
        }
    }
}

struct ConfirmScene: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Backdrop()
            LabButton(title: "Delete", id: "confirm.show") { shown = true }
                .confirmationDialog("Delete session?", isPresented: $shown, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {}
                    Button("Cancel", role: .cancel) {}
                }
        }
    }
}

struct PushZoomScene: View {
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop()
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { index in
                        NavigationLink(value: index) { Card(title: "Session \(index + 1)") }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: index, in: namespace)
                            .accessibilityIdentifier("card.\(index)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("Agents")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { index in
                Backdrop()
                    .navigationTitle("Session \(index + 1)")
                    .navigationTransition(.zoom(sourceID: index, in: namespace))
            }
        }
    }
}
