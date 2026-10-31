import SwiftUI
import MyMedsCore
import DesignSystem

/// Строка приёма = один Entry (§5). Один компонент на траекторию календаря и
/// лист дня (§12). Нативная строка: иконка статуса, название, доза; круглые
/// кнопки «принял/пропустил»; тап по строке — детали и правка дозы («изменить»).
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
                .frame(width: 44, height: 44)          // тач-таргет ≥44pt (pro-rules)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(status == .taken ? "Принял" : "Пропустил")
    }
}
