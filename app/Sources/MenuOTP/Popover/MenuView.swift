import AppKit
import OTPCore
import SwiftUI

/// Mirrors macOS menu metrics, loosened where the point of the custom menu is to
/// differ (a native menu row is locked to 22pt).
enum MenuMetrics {
    static let rowHeight: CGFloat = 25
    static let rowGap: CGFloat = 8
    static let verticalPadding: CGFloat = 4
    static let itemInset: CGFloat = 5
    static let itemPadding: CGFloat = 9
    static let iconSize: CGFloat = 18
    static let iconGap: CGFloat = 8
    /// Separators line up with the icon column, not the panel edge, as system menus do
    static let separatorInset: CGFloat = 14
    static let fontSize: CGFloat = 14
    static let radius: CGFloat = 5
}

/// The colours a real NSMenu uses (read from a live one's item text fields and measured
/// against it; see MenuPanel). AppKit's own catalog colours rather than SwiftUI's
/// `.primary`/`.secondary`, which render lighter on the panel's material.
enum MenuColors {
    /// Item text. `Color(nsColor: .labelColor)` doesn't come out as labelColor here:
    /// SwiftUI swaps the catalog colour for its own primary, measured at #5b5b5b in light
    /// mode against the real menu's #313131 (and too bright in dark mode). So it's
    /// resolved to AppKit's actual value for the appearance the view is in; the view
    /// passes its colour scheme and contrast, so it follows System Settings as they change.
    static func label(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> Color {
        let name: NSAppearance.Name = switch (scheme, contrast) {
        case (.dark, .increased): .accessibilityHighContrastDarkAqua
        case (.dark, _): .darkAqua
        case (_, .increased): .accessibilityHighContrastAqua
        default: .aqua
        }
        var resolved = NSColor.labelColor
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            resolved = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        return Color(nsColor: resolved)
    }
    /// Section headers and key equivalents (⌘Q)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    static let selectedText = Color(nsColor: .selectedMenuItemTextColor)
}

/// The highlight behind the selected row and the Copied confirmation: the emphasized
/// selection material, as menus use, so it follows the accent colour and the
/// appearance the way the system's does. A flat accent fill came out much brighter.
struct MenuHighlightBackground: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .selection
        view.isEmphasized = true
        view.state = .active
        view.blendingMode = .withinWindow
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// What the popover shows. The controller swaps it in whole and then measures, so
/// the panel is never on screen at a stale size.
enum MenuContent: Equatable {
    case rows([MenuRow])
    case copied(issuer: String, code: String)
}

/// Highlighted row, kept outside MenuContent so hovering only re-renders rows and
/// never triggers a re-measure.
@Observable
final class MenuHighlight {
    var active: Int?
    /// Row frames in MenuView's "menu" coordinate space, reported by the view and
    /// hit-tested by MenuHostingView.
    @ObservationIgnored var rowFrames: [Int: CGRect] = [:]
}

private struct RowFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct MenuView: View {
    let content: MenuContent
    let highlight: MenuHighlight
    var scrollable = false
    /// VoiceOver's activate action (pointer and keyboard go through the controller)
    var onActivate: (Int) -> Void = { _ in }

    var body: some View {
        Group {
            switch content {
            case .rows(let rows):
                if scrollable {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) { rowStack(rows) }
                            .background(ScrollToHighlight(highlight: highlight, proxy: proxy))
                    }
                } else {
                    rowStack(rows)
                }
            case .copied(let issuer, let code):
                CopiedView(issuer: issuer, code: code)
                    .padding(.vertical, MenuMetrics.verticalPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "menu")
        .onPreferenceChange(RowFramesKey.self) { frames in highlight.rowFrames = frames }
    }

    private func rowStack(_ rows: [MenuRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                rowView(row, index: index)
            }
        }
        .padding(.vertical, MenuMetrics.verticalPadding)
    }

    @ViewBuilder
    private func rowView(_ row: MenuRow, index: Int) -> some View {
        switch row.kind {
        case .title:
            MenuTitleRow(label: row.label)
        case .separator:
            // separatorColor measured within 1/255 of a real menu's separator, both modes
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .padding(.horizontal, MenuMetrics.separatorInset)
                .padding(.vertical, 5)
                .accessibilityHidden(true)
        case .header:
            // Section headers sit tighter and smaller than items, as they do natively,
            // in the tertiary label colour a real menu's section header measured at
            Text(row.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MenuColors.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(EdgeInsets(top: 4, leading: MenuMetrics.itemInset, bottom: 2, trailing: MenuMetrics.itemInset))
                .padding(.horizontal, MenuMetrics.itemInset)
                // So VoiceOver's rotor can jump between sections
                .accessibilityAddTraits(.isHeader)
        case .item:
            HighlightedRow(row: row, index: index, highlight: highlight, onActivate: onActivate)
                .id(index)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: RowFramesKey.self, value: [index: geo.frame(in: .named("menu"))])
                })
                .padding(.top, index == 0 ? 0 : MenuMetrics.rowGap)
        }
    }
}

