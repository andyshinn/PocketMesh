import MapKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Annotation view displaying stats badge with liquid glass styling
final class StatsBadgeView: MKAnnotationView {
    static let reuseIdentifier = "StatsBadgeView"

    #if canImport(UIKit)
    private let containerView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    #else
    private let containerView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .popover
        view.state = .active
        view.wantsLayer = true
        return view
    }()
    #endif
    private let label = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Container with blur
        containerView.translatesAutoresizingMaskIntoConstraints = false
        #if canImport(UIKit)
        containerView.layer.cornerRadius = 12
        containerView.layer.masksToBounds = true
        #else
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true
        #endif
        addSubview(containerView)

        // Shadow
        #if canImport(UIKit)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        #else
        wantsLayer = true
        layer?.shadowColor = UIColor.black.cgColor
        layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: 2)
        #endif

        // Label with Dynamic Type
        label.translatesAutoresizingMaskIntoConstraints = false
        let baseFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .medium)
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: baseFont)
        label.adjustsFontForContentSizeCategory = true
        #if canImport(UIKit)
        label.textColor = .label
        #else
        label.textColor = .labelColor
        #endif
        label.textAlignment = .center
        #if canImport(UIKit)
        containerView.contentView.addSubview(label)
        #else
        containerView.addSubview(label)
        #endif

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            label.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10)
        ])

        canShowCallout = false
        isEnabled = false
    }

    func configure(with annotation: StatsBadgeAnnotation) {
        label.text = annotation.displayString

        // Size to fit content
        label.sizeToFit()
        let size = CGSize(
            width: label.frame.width + 20,
            height: label.frame.height + 12
        )
        frame = CGRect(origin: .zero, size: size)
        centerOffset = CGPoint(x: 0, y: 0)

        // Accessibility
        #if canImport(UIKit)
        isAccessibilityElement = true
        accessibilityLabel = "Distance: \(annotation.distanceString), Signal: \(Int(annotation.snr)) decibels"
        accessibilityTraits = .staticText
        #else
        _isAccessibilityElement = true
        _accessibilityLabel = "Distance: \(annotation.distanceString), Signal: \(Int(annotation.snr)) decibels"
        #endif
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.text = nil
        #if canImport(UIKit)
        accessibilityLabel = nil
        #else
        _accessibilityLabel = nil
        #endif
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        if let statsAnnotation = annotation as? StatsBadgeAnnotation {
            configure(with: statsAnnotation)
        }
    }
}
