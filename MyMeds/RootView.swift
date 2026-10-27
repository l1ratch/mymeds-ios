import SwiftUI
import MyMedsCore
import DesignSystem

/// Корень: раздельные страницы-вкладки (решение пользователя от 27.10.2026 —
/// «один экран» из §12 заменён табом на каждый раздел). Системный TabView:
/// стеклянная таб-панель iOS 26, крупные заголовки, нативные списки.
struct RootView: View {
    @Environment(DataStore.self) private var store

    var body: some View {
        TabView {
            Tab("Сегодня", systemImage: "checklist") {
                HomeView()
            }
            Tab("Календарь", systemImage: "calendar") {
                CalendarView()
            }
            Tab("Разделы", systemImage: "pills.fill") {
                MedicationsListView()
            }
            Tab("Аналитика", systemImage: "chart.bar.xaxis") {
                AnalyticsView()
            }
        }
        .tint(Palette.primary)
        .task {
            NotificationSetup.requestAuthorization()
            NotificationSetup.reschedule()
        }
    }
}
