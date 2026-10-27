import SwiftUI
import MyMedsCore
import DesignSystem

/// Аналитика (§7/§12): свёртка по entries + оверлеи + heatmap + маскот.
struct AnalyticsView: View {
    @Environment(DataStore.self) private var store
    @State private var periodDays = 30
    @State private var selectedDay: CalendarView.SelectedDay?

    private var today: CivilDate { .today() }

    private struct Period: Identifiable {
        let days: Int
        let label: String
        var id: Int { days }
    }

    private let periods = [
        Period(days: 7, label: "Неделя"),
        Period(days: 30, label: "Месяц"),
        Period(days: 90, label: "90 дней"),
        Period(days: 0, label: "Всё"),
    ]

    private var periodStart: CivilDate {
        if periodDays == 0 {
            return store.data.plans.compactMap(\.startDate).min() ?? today
        }
        return today.adding(days: -(periodDays - 1))
    }

    private var adherence: AdherenceStats {
        Analytics.adherence(data: store.data, from: periodStart, to: today, today: today)
    }

    private var streak: Int {
        Analytics.currentStreak(data: store.data, today: today)
    }

    var body: some View {
        List {
            Section {
                periodPicker
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            Section {
                adherenceCard
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            Section {
                streakRow
                LabeledContent("Среднее время отметки") {
                    Text(medianTimeText)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Текущий месяц") {
                heatmapCard
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            Section("По лекарствам") {
                ForEach(store.data.medications) { med in
                    medRow(med)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Аналитика")
        .sheet(item: $selectedDay) { day in
            CalendarDaySheet(date: day.date)
        }
    }

    private var periodPicker: some View {
        Picker("", selection: $periodDays) {
            ForEach(periods, id: \.days) { period in
                Text(period.label).tag(period.days)
            }
        }
        .pickerStyle(.segmented)
    }

    private var adherenceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    GlassProgressRing(
                        progress: adherence.adherence ?? 0,
                        size: 72,
                        caption: "адгереция")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(adherence.adherence == nil
                             ? "нет решённых дней"
                             : String(format: "%.0f%% — принято от решённых дней",
                                      (adherence.adherence ?? 0) * 100))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("taken / (taken + skipped + missed)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    GlassBadge(label: "\(adherence.taken)", icon: "checkmark", color: .green)
                    GlassBadge(label: "\(adherence.skipped)", icon: "xmark", color: .orange)
                    GlassBadge(label: "\(adherence.missed)", icon: "exclamationmark", color: .red)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var streakRow: some View {
        HStack(spacing: 14) {
            MascotView(streak: streak, size: 1.3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Серия")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(streak == 0
                     ? "Отметь все приёмы сегодня — огонёк оживёт"
                     : "\(streak) дн. подряд всё принято")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var heatmapCard: some View {
        let anchor = CivilDate(year: today.year, month: today.month, day: 1)
        let cells = MonthLayout.cells(anchor: anchor)
        let lookup = MonthLayout.summaries(data: store.data, cells: cells, today: today)
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(MonthLayout.title(anchor: anchor))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                HeatmapGrid(cells: cells, summaries: lookup, today: today) { date in
                    selectedDay = CalendarView.SelectedDay(date: date)
                }
            }
        }
    }

    private var medianTimeText: String {
        guard let minutes = Analytics.medianMarkMinutes(data: store.data) else { return "—" }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// Оверлеи по лекарствам: кумулятивная доза всегда; % цели, мг/кг и прогноз —
    /// только если поля заполнены (§7).
    private func medRow(_ med: Medication) -> some View {
        let overlay = Analytics.overlay(medicationId: med.id, data: store.data, today: today)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(med.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(doseText(overlay.cumulativeDose, unit: med.unit))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("за 14 дн ≈ \(doseText(overlay.avgDailyDose14, unit: med.unit))/день")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let percent = overlay.percentOfTarget {
                HStack(spacing: 8) {
                    ProgressView(value: min(percent, 100) / 100)
                        .tint(med.accent)
                    Text("\(Int(percent))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let mgkg = overlay.mgPerKgDay {
                Text(String(format: "%.2f %@/кг/день", mgkg, med.unit.title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let days = overlay.daysToTarget {
                Text(days == 0 ? "Цель достигнута" : "До цели ≈ \(days) дн.")
                    .font(.caption)
                    .foregroundStyle(days == 0 ? .green : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
