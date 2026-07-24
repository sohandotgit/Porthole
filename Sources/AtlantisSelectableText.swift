//
//  AtlantisSelectableText.swift
//  atlantis
//

#if canImport(SwiftUI)
import SwiftUI
import Foundation

/// Selectable, wrapping, large-text-safe body renderer.
/// Owns its own scroll so TextKit lazily lays out only the visible viewport —
/// the whole body is never laid out up front. Fill it with a bounded frame from
/// the caller (it does not self-size).
///
/// `scrollToRange`/`scrollToken`: bump `scrollToken` whenever `scrollToRange`
/// should be scrolled into view (e.g. search next/prev) — the token, not the
/// range, is the change signal, so re-scrolling to the same range twice works.
@available(iOS 15.0, macOS 12.0, *)
struct AtlantisSelectableText: View {
    let attributed: AttributedString
    var wordWrap: Bool = true
    var scrollToRange: NSRange? = nil
    var scrollToken: Int = 0

    var body: some View {
        _Representable(attributed: attributed, wordWrap: wordWrap,
                        scrollToRange: scrollToRange, scrollToken: scrollToken)
    }
}

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit

@available(iOS 15.0, *)
private struct _Representable: UIViewRepresentable {
    let attributed: AttributedString
    var wordWrap: Bool
    var scrollToRange: NSRange?
    var scrollToken: Int

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
        if context.coordinator.last != attributed {
            context.coordinator.last = attributed
            tv.attributedText = NSAttributedString(attributed)
        }
        if context.coordinator.lastWordWrap != wordWrap {
            context.coordinator.lastWordWrap = wordWrap
            tv.textContainer.widthTracksTextView = wordWrap
            tv.textContainer.size = wordWrap
                ? CGSize(width: tv.bounds.width, height: CGFloat.greatestFiniteMagnitude)
                : CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        if context.coordinator.lastScrollToken != scrollToken, let range = scrollToRange {
            context.coordinator.lastScrollToken = scrollToken
            tv.scrollRangeToVisible(range)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var last: AttributedString?
        var lastWordWrap = true
        var lastScrollToken = 0
    }
}
#elseif os(macOS)
import AppKit

@available(macOS 12.0, *)
private struct _Representable: NSViewRepresentable {
    let attributed: AttributedString
    var wordWrap: Bool
    var scrollToRange: NSRange?
    var scrollToken: Int

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
        scroll.hasHorizontalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if context.coordinator.last != attributed {
            context.coordinator.last = attributed
            tv.textStorage?.setAttributedString(NSAttributedString(attributed))
        }
        if context.coordinator.lastWordWrap != wordWrap {
            context.coordinator.lastWordWrap = wordWrap
            tv.textContainer?.widthTracksTextView = wordWrap
            tv.isHorizontallyResizable = !wordWrap
            if !wordWrap {
                tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
        }
        if context.coordinator.lastScrollToken != scrollToken, let range = scrollToRange {
            context.coordinator.lastScrollToken = scrollToken
            tv.scrollRangeToVisible(range)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var last: AttributedString?
        var lastWordWrap = true
        var lastScrollToken = 0
    }
}
#endif
#endif
