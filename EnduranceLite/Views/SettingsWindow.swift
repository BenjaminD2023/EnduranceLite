import SwiftUI

struct SettingsWindow: View {
    @EnvironmentObject private var engine: EnduranceEngine

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 34)
                .padding(.top, 22)
                .padding(.bottom, 18)

            triggerRow
                .padding(.horizontal, 34)
                .padding(.bottom, 18)

            HStack(alignment: .top, spacing: 32) {
                featureList
                    .frame(width: 292)
                featureDetail
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 34)
            .frame(maxHeight: .infinity, alignment: .top)

            footer
                .padding(.horizontal, 34)
                .padding(.vertical, 14)
        }
        .frame(width: 900, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            EnduranceMark()
                .frame(width: 72, height: 46)

            Text("EnduranceLite")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Color.primary.opacity(0.82))

            Spacer()

            Toggle(isOn: Binding(
                get: { engine.isLowPowerActive },
                set: { engine.userToggleLowPower($0) }
            )) {
                Text(engine.isLowPowerActive ? "Low power mode is enabled" : "Low power mode is off")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .toggleStyle(.checkbox)
            .padding(.top, 6)
        }
    }

    private var triggerRow: some View {
        HStack(spacing: 10) {
            Text("Start low power mode:")
                .font(.system(size: 13))

            Picker("", selection: $engine.settings.startMode) {
                ForEach(StartMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 118)

            Text("at \(Int(engine.settings.thresholdPercent))%")
                .font(.system(size: 13))
                .frame(width: 64, alignment: .leading)

            VStack(spacing: 4) {
                Slider(value: $engine.settings.thresholdPercent, in: 10...100, step: 10)
                    .frame(width: 280)
                HStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { _ in
                        Circle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 3, height: 3)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: 280)
            }

            Spacer(minLength: 0)
        }
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            ForEach(PowerFeature.all) { feature in
                FeatureRow(
                    feature: feature,
                    isSelected: engine.selectedFeature == feature.id,
                    isOn: engine.settings.isEnabled(feature.id)
                ) {
                    engine.selectedFeature = feature.id
                } onToggle: { newValue in
                    engine.selectedFeature = feature.id
                    engine.setFeature(feature.id, enabled: newValue)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
        .frame(height: 318)
    }

    private var featureDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(PowerFeature.feature(for: engine.selectedFeature).detail)
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430, alignment: .leading)

            if engine.selectedFeature == .monitorExpensive {
                energyTable
            }

            if !engine.pausedApps.isEmpty, engine.isLowPowerActive {
                pausedTable
            }

            if let error = engine.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 430, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private var energyTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live energy")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            if engine.expensiveApps.isEmpty {
                Text("Waiting for samples…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(engine.expensiveApps.prefix(5)) { sample in
                    HStack {
                        Text(sample.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f%% CPU", sample.cpuPercent))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(sample.cpuPercent >= 18 ? Color.orange : Color.secondary)
                    }
                }
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: 430)
    }

    private var pausedTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Currently paused")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(engine.pausedApps.prefix(6)) { app in
                Text("\(app.name) · \(app.reason)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 430, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Show in menubar:")
                .font(.system(size: 13))

            Toggle("Battery Icon", isOn: $engine.settings.showBatteryIcon)
                .toggleStyle(.checkbox)
                .font(.system(size: 13))

            Picker("", selection: $engine.settings.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 168)

            Spacer()

            Menu {
                Toggle("Open at Login", isOn: $engine.settings.launchAtLogin)
                    .onChange(of: engine.settings.launchAtLogin) { _, _ in
                        engine.syncLoginItem()
                    }
                Toggle("Restore when plugged in", isOn: $engine.settings.restoreWhenPluggedIn)
                Divider()
                Button("About EnduranceLite") { showAbout() }
                Divider()
                Button("Uninstall EnduranceLite…", role: .destructive) {
                    engine.confirmUninstall()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Uninstall")
                        .font(.system(size: 13))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .frame(width: 110)
        }
    }

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "EnduranceLite"
        alert.informativeText = "A menu bar battery endurance utility for macOS.\n\nInspired by Endurance. Not affiliated with Magnetism Studios.\n\nVersion \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct FeatureRow: View {
    let feature: PowerFeature
    let isSelected: Bool
    let isOn: Bool
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                MacCheckbox(isOn: isOn) {
                    onToggle(!isOn)
                }

                Group {
                    if feature.usesGhost {
                        GhostIcon()
                            .frame(width: 16, height: 16)
                    } else if let systemImage = feature.systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                    }
                }

                Text(feature.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MacCheckbox: View {
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color(white: 0.78))
                    .frame(width: 16, height: 16)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

#Preview {
    SettingsWindow()
        .environmentObject(EnduranceEngine.shared)
}
