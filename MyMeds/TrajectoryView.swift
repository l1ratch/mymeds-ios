import SwiftUI
import MyMedsCore
import DesignSystem

/// Календарь-траектория (решение пользователя 31.10.2026): вертикальная линия
/// курса с узлами-днями вместо сетки-heatmap. Сегодня — первый блок, развёрнут:
/// общая сводка + лекарства с кнопками «принял / пропустил / изменить».
/// Остальные дни — свёрнутые блоки на той же траектории; тап раскрывает день.
///
/// Прозводительность: сводки всех дней и streak считаются ОДИН раз в `model`
/// (на появление и на изменение данных), а не на каждый рендер строки.
struct TrajectoryView: View {
    @Environment(DataStore.self) private var store
    @State private var expanded: CivilDate? = .today()
    @State private var detailItem: DataStore.DayItem?
    @State private var errorText: String?
    @State private var model = TrajectoryModel.empty
    var openSettings: () -> Void = {}

    /// Всё, что дорого считать, лежит здесь и обновляется только при смене данных.
    struct TrajectoryModel {
        var summaries: [Int: DaySummary] = [:]
        var futureDays: [CivilDate] = []
        var pastDays: [CivilDate] = []
        var today: CivilDate = .today()
        var courseStart: CivilDate?
        var streak: Int = 0

        static let empty = TrajectoryModel()
    }

