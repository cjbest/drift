import UIKit

/// The same calm empty state is used for first launch, empty folders and search.
final class NotebookEmptyView: UIView {
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        symbolView.contentMode = .scaleAspectFit
        symbolView.tintColor = Theme.accentUIColor
        titleLabel.font = Theme.serif(34, style: .largeTitle, italic: true)
        titleLabel.textColor = Theme.inkUIColor
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = Theme.secondaryInkUIColor
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.adjustsFontForContentSizeCategory = true
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = Theme.accentUIColor
        config.baseForegroundColor = Theme.paperUIColor
        config.cornerStyle = .capsule
        config.contentInsets = .init(top: 16, leading: 26, bottom: 16, trailing: 26)
        actionButton.configuration = config
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [symbolView, titleLabel, detailLabel, actionButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.setCustomSpacing(30, after: symbolView)
        stack.setCustomSpacing(28, after: detailLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        addSubview(scroll)
        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        content.addSubview(stack)
        let center = stack.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -16)
        center.priority = .defaultLow
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            center,
            symbolView.widthAnchor.constraint(equalToConstant: 44),
            symbolView.heightAnchor.constraint(equalToConstant: 48),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 330),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(symbol: String, title: String, detail: String, action: String?) {
        symbolView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .ultraLight))
        titleLabel.text = title
        detailLabel.text = detail
        actionButton.configuration?.title = action
        actionButton.accessibilityLabel = action
        actionButton.isHidden = action == nil
    }
}
