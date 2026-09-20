import UIKit

/// Shared, quiet controls. Navigation and scroll behavior belong to the page;
/// these buttons only supply the material, touch target, and symbol styling.
@MainActor
final class PaperIconButton: UIButton {
    init(symbol: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        var appearance: UIButton.Configuration
        if #available(iOS 26.0, *) {
            appearance = .glass()
        } else {
            appearance = .plain()
            appearance.background.backgroundColor = Theme.paperUIColor.withAlphaComponent(0.88)
            appearance.background.strokeColor = Theme.accentUIColor.withAlphaComponent(0.08)
            appearance.background.strokeWidth = 0.5
        }
        appearance.cornerStyle = .capsule
        appearance.baseForegroundColor = Theme.accentUIColor
        appearance.contentInsets = .zero
        appearance.image = UIImage(systemName: symbol)
        appearance.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: symbol == "plus" ? 23 : 17, weight: .regular)
        configuration = appearance
        tintColor = Theme.accentUIColor
        // Glass buttons otherwise apply their neutral symbol treatment even
        // when a foreground tint is supplied. Keep Drift's sepia ink explicit.
        configurationUpdateHandler = { button in
            var configuration = button.configuration
            configuration?.image = UIImage(systemName: symbol)?.withTintColor(
                Theme.accentUIColor.resolvedColor(with: button.traitCollection), renderingMode: .alwaysOriginal)
            button.configuration = configuration
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (button: PaperIconButton, _) in
            button.setNeedsUpdateConfiguration()
        }
        self.accessibilityLabel = accessibilityLabel
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 44) }
}

/// A soft continuation of the paper at the screen edge, never a touch barrier.
@MainActor
final class PaperEdgeFade: UIView {
    enum Edge { case top, bottom }
    private let edge: Edge
    var strength: CGFloat = 1 { didSet { updateColors() } }
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PaperEdgeFade, _) in
            view.updateColors()
        }
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateColors() {
        guard let gradient = layer as? CAGradientLayer else { return }
        let paper = Theme.paperUIColor.resolvedColor(with: traitCollection)
        // Keep scrolling words out of the clock and status symbols, then
        // dissolve the paper into the page instead of drawing a hard bar.
        let alphas: [CGFloat] = edge == .top ? [1, 1, 0] : [0, 0, 0.46, 0.90]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = alphas.map { paper.withAlphaComponent(min(1, $0 * strength)).cgColor }
        gradient.locations = edge == .top ? [0, 0.75, 1] : [0, 0.34, 0.78, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        CATransaction.commit()
    }
}

/// Keep UIKit's interactive Back while pages provide their own chrome.
@MainActor
final class PaperNavigationController: UINavigationController, UIGestureRecognizerDelegate, UINavigationControllerDelegate {
    var onDidShow: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        view.backgroundColor = Theme.paperUIColor
        navigationBar.tintColor = Theme.accentUIColor
        setNavigationBarHidden(true, animated: false)
        interactivePopGestureRecognizer?.delegate = self
        interactivePopGestureRecognizer?.isEnabled = true
    }

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        operation == .push ? PaperPushAnimator() : nil
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        onDidShow?()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1 && transitionCoordinator == nil
    }
}

/// Animate the page while the live keyboard arrives, avoiding the observed
/// keyboard color handoff. Pop and interactive Back remain native.
@MainActor
private final class PaperPushAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private var animator: UIViewPropertyAnimator?
    private let usesCrossFade = UIAccessibility.isReduceMotionEnabled || UIAccessibility.prefersCrossFadeTransitions

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        if transitionContext?.isAnimated == false { return 0 }
        return usesCrossFade ? 0.15 : 0.35
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        interruptibleAnimator(using: transitionContext).startAnimation()
    }

    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        if let animator { return animator }
        guard let fromController = transitionContext.viewController(forKey: .from),
              let toController = transitionContext.viewController(forKey: .to),
              let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to) else {
            transitionContext.completeTransition(false)
            return UIViewPropertyAnimator(duration: 0, curve: .linear)
        }
        let container = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: toController)
        let outgoingFrame = transitionContext.initialFrame(for: fromController)
        let direction: CGFloat = container.effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
        let distance = container.bounds.width * direction
        let originalFromTransform = fromView.transform
        let originalToTransform = toView.transform
        let originalToAlpha = toView.alpha
        let usesCrossFade = self.usesCrossFade
        fromView.frame = outgoingFrame
        toView.frame = finalFrame
        toView.transform = usesCrossFade ? originalToTransform : originalToTransform.translatedBy(x: distance, y: 0)
        toView.alpha = usesCrossFade ? 0 : originalToAlpha
        container.addSubview(toView)
        toView.layoutIfNeeded()
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext), curve: .easeInOut) {
            if !usesCrossFade {
                fromView.transform = originalFromTransform.translatedBy(x: -distance / 3, y: 0)
            }
            toView.transform = originalToTransform
            toView.alpha = originalToAlpha
        }
        animator.addCompletion { _ in
            let completed = !transitionContext.transitionWasCancelled
            fromView.transform = originalFromTransform
            toView.transform = originalToTransform
            toView.alpha = originalToAlpha
            if !completed { toView.removeFromSuperview() }
            transitionContext.completeTransition(completed)
        }
        self.animator = animator
        return animator
    }

    func animationEnded(_ transitionCompleted: Bool) {
        animator = nil
    }
}
