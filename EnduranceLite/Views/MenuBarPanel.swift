import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject private var engine: EnduranceEngine

    var body: some View {
        HStack(spacing: 4) {
            if engine.settings.showBatteryIcon {
                MenuBatteryGlyph(
                    percent: engine.battery.percent,
                    charging: engine.battery.isCharging,
                    onBattery: engine.battery.onBattery
                )
            } else {
                Image(systemName: engine.isLowPowerActive ? "infinity.circle.fill" : "infinity")
                    .imageScale(.medium)
            }

            switch engine.settings.menuBarStyle {
            case .iconOnly:
                EmptyView()
            case .iconAndPercent:
                Text(engine.battery.percentLabel)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            case .iconAndTime:
                Text(engine.battery.onBattery ? engine.battery.timeRemainingLabel : engine.battery.percentLabel)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
        }
        .accessibilityLabel("EnduranceLite, battery \(engine.battery.percentLabel)")
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject private var engine: EnduranceEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.battery.percentLabel)
                        .font(.system(size: 28, weight: .light).monospacedDigit())
                    Text(engine.battery.timeRemainingLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                EnduranceMark()
                    .frame(width: 46, height: 30)
            }

            Toggle(isOn: Binding(
                get: { engine.isLowPowerActive },
                set: { engine.userToggleLowPower($0) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Low Power Mode")
                        .font(.system(size: 13, weight: .medium))
                    Text(engine.isLowPowerActive ? "Measures are running" : "Off — waiting for threshold")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if engine.isLowPowerActive {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(activeMeasureLabels, id: \.self) { label in
                        Label(label, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            Button {
                engine.openSettings()
            } label: {
                Label("Open EnduranceLite…", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit EnduranceLite", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 280)
    }

    private var activeMeasureLabels: [String] {
        PowerFeature.all.compactMap { feature in
            engine.settings.isEnabled(feature.id) ? feature.title : nil
        }
    }
}
