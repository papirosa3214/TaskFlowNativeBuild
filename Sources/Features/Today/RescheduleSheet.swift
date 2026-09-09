import SwiftUI

// Массовый перенос просроченных — spec §3.8 `RescheduleSheet`. Открывается
// с колонки «Просрочено» на доске «Сегодня».
struct RescheduleSheetContent: View {
    let taskIds: [String]
    let taskStore: TaskStore
    let onClose: () -> Void

    @State private var pendingDate: String?
    @State private var displayedMonth = Date()
    @State private var isRescheduling = false
    @State private var done = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: TFSpacing.lg) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 18)).foregroundStyle(Color.tfText)
                }
                .frame(width: 44, height: 44)
                Spacer()
                Text("Срок").tfText(.title).foregroundStyle(Color.tfText)
                Spacer()
                Button(action: confirm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: TFIconSize.md))
                        .foregroundStyle(pendingDate != nil && !isRescheduling ? Color.tfRed : Color.tfDim)
                }
                .disabled(pendingDate == nil || isRescheduling)
                .frame(width: 44, height: 44)
            }

            if isRescheduling {
                Text("Переносим \(done) из \(taskIds.count)…")
                    .tfText(.action)
                    .foregroundStyle(Color.tfSub)
            }
            TFErrorBanner(errorMessage, variant: .block)

            VStack(spacing: TFSpacing.xs) {
                quickButton("Сегодня", subtitle: TodayDate.weekdaysFull[weekday(TodayDate.todayString())]) {
                    apply(date: TodayDate.todayString())
                }
                quickButton("Завтра") { apply(date: TodayDate.addDays(TodayDate.todayString(), 1)) }
                quickButton("На выходных") { apply(date: nearestSaturday()) }
                quickButton("Следующая неделя") { apply(date: nearestMonday()) }
                quickButton("Без срока") { apply(date: nil) }
            }

            // Быстрые кнопки закрывают почти все переносы; конкретное число
            // нужно редко, поэтому вместо самописной сетки месяца на
            // пол-экрана — компактный системный пикер одной строкой
            // (09.09.2026, тот же разбор, что у карточки задачи).
            DatePicker(
                "Другая дата",
                selection: customDateBinding,
                displayedComponents: .date
            )
            .padding(.horizontal, TFSpacing.lg)
        }
        .padding(.bottom, TFSpacing.xl)
        .disabled(isRescheduling)
    }

    /// Выбор в пикере сразу переносит задачу — отдельной кнопки
    /// «применить» здесь нет и у быстрых кнопок тоже.
    private var customDateBinding: Binding<Date> {
        Binding(
            get: { displayedMonth },
            set: { picked in
                displayedMonth = picked
                let f = DateFormatter()
                f.calendar = Calendar(identifier: .gregorian)
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(identifier: "Europe/Moscow")
                f.dateFormat = "yyyy-MM-dd"
                apply(date: f.string(from: picked))
            }
        )
    }

    private func quickButton(_ title: String, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).tfText(.body).foregroundStyle(Color.tfText)
                Spacer()
                if let subtitle {
                    Text(subtitle).tfText(.action).foregroundStyle(Color.tfSub)
                }
            }
            .padding(TFSpacing.lg)
            .background(Color.tfCard)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.lg))
        }
        .buttonStyle(TFTapRowStyle())
    }

    private func weekday(_ dateStr: String) -> Int {
        guard let d = TodayDate.calendarDate(dateStr) else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.component(.weekday, from: d) - 1
    }

    private func nearestSaturday() -> String {
        var date = TodayDate.todayString()
        for _ in 0..<7 {
            if weekday(date) == 6 { return date } // суббота
            date = TodayDate.addDays(date, 1)
        }
        return date
    }

    private func nearestMonday() -> String {
        var date = TodayDate.addDays(TodayDate.todayString(), 1)
        for _ in 0..<7 {
            if weekday(date) == 1 { return date } // понедельник
            date = TodayDate.addDays(date, 1)
        }
        return date
    }

    private func apply(date: String?) {
        pendingDate = date ?? ""
        Task { await runReschedule(date: date) }
    }

    private func confirm() {
        guard let pendingDate, !pendingDate.isEmpty else { return }
        Task { await runReschedule(date: pendingDate) }
    }

    private func runReschedule(date: String?) async {
        isRescheduling = true
        done = 0
        errorMessage = nil
        var failed = 0
        await withTaskGroup(of: Bool.self) { group in
            for id in taskIds {
                group.addTask {
                    // `ApiTask` — все поля `let` (см. Core/Models/Task.swift), точечно
                    // мутировать `inout` нечем; полагаемся на ответ сервера, который
                    // `patch()` сам подставит в стор после await — без мгновенного
                    // оптимистичного обновления строки, но корректно.
                    await taskStore.patch(taskId: id, fields: ["due_date": date.map { JSONValue.string($0) } ?? .null]) { _ in }
                }
            }
            for await ok in group {
                if ok { done += 1 } else { failed += 1 }
            }
        }
        isRescheduling = false
        if failed > 0 {
            errorMessage = "Не удалось перенести \(failed) из \(taskIds.count) задач. Остальные уже перенесены — попробуйте ещё раз."
        } else {
            onClose()
        }
    }
}
