// VoiceOver's view of the Settings window, checked from outside the app. Built and run
// by app/scripts/a11y-test.sh; see there for why this can't live in SelfTest.swift.
//
//   a11y-check --ready <pid>   wait until the app answers accessibility requests
//   a11y-check <pid>           run the checks, one PASS/FAIL line each, exit 1 on any FAIL
//
// It reads what an assistive app reads (AXDescription is the label VoiceOver speaks,
// AXRole says what it is) and presses buttons with AXPress, as VoiceOver's VO-Space does.
import ApplicationServices
import Foundation

struct Node {
    let element: AXUIElement

    func string(_ name: String) -> String { (value(name) as? String) ?? "" }
    var role: String { string(kAXRoleAttribute) }
    var subrole: String { string(kAXSubroleAttribute) }
    var label: String { string(kAXDescriptionAttribute) }
    var title: String { string(kAXTitleAttribute) }
    var text: String { string(kAXValueAttribute) }
    var children: [Node] { ((value(kAXChildrenAttribute) as? [AXUIElement]) ?? []).map(Node.init) }

    /// This node and everything under it, depth first. A scroll bar's parts (arrow and
    /// page buttons with no names) are AppKit's, not this app's, so they're left out.
    var all: [Node] { [self] + (role == kAXScrollBarRole ? [] : children.flatMap(\.all)) }

    func value(_ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &v) == .success ? v : nil
    }

    func press() -> Bool { AXUIElementPerformAction(element, kAXPressAction as CFString) == .success }
}

func wait(seconds: Double = 10, until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        usleep(100_000)
    }
    return condition()
}

let args = CommandLine.arguments
guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("""
        This terminal can't read other apps' accessibility trees. Turn it on in System \
        Settings → Privacy & Security → Accessibility, then run the test again.\n
        """.utf8))
    exit(3)
}
guard let pid = args.last.flatMap(Int32.init) else {
    FileHandle.standardError.write(Data("usage: a11y-check [--ready] <pid>\n".utf8))
    exit(2)
}
let app = Node(element: AXUIElementCreateApplication(pid))

if args.contains("--ready") {
    exit(wait { !app.role.isEmpty } ? 0 : 1)
}

var failures = 0
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    let extra = condition ? "" : detail()
    print("\(condition ? "PASS" : "FAIL")  \(name)\(extra.isEmpty ? "" : " — \(extra)")")
    if !condition { failures += 1 }
}

func settingsContent() -> Node? {
    let windows = ((app.value(kAXWindowsAttribute) as? [AXUIElement]) ?? []).map(Node.init)
    // The scroll area holds every section; the window chrome (close button, …) is outside it
    return windows.first { $0.title.hasSuffix("Settings") }?.all.first { $0.role == kAXScrollAreaRole }
}

guard wait(until: { settingsContent() != nil }), let content = settingsContent() else {
    check("Settings is open", false, "no Settings window")
    exit(1)
}

// MARK: Settings as it opens

var nodes = content.all
let buttons = nodes.filter { $0.role == kAXButtonRole }
let unnamed = buttons.filter { $0.label.isEmpty && $0.title.isEmpty }
check("every button has a name VoiceOver can read", unnamed.isEmpty, "\(unnamed.count) unnamed")

let headings = nodes.filter { $0.role == "AXHeading" }.map(\.label)
check("section titles are headings", ["Accounts", "Add Account", "General"].allSatisfy(headings.contains),
      "headings: \(headings)")

let accounts = buttons.map(\.label).filter { $0.hasPrefix("Edit ") }.map { String($0.dropFirst(5)) }
check("each account has an Edit button named for it", !accounts.isEmpty)
let labels = Set(buttons.map(\.label))
let unlabelled = accounts.filter { account in
    !labels.contains("Delete \(account)")
        || !(labels.contains("Hide \(account) from menu") || labels.contains("Show \(account) in menu"))
}
// Needs accounts to check at all: with none found, this would pass on an empty list
check("each account's hide and delete buttons are named for it", !accounts.isEmpty && unlabelled.isEmpty,
      accounts.isEmpty ? "no accounts found" : "missing for \(unlabelled)")

// Icons are decorative: VoiceOver would read a placeholder letter or an emoji's name
let iconLike = nodes.filter { $0.role == kAXImageRole || ($0.role == kAXStaticTextRole && $0.text.count == 1) }
check("account icons are hidden from VoiceOver", iconLike.isEmpty, "\(iconLike.count) found")

check("the From URL field is a secure field", nodes.contains { $0.subrole == kAXSecureTextFieldSubrole })
check("the From URL field's eye button says what it shows", labels.contains("Show URL"))

// MARK: An edit panel, opened the way VoiceOver would

let firstAccount = accounts.first ?? ""
check("VoiceOver can press Edit", buttons.first { $0.label == "Edit \(firstAccount)" }?.press() == true)
_ = wait { content.all.contains { $0.label == "Show secret" } }
nodes = content.all
// From URL's field and the edit panel's Secret
check("the edit panel's Secret field is a secure field", nodes.filter { $0.subrole == kAXSecureTextFieldSubrole }.count == 2)
let showSecret = nodes.first { $0.role == kAXButtonRole && $0.label == "Show secret" }
check("the Secret field's eye button is named", showSecret != nil)
check("VoiceOver can reveal the secret", showSecret?.press() == true)
check("revealed, the eye button offers to hide it", wait { content.all.contains { $0.label == "Hide secret" } })

// The Manual tab adds a second icon editor. Between the edit panel and this one, both
// icon modes (emoji and favicon) are on screen whatever the first account's icon is.
let manual = content.all.first { $0.role == kAXRadioButtonRole && $0.label == "Manual" }
check("VoiceOver can switch Add Account to Manual", manual?.press() == true)
_ = wait { content.all.filter { $0.label == "Clear icon" }.count >= 2 }
nodes = content.all
let named = Set(nodes.map(\.label))
check("icon editors' Clear buttons are named", nodes.filter { $0.label == "Clear icon" }.count >= 2)
let emojiMode = named.contains("Emoji") && named.contains("Open the emoji picker")
let faviconMode = named.contains("Favicon website") && named.contains("Find favicon")
check("the icon editor's fields and buttons are named", emojiMode || faviconMode,
      "labels: \(named.sorted())")
let stillUnnamed = nodes.filter { $0.role == kAXButtonRole && $0.label.isEmpty && $0.title.isEmpty }
check("every button in the edit panel and Manual form has a name", stillUnnamed.isEmpty, "\(stillUnnamed.count) unnamed")

print(failures == 0 ? "A11Y-TEST PASSED" : "A11Y-TEST FAILED: \(failures) check(s)")
exit(failures == 0 ? 0 : 1)
