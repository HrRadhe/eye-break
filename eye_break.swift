#!/usr/bin/swift

// eye_break.swift — full-screen eye break overlay
// Usage: swift eye_break.swift /path/to/eye_break.html

import Cocoa
import WebKit

// ── locate HTML ──────────────────────────────────────────────
let args = CommandLine.arguments
let htmlPath: String
if args.count > 1 {
    htmlPath = args[1]
} else {
    let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent().path
    htmlPath = "\(scriptDir)/eye_break.html"
}

guard FileManager.default.fileExists(atPath: htmlPath),
      let htmlString = try? String(contentsOfFile: htmlPath, encoding: .utf8) else {
    print("❌  Could not read: \(htmlPath)")
    exit(1)
}

// ── message handler ──────────────────────────────────────────
class CloseHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        NSApp.terminate(nil)
    }
}

// ── AppDelegate ──────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    let closeHandler = CloseHandler()
    let htmlString: String
    let htmlDir: URL

    init(htmlString: String, htmlDir: URL) {
        self.htmlString = htmlString
        self.htmlDir    = htmlDir
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame  = screen.frame

        // WKWebView config
        let config = WKWebViewConfiguration()
        config.userContentController.add(closeHandler, name: "close")

        // Inject JS shim: intercept window.close() -> message handler
        let shim = WKUserScript(
            source: """
                window.close = function() {
                    window.webkit.messageHandlers.close.postMessage('close');
                };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(shim)

        // Enable JS (modern API)
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pagePrefs

        // Build window
        window = NSWindow(
            contentRect: frame,
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false,
            screen:      screen
        )
        window.level              = .screenSaver
        window.backgroundColor    = .black
        window.isOpaque           = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        webView = WKWebView(frame: CGRect(origin: .zero, size: frame.size),
                            configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        window.contentView = webView

        // Load HTML as string (avoids /tmp sandboxing issues)
        webView.loadHTMLString(htmlString, baseURL: htmlDir)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Hard fallback — terminate after 25s no matter what
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        return true
    }
}

// ── Run ──────────────────────────────────────────────────────
let htmlDir    = URL(fileURLWithPath: htmlPath).deletingLastPathComponent()
let app        = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate   = AppDelegate(htmlString: htmlString, htmlDir: htmlDir)
app.delegate   = delegate
app.run()