import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject private var engine: EnduranceEngine

    var body: some View {
        HStack(spacing: 6) {
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
        .padding(.horizontal, 2)
        .accessibilityLabel("EnduranceLite, battery \(engine.battery.percentLabel)")
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject private var engine: EnduranceEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 12)

            statusRows
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            Divider()
                .padding(.horizontal, 12)

            lowPowerRow
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            if engine.isLowPowerActive {
                activeMeasures
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }

            Divider()
                .padding(.horizontal, 12)

            actions
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: 320)
        .fixedSize(horizontal: true, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(engine.battery.percentLabel)
                    .font(.system(size: 32, weight: .light).monospacedDigit())
                    .padding(.top, 2)
                Text(engine.battery.timeRemainingLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            EnduranceMark()
                .frame(width: 56, height: 36)
                .padding(.trailing, 4)
        }
    }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: engine.battery.isCharging ? "battery.100.bolt" : "battery.100")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(engine.battery.isCharging ? "Charging" : (engine.battery.onBattery ? "On battery" : "Plugged in"))
                    .font(.system(size: 13))
                Spacer()
                Text(engine.battery.percentLabel)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let temperature = engine.battery.temperatureC {
                HStack(spacing: 10) {
                    Circle()
                        .fill(temperatureColor(temperature))
                        .frame(width: 8, height: 8)
                        .padding(.leading, 5)
                        .padding(.trailing, 5)
                    Text("Battery temperature")
                        .font(.system(size: 13))
                    Spacer()
                    Text(String(format: "%.0f°C", temperature))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var lowPowerRow: some View {
        Toggle(isOn: Binding(
            get: { engine.isLowPowerActive },
            set: { engine.userToggleLowPower($0) }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Low Power Mode")
                    .font(.system(size: 13, weight: .medium))
                Text(engine.isLowPowerActive ? "Measures are running" : "Off — waiting for threshold")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .toggleStyle(.switch)
    }

    private var activeMeasures: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(activeMeasureLabels, id: \.self) { label in
                Label(label, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    private var actions: some View {
        VStack(spacing: 2) {
            Button {
                engine.openSettings()
            } label: {
                Label("Open EnduranceLite…", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit EnduranceLite", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var activeMeasureLabels: [String] {
        PowerFeature.all.compactMap { feature in
            engine.settings.isEnabled(feature.id) ? feature.title : nil
        }
    }

    private func temperatureColor(_ celsius: Double) -> Color {
        if celsius >= 40 { return .red }
        if celsius >= 32 { return .yellow }
        return .green
    }
}
