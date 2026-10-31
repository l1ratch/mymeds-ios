import SwiftUI
import MyMedsCore
import DesignSystem

/// Конфигуратор лекарства (настройки): все поля модели + окно напоминаний в
/// одном простом Form. medication == nil → создание нового.
struct MedicationEditSheet: View {
    let medication: Medication?

    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unit: DoseUnit = .mg
    @State private var form = ""
    @State private var intakeRule = ""
    @State private var targetText = ""
    @State private var weightText = ""
    @State private var notifyOn = false
    @State private var startHour = 20
    @State private var endHour = 23
    @State private var intervalIndex = 1
    @State private var errorText: String?

    private let intervals = [15, 30, 60, 120]

    var body: some View {
        NavigationStack {
            Form {
                Section("Лекарство") {
                    TextField("Название", text: $name)
                    Picker("Единица", selection: $unit) {
                        ForEach(DoseUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Форма (капсула, таблетка…)", text: $form)
                    TextField("Правило приёма (после еды…)", text: $intakeRule)
                }
                Section("Цель и вес (необязательно)") {
                    TextField("Цель курса, \(unit.title)", text: $targetText)
                        .keyboardType(.decimalPad)
                    TextField("Вес, кг", text: $weightText)
                        .keyboardType(.decimalPad)
                }
                Section("Напоминания") {
                    Toggle("Напоминания", isOn: $notifyOn)
                    if notifyOn {
                        Stepper("С \(startHour):00", value: $startHour, in: 0...23)
                        Stepper("По \(endHour):00", value: $endHour, in: 0...23)
                        Picker("Интервал", selection: $intervalIndex) {
                            ForEach(intervals.indices, id: \.self) { idx in
                                Text("\(intervals[idx]) мин").tag(idx)
                            }
                        }
                    }
                }
            }
            .navigationTitle(medication == nil ? "Новое лекарство" : medication?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { save() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Ошибка", isPresented: Binding(get: { errorText != nil },
                                                  set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let med = medication else { return }
        name = med.name
        unit = med.unit
        form = med.form ?? ""
        intakeRule = med.intakeRule ?? ""
        targetText = med.cumulativeTarget.map { trim($0) } ?? ""
        weightText = med.weightKg.map { trim($0) } ?? ""
        if let w = med.notifyWindow {
            notifyOn = true
            startHour = w.startHour
            endHour = w.endHour
            intervalIndex = intervals.firstIndex(of: w.intervalMinutes) ?? 1
        }
    }

    private func trim(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }

    private func number(_ text: String) -> Double? {
        let value = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
        return value > 0 ? value : nil
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorText = "Укажите название лекарства"
            return
        }
        let window: NotifyWindow? = notifyOn
            ? NotifyWindow(startHour: startHour,
                           endHour: max(endHour, startHour),
                           intervalMinutes: intervals[intervalIndex])
            : nil
        let med = Medication(
            id: medication?.id ?? UUID(),
            name: trimmed,
            form: nilIfEmpty(form),
            unit: unit,
            intakeRule: nilIfEmpty(intakeRule),
            cumulativeTarget: number(targetText),
            weightKg: number(weightText),
            notifyWindow: window,
            colorHex: medication?.colorHex,
            createdAt: medication?.createdAt ?? Date())
        do {
            try store.upsertMedication(med)
            HapticManager.shared.notifySuccess()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func nilIfEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
