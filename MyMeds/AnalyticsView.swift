import SwiftUI
import MyMedsCore
import DesignSystem

/// Аналитика (решение 31.10.2026): подробная понятная сводка — одна глобальная
/// карточка за всю историю курса + карточка по каждому блоку + строки по
/// лекарствам с оверлеями (§7). Без переключателей периода: глобально = вся
/// история, детализацию дают блоки.
struct AnalyticsView: View {
    @Environment(DataStore.self) private var store

    private var today: CivilDate { .today() }

    private var adherence: AdherenceStats {
        let start = store.data.plans.compactMap(\.startDate).min() ?? today
        return Analytics.adherence(data: store.data, from: start, to: today, today: today)
    }

    private var sortedPlans: [Plan] {
        store.data.plans.sorted {
            ($0.startDate?.daysSinceEpoch ?? Int.max) < ($1.startDate?.daysSinceEpoch ?? Int.max)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    globalCard
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                Section("По блокам") {
                    ForEach(sortedPlans) { plan in
                        NavigationLink {
                            PlanGridView(plan: plan)
                        } label: {
                            blockCard(plan)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                Section("По лекарствам") {
                    ForEach(store.data.medications) { med in
                        medRow(med)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Аналитика")
        }
    }

    // MARK: - Глобальная карточка

    private var globalCard: some View {
        let streak = Analytics.currentStreak(data: store.data, today: today)
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    GlassProgressRing(progress: adherence.adherence ?? 0,
                                      size: 72,
                                      caption: "адгереция")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(adherence.adherence == nil
                             ? "Ещё нет решённых дней"
                             : "\(Int((adherence.adherence ?? 0) * 100))% решённых дней принято")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("по всей истории курса")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    GlassBadge(label: "\(adherence.taken) принято", icon: "checkmark", color: .green)
                    GlassBadge(label: "\(adherence.skipped) пропущено", icon: "xmark", color: .orange)
                    GlassBadge(label: "\(adherence.missed) без отметки", icon: "exclamationmark", color: .red)
                    Spacer(minLength: 0)
                }
                Divider()
                HStack {
                    Label(streak == 0 ? "серия сброшена" : "серия \(streak) дн.",
                          systemImage: streak > 0 ? "flame.fill" : "flame")
                        .font(.caption)
                        .foregroundStyle(streak > 0 ? .orange : .secondary)
                    Spacer()
                    Label(medianTimeText, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var medianTimeText: String {
        guard let minutes = Analytics.medianMarkMinutes(data: store.data) else { return "—" }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: - Карточка блока

    private func blockCard(_ plan: Plan) -> some View {
        let stats = Stats.planStats(plan: plan, data: store.data, today: today)
        let med = store.medication(plan.medicationId)
        let state = PlanStatus.state(of: plan, on: today)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(plan.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if let med {
                    Text(med.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                GlassBadge(label: state.label, icon: state.icon, color: state.color)
            }
            if let start = plan.startDate, let last = PlanStatus.lastDay(of: plan) {
                Text("\(start.description) – \(last.description) · день \(stats.elapsedDays) из \(plan.durationDays)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: stats.progress)
                .tint(med?.accent ?? Palette.primary)
            HStack {
                Text("\(stats.taken) принято · \(stats.skipped) пропущено · \(stats.missed) без отметки")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(doseText(stats.cumulativeDose, unit: med?.unit ?? .mg))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)
        )
        .padding(.vertical, 2)
    }

    // MARK: - Строка лекарства (оверлеи §7)

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
