import AppKit
import Foundation

private enum OverlayCommand: String {
    case showViolation
    case hide
    case exit
}

private final class OverlayController {
    private var windows: [NSWindow] = []

    func showViolation() {
        hide()

        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        windows = screens.map { screen in
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.72)
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.contentView = makeViolationView(frame: screen.frame)
            window.orderFrontRegardless()
            return window
        }

        NSApp.activate(ignoringOtherApps: true)
        print("overlay:showingViolation")
        fflush(stdout)
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        print("overlay:hidden")
        fflush(stdout)
    }

    private func makeViolationView(frame: NSRect) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "⚡ FARADAY VIOLATION")
        title.font = .systemFont(ofSize: 44, weight: .heavy)
        title.textColor = .systemYellow
        title.alignment = .center

        let message = NSTextField(labelWithString: "Phone beacon is inside forbidden proximity.")
        message.font = .systemFont(ofSize: 26, weight: .semibold)
        message.textColor = .white
        message.alignment = .center

        let instruction = NSTextField(labelWithString: "Move phone to acceptable location to continue focus session.")
        instruction.font = .systemFont(ofSize: 20, weight: .medium)
        instruction.textColor = .lightGray
        instruction.alignment = .center

        for field in [title, message, instruction] {
            field.maximumNumberOfLines = 0
            stack.addArrangedSubview(field)
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 48),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -48)
        ])

        return view
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    let overlay = OverlayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        print("Faraday overlay helper ready")
        fflush(stdout)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let line = readLine() {
                guard let command = OverlayCommand(rawValue: line.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    continue
                }

                DispatchQueue.main.async {
                    guard let self else { return }
                    switch command {
                    case .showViolation:
                        self.overlay.showViolation()
                    case .hide:
                        self.overlay.hide()
                    case .exit:
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
