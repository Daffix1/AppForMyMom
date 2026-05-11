import SwiftUI

struct CustomSlider: View {
    // ссылка на State из видеовью
    @Binding var value: Double
    
    // Диапазон длительности видео
    let range: ClosedRange<Double>
    
    // Тянут ползунок или нет
    let onEditingChanged: (Bool) -> Void
    
    // Переключалка тянучки
    @State private var isDragging = false
    
    var body: some View {
        // GeometryReader даёт нам точные размеры родителя
        // Это нужно чтобы вычислить позицию ползунка в пикселях
        GeometryReader { geometry in
            // Копируем дефолтный слайдер
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.white)
                    .frame(
                        width: progressWidth(totalWidth: geometry.size.width),
                        height: 4
                    )
                
                // Кружок ползунок
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .offset(x: progressWidth(totalWidth: geometry.size.width) - 7)
            }
            .frame(height: 32)
            .contentShape(Rectangle())// делает всю область ползунка + небольшую зону вокруг кликабельной
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        // Начали тянуть
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        // Вычисляем новое значение по позиции пальца
                        updateValue(
                            location: gesture.location.x,
                            totalWidth: geometry.size.width
                        )
                    }
                    .onEnded { _ in
                        // Отпустили
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 32)
    }
    
    // MARK: - Вычисление ширины заполненной части
    
    private func progressWidth(totalWidth: CGFloat) -> CGFloat {
        let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        // Ограничиваем 0...1 чтобы кружок не вылетал за границы
        let clamped = max(0, min(1, progress))
        return CGFloat(clamped) * totalWidth
    }
    
    // MARK: - Обновление значения по позиции пальца
    
    private func updateValue(location: CGFloat, totalWidth: CGFloat) {
        // Защита от деления на ноль
        guard totalWidth > 0 else { return }
        
        // Превращаем позицию пальца в значение от 0 до 1
        let progress = max(0, min(1, location / totalWidth))
        
        // Превращаем в значение в нужном диапазоне
        let newValue = range.lowerBound + Double(progress) * (range.upperBound - range.lowerBound)
        
        value = newValue
    }
}
