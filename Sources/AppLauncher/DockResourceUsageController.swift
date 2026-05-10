import AppKit
import Darwin

// MARK: - UserDefaults

enum DockResourceUsageDefaults {
    static let showOnDockIconKey = "showDockResourceUsage"
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
        // HOST_VM_INFO64_COUNT is not imported into Swift; match mach/vm_statistics.h.
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

// MARK: - Icon composition

private enum DockIconComposer {
    static func image(base: NSImage, cpuPercent: Int, ramPercent: Int) -> NSImage {
        let size = base.size
        guard size.width > 1, size.height > 1 else {
            return base
        }

        return NSImage(size: size, flipped: false) { bounds in
            NSGraphicsContext.current?.imageInterpolation = .high
            base.draw(in: bounds)

            // Use most of the lower half of the canvas so type stays huge after Dock scaling
            // (the previous ~11.5pt cap was effectively invisible at dock size).
            let side = min(bounds.width, bounds.height)
            let barHeight = max(side * 0.58, side * 0.5)
            let barRect = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)

            NSGradient(
                colors: [
                    NSColor.black.withAlphaComponent(0.85),
                    NSColor.black.withAlphaComponent(0.5),
                ],
                atLocations: [0, 1],
                colorSpace: NSColorSpace.deviceRGB
            )?.draw(in: barRect, angle: 90)

            // ~15–20× prior effective size (~11.5pt cap): scale with icon pixel size (typically 512pt).
            let fontSize = max(48, min(side * 0.42, barHeight * 0.82))
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail

            let shadow = NSShadow()
            shadow.shadowBlurRadius = max(4, fontSize * 0.05)
            shadow.shadowOffset = NSSize(width: 0, height: -fontSize * 0.02)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
                .shadow: shadow,
            ]

            let combined = NSAttributedString(
                string: "CPU \(cpuPercent)%   RAM \(ramPercent)%",
                attributes: attrs
            )

            let pad = max(side * 0.03, 10)
            let textRect = NSRect(
                x: barRect.minX + pad,
                y: barRect.minY + pad,
                width: barRect.width - pad * 2,
                height: barRect.height - pad * 2
            )
            combined.draw(with: textRect, options: [.usesLineFragmentOrigin])

            return true
        }
    }

    static func loadBaseIconFromBundle() -> NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        let execURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let bundleURL = execURL.deletingLastPathComponent().appendingPathComponent("AppLauncher_AppLauncher.bundle")
        if let bundle = Bundle(url: bundleURL),
           let url = bundle.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
}

// MARK: - Controller

/// All entry points (`start`, timer, notifications) are scheduled on the main thread / main run loop.
final class DockResourceUsageController {
    private var timer: Timer?
    private var cpuSampler = CPUSampler()
    private var settingObserver: NSObjectProtocol?

    func start() {
        settingObserver = NotificationCenter.default.addObserver(
            forName: .dockResourceUsageSettingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySettings()
        }
        applySettings()
    }

    func applySettings() {
        let enabled = UserDefaults.standard.object(forKey: DockResourceUsageDefaults.showOnDockIconKey) as? Bool ?? true

        timer?.invalidate()
        timer = nil
        cpuSampler = CPUSampler()

        if enabled {
            let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            tick()
        } else {
            NSApp.applicationIconImage = nil
        }
    }

    private lazy var cachedBaseIcon: NSImage = DockIconComposer.loadBaseIconFromBundle()

    private func tick() {
        let enabled = UserDefaults.standard.object(forKey: DockResourceUsageDefaults.showOnDockIconKey) as? Bool ?? true
        guard enabled else {
            return
        }

        let cpu = cpuSampler.usagePercentRounded()
        let ramPercent = MemoryUsageReader.systemUsedFractionAndPercent().percentRounded
        let composed = DockIconComposer.image(base: cachedBaseIcon, cpuPercent: cpu, ramPercent: ramPercent)
        NSApp.applicationIconImage = composed
    }

    deinit {
        if let settingObserver {
            NotificationCenter.default.removeObserver(settingObserver)
        }
        timer?.invalidate()
    }
}
