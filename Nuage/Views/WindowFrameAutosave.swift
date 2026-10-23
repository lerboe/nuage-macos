//
//  WindowFrameAutosave.swift
//  Nuage
//

import SwiftUI
import AppKit

/// Restores and persists the window frame across launches.
///
/// SwiftUI's `WindowGroup` never sets a frame autosave name, so AppKit does
/// not remember the size the window was left at. Setting one hands the job
/// back to AppKit, which stores the frame in UserDefaults for us.
private final class WindowFrameAutosaveView: NSView {

    private let name: String
    private var didRestore = false

    init(name: String) {
        self.name = name
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard !didRestore, let window = window else { return }
        didRestore = true

        // Already persisting, restoring again would only fight the user.
        guard window.frameAutosaveName != name else { return }

        // Fails when another window already holds the name, e.g. a second
        // window opened with ⌘N. That window just doesn't persist its frame.
        guard window.setFrameAutosaveName(name) else { return }

        // setFrameAutosaveName only persists from this point on, so the frame
        // stored by a previous launch has to be applied explicitly.
        window.setFrameUsingName(name)
    }

}

private struct WindowFrameAutosave: NSViewRepresentable {

    let name: String

    func makeNSView(context: Context) -> NSView {
        WindowFrameAutosaveView(name: name)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

}

extension View {

    func persistWindowFrame() -> some View {
        background(WindowFrameAutosave(name: "main"))
    }

}
