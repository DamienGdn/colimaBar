import AppKit
import Foundation

final class LogsWindowController: NSWindowController {

    private var containerLabel: NSTextField!
    private var followBtn:      NSButton!
    private var clearBtn:       NSButton!
    private var scrollView:     NSScrollView!
    private var textView:       NSTextView!

    private var process:          Process?
    private var isFollowing       = false
    private var lineCount         = 0
    private let maxLines          = 5000
    private let trimLines         = 1000
    private var dockerPath        = "/opt/homebrew/bin/docker"
    private var currentContainer  = ""

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 450),
            styleMask:   [.titled, .closable, .resizable, .miniaturizable],
            backing:     .buffered,
            defer:       false
        )
        window.center()
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let window else { return }
        let cv = NSView()
        window.contentView = cv

        containerLabel = NSTextField(labelWithString: "")
        containerLabel.font      = .boldSystemFont(ofSize: 13)
        containerLabel.textColor = .labelColor
        containerLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(containerLabel)

        followBtn = NSButton(title: "■ Stop", target: self, action: #selector(toggleFollow))
        followBtn.bezelStyle  = .rounded
        followBtn.controlSize = .small
        followBtn.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(followBtn)

        clearBtn = NSButton(title: "Clear", target: self, action: #selector(clearAction))
        clearBtn.bezelStyle  = .rounded
        clearBtn.controlSize = .small
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(clearBtn)

        textView = NSTextView()
        textView.isEditable   = false
        textView.isSelectable = true
        textView.font         = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor    = NSColor(white: 0.1, alpha: 1)
        textView.textColor          = .white
        textView.autoresizingMask   = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 4)

        scrollView = NSScrollView()
        scrollView.documentView        = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.borderType          = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(scrollView)

        NSLayoutConstraint.activate([
            containerLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 8),
            containerLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            containerLabel.trailingAnchor.constraint(lessThanOrEqualTo: followBtn.leadingAnchor, constant: -8),
            containerLabel.centerYAnchor.constraint(equalTo: followBtn.centerYAnchor),

            followBtn.topAnchor.constraint(equalTo: cv.topAnchor, constant: 8),
            followBtn.trailingAnchor.constraint(equalTo: clearBtn.leadingAnchor, constant: -6),

            clearBtn.topAnchor.constraint(equalTo: cv.topAnchor, constant: 8),
            clearBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: containerLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        window.delegate = self
    }

    func show(containerName: String, dockerPath: String) {
        stopStreaming()
        self.dockerPath       = dockerPath
        self.currentContainer = containerName
        window?.title         = "ColimaBar — \(containerName) logs"
        containerLabel.stringValue = containerName
        clearLogs()
        startStreaming()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func startStreaming() {
        isFollowing     = true
        followBtn.title = "■ Stop"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: dockerPath)
        proc.arguments     = ["logs", "--tail", "200", "-f", currentContainer]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.appendText(str) }
        }

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isFollowing      = false
                self?.followBtn?.title = "▶ Follow"
                if let data = try? pipe.fileHandleForReading.readToEnd(),
                   !data.isEmpty,
                   let str = String(data: data, encoding: .utf8) {
                    self?.appendText(str)
                }
            }
        }

        do {
            try proc.run()
            self.process = proc
        } catch {
            appendText("Error starting docker logs: \(error.localizedDescription)\n")
            isFollowing     = false
            followBtn.title = "▶ Follow"
        }
    }

    private func stopStreaming() {
        process?.terminate()
        process?.waitUntilExit()
        process        = nil
        isFollowing    = false
        followBtn?.title = "▶ Follow"
    }

    private func appendText(_ text: String) {
        let newLines = text.components(separatedBy: .newlines).count
        lineCount += newLines

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white,
        ]
        textView.textStorage?.append(NSAttributedString(string: text, attributes: attrs))

        if lineCount > maxLines { trimOldLines() }
        if isFollowing { textView.scrollToEndOfDocument(nil) }
    }

    private func trimOldLines() {
        guard let storage = textView.textStorage else { return }
        var lines = storage.string.components(separatedBy: .newlines)
        guard lines.count > maxLines else { return }
        lines.removeFirst(trimLines)
        lineCount = lines.count
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white,
        ]
        storage.setAttributedString(NSAttributedString(string: lines.joined(separator: "\n"), attributes: attrs))
    }

    private func clearLogs() {
        textView?.textStorage?.setAttributedString(NSAttributedString(string: ""))
        lineCount = 0
    }

    @objc private func toggleFollow() {
        if isFollowing { stopStreaming() } else { startStreaming() }
    }

    @objc private func clearAction() { clearLogs() }
}

extension LogsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        stopStreaming()
    }
}
