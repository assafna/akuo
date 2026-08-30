public struct Correction: Equatable, Sendable {
    public let original: String
    public let replacement: String
    public let target: Language

    public init(original: String, replacement: String, target: Language) {
        self.original = original
        self.replacement = replacement
        self.target = target
    }
}

public enum KeepReason: Equatable, Sendable {
    case excluded
    case noConversion
    case originalRecognized
    case candidateUnknown
    case ambiguous
}

public enum CorrectionDecision: Equatable, Sendable {
    case correct(Correction)
    case keep(KeepReason)
}

public struct CorrectionPolicy {
    private let layoutMap: KeyboardLayoutMap
    private let originalScorer: WordScorer
    private let candidateScorer: WordScorer
    private let excluder: TokenExcluder

    public init(
        layoutMap: KeyboardLayoutMap,
        originalScorer: WordScorer,
        candidateScorer: WordScorer,
        excluder: TokenExcluder
    ) {
        self.layoutMap = layoutMap
        self.originalScorer = originalScorer
        self.candidateScorer = candidateScorer
        self.excluder = excluder
    }

    public func decision(for token: String) -> CorrectionDecision {
        guard !excluder.shouldExclude(token) else { return .keep(.excluded) }
        guard let conversion = layoutMap.convert(token) else { return .keep(.noConversion) }

        let original = originalScorer.evidence(
            for: conversion.original,
            language: conversion.source
        )
        guard !original.recognized else { return .keep(.originalRecognized) }

        let candidate = candidateScorer.evidence(
            for: conversion.candidate,
            language: conversion.target
        )
        guard candidate.recognized else { return .keep(.candidateUnknown) }
        guard candidate.score - original.score >= 60 else { return .keep(.ambiguous) }

        return .correct(.init(
            original: conversion.original,
            replacement: conversion.candidate,
            target: conversion.target
        ))
    }
}
