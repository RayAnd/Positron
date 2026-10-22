// SPDX-License-Identifier: MIT
import AppKit
import Foundation

/// Watches every steamapps folder (appmanifest files appear there when a download finishes),
/// drive mounts, and app activation, then calls onChange once things settle.
@MainActor
final class SteamLibraryWatcher {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleChange() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleChange() }
        })
    }

    func watch(_ directories: [URL]) {
        let wanted = Set(directories.map { $0.path(percentEncoded: false) })
        for (path, source) in sources where !wanted.contains(path) {
            source.cancel()
            sources[path] = nil
        }
        for path in wanted where sources[path] == nil {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleChange() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources[path] = source
        }
    }

    private func scheduleChange() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
