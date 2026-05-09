import AppKit
import Combine

/// Routes arrow keys while the launcher window is key; returns `nil` to consume the event.
final class LauncherKeyMonitor: ObservableObject {
    var onKeyDown: ((NSEvent) -> NSEvent?)?

    private var monitor: Any?

    func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let handler = self.onKeyDown else {
                return event
            }
            return handler(event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        stop()
    }
}
