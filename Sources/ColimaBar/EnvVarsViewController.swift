import AppKit
import ColimaBarCore

final class EnvVarsViewController: NSViewController {
    var containerName: String = ""
    private var envVars: [(key: String, value: String)] = []

    private var headerLbl:   NSTextField!
    private var scrollView:  NSScrollView!
    private var tableView:   NSTableView!
    private var statusLbl:   NSTextField!
    private var copyAllBtn:  NSButton!

    func loadEnvVars(_ vars: [String]) {
        envVars = vars.map { s -> (String, String) in
            if let idx = s.firstIndex(of: "=") {
                return (String(s[..<idx]), String(s[s.index(after: idx)...]))
            }
            return (s, "")
        }
        tableView?.reloadData()
        statusLbl?.stringValue = envVars.isEmpty ? L.t("Aucune variable", "No env vars") : ""
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 320))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        statusLbl.stringValue = L.t("Chargement…", "Loading…")
    }

    private func buildUI() {
        headerLbl = NSTextField(labelWithString: containerName)
        headerLbl.font      = .boldSystemFont(ofSize: 13)
        headerLbl.textColor = .labelColor
        headerLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLbl)

        tableView = NSTableView()
        tableView.style      = .plain
        tableView.rowHeight  = 20
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.headerView = NSTableHeaderView()

        for (id, title, width) in [
            ("key",   L.t("Clé", "Key"),       180.0),
            ("value", L.t("Valeur", "Value"),   280.0),
        ] as [(String, String, CGFloat)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title; col.width = width; col.minWidth = 40
            tableView.addTableColumn(col)
        }

        scrollView = NSScrollView()
        scrollView.documentView        = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.borderType          = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        statusLbl = NSTextField(labelWithString: "")
        statusLbl.font        = .systemFont(ofSize: 11)
        statusLbl.textColor   = .secondaryLabelColor
        statusLbl.alignment   = .center
        statusLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLbl)

        copyAllBtn = NSButton(title: L.t("Copier tout", "Copy all"),
                              target: self, action: #selector(copyAll))
        copyAllBtn.bezelStyle  = .rounded
        copyAllBtn.controlSize = .small
        copyAllBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(copyAllBtn)

        NSLayoutConstraint.activate([
            headerLbl.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            headerLbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            headerLbl.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: headerLbl.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: copyAllBtn.topAnchor, constant: -6),

            statusLbl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLbl.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            copyAllBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            copyAllBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
        ])
    }

    @objc private func copyAll() {
        let text = envVars.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension EnvVarsViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { envVars.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id  = tableColumn?.identifier.rawValue ?? ""
        let cid = NSUserInterfaceItemIdentifier("env-\(id)")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cid, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cid
            let tf = NSTextField(labelWithString: "")
            tf.font          = .monospacedSystemFont(ofSize: 11, weight: .regular)
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf); cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let pair = envVars[row]
        switch id {
        case "key":
            cell.textField?.stringValue = pair.key
            cell.textField?.textColor   = .labelColor
        case "value":
            cell.textField?.stringValue = pair.value
            cell.textField?.textColor   = .secondaryLabelColor
        default: break
        }
        return cell
    }
}
