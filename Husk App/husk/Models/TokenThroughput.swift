//
//  TokenThroughput.swift
//  husk
//

import Foundation

struct TokenThroughput {
    let tokensPerSecond: Double
    let isEstimated: Bool
}

/// Measures generation speed independently of any provider SDK.
struct TokenThroughputTracker {
    private var firstGeneratedContentAt: Date?
    private var generatedText = ""

    mutating func record(content: String, reasoningContent: String?) {
        let text = (reasoningContent ?? "") + content
        guard !text.isEmpty else { return }

        if firstGeneratedContentAt == nil {
            firstGeneratedContentAt = Date()
        }
        generatedText += text
    }

    func result(reportedCompletionTokens: Int?, completedAt: Date = Date()) -> TokenThroughput? {
        guard let firstGeneratedContentAt else { return nil }
        let generationDuration = completedAt.timeIntervalSince(firstGeneratedContentAt)
        guard generationDuration > 0 else { return nil }

        if let reportedCompletionTokens, reportedCompletionTokens > 0 {
            return TokenThroughput(
                tokensPerSecond: Double(reportedCompletionTokens) / generationDuration,
                isEstimated: false
            )
        }

        let estimatedTokens = Self.estimateTokenCount(in: generatedText)
        guard estimatedTokens > 0 else { return nil }
        return TokenThroughput(
            tokensPerSecond: Double(estimatedTokens) / generationDuration,
            isEstimated: true
        )
    }

    /// A tokenizer-independent fallback for providers that omit streaming usage.
    /// ASCII text averages roughly four bytes per token; non-ASCII scalars are
    /// counted individually to avoid severely undercounting CJK text.
    private static func estimateTokenCount(in text: String) -> Int {
        var asciiByteCount = 0
        var nonASCIICharacterCount = 0

        for scalar in text.unicodeScalars {
            if scalar.isASCII {
                asciiByteCount += scalar.utf8.count
            } else {
                nonASCIICharacterCount += 1
            }
        }

        let estimatedASCIITokens = Int(ceil(Double(asciiByteCount) / 4.0))
        return estimatedASCIITokens + nonASCIICharacterCount
    }
}

