import SwiftUI
import MyMedsCore
import DesignSystem

/// Разделы — список лекарств с сегментом «активные/архив» (§12).
/// Архив = завершённые планы, производно из дат, без отдельного экрана.
struct MedicationsListView: View {
    @Environment(DataStore.self) private var store

    enum Segment: String, CaseIterable, Identifiable {
        case active = "Активные"
        case archive = "Архив"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .active
    @State private var showConstructor = false

    private var today: CivilDate { .today() }

    /// Лекарства с незавершёнными планами (или вообще без планов).
    private var activeMedications: [Medication] {
        store.data.medications.filter { med in
            let plans = store.data.plans.filter { $0.medicationId == med.id }
            return plans.isEmpty
                || plans.contains { PlanStatus.state(of: $0, on: today) != .finished }
        }
    }

    /// Завершённые планы, свежие сверху.
    private var finishedPlans: [Plan] {
        store.data.plans
            .filter { PlanStatus.state(of: $0, on: today) == .finished }
            .sorted { ($0.startDate?.daysSinceEpoch ?? 0) > ($1.startDate?.daysSinceEpoch ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            List {
                Section {
                    Button {
                        showConstructor = true
                    } label: {
                        Label("Новый план", systemImage: "plus.circle.fill")
                    }
                }
                if segment == .active {
                    Section("Активные") {
                        if activeMedications.isEmpty {
                            emptyRow("Пока нет ни одного раздела",
                                     hint: "Создайте план кнопкой выше или импортируйте файл medplan/1 в настройках")
                        } else {
                            ForEach(activeMedications) { med in
                                NavigationLink {
                                    MedicationDetailView(medication: med)
                                } label: {
                                    MedicationRow(medication: med)
                                }
                            }
                        }
                    }
                } else {
                    Section("Завершённые планы") {
                        if finishedPlans.isEmpty {
                            emptyRow("Архив пуст",
                                     hint: "Сюда попадают планы, у которых закончились дни")
                        } else {
                            ForEach(finishedPlans) { plan in
                                NavigationLink {
                                    PlanGridView(plan: plan)
                                } label: {
                                    ArchiveRow(plan: plan)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Разделы")
        .sheet(isPresented: $showConstructor) {
            PlanConstructorView()
        }
    }

    private func emptyRow(_ title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

/// Строка активного раздела: лекарство + текущий план + прогресс.
struct MedicationRow: View {
    let medication: Medication
    @Environment(DataStore.self) private var store

    private var today: CivilDate { .today() }

    private var plans: [Plan] {
        store.data.plans.filter { $0.medicationId == medication.id }
    }

    /// Текущий план: активный, иначе ближайший незавершённый.
    private var currentPlan: Plan? {
        plans.first { PlanStatus.state(of: $0, on: today) == .active }
            ?? plans.filter { PlanStatus.state(of: $0, on: today) != .finished }
                .min { ($0.startDate?.daysSinceEpoch ?? Int.max) < ($1.startDate?.daysSinceEpoch ?? Int.max) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(medication.accent)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(medication.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let plan = currentPlan {
                    let stats = Stats.planStats(plan: plan, data: store.data, today: today)
                    Text("\(plan.name) · день \(max(stats.elapsedDays, 0)) из \(plan.durationDays)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("нет активных планов")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(doseText(
                Stats.medicationCumulative(medicationId: medication.id, data: store.data, today: today),
                unit: medication.unit))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Строка архива: завершённый план.
struct ArchiveRow: View {
    let plan: Plan
    @Environment(DataStore.self) private var store

    private var medication: Medication? { store.medication(plan.medicationId) }

    var body: some View {
        let stats = Stats.planStats(plan: plan, data: store.data)
        let med = medication
        let unit = med?.unit ?? .mg
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(med?.name ?? "—") · \(plan.name)")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let start = plan.startDate, let last = PlanStatus.lastDay(of: plan) {
                    Text("\(start.description) – \(last.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text("\(stats.taken) · \(doseText(stats.cumulativeDose, unit: unit))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
