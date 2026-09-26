import SwiftUI
import UIKit

enum ControlScenes {
    static let all: [String: () -> AnyView] = [
        "button.styles": { AnyView(ButtonStylesScene()) },
        "button.press": { AnyView(ButtonPressScene()) },
        "toggle": { AnyView(ToggleScene()) },
        "slider": { AnyView(SliderScene()) },
        "segmented": { AnyView(SegmentedScene()) },
        "stepper": { AnyView(StepperScene()) },
        "picker.menu": { AnyView(MenuPickerScene()) },
        "datepicker.compact": { AnyView(DatePickerScene(style: .compact)) },
        "datepicker.inline": { AnyView(DatePickerScene(style: .inline)) },
        "datepicker.wheel": { AnyView(DatePickerScene(style: .wheel)) },
        "pagecontrol": { AnyView(PageControlScene()) },
        "textfield": { AnyView(TextFieldScene()) },
        "list.form": { AnyView(FormScene()) },
        "swipe.row": { AnyView(SwipeScene()) },
        "progress": { AnyView(ProgressScene()) },
    ]
}

struct ButtonStylesScene: View {
    private let sizes: [ControlSize] = [.small, .regular, .large, .extraLarge]

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 18) {
                ForEach(sizes, id: \.self) { size in
                    HStack(spacing: 12) {
                        Button("Glass") {}.buttonStyle(.glass)
                        Button("Prominent") {}.buttonStyle(.glassProminent).tint(Lab.accent)
                        Button("Clear") {}.buttonStyle(.glass(.clear))
                    }
                    .controlSize(size)
                }
                HStack(spacing: 16) {
                    Button {} label: { Image(systemName: "plus") }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                    Button {} label: { Image(systemName: "play.fill") }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .tint(Lab.accent)
                    Button {} label: { Image(systemName: "xmark") }
                        .buttonStyle(.glass(.clear))
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                }
            }
        }
    }
}

struct ButtonPressScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 60) {
                Button("Glass button") {}
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .accessibilityIdentifier("btn.glass")
                Button("Prominent button") {}
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(Lab.accent)
                    .accessibilityIdentifier("btn.prominent")
            }
        }
    }
}

struct ToggleScene: View {
    @State private var off = false
    @State private var on = true

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 60) {
                Toggle("Off", isOn: $off).labelsHidden().accessibilityIdentifier("toggle.off")
                Toggle("On", isOn: $on).labelsHidden().accessibilityIdentifier("toggle.on")
            }
        }
    }
}

struct SliderScene: View {
    @State private var plain = 0.5
    @State private var stepped = 5.0
    @State private var neutral = 0.0
    @State private var thumbless = 0.4

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 48) {
                Slider(value: $plain) { Text("Default") }
                    .labelsHidden()
                    .accessibilityIdentifier("slider.default")
                Slider(value: $stepped, in: 0...10, step: 1) { Text("Stepped") }
                    .labelsHidden()
                Slider(value: $neutral, in: -1...1, neutralValue: 0) { Text("Neutral") }
                    .labelsHidden()
                Slider(value: $thumbless) { Text("Thumbless") }
                    .labelsHidden()
                    .sliderThumbVisibility(.hidden)
            }
            .frame(width: 300)
        }
    }
}

struct SegmentedScene: View {
    @State private var selection = 0

    var body: some View {
        ZStack {
            Backdrop()
            Picker("Filter", selection: $selection) {
                Text("All").tag(0)
                Text("Running").tag(1)
                Text("Done").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .accessibilityIdentifier("segmented")
        }
    }
}

struct StepperScene: View {
    @State private var value = 3

    var body: some View {
        ZStack {
            Backdrop()
            Stepper("Agents: \(value)", value: $value, in: 0...10)
                .frame(width: 300)
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct MenuPickerScene: View {
    @State private var model = "Opus"

    var body: some View {
        ZStack {
            Backdrop()
            Picker("Model", selection: $model) {
                Text("Opus").tag("Opus")
                Text("Sonnet").tag("Sonnet")
                Text("Haiku").tag("Haiku")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("picker")
        }
    }
}

enum LabDatePickerStyle {
    case compact, inline, wheel
}

struct DatePickerScene: View {
    let style: LabDatePickerStyle
    @State private var date = Date(timeIntervalSince1970: 1_790_000_000)

    var body: some View {
        ZStack {
            Backdrop()
            picker.accessibilityIdentifier("datepicker")
        }
    }

    @ViewBuilder private var picker: some View {
        switch style {
        case .compact:
            DatePicker("Due", selection: $date).datePickerStyle(.compact).labelsHidden()
        case .inline:
            DatePicker("Due", selection: $date).datePickerStyle(.graphical).frame(width: 360)
        case .wheel:
            DatePicker("Due", selection: $date).datePickerStyle(.wheel).labelsHidden()
        }
    }
}

struct PageControlView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.numberOfPages = 5
        control.currentPage = 1
        control.backgroundStyle = .prominent
        return control
    }

    func updateUIView(_ uiView: UIPageControl, context: Context) {}
}

struct PageControlScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            PageControlView().fixedSize()
        }
    }
}

struct TextFieldScene: View {
    @State private var text = ""
    @State private var search = ""

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 32) {
                TextField("Message", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("field.text")
                TextField("Search", text: $search)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .glassEffect()
                    .accessibilityIdentifier("field.search")
            }
            .frame(width: 320)
        }
    }
}

struct FormScene: View {
    @State private var alerts = true
    @State private var sounds = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Desktop", value: "127.0.0.1")
                    LabeledContent("Status", value: "Connected")
                }
                Section("Phone alerts") {
                    Toggle("Alerts", isOn: $alerts)
                    Toggle("Sounds", isOn: $sounds)
                }
                Section {
                    Button("Remove desktop", role: .destructive) {}
                }
            }
            .accessibilityIdentifier("form")
            .navigationTitle("Settings")
        }
    }
}

struct SwipeScene: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(1...6, id: \.self) { index in
                    Text("Session \(index)")
                        .swipeActions {
                            Button("Kill", role: .destructive) {}
                            Button("Pin") {}.tint(.orange)
                        }
                        .accessibilityIdentifier("row.\(index)")
                }
            }
            .navigationTitle("Sessions")
        }
    }
}

struct ProgressScene: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 40) {
                ProgressView(value: 0.6).frame(width: 300)
                ProgressView().controlSize(.large)
                Slider(value: .constant(0.3)) { Text("Progress") }
                    .labelsHidden()
                    .sliderThumbVisibility(.hidden)
                    .frame(width: 300)
            }
        }
    }
}
