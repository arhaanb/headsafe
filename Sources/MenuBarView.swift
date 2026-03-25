import SwiftUI

struct MenuBarView: View {
    @ObservedObject var audioManager: AudioDeviceManager
    @State private var showDeviceList = false

    private var limitPercent: Int {
        Int(audioManager.volumeLimit * 100)
    }

    private var currentPercent: Int {
        Int(audioManager.currentVolume * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "headphones.circle.fill")
                    .font(.title2)
                    .foregroundStyle(audioManager.isEnabled ? .blue : .secondary)
                Text("HeadSafe")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $audioManager.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }

            Divider()

            // Current device
            VStack(alignment: .leading, spacing: 4) {
                Text("Output Device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Image(systemName: deviceIcon)
                        .foregroundStyle(audioManager.currentDeviceIsHeadphone ? .blue : .secondary)
                    Text(audioManager.currentDeviceName)
                        .font(.system(.body, design: .rounded))
                    Spacer()
                    if audioManager.currentDeviceIsHeadphone {
                        Text("Protected")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    } else {
                        Text("Inactive")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
            }

            // Volume control
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Volume")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(currentPercent)%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(audioManager.isLimiting ? .orange : .primary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { audioManager.currentVolume },
                            set: { newValue in
                                let clamped = audioManager.currentDeviceIsHeadphone && audioManager.isEnabled
                                    ? min(newValue, audioManager.volumeLimit)
                                    : newValue
                                audioManager.setVolumeFromUI(clamped)
                            }
                        ),
                        in: 0.0...1.0,
                        step: 0.05
                    )
                    .controlSize(.small)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Volume limit slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Volume Limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(limitPercent)%")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                }

                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $audioManager.volumeLimit, in: 0.0...1.0, step: 0.05)
                        .controlSize(.small)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Device override
            Button {
                showDeviceList.toggle()
            } label: {
                HStack {
                    Image(systemName: "list.bullet")
                    Text("Device Overrides")
                    Spacer()
                    Image(systemName: showDeviceList ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if showDeviceList {
                DeviceOverrideView(audioManager: audioManager)
            }

            Divider()

            // Footer
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)

                Spacer()

                if audioManager.isLimiting {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                        Text("Limiting")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var deviceIcon: String {
        if audioManager.currentDeviceIsHeadphone {
            return "headphones"
        }
        if audioManager.currentDeviceName.lowercased().contains("bluetooth") ||
           audioManager.currentDeviceName.lowercased().contains("airpods") {
            return "wave.3.right"
        }
        return "speaker.wave.2"
    }
}

struct DeviceOverrideView: View {
    @ObservedObject var audioManager: AudioDeviceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mark devices as headphones or not. This overrides auto-detection.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if audioManager.deviceOverrides.isEmpty {
                Text("No overrides set. Devices are auto-detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(audioManager.deviceOverrides.keys.sorted()), id: \.self) { device in
                    HStack {
                        Image(systemName: audioManager.deviceOverrides[device] == true ? "headphones" : "speaker.wave.2")
                            .font(.caption)
                            .foregroundStyle(audioManager.deviceOverrides[device] == true ? .blue : .secondary)
                        Text(device)
                            .font(.caption)
                        Spacer()
                        Button {
                            audioManager.deviceOverrides.removeValue(forKey: device)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    audioManager.deviceOverrides[audioManager.currentDeviceName] = true
                } label: {
                    Label("Mark as Headphone", systemImage: "headphones")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(audioManager.currentDeviceName == "None")

                Button {
                    audioManager.deviceOverrides[audioManager.currentDeviceName] = false
                } label: {
                    Label("Not Headphone", systemImage: "speaker.wave.2")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(audioManager.currentDeviceName == "None")
            }
        }
    }
}
