import AppKit
import CoreAudio
import Darwin
import Observation

@MainActor
@Observable
final class PlaybackMonitor {
    static let ignoredBundleIDsKey = "ignoredAudioBundleIDs"

    private(set) var playingApps: [String] = []

    var playingApp: String? {
        playingApps.first
    }

    @ObservationIgnored var ignoredBundleIDs: Set<String>
    @ObservationIgnored var onTick: ((String?) -> Void)?
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let ownPID = getpid()
    @ObservationIgnored private var processes: [AudioObjectID: AudioProcess] = [:]
    @ObservationIgnored private var listBlock: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(ignoredBundleIDs: Set<String>, pollInterval: Duration = .seconds(1)) {
        self.ignoredBundleIDs = ignoredBundleIDs
        self.pollInterval = pollInterval
    }

    static func savedIgnoreList(in defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: ignoredBundleIDsKey) ?? AppNaming.defaultIgnoredBundleIDs)
    }

    func start() {
        guard pollTask == nil else { return }
        refreshProcessList()
        listenForProcessListChanges()
        pollTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let listBlock {
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listBlock)
        }
        listBlock = nil
    }

    private func poll() {
        let active = processes
            .filter { id, process in
                !AppNaming.isIgnored(process, ownPID: ownPID, ignoredBundleIDs: ignoredBundleIDs)
                    && Self.isRunningOutput(id)
            }
            .map { AppNaming.displayName(for: $0.value, appNameForBundleID: Self.runningAppName) }
        playingApps = Array(Set(active)).sorted()
        onTick?(playingApp)
    }

    private func listenForProcessListChanges() {
        guard listBlock == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refreshProcessList()
            }
        }
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        listBlock = block
    }

    private func refreshProcessList() {
        let ids = Set(Self.processObjectIDs())
        processes = processes.filter { ids.contains($0.key) }
        for id in ids where processes[id] == nil {
            let pid = Self.pid(of: id)
            processes[id] = AudioProcess(
                pid: pid,
                bundleID: Self.bundleID(of: id),
                appName: NSRunningApplication(processIdentifier: pid)?.localizedName,
                processName: Self.processName(of: pid)
            )
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func processObjectIDs() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func pid(of object: AudioObjectID) -> pid_t {
        var address = address(kAudioProcessPropertyPID)
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return value
    }

    private static func bundleID(of object: AudioObjectID) -> String {
        var address = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() else { return "" }
        return string as String
    }

    private static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = address(kAudioProcessPropertyIsRunningOutput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return value != 0
    }

    private static func processName(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func runningAppName(for bundleID: String) -> String? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
    }
}
