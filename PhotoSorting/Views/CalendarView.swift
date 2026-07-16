import SwiftUI

struct CalendarView: View {

    let onDaySelected: (Date) -> Void

    let selectedMonth: Int
    let selectedDay: Int

    @Environment(\.dismiss) private var dismiss

    @State private var displayedMonth: Int
    @State private var isMovingForward = true

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
                        let isSelected = (day == selectedDay && displayedMonth == selectedMonth)
                        Button {
                            selectDay(day)
                        } label: {
                            Text("\(day)")
                                .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? .white : .primary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
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

    private func selectDay(_ day: Int) {
        var components = DateComponents()
        components.month = displayedMonth
        components.day = day

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        for year in stride(from: currentYear, through: currentYear - 8, by: -1) {
            var c = components
            c.year = year
            if let date = calendar.date(from: c) {
                let check = calendar.dateComponents([.month, .day], from: date)
                if check.month == displayedMonth, check.day == day {
                    onDaySelected(date)
                    dismiss()
                    return
                }
            }
        }
        dismiss()
    }
}

#Preview {
    CalendarView(selectedMonth: 4, selectedDay: 1, onDaySelected: { date in
        print("Выбран день: \(date)")
    })
}
