import UIKit

/// A cropped view of the system chooser, with Browse called out before it opens.
final class FolderPickerIllustrationView: UIView {
    static let aspectRatio: CGFloat = 900.0 / 310.0

    private let screenshotView = UIImageView()
    private let browseRing = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 18
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = "Tap Browse at the bottom right of the next screen."
        screenshotView.isAccessibilityElement = false
        screenshotView.contentMode = .scaleToFill
        addSubview(screenshotView)

        browseRing.fillColor = UIColor.clear.cgColor
        browseRing.strokeColor = UIColor(red: 1, green: 0.27, blue: 0.20, alpha: 1).cgColor
        browseRing.lineCap = .round
        layer.addSublayer(browseRing)

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: FolderPickerIllustrationView, _) in
            view.updateScreenshot()
        }
        updateScreenshot()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 320, height: 320 / Self.aspectRatio)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let screenshot = screenshotView.image, bounds.width > 0 else { return }

        // Keep the original screenshots intact. The viewport hides their empty upper area.
        let crop = CGRect(x: 150, y: traitCollection.userInterfaceStyle == .dark ? 339 : 510,
                          width: 900, height: 310)
        let scale = min(bounds.width / crop.width, bounds.height / crop.height)
        let origin = CGPoint(x: (bounds.width - crop.width * scale) / 2,
                             y: (bounds.height - crop.height * scale) / 2)
        screenshotView.frame = CGRect(x: origin.x - crop.minX * scale,
                                      y: origin.y - crop.minY * scale,
                                      width: screenshot.size.width * scale,
                                      height: screenshot.size.height * scale)

        let ringRect = CGRect(x: origin.x + 554 * scale, y: origin.y + 50 * scale,
                              width: 312 * scale, height: 217 * scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        browseRing.frame = bounds
        browseRing.path = UIBezierPath(ovalIn: ringRect).cgPath
        browseRing.lineWidth = max(3.5, 12 * scale)
        CATransaction.commit()
    }

    private func updateScreenshot() {
        screenshotView.image = UIImage(named: "FolderPickerTabs", in: .main, compatibleWith: traitCollection)
        setNeedsLayout()
    }
}
