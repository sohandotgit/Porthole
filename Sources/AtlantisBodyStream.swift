//
//  AtlantisBodyStream.swift
//  atlantis
//
//  docs/plan-progressive-body-render.md Part 1 — reference-typed, incrementally
//  grown render output. Replaces the all-or-nothing `AtlantisBodyBuilt`: the
//  viewer publishes `version`, and `AtlantisCodeTextView` appends only the
//  chunks it has not yet applied (Part 2).
//

#if canImport(SwiftUI)
import Foundation
import Combine

/// Line-aligned incremental render output for one `(mode, asciiVisible)` body
/// build. Chunk boundaries always land on `\n` — never split a line, or the
/// gutter's `lineStarts` binary search and the wrap geometry both go wrong.
@MainActor
final class AtlantisBodyStream: ObservableObject {
    struct Chunk {
        let attributed: NSAttributedString   // line-aligned slice
        let lineStarts: [Int]                // absolute UTF-16 offsets, this chunk's lines only
        let utf16Length: Int
    }

    /// The full text this stream will eventually display in full — available
    /// immediately (built off-main before chunking), independent of streaming
    /// progress, so Copy always copies the whole payload (design §5.3), never
    /// a truncated prefix.
    let fullText: String
    let totalUTF16: Int
    /// Hex-mode column divider x-offsets (offset|bytes, bytes|ASCII), relative to
    /// `canvasInset` — empty for every other mode (B-5, design §6.3).
    let hexDividerOffsets: [CGFloat]

    @Published private(set) var version = 0        // == chunks.count
    private(set) var chunks: [Chunk] = []
    private(set) var lineStarts: [Int] = []
    private(set) var loadedUTF16 = 0
    private(set) var loadedText = ""
    @Published private(set) var isComplete = false

    init(fullText: String, totalUTF16: Int, hexDividerOffsets: [CGFloat] = []) {
        self.fullText = fullText
        self.totalUTF16 = totalUTF16
        self.hexDividerOffsets = hexDividerOffsets
    }

    func append(_ chunk: Chunk) {
        guard !isComplete else { return }
        chunks.append(chunk)
        loadedUTF16 += chunk.utf16Length
        loadedText += chunk.attributed.string
        lineStarts.append(contentsOf: chunk.lineStarts)
        version += 1
    }

    func markComplete() {
        isComplete = true
    }

    // MARK: - Chunking

    /// Splits `attributed` into line-aligned chunks per `lineStarts` (the
    /// global line-start table for the same text). Chunk size: whichever comes
    /// first of `AtlantisSyntaxTheme.streamChunkMaxLines` lines or
    /// `AtlantisSyntaxTheme.streamChunkMaxUTF16` UTF-16 units; the first chunk
    /// is capped at `streamFirstChunkMaxLines` so something is on screen in one
    /// frame. Concatenating every chunk's `attributed` reproduces `attributed`
    /// exactly; concatenating every chunk's `lineStarts` reproduces `lineStarts`
    /// exactly.
    nonisolated static func makeChunks(attributed: NSAttributedString, lineStarts: [Int]) -> [Chunk] {
        let totalUTF16 = attributed.length
        guard totalUTF16 > 0, !lineStarts.isEmpty else { return [] }

        var chunks: [Chunk] = []
        var chunkStartLineIdx = 0
        var isFirst = true
        let lineCount = lineStarts.count

        while chunkStartLineIdx < lineCount {
            let maxLines = isFirst ? AtlantisSyntaxTheme.streamFirstChunkMaxLines : AtlantisSyntaxTheme.streamChunkMaxLines
            let startOffset = lineStarts[chunkStartLineIdx]
            var endLineIdx = chunkStartLineIdx
            while endLineIdx + 1 < lineCount {
                let nextLineIdx = endLineIdx + 1
                let linesSoFar = nextLineIdx - chunkStartLineIdx
                let utf16SoFar = lineStarts[nextLineIdx] - startOffset
                if linesSoFar >= maxLines || utf16SoFar >= AtlantisSyntaxTheme.streamChunkMaxUTF16 { break }
                endLineIdx = nextLineIdx
            }

            let nextStartLineIdx = endLineIdx + 1
            let endOffset = nextStartLineIdx < lineCount ? lineStarts[nextStartLineIdx] : totalUTF16
            let range = NSRange(location: startOffset, length: endOffset - startOffset)
            let sub = attributed.attributedSubstring(from: range)
            let chunkLineStarts = Array(lineStarts[chunkStartLineIdx..<nextStartLineIdx])
            chunks.append(Chunk(attributed: sub, lineStarts: chunkLineStarts, utf16Length: range.length))

            chunkStartLineIdx = nextStartLineIdx
            isFirst = false
        }

        return chunks
    }
}
#endif
