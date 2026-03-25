import AudioToolbox
import CoreAudio
import Foundation
import IOBluetooth

@MainActor
final class AudioDeviceManager: ObservableObject {
    @Published var currentDeviceName: String = "None"
    @Published var currentDeviceIsHeadphone: Bool = false
    @Published var isLimiting: Bool = false
    @Published var currentVolume: Float = 0.0

    private var defaultOutputListenerID: AudioObjectPropertyListenerBlock?
    private var volumeListenerID: AudioObjectPropertyListenerBlock?
    private var currentDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var isEnforcing: Bool = false

    // User settings
    @Published var volumeLimit: Float = 0.7 {
        didSet {
            UserDefaults.standard.set(volumeLimit, forKey: "volumeLimit")
            enforceLimit()
        }
    }
    @Published var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
            if isEnabled {
                enforceLimit()
            } else {
                isLimiting = false
            }
        }
    }

    // Devices the user has manually marked as headphones or not
    @Published var deviceOverrides: [String: Bool] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(deviceOverrides) {
                UserDefaults.standard.set(data, forKey: "deviceOverrides")
            }
            refreshCurrentDevice()
        }
    }

    init() {
        volumeLimit = UserDefaults.standard.object(forKey: "volumeLimit") as? Float ?? 0.7
        isEnabled = UserDefaults.standard.object(forKey: "isEnabled") as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: "deviceOverrides"),
           let overrides = try? JSONDecoder().decode([String: Bool].self, from: data) {
            deviceOverrides = overrides
        }

        startListeningForDeviceChanges()
        refreshCurrentDevice()
    }

    nonisolated deinit {
        // Cleanup happens when the app terminates; listeners are automatically removed
    }

    // MARK: - Device Change Listening

    private func startListeningForDeviceChanges() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshCurrentDevice()
            }
        }
        defaultOutputListenerID = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func stopListening() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if let block = defaultOutputListenerID {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
        removeVolumeListener()
    }

    // MARK: - Device Inspection

    func refreshCurrentDevice() {
        let deviceID = getDefaultOutputDevice()
        currentDeviceID = deviceID

        let name = getDeviceName(deviceID)
        let transportType = getTransportType(deviceID)
        let isHeadphone = classifyDevice(name: name, transportType: transportType)

        currentDeviceName = name
        currentDeviceIsHeadphone = isHeadphone
        currentVolume = getVolume(deviceID)

        // Set up volume listener on this device
        removeVolumeListener()
        if isHeadphone && isEnabled {
            addVolumeListener(deviceID)
            enforceLimit()
        } else {
            isLimiting = false
        }
    }

    private func getDefaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr, let cfName = name?.takeRetainedValue() else {
            return "Unknown"
        }
        return cfName as String
    }

    private func getTransportType(_ deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transportType)
        return transportType
    }

    // MARK: - Device Classification

    func classifyDevice(name: String, transportType: UInt32) -> Bool {
        // Check user overrides first
        if let override = deviceOverrides[name] {
            return override
        }

        // Wired headphones — always treat as headphones
        // kAudioDeviceTransportTypeWired is not always available; its raw value is 'wire'
        let kTransportTypeWired: UInt32 = 0x77697265 // 'wire'
        if transportType == kTransportTypeWired {
            return true
        }

        // Built-in speaker — never headphones
        if transportType == kAudioDeviceTransportTypeBuiltIn {
            return false
        }

        // Bluetooth — try to classify via IOBluetooth
        if transportType == kAudioDeviceTransportTypeBluetooth ||
           transportType == kAudioDeviceTransportTypeBluetoothLE {
            return classifyBluetoothDevice(name: name)
        }

        // USB audio (could be a DAC for headphones) — check name heuristics
        if transportType == kAudioDeviceTransportTypeUSB {
            return nameMatchesHeadphone(name)
        }

        return false
    }

    private func classifyBluetoothDevice(name: String) -> Bool {
        // Try IOBluetooth device class lookup
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in devices {
                if device.name == name || device.nameOrAddress == name {
                    let deviceClass = device.classOfDevice
                    // Major device class: bits 12-8
                    let majorClass = (deviceClass >> 8) & 0x1F
                    // Minor device class: bits 7-2
                    let minorClass = (deviceClass >> 2) & 0x3F

                    // Major class 0x04 = Audio/Video
                    if majorClass == 0x04 {
                        // Minor classes for headphones/earbuds:
                        // 0x01 = Wearable Headset
                        // 0x02 = Hands-free
                        // 0x06 = Headphones
                        // 0x07 = Portable Audio (some earbuds report this)
                        let headphoneMinors: Set<UInt32> = [0x01, 0x02, 0x06, 0x07]

                        // Minor classes for speakers:
                        // 0x05 = Loudspeaker
                        if minorClass == 0x05 {
                            return false
                        }
                        if headphoneMinors.contains(minorClass) {
                            return true
                        }
                    }
                }
            }
        }

        // Fallback to name heuristics
        return nameMatchesHeadphone(name)
    }

    private func nameMatchesHeadphone(_ name: String) -> Bool {
        let lower = name.lowercased()
        let headphoneKeywords = [
            "airpods", "headphone", "earphone", "earbud", "earbuds",
            "headset", "in-ear", "over-ear", "on-ear",
            "wh-1000", "wf-1000", "buds", "pods",
            "beats", "airtag" // Beats are always headphones; exclude AirTag false positive below
        ]
        let speakerKeywords = [
            "speaker", "soundbar", "homepod", "echo", "boom",
            "charge", "flip", "megaboom", "wonderboom", "airtag"
        ]

        // If it matches a speaker keyword, not headphones
        for keyword in speakerKeywords {
            if lower.contains(keyword) { return false }
        }

        // If it matches a headphone keyword, it's headphones
        for keyword in headphoneKeywords {
            if lower.contains(keyword) { return true }
        }

        // Unknown BT device — default to not headphones (safe default)
        return false
    }

    // MARK: - Volume Control

    func getVolume(_ deviceID: AudioDeviceID) -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        return volume
    }

    func setVolumeFromUI(_ volume: Float) {
        guard currentDeviceID != kAudioObjectUnknown else { return }
        isEnforcing = true
        setVolume(currentDeviceID, volume: volume)
        currentVolume = volume
        isEnforcing = false
    }

    func setVolume(_ deviceID: AudioDeviceID, volume: Float) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol = volume
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
    }

    private func addVolumeListener(_ deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.onVolumeChanged()
            }
        }
        volumeListenerID = block

        AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
    }

    private func removeVolumeListener() {
        guard currentDeviceID != kAudioObjectUnknown, let block = volumeListenerID else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(currentDeviceID, &address, DispatchQueue.main, block)
        volumeListenerID = nil
    }

    private func onVolumeChanged() {
        currentVolume = getVolume(currentDeviceID)
        enforceLimit()
    }

    func enforceLimit() {
        guard isEnabled, currentDeviceIsHeadphone, !isEnforcing else {
            if !isEnabled || !currentDeviceIsHeadphone {
                isLimiting = false
            }
            return
        }

        isEnforcing = true
        defer { isEnforcing = false }

        let vol = getVolume(currentDeviceID)
        currentVolume = vol

        if vol > volumeLimit + 0.005 {
            setVolume(currentDeviceID, volume: volumeLimit)
            currentVolume = volumeLimit
            isLimiting = true
        } else {
            isLimiting = vol >= volumeLimit - 0.02
        }
    }
}
