import SwiftUI
import UIKit

/// Restores the edge-swipe-back that hiding the navigation bar takes away.
///
/// Every screen here draws its own `AppBar` and sets `navigationBarHidden`, and
/// UIKit's interactive pop gesture refuses to fire when there is no bar to pop.
/// So the app had no swipe-back anywhere — which is most of why moving between
/// screens felt inconsistent: the gesture worked in every other app on the
/// phone and did nothing in this one. Re-pointing the recogniser's delegate
/// brings it back without touching how the bar is drawn.
final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()

    /// Only when there is somewhere to go back to. Letting it begin on a stack
    /// root leaves the screen half-dragged and unresponsive.
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        navigationController(owning: gesture).map { $0.viewControllers.count > 1 } ?? false
    }

    /// Nothing else may run alongside it. The tab pager is a horizontal scroll
    /// view sitting directly under these screens, and allowing both to begin
    /// meant one edge swipe both popped a screen and turned the page.
    func gestureRecognizer(_ gesture: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        false
    }

    /// Read from the gesture itself rather than from a stored reference: there
    /// is one stack per tab, and the delegate is shared between them.
    private func navigationController(owning gesture: UIGestureRecognizer) -> UINavigationController? {
        var responder: UIResponder? = gesture.view
        while let current = responder {
            if let nav = current as? UINavigationController { return nav }
            responder = current.next
        }
        return nil
    }
}

/// An empty view controller whose only job is to find the navigation controller
/// it was pushed into and hand it the delegate above.
///
/// The delegate is a singleton because UIKit holds it weakly — putting it on
/// this controller would leave a dangling reference the moment the screen went
/// away, and the gesture would quietly stop working again.
private struct SwipeBackProbe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Probe() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    final class Probe: UIViewController {
        private func adopt() {
            navigationController?.interactivePopGestureRecognizer?.delegate = SwipeBackDelegate.shared
        }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            adopt()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            adopt()   // the parent is not always set by didMove
        }
    }
}

extension View {
    /// Put this on the root of a `NavigationStack` whose screens hide the bar.
    func swipeBackEnabled() -> some View {
        background(
            SwipeBackProbe()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}
