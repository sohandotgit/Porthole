//
//  AtlantisSelectableText.swift
//  atlantis
//

#if canImport(SwiftUI)
import SwiftUI

/// Selectable, wrapping, large-text-safe body renderer.
/// Owns its own scroll so TextKit lazily lays out only the visible viewport —
/// the whole body is never laid out up front. Fill it with a bounded frame from
/// the caller (it does not self-size).
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
        tv.isScrollEnabled = true              // own scroll → TextKit lazy layout
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = true
        tv.font = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
            weight: .regular)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // Skip redundant O(n) restyling when the content has not changed.
        if context.coordinator.last == attributed { return }
        context.coordinator.last = attributed
        tv.attributedText = NSAttributedString(attributed)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var last: AttributedString?
    }
}
#elseif os(macOS)
import AppKit

@available(macOS 12.0, *)
private struct _Representable: NSViewRepresentable {
    let attributed: AttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.textContainer?.lineFragmentPadding = 0
        tv.font = NSFont.monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .footnote).pointSize,
            weight: .regular)
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if context.coordinator.last == attributed { return }
        context.coordinator.last = attributed
        tv.textStorage?.setAttributedString(NSAttributedString(attributed))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var last: AttributedString?
    }
}
#endif
#endif
