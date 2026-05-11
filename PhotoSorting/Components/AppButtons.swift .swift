import SwiftUI

// MARK: - ButtonStyle: Primary

// Основная кнопка приложения. Синий фон, белый текст.
// Используется для главных действий: "Начать", "Разрешить доступ", "Дальше"
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - ButtonStyle: Destructive

// Опасное действие. Красный фон, белый текст.
// Используется для удаления: "Удалить N фото в корзину"
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - ButtonStyle: Secondary

// Альтернативное действие. Бледно-синий фон, синий текст.
// Используется когда у Primary есть конкурирующая опция.
// Пример: "Отсортировать остальное" рядом с "Удалить N в корзину"
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.blue.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - ButtonStyle: Plain Destructive

// "Тихая" опасная кнопка. Прозрачный фон, красный текст.
// Используется для опасных действий, которые не должны быть слишком заметными.
// Пример: "Начать сортировку заново" — пользователь сначала должен видеть
// безопасные опции, а это альтернатива внизу
struct PlainDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

// Удобные шорткаты для применения стилей.
// Позволяют писать .primaryButtonStyle() вместо .buttonStyle(PrimaryButtonStyle())
extension View {
    func primaryButtonStyle() -> some View {
        self.buttonStyle(PrimaryButtonStyle())
    }
    
    func destructiveButtonStyle() -> some View {
        self.buttonStyle(DestructiveButtonStyle())
    }
    
    func secondaryButtonStyle() -> some View {
        self.buttonStyle(SecondaryButtonStyle())
    }
    
    func plainDestructiveButtonStyle() -> some View {
        self.buttonStyle(PlainDestructiveButtonStyle())
    }
}
