import UIKit

/// A brief visual cue before handing navigation over to the system's folder picker.
final class FolderPickerGuideViewController: UIViewController {
    var onContinue: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.paperUIColor
        view.tintColor = Theme.accentUIColor
        view.accessibilityIdentifier = "folder-picker-guide"

        let title = UILabel()
        title.text = "Find your iCloud folder"
        title.font = Theme.serif(28, style: .title1)
        title.textColor = Theme.inkUIColor
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits.insert(.header)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = Theme.secondaryInkUIColor
        close.accessibilityLabel = "Close"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        close.widthAnchor.constraint(equalToConstant: 44).isActive = true
        close.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let heading = UIStackView(arrangedSubviews: [title, close])
        heading.alignment = .center
        heading.spacing = 8

        let detail = UILabel()
        let font = UIFont.preferredFont(forTextStyle: .body)
        let text = "On the next screen, tap Browse and choose a folder on your iCloud Drive."
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font])
        if let bold = font.fontDescriptor.withSymbolicTraits(.traitBold) {
            for phrase in ["Browse", "iCloud Drive"] {
                attributed.addAttribute(.font, value: UIFont(descriptor: bold, size: 0),
                                        range: (text as NSString).range(of: phrase))
            }
        }
        detail.attributedText = attributed
        detail.textColor = Theme.inkUIColor
        detail.numberOfLines = 0
        detail.adjustsFontForContentSizeCategory = true

        let illustration = FolderPickerIllustrationView()
        illustration.heightAnchor.constraint(equalTo: illustration.widthAnchor,
                                             multiplier: 1 / FolderPickerIllustrationView.aspectRatio).isActive = true

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Continue"
        configuration.baseBackgroundColor = Theme.accentUIColor
        configuration.baseForegroundColor = Theme.paperUIColor
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .init(top: 16, leading: 24, bottom: 16, trailing: 24)
        let next = UIButton(configuration: configuration)
        next.accessibilityIdentifier = "folder-guide-continue"
        next.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.view.isUserInteractionEnabled = false
            let continueAction = self.onContinue
            self.dismiss(animated: true) { continueAction?() }
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [heading, detail, illustration, next])
        stack.axis = .vertical
        stack.spacing = 22
        stack.setCustomSpacing(14, after: heading)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -56),
        ])
        preferredContentSize = CGSize(width: 440, height: 430)
    }
}
