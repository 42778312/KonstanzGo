import SwiftUI

#if os(iOS)
import UIKit

extension View {
    /// The system's swipe back, which iOS turns off when a stack hides its navigation bar.
    func kgSwipeBack() -> some View {
        background(SwipeBack().frame(width: 0, height: 0))
    }
}

private struct SwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard let stack = navigationController else { return }
            stack.interactivePopGestureRecognizer?.isEnabled = true
            stack.interactivePopGestureRecognizer?.delegate = self
            if #available(iOS 26, *) {
                stack.interactiveContentPopGestureRecognizer?.isEnabled = true
                stack.interactiveContentPopGestureRecognizer?.delegate = self
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
#else
extension View {
    func kgSwipeBack() -> some View { self }
}
#endif
