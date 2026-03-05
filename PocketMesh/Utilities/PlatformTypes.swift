// PlatformTypes.swift
// Cross-platform compatibility layer for UIKit/AppKit types.
//
// On macOS, provides typealiases and extensions so existing code using
// UIImage, UIColor, UIImageView, and UIApplication can compile without
// per-file #if guards for the common cases.

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit

// MARK: - Type Aliases

public typealias UIImage = NSImage
public typealias UIColor = NSColor
public typealias UIImageView = NSImageView
public typealias UIView = NSView
public typealias UIFont = NSFont
public typealias UIBezierPath = NSBezierPath

// MARK: - NSBezierPath Extensions (UIBezierPath API compatibility)

extension NSBezierPath {
    /// Bridge UIBezierPath.addLine(to:) to NSBezierPath.line(to:).
    func addLine(to point: CGPoint) {
        line(to: point)
    }

    /// Bridge UIBezierPath.cgPath to NSBezierPath.
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let element = self.element(at: i, associatedPoints: &points)
            switch element {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

// MARK: - NSImage Extensions (UIImage API compatibility)

extension NSImage {
    convenience init?(systemName: String) {
        self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }

    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    static func animatedImage(with images: [NSImage], duration: TimeInterval) -> NSImage? {
        images.first
    }
}

// MARK: - NSImageView Extensions (UIImageView API compatibility)

extension NSImageView {
    var contentMode: NSImageView.ContentMode {
        get { .scaleAspectFit }
        set { imageScaling = newValue.nsScaling }
    }

    enum ContentMode {
        case scaleAspectFit
        case scaleAspectFill
        case center

        var nsScaling: NSImageScaling {
            switch self {
            case .scaleAspectFit: .scaleProportionallyUpOrDown
            case .scaleAspectFill: .scaleProportionallyUpOrDown
            case .center: .scaleNone
            }
        }
    }

    /// Bridge UIImageView.tintColor to NSImageView.contentTintColor.
    var tintColor: NSColor? {
        get { contentTintColor }
        set { contentTintColor = newValue }
    }

    var isAnimating: Bool { false }
    func startAnimating() {}
    func stopAnimating() {}

    var animationImages: [NSImage]? {
        get { nil }
        set {}
    }

    var animationDuration: TimeInterval {
        get { 0 }
        set {}
    }

    var animationRepeatCount: Int {
        get { 0 }
        set {}
    }
}

// MARK: - NSView Extensions (UIView API compatibility)

extension NSView {
    var alpha: CGFloat {
        get { alphaValue }
        set { alphaValue = newValue }
    }

    var clipsToBounds: Bool {
        get { layer?.masksToBounds ?? false }
        set { layer?.masksToBounds = newValue }
    }

    var backgroundColor: NSColor? {
        get {
            guard let cgColor = layer?.backgroundColor else { return nil }
            return NSColor(cgColor: cgColor)
        }
        set {
            wantsLayer = true
            layer?.backgroundColor = newValue?.cgColor
        }
    }
}

// MARK: - NSColor Extensions (UIColor API compatibility)

extension NSColor {
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    static var systemGray5: NSColor { .separatorColor }
}

// MARK: - UIPasteboard Compatibility

/// Provides UIPasteboard-compatible API on macOS using NSPasteboard.
/// Uses a class (reference type) so `UIPasteboard.general.string = ...` works.
final class UIPasteboard: @unchecked Sendable {
    static let general = UIPasteboard()

    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue {
                NSPasteboard.general.setString(newValue, forType: .string)
            }
        }
    }

    private init() {}
}

// MARK: - UIScreen Compatibility

struct UIScreen {
    static var main: UIScreen { UIScreen() }

    var scale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2.0
    }

    private init() {}
}

// MARK: - SwiftUI Compatibility (iOS-only modifiers)

import SwiftUI

/// Bridge `Image(uiImage:)` to `Image(nsImage:)` on macOS.
extension Image {
    init(uiImage: NSImage) {
        self.init(nsImage: uiImage)
    }
}

/// Stub types and modifiers that only exist on iOS.
enum NavigationBarItem {
    enum TitleDisplayMode {
        case automatic, inline, large
    }
}

enum UIKeyboardType {
    case `default`, numberPad, decimalPad, emailAddress, URL, asciiCapable, numbersAndPunctuation
}

struct TextInputAutocapitalization {
    static let never = TextInputAutocapitalization()
    static let characters = TextInputAutocapitalization()
    static let words = TextInputAutocapitalization()
    static let sentences = TextInputAutocapitalization()
}

extension View {
    func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View { self }
    func keyboardType(_ type: UIKeyboardType) -> some View { self }
    func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View { self }
}

/// ToolbarItemPlacement compatibility — `.topBarLeading` / `.topBarTrailing` don't exist on macOS.
extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}

// MARK: - UILabel Compatibility

/// NSTextField configured as a non-editable label, matching UILabel's property API.
class UILabel: NSTextField {
    var text: String? {
        get { stringValue }
        set { stringValue = newValue ?? "" }
    }

    var numberOfLines: Int {
        get { maximumNumberOfLines }
        set { maximumNumberOfLines = newValue }
    }

    var textAlignment: NSTextAlignment {
        get { alignment }
        set { alignment = newValue }
    }

    /// No-op on macOS (no Dynamic Type).
    var adjustsFontForContentSizeCategory: Bool {
        get { false }
        set {}
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        isEditable = false
        isSelectable = false
        drawsBackground = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - UIFontMetrics Compatibility

/// Stub for UIFontMetrics — on macOS, returns the font unscaled (no Dynamic Type).
struct UIFontMetrics {
    let textStyle: NSFont.TextStyle

    init(forTextStyle textStyle: NSFont.TextStyle) {
        self.textStyle = textStyle
    }

    func scaledFont(for font: NSFont) -> NSFont { font }
}

// MARK: - Gesture Recognizer Compatibility

/// UITapGestureRecognizer shim — wraps NSClickGestureRecognizer with numberOfTapsRequired.
class UITapGestureRecognizer: NSClickGestureRecognizer {
    var numberOfTapsRequired: Int {
        get { numberOfClicksRequired }
        set { numberOfClicksRequired = newValue }
    }
}

typealias UIGestureRecognizer = NSGestureRecognizer
typealias UIGestureRecognizerDelegate = NSGestureRecognizerDelegate

// MARK: - UIEvent Compatibility

typealias UIEvent = NSEvent

// MARK: - NSView Accessibility Property Compatibility

/// UIKit uses property assignment for accessibility; AppKit uses methods.
/// These computed properties bridge the pattern `view.isAccessibilityElement = true`.
extension NSView {
    var _isAccessibilityElement: Bool {
        get { isAccessibilityElement() }
        set { setAccessibilityElement(newValue) }
    }

    var _accessibilityLabel: String? {
        get { accessibilityLabel() }
        set { setAccessibilityLabel(newValue) }
    }

    var _accessibilityHint: String? {
        get { accessibilityHelp() }
        set { setAccessibilityHelp(newValue) }
    }
}

// MARK: - UIAccessibilityTraits Compatibility

struct UIAccessibilityTraits: OptionSet {
    let rawValue: UInt64
    static let button = UIAccessibilityTraits(rawValue: 1 << 0)
    static let selected = UIAccessibilityTraits(rawValue: 1 << 1)
    static let notEnabled = UIAccessibilityTraits(rawValue: 1 << 2)
    static let none = UIAccessibilityTraits(rawValue: 0)
}
#endif