    private var today: CivilDate { model.today }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if model.courseStart == nil {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            dayRow(today, isFirst: true,
                                   isLast: model.futureDays.isEmpty && model.pastDays.isEmpty)
                            if !model.futureDays.isEmpty {
                                groupHeader("Впереди")
                                ForEach(model.futureDays.indices, id: \.self) { i in
                                    dayRow(model.futureDays[i], isFirst: i == 0,
                                           isLast: i == model.futureDays.count - 1 && model.pastDays.isEmpty)
                                }
                            }
                            if !model.pastDays.isEmpty {
                                groupHeader("История")
                                ForEach(model.pastDays.indices, id: \.self) { i in
                                    dayRow(model.pastDays[i], isFirst: i == 0,
                                           isLast: i == model.pastDays.count - 1)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        // Контент не должен уходить под плавающий TabView
                        .padding(.bottom, 72)
                    }
                }
            }
            .navigationTitle("Календарь")
            .sheet(item: $detailItem) { DayDetailSheet(item: $0) }
            .task { rebuild() }
            .onChange(of: store.data) { _, _ in
                rebuild()
                NotificationSetup.reschedule()
            }
            .alert("Ошибка", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    /// Один пересчёт на смену данных: дни курса + сводки + streak.
    private func rebuild() {
        let now = CivilDate.today()
        let start = store.data.plans.compactMap(\.startDate).min()
        let end = max(store.data.plans.compactMap { PlanStatus.lastDay(of: $0) }.max() ?? now, now)
        var future: [CivilDate] = []
        var d = now.adding(days: 1)
        while d <= end && future.count < 500 { future.append(d); d = d.adding(days: 1) }
        var past: [CivilDate] = []
        if let start {
            d = now.adding(days: -1)
            while d >= start && past.count < 500 { past.append(d); d = d.adding(days: -1) }
        }
        let summaries = start == nil
            ? [:]
            : Stats.trajectorySummaries(data: store.data, from: start!, to: end, today: now)
        model = TrajectoryModel(
            summaries: summaries,
            futureDays: future,
            pastDays: past,
            today: now,
            courseStart: start,
            streak: Analytics.currentStreak(data: store.data, today: now))
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    }

    // MARK: - Строка траектории

    private func dayRow(_ date: CivilDate, isFirst: Bool, isLast: Bool) -> some View {
        let summary = model.summaries[date.daysSinceEpoch]
            ?? DaySummary(date: date, total: 0, taken: 0)
        return HStack(alignment: .top, spacing: 12) {
            nodeColumn(date: date, summary: summary, isFirst: isFirst, isLast: isLast)
            dayCard(date: date, summary: summary, isExpanded: expanded == date)
                .padding(.bottom, 10)
        }
    }

    /// Узел на линии: сегмент сверху до узла, узел, сегмент вниз к следующему.
    private func nodeColumn(date: CivilDate, summary: DaySummary,
                            isFirst: Bool, isLast: Bool) -> some View {
        let color = nodeColor(summary: summary, date: date)
        let isToday = date == today
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 2, height: isFirst ? 0 : 21)
            ZStack {
                if isToday {
                    Circle()
                        .strokeBorder(Palette.primary.opacity(0.45), lineWidth: 3)
                        .frame(width: 20, height: 20)
                }
                Circle()
                    .fill(color)
                    .frame(width: isToday ? 14 : 12, height: isToday ? 14 : 12)
            }
            .frame(height: 21)
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .opacity(isLast ? 0 : 1)
        }
        .frame(width: 20)
        .accessibilityHidden(true)   // декорация: состояние озвучивает карточка
    }

    private func dayCard(date: CivilDate, summary: DaySummary, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.statusChange) {
                    expanded = isExpanded ? nil : date
                }
            } label: {
                header(date: date, summary: summary, isExpanded: isExpanded)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("\(dayTitle(date)), \(daySubtitle(date, summary))")
            .accessibilityValue(isExpanded ? "развёрнуто" : "свёрнуто")
            if isExpanded {
                Divider().padding(.horizontal, 14)
                expandedBody(date: date)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)
        )
        .opacity(date > today ? 0.75 : 1)
    }

    private func header(date: CivilDate, summary: DaySummary, isExpanded: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayTitle(date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(daySubtitle(date, summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if summary.total > 0 {
                Text("\(summary.taken)/\(summary.total)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(nodeColor(summary: summary, date: date))
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// Развёрнутое поле: для сегодня — общая сводка кольцом + маскот,
    /// ниже — лекарства с кнопками отметки и правкой дозы.
    private func expandedBody(date: CivilDate) -> some View {
        let items = store.items(on: date, today: today)
        let taken = items.filter { $0.status == .taken }.count
        return VStack(alignment: .leading, spacing: 4) {
            if date == today {
                HStack(spacing: 12) {
                    GlassProgressRing(
                        progress: items.isEmpty ? 0 : Double(taken) / Double(items.count),
                        size: 44,
                        caption: "сегодня")
                    Text(items.isEmpty
                         ? "На сегодня приёмов нет"
                         : "Принято \(taken) из \(items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    MascotView(streak: model.streak)
                }
                .padding(.top, 10)
                Divider().padding(.vertical, 4)
            }
            if items.isEmpty {
                Text("В этот день приёмов нет")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(items) { item in
                    IntakeRow(item: item,
                              onDetail: { detailItem = item },
                              onError: { errorText = $0 })
                }
            }
        }
    }

    // MARK: - Подписи и цвет узла

    private func nodeColor(summary: DaySummary, date: CivilDate) -> Color {
        if date > today { return Color.secondary.opacity(0.5) }
        guard summary.total > 0, let fraction = summary.fraction else {
            return Color.secondary.opacity(0.35)
        }
        if fraction >= 1 { return .green }
        if fraction >= 2.0 / 3.0 { return .green.opacity(0.75) }
        if fraction >= 1.0 / 3.0 { return .green.opacity(0.5) }
        if fraction > 0 { return .orange }
        return .red
    }

    private func dayTitle(_ date: CivilDate) -> String {
        if date == today { return "Сегодня" }
        if date == today.adding(days: -1) { return "Вчера" }
        if date == today.adding(days: 1) { return "Завтра" }
        return Self.dayFormat.string(from: Self.date(date))
    }

    private func daySubtitle(_ date: CivilDate, _ summary: DaySummary) -> String {
        let weekday = Self.weekdayFormat.string(from: Self.date(date))
        let counts = summary.total == 0
            ? "приёмов нет"
            : "\(summary.total) \(plural(summary.total)) · принято \(summary.taken)"
        return "\(weekday) · \(counts)"
    }

    private func plural(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "приём" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "приёма" }
        return "приёмов"
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f
    }()

    private static let weekdayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE"
        return f
    }()

    private static func date(_ civil: CivilDate) -> Date {
        var comps = DateComponents()
        comps.year = civil.year
        comps.month = civil.month
        comps.day = civil.day
        return Calendar.current.date(from: comps) ?? .now
    }

    // MARK: - Пустое состояние

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Курс ещё не начат")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Создайте блок в настройках или импортируйте бэкап — и здесь появится траектория приёма по дням.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Открыть настройки", action: openSettings)
                .buttonStyle(.glass)
        }
        .padding(32)
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 32)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }
}
