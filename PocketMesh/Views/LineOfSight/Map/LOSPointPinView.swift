import MapKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pin view for dropped-pin A/B markers on the line of sight map
final class LOSPointPinView: MKAnnotationView {
    static let reuseIdentifier = "LOSPointPinView"

    // MARK: - UI Components

    private let circleView = UIView()
    private let labelView = UILabel()

    // MARK: - Initialization

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        let size: CGFloat = 32

        circleView.translatesAutoresizingMaskIntoConstraints = false
        #if canImport(UIKit)
        circleView.layer.cornerRadius = size / 2
        circleView.layer.shadowColor = UIColor.black.cgColor
        circleView.layer.shadowOpacity = 0.3
        circleView.layer.shadowRadius = 2
        circleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        #else
        circleView.wantsLayer = true
        circleView.layer?.cornerRadius = size / 2
        circleView.layer?.shadowColor = UIColor.black.cgColor
        circleView.layer?.shadowOpacity = 0.3
        circleView.layer?.shadowRadius = 2
        circleView.layer?.shadowOffset = CGSize(width: 0, height: 2)
        #endif
        addSubview(circleView)

        labelView.translatesAutoresizingMaskIntoConstraints = false
        let baseFont = UIFont.systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
            weight: .bold
        )
        labelView.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: baseFont)
        labelView.adjustsFontForContentSizeCategory = true
        labelView.textColor = .white
        labelView.textAlignment = .center
        circleView.addSubview(labelView)

        NSLayoutConstraint.activate([
            circleView.widthAnchor.constraint(equalToConstant: size),
            circleView.heightAnchor.constraint(equalToConstant: size),
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: centerYAnchor),

            labelView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            labelView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor)
        ])

        frame = CGRect(x: 0, y: 0, width: size, height: size)
        centerOffset = .zero
        canShowCallout = false
        displayPriority = .required
    }

    // MARK: - Configuration

    func configure(label: String, color: UIColor, opacity: CGFloat) {
        circleView.backgroundColor = color
        labelView.text = label
        alpha = opacity

        #if canImport(UIKit)
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = label == "A"
            ? L10n.Tools.Tools.LineOfSight.pointA
            : L10n.Tools.Tools.LineOfSight.pointB
        accessibilityHint = L10n.Tools.Tools.LineOfSight.PointPin.accessibilityHint
        #else
        _isAccessibilityElement = true
        _accessibilityLabel = label == "A"
            ? L10n.Tools.Tools.LineOfSight.pointA
            : L10n.Tools.Tools.LineOfSight.pointB
        _accessibilityHint = L10n.Tools.Tools.LineOfSight.PointPin.accessibilityHint
        #endif
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        alpha = 1.0
        labelView.text = nil
        #if canImport(UIKit)
        accessibilityLabel = nil
        #else
        _accessibilityLabel = nil
        #endif
    }
}
