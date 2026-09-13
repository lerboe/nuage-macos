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
private class WindowFrameAutosaveView: NSView {

    var name = "main"

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window = window, window.frameAutosaveName != name else { return }

        // setFrameAutosaveName only persists from this point on, so the frame
        // stored by a previous launch has to be applied explicitly.
        window.setFrameAutosaveName(name)
        window.setFrameUsingName(name)
    }

}

private struct WindowFrameAutosave: NSViewRepresentable {

    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = WindowFrameAutosaveView()
        view.name = name
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

}

extension View {

    func persistWindowFrame(_ name: String = "main") -> some View {
        background(WindowFrameAutosave(name: name))
    }

}
