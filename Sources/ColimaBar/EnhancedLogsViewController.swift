// Sources/ColimaBar/EnhancedLogsViewController.swift
import AppKit
import ColimaBarCore

final class EnhancedLogsViewController: NSViewController {
    // UI
    private let containerPicker = NSPopUpButton()
    private let searchField = NSSearchField()
    private let explainButton = NSButton(title: "Expliquer l'erreur", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private var textView: NSTextView!

    // State
    private var containers: [DockerContainer] = []
    private var allLines: [String] = []
    private var streamProcess: Process?
    private let dockerPath = "/opt/homebrew/bin/docker"

    private var currentContainer: DockerContainer? {
        let idx = containerPicker.indexOfSelectedItem
        guard idx >= 0 && idx < containers.count else { return nil }
        return containers[idx]
    }

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    // MARK: - Public

    func updateContainers(_ all: [DockerContainer]) {
        if !isViewLoaded { _ = view }
        let running = all.filter { $0.isRunning }
        containers = running
        let selected = currentContainer?.name
        containerPicker.removeAllItems()
        containerPicker.addItems(withTitles: running.isEmpty ? ["—"] : running.map { $0.name })
        if let sel = selected, let idx = running.firstIndex(where: { $0.name == sel }) {
            containerPicker.selectItem(at: idx)
        } else if !running.isEmpty {
            startStreaming()
        }
    }

    func showLogs(for containerName: String) {
        if let idx = containers.firstIndex(where: { $0.name == containerName }) {
            containerPicker.selectItem(at: idx)
            startStreaming()
        }
    }

    // MARK: - Private

    private func buildUI() {
        containerPicker.target = self
        containerPicker.action = #selector(containerChanged)
        containerPicker.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Filtrer les logs…"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        explainButton.bezelStyle = .rounded
        explainButton.target = self
        explainButton.action = #selector(explainError)
        explainButton.translatesAutoresizingMaskIntoConstraints = false

        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearLogs)
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.backgroundColor = NSColor(white: 0.1, alpha: 1)
        tv.textColor = .white
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 4, height: 4)
        textView = tv

        scrollView.documentView = tv
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        for sub in [containerPicker, searchField, explainButton, clearButton, scrollView] as [NSView] {
            view.addSubview(sub)
        }

        NSLayoutConstraint.activate([
            containerPicker.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            containerPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            containerPicker.widthAnchor.constraint(equalToConstant: 180),

            searchField.centerYAnchor.constraint(equalTo: containerPicker.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: containerPicker.trailingAnchor, constant: 8),
            searchField.widthAnchor.constraint(equalToConstant: 200),

            clearButton.centerYAnchor.constraint(equalTo: containerPicker.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: explainButton.leadingAnchor, constant: -8),
            clearButton.widthAnchor.constraint(equalToConstant: 60),

            explainButton.centerYAnchor.constraint(equalTo: containerPicker.centerYAnchor),
            explainButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            explainButton.widthAnchor.constraint(equalToConstant: 140),

            scrollView.topAnchor.constraint(equalTo: containerPicker.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func startStreaming() {
        stopStreaming()
        allLines = []
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        guard let container = currentContainer else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: dockerPath)
        proc.arguments = ["logs", "--tail", "200", "-f", container.name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.appendRaw(str) }
        }
        try? proc.run()
        streamProcess = proc
    }

    private func stopStreaming() {
        streamProcess?.terminate()
        streamProcess?.waitUntilExit()
        streamProcess = nil
    }

    private func appendRaw(_ text: String) {
        let newLines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        allLines.append(contentsOf: newLines)
        applyFilter(searchField.stringValue)
    }

    private func applyFilter(_ query: String) {
        let filtered = LogFilter.apply(lines: allLines, query: query)
        let storage = NSMutableAttributedString()
        for line in filtered {
            let color: NSColor
            switch line.level {
            case .error:   color = .systemRed
            case .warning: color = .systemOrange
            case .success: color = .systemGreen
            case .normal:  color = .white
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: color,
            ]
            storage.append(NSAttributedString(string: line.text + "\n", attributes: attrs))
        }
        textView.textStorage?.setAttributedString(storage)
        textView.scrollToEndOfDocument(nil)
    }

    @objc private func containerChanged() { startStreaming() }

    @objc private func clearLogs() {
        allLines = []
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

    @objc private func explainError() {
        let errorLines = LogFilter.extractErrorLines(from: allLines, max: 20)
        guard !errorLines.isEmpty else { return }
        let joined = errorLines.joined(separator: "\n")
        let prompt = "Les erreurs suivantes sont apparues dans mes logs Docker :\n\n\(joined)\n\nPeux-tu m'expliquer ces erreurs ?"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }
}

extension EnhancedLogsViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }
}
