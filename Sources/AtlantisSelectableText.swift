//
//  AtlantisSelectableText.swift
//  atlantis
//

#if canImport(SwiftUI)
import SwiftUI

/// Selectable, wrapping, large-text-safe body renderer.
/// Replaces `Text(...).textSelection(.enabled)` inside a horizontal ScrollView,
/// which hangs and renders blank on CoreText past ~tens of thousands of glyphs.
@available(iOS 15.0, macOS 12.0, *)
struct AtlantisSelectableText: View {
    let attributed: AttributedString

    var body: some View { _Representable(attributed: attributed) }
}

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit

@available(iOS 15.0, *)
private struct _Representable: UIViewRepresentable {
    let attributed: AttributedString

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false            // let List own scroll; self-size height
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = true
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let ns = NSMutableAttributedString(attributed)
        let size = UIFont.preferredFont(forTextStyle: .footnote).pointSize
        ns.addAttribute(.font,
                        value: UIFont.monospacedSystemFont(ofSize: size, weight: .regular),
                        range: NSRange(location: 0, length: ns.length))
        tv.attributedText = ns
    }
}
#elseif os(macOS)
import AppKit

@available(macOS 12.0, *)
private struct _Representable: NSViewRepresentable {
    let attributed: AttributedString

    func makeNSView(context: Context) -> NSTextView {
        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        let ns = NSMutableAttributedString(attributed)
        let size = NSFont.preferredFont(forTextStyle: .footnote).pointSize
        ns.addAttribute(.font,
                        value: NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
                        range: NSRange(location: 0, length: ns.length))
        tv.textStorage?.setAttributedString(ns)
    }
}
#endif
#endif
