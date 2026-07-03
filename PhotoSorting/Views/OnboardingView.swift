import SwiftUI

struct OnboardingView: View {
    // Колбэк вызывается когда пользователь прошёл онбординг
    // (либо долистал и нажал финальную кнопку, либо нажал "Пропустить").
    // Дальше по цепочке MainScreenView.loadPhotos() запросит доступ к фото.
    let onComplete: () -> Void
    
    @State private var currentPage = 0
    
    // Все страницы онбординга
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "photo.stack.fill",
            iconColor: .red,
            title: "Галерея переполнена?",
            description: "У нас всех тысячи ненужных скриншотов, дубликатов и случайных снимков, которые занимают место и мешают находить важные моменты.",
            buttonTitle: "Дальше"
        ),
        OnboardingPage(
            icon: "hand.draw.fill",
            iconColor: .blue,
            title: "Маленькая порция в день",
            description: "Каждый день — фото из этого же дня прошлых лет. Свайп влево — удалить, вправо — оставить. Несколько минут — и галерея чище.",
            buttonTitle: "Дальше"
        ),
        OnboardingPage(
            icon: "sparkles",
            iconColor: .orange,
            title: "Готовы начать?",
            description: "Нам нужен доступ к вашей галерее, чтобы найти фото для разбора. Все ваши данные остаются на устройстве — мы ничего никуда не отправляем.",
            // На последней странице надпись финальной кнопки переопределяется
            // вычисляемым свойством actionButtonTitle (см. ниже). Это значение
            // здесь — запасное, на случай если логика страниц поменяется.
            buttonTitle: "Дать доступ к фото"
        )
    ]
    
    // Удобный флаг: находимся ли на последней странице.
    private var isLastPage: Bool {
        currentPage == pages.count - 1
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Верхний ряд: "Назад" слева, "Пропустить" справа
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                
                // Индикатор страниц
                pageIndicator
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                
                // Содержимое текущей страницы
                TabView(selection: $currentPage) {
                    // ForEach перебирает страницы и создаёт View для каждой
                    ForEach(0..<pages.count, id: \.self) { index in
                        pageContent(pages[index])
                            .tag(index)
                    }
                }
                
                .tabViewStyle(.page(indexDisplayMode: .never)) // чтобы свайп работал
                
                // Кнопка действия
                actionButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
    }
    
    // MARK: - Верхний ряд (Назад / Пропустить)
    
    private var topBar: some View {
        HStack {
            // "Назад" — появляется со 2-й страницы.
            // На 1-й странице рисуем невидимую заглушку того же размера,
            // чтобы "Пропустить" справа не прыгал по горизонтали.
            if currentPage > 0 {
                Button {
                    goBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Назад")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.blue)
                }
            } else {
                // Невидимая заглушка-распорка (занимает место, но не видна)
                Text("Назад")
                    .font(.system(size: 16, weight: .medium))
                    .opacity(0)
            }
            
            Spacer()
            
            // "Пропустить" — на всех страницах, кроме последней.
            // Делает то же, что финальная кнопка: завершает онбординг.
            if !isLastPage {
                Button {
                    completeOnboarding()
                } label: {
                    Text("Пропустить")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else {
                // Заглушка-распорка для симметрии высоты ряда
                Text("Пропустить")
                    .font(.system(size: 16, weight: .medium))
                    .opacity(0)
            }
        }
        .frame(height: 24)
    }
    
    // MARK: - Индикатор страниц
    
    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { index in
                // Активная страница - широкая полоска, неактивная - точка
                Capsule()
                    .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.3))
                    .frame(
                        width: index == currentPage ? 24 : 8,
                        height: 8
                    )
                    // Анимация при смене страницы
                    .animation(.spring(response: 0.3), value: currentPage)
            }
        }
    }
    
    // MARK: - Содержимое одной страницы
    
    private func pageContent(_ page: OnboardingPage) -> some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Иконка
            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundColor(page.iconColor)
                .shadow(color: page.iconColor.opacity(0.3), radius: 20, y: 10)
            
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(4)
            }
            
            Spacer()
            Spacer()
        }
    }
    
    // MARK: - Кнопка действия
    
    private var actionButton: some View {
        Button(actionButtonTitle) {
            handleButtonTap()
        }
        .primaryButtonStyle()
    }
    
    // Надпись на нижней кнопке: на последней странице — "Дать доступ к фото",
    // на остальных — "Дальше". Берём текст из модели страницы, но для
    // последней страницы делаем явный кейс, чтобы намерение читалось в коде.
    private var actionButtonTitle: String {
        if isLastPage {
            return "Дать доступ к фото"
        } else {
            return pages[currentPage].buttonTitle
        }
    }
    
    // MARK: - Логика кнопок
    
    // Тап по нижней кнопке.
    private func handleButtonTap() {
        if isLastPage {
            // Последняя страница — завершаем онбординг.
            // Дальше MainScreenView запросит доступ к фото (системное окно).
            completeOnboarding()
        } else {
            // Не последняя страница — листаем вперёд.
            withAnimation {
                currentPage += 1
            }
        }
    }
    
    // "Назад" — на предыдущую страницу.
    private func goBack() {
        guard currentPage > 0 else { return }
        withAnimation {
            currentPage -= 1
        }
    }
    
    // Завершение онбординга. Вызывается из:
    //   - финальной кнопки на последней странице
    //   - кнопки "Пропустить"
    // Оба сценария ведут к одному и тому же: помечаем онбординг пройденным
    // и зовём onComplete(), который запустит запрос доступа к фото.
    private func completeOnboarding() {
        StorageService.shared.onboardingCompleted = true
        onComplete()
    }
}

// MARK: - Модель страницы

// Структура одной страницы онбординга
struct OnboardingPage {
    let icon: String         // имя SF Symbol
    let iconColor: Color
    let title: String
    let description: String
    let buttonTitle: String
}

#Preview {
    OnboardingView(onComplete: {})
}
