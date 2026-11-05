import AppKit
import BrowserKit
import ThemeKit

/// The quiet header before the files a search found only by what is inside
/// them: "Found inside files (1,594)", a hairline, and Hide, which leaves
/// them out of this search (the search bar's Inside files chip brings them back).
final class InsideFilesHeaderView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("insideFilesHeader")

    private let label = NSTextField(labelWithString: "")
    private let rule = NSBox()
    private let hide = NSButton(title: "Hide", target: nil, action: nil)
    private var onHide: (() -> Void)?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        rule.boxType = .custom
        rule.borderWidth = 0
        rule.translatesAutoresizingMaskIntoConstraints = false
        hide.isBordered = false
        hide.font = .systemFont(ofSize: 11)
        hide.target = self
        hide.action = #selector(hideClicked(_:))
        hide.setAccessibilityLabel("Hide matches inside files")
        hide.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(rule)
        addSubview(hide)
        textField = label
        setAccessibilityIdentifier("nexus.search.insideFilesHeader")
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            rule.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            rule.centerYAnchor.constraint(equalTo: centerYAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            hide.leadingAnchor.constraint(equalTo: rule.trailingAnchor, constant: 8),
            hide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            hide.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        label.setContentHuggingPriority(.required, for: .horizontal)
        hide.setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    func show(count: Int, theme: Theme?, onHide: @escaping () -> Void) {
        self.onHide = onHide
        label.stringValue = ItemFormat.insideFilesHeader(count)
        if let theme {
            label.textColor = NSColor(theme.dim)
            rule.fillColor = NSColor(theme.hairline)
            hide.contentTintColor = NSColor(theme.accent)
        }
    }

    @objc private func hideClicked(_ sender: Any?) {
        onHide?()
    }
}
