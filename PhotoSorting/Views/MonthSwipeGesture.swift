import SwiftUI
import UIKit

// Горизонтальный свайп для листания месяцев в календаре.
//
// Почему UIKit, а не SwiftUI DragGesture: DragGesture конкурирует с системным
// свайпом-вниз, которым закрывается .sheet, и часто перехватывает вертикаль,
// ломая закрытие. UISwipeGestureRecognizer, настроенный ТОЛЬКО на .left/.right,
// по устройству не реагирует на вертикаль — свайп-вниз для закрытия листа
// остаётся полностью за системой. Тот же приём, что в ZoomGestureOverlay.
struct MonthSwipeGesture: UIViewRepresentable {

    let onSwipeLeft: () -> Void   // палец справа налево → следующий месяц
    let onSwipeRight: () -> Void  // палец слева направо → предыдущий месяц

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let left = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLeft)
        )
        left.direction = .left
        view.addGestureRecognizer(left)

        let right = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRight)
        )
        right.direction = .right
        view.addGestureRecognizer(right)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onLeft: onSwipeLeft, onRight: onSwipeRight)
    }

    final class Coordinator: NSObject {
        let onLeft: () -> Void
        let onRight: () -> Void

        init(onLeft: @escaping () -> Void, onRight: @escaping () -> Void) {
            self.onLeft = onLeft
            self.onRight = onRight
        }

        @objc func handleLeft() { onLeft() }
        @objc func handleRight() { onRight() }
    }
}
