import SwiftUI

#if canImport(UIKit)
import UIKit

/// UIViewRepresentable that renders animated GIF data using UIImageView
struct AnimatedGIFView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.image = image
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        imageView.image = image
    }

    static func dismantleUIView(_ imageView: UIImageView, coordinator: ()) {
        imageView.image = nil
    }
}
#else
import AppKit

/// NSViewRepresentable that renders GIF data using NSImageView
struct AnimatedGIFView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = image
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        imageView.image = image
    }

    static func dismantleNSView(_ imageView: NSImageView, coordinator: ()) {
        imageView.image = nil
    }
}
#endif
