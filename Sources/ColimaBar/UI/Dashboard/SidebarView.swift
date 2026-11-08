import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: AppStore

    private struct Item { let section: DashboardSection; let icon: String; let label: String; let count: Int? }

    private var dockerItems: [Item] {
        [
            Item(section: .compose, icon: "square.stack.3d.up.fill", label: "Compose", count: store.groups.stacks.count),
            Item(section: .containers, icon: "shippingbox.fill", label: "Containers", count: store.state.containers.count),
            Item(section: .images, icon: "photo.stack.fill", label: "Images", count: nil),
            Item(section: .volumes, icon: "internaldrive.fill", label: "Volumes", count: nil),
            Item(section: .networks, icon: "network", label: "Networks", count: nil),
        ]
    }

    private var colimaItems: [Item] {
        [
            Item(section: .logs, icon: "text.alignleft", label: "Logs", count: nil),
            Item(section: .snapshots, icon: "camera.viewfinder", label: "Snapshots", count: nil),
        ]
    }

    private var selection: Binding<DashboardSection?> {
        Binding(get: { store.section },
                set: { if let s = $0 { store.route = .section; store.section = s } })
    }

    var body: some View {
        List(selection: selection) {
            Section("Docker") { ForEach(dockerItems, id: \.section) { row($0) } }
            Section("Colima") { ForEach(colimaItems, id: \.section) { row($0) } }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .frame(width: 18)
                .foregroundColor(store.section == item.section ? .tkAccent : .tkText2)
            Text(item.label).foregroundColor(.tkText)
            Spacer(minLength: 4)
            if let n = item.count {
                Text("\(n)")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundColor(.tkText2)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(Color.tkSurface2))
            }
        }
        .tag(item.section)
    }
}
