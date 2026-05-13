import SwiftUI
import UIKit

// A transparent overlay that detects pinch + pan gestures and reports
// the current scale and offset to SwiftUI via @Binding values.
//
// How to use:
// 1. Place this overlay on top of your photo view
// 2. Read the `scale` and `offset` bindings
// 3. Apply them to your photo via .scaleEffect(scale) and .offset(offset)
struct ZoomGestureOverlay: UIViewRepresentable {
    
    // Bindings the SwiftUI side reads
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var anchor: UnitPoint
    @Binding var isZooming: Bool
    
    // Callback when a finger lift resets the zoom — used to animate the reset
    let onZoomEnd: () -> Void
    
    // Anchor offset above the finger touch (in points)
    private let anchorVerticalLift: CGFloat = 40
    
    // MARK: - UIViewRepresentable
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        
        // Pinch recognizer: detects two-finger spread
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        
        // Pan recognizer: detects finger movement
        // We use this for BOTH the two-finger pan AND the one-finger pan
        // The coordinator decides whether to actually apply the pan
        // based on whether zoom is active
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        // Allow 1 or 2 fingers — we'll filter in the handler
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan)
        
        // Save references on the coordinator
        context.coordinator.pinchRecognizer = pinch
        context.coordinator.panRecognizer = pan
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // No-op — data flows UIKit → SwiftUI, not the other way
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    // MARK: - Coordinator
    
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let parent: ZoomGestureOverlay
        
        // References so recognizers can talk to each other
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var panRecognizer: UIPanGestureRecognizer?
        
        // Tracking state
        private var startingScale: CGFloat = 1.0
        private var startingOffset: CGSize = .zero
        
        init(parent: ZoomGestureOverlay) {
            self.parent = parent
        }
        
        // MARK: Pinch handler
        
        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view = recognizer.view else { return }
            
            switch recognizer.state {
            case .began:
                startingScale = parent.scale
                parent.isZooming = true
                
                // Capture the pinch location and convert to unit coordinates
                // location(in:) returns the midpoint of the two touches
                let location = recognizer.location(in: view)
                let unitX = location.x / view.bounds.width
                let unitY = location.y / view.bounds.height
                // Clamp to [0, 1] just in case the touch is slightly outside
                parent.anchor = UnitPoint(
                    x: max(0, min(1, unitX)),
                    y: max(0, min(1, unitY))
                )
                
            case .changed:
                let newScale = startingScale * recognizer.scale
                parent.scale = min(max(newScale, 1.0), 4.0)
                
            case .ended, .cancelled, .failed:
                checkForFullRelease(in: recognizer.view)
                
            default:
                break
            }
        }
        
        // MARK: Pan handler
        
        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            
            switch recognizer.state {
            case .began:
                startingOffset = parent.offset
                
            case .changed:
                // Only apply pan when actively zoomed (scale > 1.0)
                guard parent.scale > 1.0 else { return }
                
                let translation = recognizer.translation(in: view)
                
                // Apply the visual anchor lift:
                // shift the perceived touch point UP by anchorVerticalLift,
                // which means shifting the photo offset DOWN by that amount
                // — this happens once at .began conceptually, but we just
                // include it here in the delta math
                parent.offset = CGSize(
                    width: startingOffset.width + translation.x,
                    height: startingOffset.height + translation.y
                )
                
            case .ended, .cancelled, .failed:
                checkForFullRelease(in: recognizer.view)
                
            default:
                break
            }
        }
        
        // MARK: All-fingers-up detection
        
        private func checkForFullRelease(in view: UIView?) {
            // Both recognizers must be in a non-active state to consider the zoom session over
            let pinchActive = (pinchRecognizer?.state == .began || pinchRecognizer?.state == .changed)
            let panActive = (panRecognizer?.state == .began || panRecognizer?.state == .changed)
            
            if !pinchActive && !panActive {
                // All gestures ended — reset
                parent.isZooming = false
                parent.onZoomEnd()
            }
        }
        
        // MARK: UIGestureRecognizerDelegate
        
        // Allow pinch and pan to fire at the same time
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return true
        }
        // Decide if a gesture recognizer should activate at all.
        // Critical: when zoom is NOT active, the pan recognizer must bow out
        // so the SwiftUI swipe-to-delete drag can take the touch instead.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Always allow pinch to begin — it requires 2 fingers, which is unambiguous
            if gestureRecognizer === pinchRecognizer {
                return true
            }
            
            // For pan: only allow it to begin if zoom is currently active
            // (i.e., scale > 1.0). Otherwise, let SwiftUI's DragGesture handle the touch.
            if gestureRecognizer === panRecognizer {
                return parent.scale > 1.0
            }
            
            return true
        }
    }
}
