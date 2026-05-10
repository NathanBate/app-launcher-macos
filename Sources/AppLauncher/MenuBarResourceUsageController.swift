import AppKit
import Darwin

// MARK: - UserDefaults

enum MenuBarResourceUsageDefaults {
    static let showInMenuBarKey = "showMenuBarCPUAndRAM"
    private static let legacyDockPreferenceKey = "showDockResourceUsage"

    /// Copies the old Dock-toggle preference once so upgrades keep the same on/off choice.
    static func migrateFromDockPreferenceIfNeeded() {
        guard UserDefaults.standard.object(forKey: showInMenuBarKey) == nil else {
            return
        }
        if let legacy = UserDefaults.standard.object(forKey: legacyDockPreferenceKey) as? Bool {
            UserDefaults.standard.set(legacy, forKey: showInMenuBarKey)
        }
    }
}

// MARK: - System sampling

private struct CPUSampler {
    private var previousIdle: UInt64 = 0
    private var previousTotal: UInt64 = 0
    private var hasPreviousSample = false

    mutating func usagePercentRounded() -> Int {
        guard let (idle, total) = Self.hostCPUTicks() else {
            return 0
        }

        if !hasPreviousSample {
            previousIdle = idle
            previousTotal = total
            hasPreviousSample = true
            return 0
        }

        let idleDelta = idle &- previousIdle
        let totalDelta = total &- previousTotal
        previousIdle = idle
        previousTotal = total

        guard totalDelta > 0 else {
            return 0
        }

        let usage = 100.0 * (1.0 - Double(idleDelta) / Double(totalDelta))
        return min(100, max(0, Int(round(usage))))
    }

    private static func hostCPUTicks() -> (idle: UInt64, total: UInt64)? {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )
        guard kr == KERN_SUCCESS, let cpuInfo else {
            return nil
        }

        defer {
            let byteCount = vm_size_t(Int(numCpuInfo) * MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), byteCount)
        }

        let summary = cpuInfo.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(numCPUs)) { loads -> (UInt64, UInt64) in
            var idle: UInt64 = 0
            var total: UInt64 = 0
            for i in 0 ..< Int(numCPUs) {
                let ticks = loads[i].cpu_ticks
                idle += UInt64(ticks.2)
                total += UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.2) + UInt64(ticks.3)
            }
            return (idle, total)
        }

        return (idle: summary.0, total: summary.1)
    }
}

private enum MemoryUsageReader {
    static func systemUsedFractionAndPercent() -> (usedFraction: Double, percentRounded: Int) {
        let physical = ProcessInfo.processInfo.physicalMemory
        guard physical > 0 else {
            return (0, 0)
        }

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard kr == KERN_SUCCESS else {
            return (0, 0)
        }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return (0, 0)
        }

        let usedPages = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let usedBytes = usedPages * UInt64(pageSize)
        let fraction = min(1.0, Double(usedBytes) / Double(physical))
        let percent = min(100, max(0, Int(round(fraction * 100))))
        return (fraction, percent)
    }
}

// MARK: - Controller

/// Entry points (`start`, timer, notifications) run on the main thread / main run loop.
final class MenuBarResourceUsageController {
    private var timer: Timer?
    private var cpuSampler = CPUSampler()
    private var settingObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?

    func start() {
        settingObserver = NotificationCenter.default.addObserver(
            forName: .menuBarResourceUsageSettingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySettings()
        }
        applySettings()
    }

    func applySettings() {
        // Clear any legacy Dock overlay from earlier builds.
        NSApp.applicationIconImage = nil

        let enabled = UserDefaults.standard.object(forKey: MenuBarResourceUsageDefaults.showInMenuBarKey) as? Bool ?? true

        timer?.invalidate()
        timer = nil
        cpuSampler = CPUSampler()
        removeStatusItem()

        if enabled {
            installStatusItem()
            let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            tick()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "applauncher_cpu_ram"
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return
        }

        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.title = "CPU —%  RAM —%"
        button.image = nil
        button.imagePosition = .noImage
        button.toolTip = "System CPU and memory usage"
        statusItem = item
    }

    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    /// Screen rect for the CPU/RAM status item, used to ignore “click outside” when that item is hit.
    func clickAwayExclusionScreenFrame() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else {
            return nil
        }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func tick() {
        let enabled = UserDefaults.standard.object(forKey: MenuBarResourceUsageDefaults.showInMenuBarKey) as? Bool ?? true
        guard enabled, let button = statusItem?.button else {
            return
        }

        let cpu = cpuSampler.usagePercentRounded()
        let ramPercent = MemoryUsageReader.systemUsedFractionAndPercent().percentRounded
        let title = String(format: "CPU %d%%  RAM %d%%", cpu, ramPercent)
        button.title = title
        button.setAccessibilityLabel("CPU \(cpu) percent, RAM \(ramPercent) percent")
    }

    deinit {
        if let settingObserver {
            NotificationCenter.default.removeObserver(settingObserver)
        }
        timer?.invalidate()
        removeStatusItem()
    }
}
