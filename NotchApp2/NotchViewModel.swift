import SwiftUI

@MainActor
@Observable
final class NotchViewModel {
    var isMouseInside = false
    var isElevated = false
    var isQuickPeeking = false
    var isExpanded = false
    var isPinned = false  // prevents auto-collapse (dropdown open, pin button, etc.)
    var isRenamingView = false
    var renameViewName = ""
    var renameViewFieldScreenRect: CGRect = .zero

    var notchWidth: CGFloat = 0
    var notchHeight: CGFloat = 0
    let viewManager = ViewManager()

    // Expanded panel dimensions
    var screenWidth: CGFloat = 0
    var expandedWidth: CGFloat { screenWidth * 0.54 }
    var expandedHeight: CGFloat { 300 }

    private let log = FileLog()
    private var elevateTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    private static let peekAnim: Animation = .interpolatingSpring(
        duration: 0.35, bounce: 0.05
    )
    private static let elevateAnim: Animation = .interpolatingSpring(
        duration: 0.35, bounce: 0.45
    )

    func mouseEntered() {
        log.write("VM: mouseEntered")
        collapseTask?.cancel()
        isMouseInside = true

        withAnimation(Self.elevateAnim) {
            isElevated = true
        }

        elevateTask?.cancel()
        elevateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, isMouseInside else { return }
            log.write("VM: quickPeeking")
            withAnimation(Self.peekAnim) {
                isQuickPeeking = true
            }
        }
    }

    func mouseExited() {
        log.write("VM: mouseExited")
        elevateTask?.cancel()
        isMouseInside = false

        guard !isPinned else { return }

        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, !isPinned, !isMouseInside else { return }
            collapse()
        }
    }

    func clicked() {
        log.write("VM: clicked, expanding")
        collapseTask?.cancel()
        withAnimation(Self.peekAnim) {
            isExpanded = true
            isElevated = true
            isQuickPeeking = true
        }
    }

    func collapse() {
        log.write("VM: collapsing")
        withAnimation(Self.elevateAnim) {
            isExpanded = false
            isQuickPeeking = false
            isElevated = false
            isPinned = false
        }
    }
}
