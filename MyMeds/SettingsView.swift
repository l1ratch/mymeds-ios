import SwiftUI
import MyMedsCore
import DesignSystem
import UniformTypeIdentifiers
import UserNotifications

/// Настройки — отдельная страница (решение 31.10.2026): конфигуратор лекарств
/// и блоков, уведомления с бюджетом «X из 64», синхронизация (заготовка),
/// данные (экспорт/импорт/восстановление), сведения о приложении.
struct SettingsView: View {
    @Environment(DataStore.self) private var store

    @State private var showImporter = false
    @State private var shareURL: IdentifiableURL?
    @State private var backupToRestore: PendingBackup?
    @State private var planToImport: PendingPlan?
    @State private var errorText: String?
    @State private var editingMed: Medication?
    @State private var creatingMed = false
    @State private var showConstructor = false
    @State private var authStatus: UNAuthorizationStatus?

    struct PendingBackup: Identifiable {
        let id = UUID()
        let data: Data
        let preview: AppData
    }

    struct PendingPlan: Identifiable {
        let id = UUID()
        let data: Data
        let file: MedPlanFile
    }

    private var sortedPlans: [Plan] {
        store.data.plans.sorted {
            ($0.startDate?.daysSinceEpoch ?? Int.max) < ($1.startDate?.daysSinceEpoch ?? Int.max)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Лекарства и блоки") {
                    ForEach(store.data.medications) { med in
                        NavigationLink {
                            MedicationDetailView(medication: med)
                        } label: {
                            HStack(spacing: 10) {
                                Circle().fill(med.accent).frame(width: 10, height: 10)
                                Text(med.name).foregroundStyle(.primary)
                                Spacer()
                                Text(med.unit.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        creatingMed = true
                    } label: {
                        Label("Добавить лекарство", systemImage: "plus.circle")
                    }
                    ForEach(sortedPlans) { plan in
                        NavigationLink {
                            PlanGridView(plan: plan)
                        } label: {
                            planRow(plan)
                        }
                    }
                    Button {
                        showConstructor = true
                    } label: {
                        Label("Новый блок", systemImage: "plus.circle")
                    }
                }
                Section("Уведомления") {
                    LabeledContent("Запланировано") {
                        Text("\(notificationPlan.total) из \(NotificationPlanner.systemLimit)")
                    }
                    if notificationPlan.trimmed {
                        Label("Бюджет плотный — интервалы укрупнены",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Stepper("Горизонт: \(store.data.settings.notifyHorizonDays) дн.",
                            value: horizonBinding, in: 1...7)
                    if let auth = authStatus, auth != .authorized, auth != .provisional {
                        Button("Разрешение не выдано — открыть настройки") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                Section("Синхронизация") {
                    LabeledContent("Статус") {
                        Text(store.sync.isAvailable ? "подключена" : "не подключена")
                            .foregroundStyle(.secondary)
                    }
                    Text("Модуль зарезервирован на будущее: данные живут на устройстве, сервер подключим без смены схемы хранения.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Данные") {
                    Button {
                        exportBackup()
                    } label: {
                        Label("Экспорт данных (JSON)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Импорт плана или бэкапа", systemImage: "square.and.arrow.down")
                    }
                    LabeledContent("Лекарств") { Text("\(store.data.medications.count)") }
                    LabeledContent("Планов") { Text("\(store.data.plans.count)") }
                    LabeledContent("Отметок") { Text("\(store.data.intakes.count)") }
                }
                Section("Приложение") {
                    LabeledContent("Версия") { Text(AppVersion.versionName) }
                    LabeledContent("Сборка") {
                        Text("\(AppVersion.buildNumber) · \(AppVersion.buildChannel)")
                    }
                    LabeledContent("Коммит") { Text(AppVersion.commitSha) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Настройки")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url.value])
            }
            .sheet(item: $planToImport) { pending in
                MedPlanImportSheet(file: pending.file, data: pending.data)
            }
            .sheet(item: $editingMed) { med in
                MedicationEditSheet(medication: med)
            }
            .sheet(isPresented: $creatingMed) {
                MedicationEditSheet(medication: nil)
            }
            .sheet(isPresented: $showConstructor) {
                PlanConstructorView()
            }
            .task {
                authStatus = await UNUserNotificationCenter.current()
                    .notificationSettings().authorizationStatus
            }
            .confirmationDialog(
                "Восстановить бэкап?",
                isPresented: Binding(get: { backupToRestore != nil },
                                     set: { if !$0 { backupToRestore = nil } }),
                titleVisibility: .visible
            ) {
                Button("Заменить ВСЕ данные", role: .destructive) {
                    restoreBackup()
                }
                Button("Отмена", role: .cancel) { backupToRestore = nil }
            } message: {
                if let pending = backupToRestore {
                    Text("Лекарств: \(pending.preview.medications.count), "
                         + "планов: \(pending.preview.plans.count), "
                         + "отметок: \(pending.preview.intakes.count). "
                         + "Текущие данные будут полностью заменены (не слияние).")
                }
            }
            .alert("Ошибка", isPresented: Binding(get: { errorText != nil },
                                                  set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private func planRow(_ plan: Plan) -> some View {
        let state = PlanStatus.state(of: plan, on: .today())
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let start = plan.startDate {
                    Text("с \(start.description) · \(plan.durationDays) дн.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("черновик — ещё не начат")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            GlassBadge(label: state.label, icon: state.icon, color: state.color)
        }
        .padding(.vertical, 2)
    }

    private var notificationPlan: NotificationPlan {
        NotificationPlanner.plan(data: store.data)
    }

    private var horizonBinding: Binding<Int> {
        Binding(get: { store.data.settings.notifyHorizonDays },
                set: { newValue in try? store.setNotifyHorizon(days: newValue) })
    }

    private func exportBackup() {
        do {
            let data = try store.exportBackup()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mymeds_backup_\(CivilDate.today()).json")
            try data.write(to: url)
            shareURL = IdentifiableURL(value: url)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if let backup = try? MedPlanCodec.decodeBackup(data) {
                    backupToRestore = PendingBackup(data: data, preview: backup)
                } else if let file = try? MedPlanCodec.decodeFile(data) {
                    planToImport = PendingPlan(data: data, file: file)
                } else {
                    errorText = "Незнакомый файл: ожидается medplan/1 (план) или mymeds-backup/1 (бэкап)"
                }
            } catch {
                errorText = "Не удалось прочитать файл: \(error.localizedDescription)"
            }
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }

    private func restoreBackup() {
        guard let pending = backupToRestore else { return }
        backupToRestore = nil
        do {
            try store.importBackup(pending.data)
            HapticManager.shared.notifySuccess()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct IdentifiableURL: Identifiable {
    let value: URL
    var id: URL { value }
}

/// Share sheet (UIActivityViewController) — системный механизм, без зависимостей.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
