// Sources/ColimaBar/EnhancedLogsViewController.swift
import AppKit
import ColimaBarCore

final class EnhancedLogsViewController: NSViewController {
    // UI
    private let containerPicker = NSPopUpButton()
    private let searchField = NSSearchField()
    private let explainButton = NSButton(title: "", target: nil, action: nil)
    private let clearButton = NSButton(title: "", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private var card: ThemedView!
    private var textView: NSTextView!

    // State
    private var containers: [DockerContainer] = []
    private var allLines: [String] = []
    private var streamProcess: Process?
    /// Whether the streamed container was running when the stream started.
    private var streamedRunning: Bool?
    private let dockerPath = "/opt/homebrew/bin/docker"

    private var currentContainer: DockerContainer? {
        let idx = containerPicker.indexOfSelectedItem
        guard idx >= 0 && idx < containers.count else { return nil }
        return containers[idx]
    }

    override func loadView() { view = ThemedView(fill: Theme.Tokens.bg) }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    // MARK: - Public

    /// Lists every container (running first): `docker logs` also works on exited ones.
    func updateContainers(_ all: [DockerContainer]) {
        if !isViewLoaded { _ = view }
        let targets = LogTargets.order(all)
        let selected = currentContainer
        containers = targets
        containerPicker.removeAllItems()
        containerPicker.addItems(withTitles: targets.isEmpty ? ["—"] : targets.map { c in
            c.isRunning ? c.name : "\(c.name) (\(L.t("arrêté", "stopped")))"
        })
        if let sel = selected, let idx = targets.firstIndex(where: { $0.name == sel.name }) {
            containerPicker.selectItem(at: idx)
            // A stream started on a stopped container has ended: follow again once it runs.
            if targets[idx].isRunning && streamedRunning == false { startStreaming() }
        } else if !targets.isEmpty {
            startStreaming()
        } else {
            stopStreaming()
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

        searchField.placeholderString = L.t("Filtrer les logs…", "Filter logs…")
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        explainButton.title = L.t("Expliquer l'erreur", "Explain error")
        explainButton.bezelStyle = .rounded
        explainButton.target = self
        explainButton.action = #selector(explainError)
        explainButton.translatesAutoresizingMaskIntoConstraints = false

        clearButton.title = L.t("Effacer", "Clear")
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearLogs)
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.drawsBackground = false
        tv.textColor = Theme.Tokens.text
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 4, height: 4)
        textView = tv

        scrollView.documentView = tv
        scrollView.hasVerticalScroller = true
        card = Theme.card(wrapping: scrollView)

        for sub in [containerPicker, searchField, explainButton, clearButton, card] as [NSView] {
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

            card.topAnchor.constraint(equalTo: containerPicker.bottomAnchor, constant: 10),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    private func startStreaming() {
        stopStreaming()
        allLines = []
        textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        streamedRunning = nil
        guard let container = currentContainer else { return }
        streamedRunning = container.isRunning

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
            case .error:   color = Theme.Tokens.red
            case .warning: color = Theme.Tokens.amber
            case .success: color = Theme.Tokens.green
            case .normal:  color = Theme.Tokens.text
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
