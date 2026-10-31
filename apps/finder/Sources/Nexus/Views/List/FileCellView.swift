import AppKit
import BrowserKit
import ThemeKit

/// One cell: the name column has an SF Symbol, the name, tag dots and the
/// Google Drive badge (R14); the others are one line of text. Text truncates.
final class FileCellView: NSTableCellView {
    struct Info {
        let folderSize: Int64?
        let badge: DriveBadge?
        let isCut: Bool
        let theme: Theme?
    }

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let extra = NSImageView()
    private let tagDots = NSStackView()

    init(column: FileColumn, identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = column == .name ? .byTruncatingMiddle : .byTruncatingTail
        label.alignment = column.alignment
        label.cell?.usesSingleLineMode = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField = label
        addSubview(label)
        if column == .name {
            label.isEditable = true
            icon.translatesAutoresizingMaskIntoConstraints = false
            extra.translatesAutoresizingMaskIntoConstraints = false
            tagDots.translatesAutoresizingMaskIntoConstraints = false
            tagDots.spacing = 2
            imageView = icon
            addSubview(icon)
            addSubview(tagDots)
            addSubview(extra)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                tagDots.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
                tagDots.centerYAnchor.constraint(equalTo: centerYAnchor),
                extra.leadingAnchor.constraint(equalTo: tagDots.trailingAnchor, constant: 4),
                extra.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
                extra.centerYAnchor.constraint(equalTo: centerYAnchor),
                extra.widthAnchor.constraint(equalToConstant: 14),
            ])
        } else {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(_ item: FileItem, column: FileColumn, row info: Info) {
        let text = info.theme.map { NSColor($0.text) } ?? .labelColor
        let dim = info.theme.map { NSColor($0.dim) } ?? .secondaryLabelColor
        alphaValue = info.isCut ? 0.45 : 1
        switch column {
        case .name:
            label.stringValue = item.name
            label.textColor = text
            label.isEditable = !item.isInArchive
            icon.image = NSImage(systemSymbolName: FileSymbol.name(for: item), accessibilityDescription: nil)
            let accent = info.theme.map { NSColor($0.accent) } ?? .controlAccentColor
            icon.contentTintColor = item.isFolder ? accent : dim
            extra.image = info.badge.flatMap { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.label) }
            extra.contentTintColor = dim
            extra.toolTip = info.badge?.label
            showTags(item.tags, theme: info.theme)
        case .modified:
            label.stringValue = item.modified.map { ItemFormat.date($0) } ?? "--"
            label.textColor = dim
        case .size:
            let bytes = item.isFolder ? info.folderSize : item.size
            label.stringValue = bytes.map(ItemFormat.size) ?? (item.isFolder ? "…" : "--")
            label.textColor = dim
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        case .kind:
            label.stringValue = item.kind
            label.textColor = dim
        }
    }

    /// Finder's colour tags as dots, in the theme's terminal colours.
    private func showTags(_ tags: [String], theme: Theme?) {
        tagDots.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let slots: [String: Int] = ["Red": 1, "Orange": 9, "Yellow": 3, "Green": 2, "Blue": 4, "Purple": 5, "Gray": 8]
        for tag in tags.prefix(4) {
            let dot = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: tag) ?? NSImage())
            dot.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 7, weight: .regular)
            if let theme, let slot = slots[tag], slot < theme.palette.count {
                dot.contentTintColor = NSColor(theme.palette[slot])
            } else {
                dot.contentTintColor = theme.map { NSColor($0.faint) }
            }
            dot.toolTip = tag
            tagDots.addArrangedSubview(dot)
        }
    }
}
