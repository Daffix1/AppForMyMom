import SwiftUI

// Экран выбора даты для сортировки "этого дня прошлых лет".
//
// Что делает:
//   - Показывает системный календарь (DatePicker в стиле .graphical).
//   - Позволяет выбрать любой день от далёкого прошлого до сегодня включительно.
//     Будущее выбрать нельзя — там нет "прошлых лет" относительно будущей даты,
//     это только сбивало бы с толку.
//   - По кнопке "Начать сортировку" отдаёт выбранную дату наверх через колбэк
//     onDateSelected и закрывается.
//
// Чего НЕ делает (намеренно):
//   - Не знает про SessionStore, SortingView, StorageService и прочую механику
//     сортировки. Его единственная задача — выбрать дату и сообщить наверх.
//     Куда потом ведёт эта дата — решает вызывающая сторона (MainScreenView).
//     Такое разделение делает экран самодостаточным и лёгким для тестирования.
struct CalendarView: View {
    
    // Колбэк: вызывается с выбранной датой, когда пользователь
    // нажал "Начать сортировку". Вызывающая сторона решает, что делать дальше.
    let onDateSelected: (Date) -> Void
    
    // dismiss — стандартный способ закрыть .sheet изнутри самого экрана.
    @Environment(\.dismiss) private var dismiss
    
    // Выбранная дата. По умолчанию — сегодня.
    // @State: локальное состояние экрана, DatePicker будет писать сюда через $binding.
    @State private var selectedDate = Date()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // MARK: - Календарь
                
                DatePicker(
                    "Дата",
                    selection: $selectedDate,
                    // Ограничиваем диапазон: от "давным-давно" до сегодня включительно.
                    // ...dateRangeUpperBound означает "любая дата вплоть до верхней границы".
                    // Дни за пределами диапазона в календаре становятся недоступными (серыми).
                    in: dateRangeLowerBound...dateRangeUpperBound,
                    displayedComponents: .date  // только дата, без времени
                )
                // .graphical — тот самый календарь-сетка с кружочками дней.
                // Именно этот стиль показывает месяц целиком, а не выпадашку.
                .datePickerStyle(.graphical)
                // Красим акцент в синий, чтобы совпадало с остальным приложением.
                .tint(.blue)
                .padding(.horizontal, 12)
                
                Spacer()
                
                // MARK: - Пояснение + кнопка
                
                VStack(spacing: 16) {
                    // Подсказка: за какой день соберём фото.
                    // Помогает пользователю понять, что выбор даты = "этот день прошлых лет".
                    VStack(spacing: 4) {
                        Text("Будут показаны фото за")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text(selectedDayString)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("во все прошлые годы")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    
                    Button("Начать сортировку") {
                        // Отдаём выбранную дату наверх и закрываемся.
                        onDateSelected(selectedDate)
                        dismiss()
                    }
                    .primaryButtonStyle()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("Выбор дня")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Кнопка закрытия без выбора — просто уйти с экрана.
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
    
    // MARK: - Границы диапазона дат
    
    // Верхняя граница — сегодня. Будущее недоступно.
    private var dateRangeUpperBound: Date {
        Date()
    }
    
    // Нижняя граница — 40 лет назад. Совпадает с yearsBack в PhotoLibraryService:
    // глубже мы всё равно не ищем фото, так что и выбирать нет смысла.
    private var dateRangeLowerBound: Date {
        Calendar.current.date(byAdding: .year, value: -40, to: Date()) ?? Date()
    }
    
    // MARK: - Красивая строка выбранного дня
    
    // Выбранную дату показываем как "3 мая" — день и месяц словом, по-русски.
    // Год не показываем: суть механики в "этом дне прошлых лет", год тут не важен.
    private var selectedDayString: String {
        selectedDate.formatted(.dateTime.day().month(.wide))
    }
}

#Preview {
    // В превью колбэк ничего не делает — просто печатает дату в консоль.
    CalendarView(onDateSelected: { date in
        print("Выбрана дата: \(date)")
    })
}
