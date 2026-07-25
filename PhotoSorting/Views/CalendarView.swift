import SwiftUI

struct CalendarView: View {

    let onDaySelected: (Date) -> Void

    let selectedMonth: Int
    let selectedDay: Int

    @Environment(\.dismiss) private var dismiss

    @State private var displayedMonth: Int
    @State private var isMovingForward = true

    // День, только что тапнутый пользователем — для анимации подсветки
    // перед закрытием календаря. Имеет ВЫСШИЙ приоритет над isSelected
    // (старый выбор) и isToday. nil, пока ничего не тапнули в этой сессии.
    @State private var justTappedDay: Int?
    // Блокирует повторные тапы, пока идёт анимация выбора и пауза перед
    // закрытием (иначе можно тапнуть второй день за время паузы).
    @State private var isSelecting = false

    init(selectedMonth: Int, selectedDay: Int, onDaySelected: @escaping (Date) -> Void) {
        self.selectedMonth = selectedMonth
        self.selectedDay = selectedDay
        self.onDaySelected = onDaySelected
        _displayedMonth = State(initialValue: selectedMonth)
    }

    private let daysPerMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    private var monthName: String {
        let symbols = DateFormatter().standaloneMonthSymbols ?? []
        guard displayedMonth >= 1, displayedMonth <= symbols.count else { return "" }
        return symbols[displayedMonth - 1].capitalized
    }

    private var daysInDisplayedMonth: Int {
        daysPerMonth[displayedMonth - 1]
    }

    // Компоненты «сегодня». Сравниваем ТОЛЬКО целые числа — никакого
    // конструирования Date для сравнения, чтобы не нарваться на
    // нормализацию 29 февраля в невисокосный год.
    private var todayMonth: Int {
        Calendar.current.component(.month, from: Date())
    }

    private var todayDay: Int {
        Calendar.current.component(.day, from: Date())
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                HStack {
                    Button {
                        stepMonth(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.blue)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    Text(monthName)
                        .font(.system(size: 20, weight: .semibold))
                        .id("month-\(displayedMonth)")
                        .transition(.opacity)

                    Spacer()

                    Button {
                        stepMonth(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.blue)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(1...daysInDisplayedMonth, id: \.self) { day in
                        // Только что тапнутый день (в текущем показанном месяце)
                        // — высший приоритет: это активный выбор пользователя.
                        let isTapped = (justTappedDay == day)
                        // Старый выбранный день. ВАЖНО: как только пользователь
                        // тапнул новый день (justTappedDay != nil), старое
                        // выделение гасим — иначе на экране два синих числа.
                        let isSelected = (justTappedDay == nil)
                            && (day == selectedDay && displayedMonth == selectedMonth)
                        // Заливка (синий фон) — либо тапнутый сейчас, либо
                        // ранее выбранный день (пока не тапнули новый).
                        let isFilled = isTapped || isSelected
                        // «Сегодня» показываем только если день НЕ залит —
                        // заливка имеет приоритет над обводкой сегодня.
                        let isToday = (day == todayDay && displayedMonth == todayMonth) && !isFilled
                        Button {
                            selectDay(day)
                        } label: {
                            Text("\(day)")
                                .font(.system(size: 17, weight: (isFilled || isToday) ? .semibold : .regular))
                                .foregroundColor(isFilled ? .white : (isToday ? .blue : .primary))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(isFilled ? Color.blue : Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    // Обводка для сегодня (когда он не залит)
                                    if isToday {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.blue, lineWidth: 2)
                                    }
                                }
                        }
                        .disabled(isSelecting)
                    }
                }
                .padding(.horizontal, 12)
                .id(displayedMonth)
                .transition(.asymmetric(
                    insertion: .move(edge: isMovingForward ? .trailing : .leading)
                        .combined(with: .opacity),
                    removal: .move(edge: isMovingForward ? .leading : .trailing)
                        .combined(with: .opacity)
                ))

                Spacer()

                Text("Будут показаны фото за этот день во все прошлые годы")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
            .background(
                MonthSwipeGesture(
                    onSwipeLeft: { stepMonth(1) },
                    onSwipeRight: { stepMonth(-1) }
                )
            )
            .navigationTitle("Выбор дня")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сегодня") { goToToday() }
                        .disabled(isSelecting)
                }
            }
        }
    }

    private func stepMonth(_ delta: Int) {
        HapticsService.shared.play(.light)
        isMovingForward = delta > 0

        let zeroBased = displayedMonth - 1 + delta
        let wrapped = ((zeroBased % 12) + 12) % 12

        withAnimation(.easeInOut(duration: 0.25)) {
            displayedMonth = wrapped + 1
        }
    }

    // MARK: - Переход на сегодня
    //
    // Вариант Б: сначала анимированно перелистываем календарь на текущий
    // месяц, даём анимации отыграть, затем выбираем сегодняшнее число
    // через существующий selectDay (он найдёт валидный Date, дёрнет
    // onDaySelected и закроет календарь).
    private func goToToday() {
        guard !isSelecting else { return }

        // Уже на текущем месяце — листать нечего, сразу выбираем.
        guard displayedMonth != todayMonth else {
            selectDay(todayDay)
            return
        }

        HapticsService.shared.play(.light)

        // Направление анимации по кратчайшему пути на кольце из 12 месяцев:
        // вперёд, если до текущего месяца ближе «по возрастанию».
        let forwardSteps = ((todayMonth - displayedMonth) + 12) % 12
        isMovingForward = forwardSteps <= 6

        withAnimation(.easeInOut(duration: 0.25)) {
            displayedMonth = todayMonth
        }

        // Пауза, чтобы переход месяца был виден до закрытия календаря.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            selectDay(todayDay)
        }
    }

    private func selectDay(_ day: Int) {
        // Защита от повторного тапа во время анимации/паузы.
        guard !isSelecting else { return }

        // Ищем валидный Date для (displayedMonth, day) в ближайших годах.
        // Делаем это ДО подсветки: если дата почему-то не собирается,
        // просто закрываемся без ложной анимации выбора.
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        var resolvedDate: Date?
        for year in stride(from: currentYear, through: currentYear - 8, by: -1) {
            var c = DateComponents()
            c.month = displayedMonth
            c.day = day
            c.year = year
            if let date = calendar.date(from: c) {
                let check = calendar.dateComponents([.month, .day], from: date)
                if check.month == displayedMonth, check.day == day {
                    resolvedDate = date
                    break
                }
            }
        }

        guard let date = resolvedDate else {
            dismiss()
            return
        }

        // Фаза 1: подсвечиваем тапнутый день (синяя заливка) с анимацией.
        isSelecting = true
        HapticsService.shared.play(.medium)
        withAnimation(.easeOut(duration: 0.15)) {
            justTappedDay = day
        }

        // Фаза 2: пауза, чтобы подсветку было видно, затем выбор и закрытие.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onDaySelected(date)
            dismiss()
        }
    }
}

#Preview {
    CalendarView(selectedMonth: 4, selectedDay: 1, onDaySelected: { date in
        print("Выбран день: \(date)")
    })
}