/// The menu's name in bold, in the item text colour, lined up with the item labels:
/// how macOS 26's own status menus (Focus, Wi-Fi) open.
struct MenuTitleRow: View {
    let label: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(label)
            .font(.system(size: MenuMetrics.fontSize, weight: .bold))
            .foregroundStyle(MenuColors.label(colorScheme, contrast))
            .lineLimit(1)
            .frame(height: MenuMetrics.rowHeight)
            .padding(.horizontal, MenuMetrics.itemInset + MenuMetrics.itemPadding)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Reads the highlight in its own body. Read from inside MenuView's ForEach
/// closure instead, the macOS 27 SDK stopped re-rendering rows when it changed
/// (the macOS 26 SDK did); a View's own body is always observation-tracked.
struct HighlightedRow: View {
    let row: MenuRow
    let index: Int
    let highlight: MenuHighlight
    let onActivate: (Int) -> Void

    var body: some View {
        MenuItemRow(row: row, isActive: highlight.active == index)
            // Clicks arrive through MenuHostingView's raw mouse handling, which
            // VoiceOver can't trigger; this gives it the same action
            .accessibilityAction { onActivate(index) }
    }
}

/// In a menu taller than the screen, keeps the keyboard-highlighted row in view.
/// Its own view so its body, which reads the highlight, is observation-tracked (see
/// HighlightedRow).
struct ScrollToHighlight: View {
    let highlight: MenuHighlight
    let proxy: ScrollViewProxy

    var body: some View {
        Color.clear.onChange(of: highlight.active) { _, index in
            // No anchor: scroll only as far as needed to reveal the row
            if let index { proxy.scrollTo(index) }
        }
    }
}

struct MenuItemRow: View {
    let row: MenuRow
    let isActive: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: MenuMetrics.iconGap) {
            if IconView.hasIcon(row.icon) {
                IconView(icon: row.icon, size: MenuMetrics.iconSize)
                    .modifier(MenuIconStyle(isActive: isActive))
            }
            Text(row.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? MenuColors.selectedText : MenuColors.label(colorScheme, contrast))
            Spacer(minLength: 0)
            if let accelerator = row.accelerator {
                Text(accelerator)
                    .monospacedDigit()
                    .foregroundStyle(isActive ? MenuColors.selectedText : MenuColors.tertiary)
                    .padding(.leading, 12)
            }
        }
        .font(.system(size: MenuMetrics.fontSize))
        .padding(.horizontal, MenuMetrics.itemPadding)
        .frame(height: MenuMetrics.rowHeight)
        .background {
            if isActive { MenuHighlightBackground(radius: MenuMetrics.radius) }
        }
        .padding(.horizontal, MenuMetrics.itemInset)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

/// The reason this menu isn't a native one: icons are greyed and inverted until
/// their row is highlighted.
struct MenuIconStyle: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
        } else {
            content.grayscale(1).colorInvert().opacity(0.6)
        }
    }
}

/// Replaces the whole menu after a copy, in the highlight colour, at a size meant
/// to be read at a glance: issuer, "Copied" (fades once the code has been read),
/// code. Stays until the panel is dismissed; there is no auto-close.
struct CopiedView: View {
    let issuer: String
    let code: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showWord = true

    var body: some View {
        HStack(spacing: 16) {
            // Each side column holds both strings (one hidden), so the two columns
            // are equally wide and "Copied" sits dead centre, like the Electron
            // version's `grid-template-columns: 1fr auto 1fr`.
            ZStack(alignment: .leading) {
                Text(code).hidden()
                Text(issuer)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Copied").opacity(showWord ? 1 : 0)
            ZStack(alignment: .trailing) {
                Text(issuer).hidden()
                Text(code).tracking(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 18, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(MenuColors.selectedText)
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .frame(minWidth: 300)
        .background(MenuHighlightBackground(radius: MenuMetrics.radius))
        .padding(.horizontal, MenuMetrics.itemInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(issuer) code \(code) copied")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.9).delay(0.9)) { showWord = false }
        }
    }
}

/// Hosts MenuView and tracks the pointer itself. SwiftUI's hover and tap handling
/// follow the window's key/active state, and this panel belongs to an app that is
/// deliberately never activated; an `.activeAlways` tracking area plus hit-testing
/// the row frames MenuView reports works regardless.
final class MenuHostingView: NSHostingView<MenuView> {
    var rowAt: ((CGPoint) -> Int?)?
    var onHover: ((Int?) -> Void)?
    var onClick: ((Int) -> Void)?
    private var trackingArea: NSTrackingArea?

    required init(rootView: MenuView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?(row(at: event)) }
    override func mouseMoved(with event: NSEvent) { onHover?(row(at: event)) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }
    // A menu acts on mouse-up; swallowing mouse-down keeps SwiftUI out of it
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if let index = row(at: event) { onClick?(index) }
    }
    // Right-clicking inside a menu does nothing
    override func rightMouseDown(with event: NSEvent) {}

    private func row(at event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        return rowAt?(CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y))
    }
}
