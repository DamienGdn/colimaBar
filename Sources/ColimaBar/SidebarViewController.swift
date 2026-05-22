// Sources/ColimaBar/SidebarViewController.swift
import AppKit

final class SidebarViewController: NSViewController {
    var onSelectionChange: ((Int) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    private let items: [(icon: String, label: String)] = [
        ("shippingbox.fill",  "Containers"),
        ("internaldrive.fill","Volumes"),
        ("doc.text.fill",     "Compose"),
        ("text.alignleft",    "Logs"),
        ("gear",              "Settings"),
    ]

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.isEditable = false
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = NSColor.controlBackgroundColor
        tableView.style = .sourceList
        tableView.rowHeight = 32

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    func selectItem(at index: Int) {
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
}

extension SidebarViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
}

extension SidebarViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let cell = NSTableCellView()

        let img = NSImageView()
        img.image = NSImage(systemSymbolName: item.icon, accessibilityDescription: item.label)
        img.contentTintColor = .secondaryLabelColor
        img.translatesAutoresizingMaskIntoConstraints = false

        let lbl = NSTextField(labelWithString: item.label)
        lbl.font = .systemFont(ofSize: 13)
        lbl.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(img)
        cell.addSubview(lbl)
        NSLayoutConstraint.activate([
            img.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            img.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            img.widthAnchor.constraint(equalToConstant: 16),
            img.heightAnchor.constraint(equalToConstant: 16),
            lbl.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 6),
            lbl.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            lbl.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let idx = tableView.selectedRow
        guard idx >= 0 else { return }
        onSelectionChange?(idx)
    }
}
