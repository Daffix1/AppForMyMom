import SwiftUI

struct OnboardingView: View {
    // Колбэк вызывается когда пользователь прошёл онбординг
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
            buttonTitle: "Поехали"
        )
    ]
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Индикатор страниц вверху
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
        Button(pages[currentPage].buttonTitle) {
            handleButtonTap()
        }
        .primaryButtonStyle()
    }
    
    // MARK: - Логика кнопки
    
    private func handleButtonTap() {
        if currentPage < pages.count - 1 {
            // Не последняя страница — листаем вперёд
            withAnimation {
                currentPage += 1
            }
        } else {
            // Последняя страница — отмечаем онбординг пройденным
            StorageService.shared.onboardingCompleted = true
            onComplete()
        }
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
