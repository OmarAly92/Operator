import SwiftUI
import UIKit

enum Lab {
    static let environment = ProcessInfo.processInfo.environment
    static let sceneID = environment["GLASS_LAB_SCENE"]
    static let bare = environment["GLASS_LAB_BARE"] == "1"
    static let backdropID = environment["GLASS_LAB_BACKDROP"] ?? "stripes"
    static let accent = Color(red: 0x1A / 255, green: 0xCB / 255, blue: 0x64 / 255)

    static func image(_ id: String) -> UIImage? {
        let documents = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/glass_lab")
        return UIImage(contentsOfFile: documents.appendingPathComponent("\(id).png").path)
    }
}

struct ReadyMarker: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("scene.ready")
    }
}

struct Backdrop: View {
    var id: String = Lab.backdropID

    var body: some View {
        if id == "scroll" {
            ScrollBackdrop()
        } else if id == "none" {
            Color(uiColor: .systemBackground).ignoresSafeArea()
        } else if let image = Lab.image(id) {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()
        } else {
            Color.gray.ignoresSafeArea()
        }
    }
}

struct ScrollBackdrop: View {
    var body: some View {
        ScrollView {
            if let image = Lab.image("scroll") {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(image.size, contentMode: .fit)
            }
        }
        .accessibilityIdentifier("scroll.content")
        .ignoresSafeArea()
    }
}

struct GlassBlock: View {
    let width: CGFloat
    let height: CGFloat
    var glass: Glass = .regular

    var body: some View {
        Color.clear
            .frame(width: width, height: height)
            .glassEffect(glass)
    }
}

struct Card: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 16, weight: .semibold))
            Text("feat/branch").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LabButton: View {
    let title: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
