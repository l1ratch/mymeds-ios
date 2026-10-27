import SwiftUI
import MyMedsCore
import DesignSystem

/// Вкладка «Сегодня»: сводка дня + список приёмов. Нативный insetGrouped-лист;
/// стекло — только hero-карточка, остальное системные строки.
struct HomeView: View {
    @Environment(DataStore.self) private var store
    @State private var showSettings = false
    @State private var detailItem: DataStore.DayItem?
    @State private var errorText: String?

    private var items: [DataStore.DayItem] { store.todaysItems() }
    private var takenCount: Int { items.filter { $0.status == .taken }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    hero
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                if items.isEmpty {
                    Section {
                        emptyRow
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section("Приёмы") {
                        ForEach(items) { item in
                            IntakeRow(item: item,
                                      onDetail: { detailItem = item },
                                      onError: { errorText = $0 })
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Сегодня")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $detailItem) { DayDetailSheet(item: $0) }
            .onChange(of: store.data) { _, _ in
                // Любая мутация (отметка/доза/импорт/настройки) → перевзвод
                // скользящего окна уведомлений (§8: идемпотентный пересчёт).
                NotificationSetup.reschedule()
            }
            .alert("Ошибка", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    }

    private var hero: some View {
        GlassCard {
            HStack(spacing: 16) {
                GlassProgressRing(
                    progress: items.isEmpty ? 0 : Double(takenCount) / Double(items.count),
                    size: 64,
                    caption: "сегодня")
                VStack(alignment: .leading, spacing: 4) {
                    Text(CivilDate.today().humanText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(items.isEmpty
                         ? "приёмов нет"
                         : "\(takenCount) из \(items.count) принято")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Маскот = визуализация streak (§12), без хранения
                MascotView(streak: Analytics.currentStreak(data: store.data))
            }
        }
    }

    /// Пустое состояние — приглашение к действию, а не настроение.
    private var emptyRow: some View {
        VStack(spacing: 10) {
            Image(systemName: "cross.case")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("На сегодня приёмов нет")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Создайте план на вкладке «Разделы» или импортируйте готовый из файла в настройках.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Открыть настройки") { showSettings = true }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// Строка приёма = один Entry (§5). Один компонент на «Сегодня» и лист дня
/// календаря (§12). Нативная строка списка: иконка статуса, название, доза;
/// круглые кнопки отметки справа; тап по строке — детали и доза дня.
struct IntakeRow: View {
    let item: DataStore.DayItem
    var onDetail: () -> Void
    var onError: (String) -> Void

    @Environment(DataStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(item.status.color)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(item.status.color.opacity(item.intake?.status == nil ? 0.10 : 0.16))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(item.medication.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(doseText(item.plannedDose, unit: item.medication.unit)) · \(item.plan.name), день \(item.entry.day)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                markButton(status: .taken, icon: "checkmark", tint: .green)
                markButton(status: .skipped, icon: "xmark", tint: .orange)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDetail)
        .animation(Motion.statusChange, value: item.status)
    }

    private var statusIcon: String {
        switch item.status {
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .missed: return "exclamationmark.circle.fill"
        case .pending: return "circle.dashed"
        case .scheduled: return "circle"
        }
    }

    private func markButton(status: Intake.Status, icon: String, tint: Color) -> some View {
        let selected = item.intake?.status == status
        return Button {
            do {
                try store.mark(planId: item.entry.planId, day: item.entry.day, status: status)
                HapticManager.shared.notifySuccess()
            } catch {
                onError(error.localizedDescription)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selected ? Color.white : tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(selected ? tint : tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
