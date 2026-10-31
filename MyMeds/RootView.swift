import SwiftUI
import MyMedsCore
import DesignSystem

/// Корень: три раздельные страницы (решение 31.10.2026):
/// Календарь-траектория (главный экран), Аналитика, Настройки с конфигуратором.
struct RootView: View {
    @Environment(DataStore.self) private var store
    @State private var tab: RootTab = .calendar

    enum RootTab: Hashable {
        case calendar, analytics, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Календарь", systemImage: "calendar", value: .calendar) {
                TrajectoryView(openSettings: { tab = .settings })
            }
            Tab("Аналитика", systemImage: "chart.bar.xaxis", value: .analytics) {
                AnalyticsView()
            }
            Tab("Настройки", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .tint(Palette.primary)
        .task {
            NotificationSetup.requestAuthorization()
            NotificationSetup.reschedule()
        }
    }
}
