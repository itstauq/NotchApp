import SwiftUI

struct ViewSwitcher: View {
    var viewManager: ViewManager
    var vm: NotchViewModel

    var body: some View {
        Menu {
            ForEach(viewManager.views) { view in
                Button {
                    viewManager.select(view)
                } label: {
                    HStack {
                        Image(systemName: view.icon)
                        Text(view.name)
                        if view.id == viewManager.selectedViewID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button {
                viewManager.addView(name: "New View")
            } label: {
                Label("Add View", systemImage: "plus")
            }

            if let view = viewManager.selectedView {
                Button {
                    vm.renameViewName = view.name
                    vm.isRenamingView = true
                } label: {
                    Label("Rename View", systemImage: "pencil")
                }

                Menu {
                    ForEach(ViewManager.availableIcons, id: \.self) { icon in
                        Button {
                            viewManager.setIcon(view, to: icon)
                        } label: {
                            HStack {
                                Image(systemName: icon)
                                Text(icon.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ").capitalized)
                                if icon == view.icon {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Icon", systemImage: "paintpalette")
                }

                if viewManager.views.count > 1 {
                    Button(role: .destructive) {
                        viewManager.removeView(view)
                    } label: {
                        Label("Delete \"\(view.name)\"", systemImage: "trash")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let view = viewManager.selectedView {
                    Image(systemName: view.icon)
                        .font(.system(size: 10))
                    Text(view.name)
                        .font(.system(size: 12, weight: .medium))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            vm.isViewMenuOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            vm.isViewMenuOpen = false
        }
    }
}
