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
    case recognitionUnavailable
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

    public func decision(
        for token: String,
        sourceHint: Language? = nil,
        keyStrokes: [ObservedKeyStroke] = []
    ) -> CorrectionDecision {
        let conversion = layoutMap.convert(
            token,
            sourceHint: sourceHint,
            keyStrokes: keyStrokes
        )
        guard !excluder.shouldExclude(token, conversion: conversion) else { return .keep(.excluded) }
        guard let conversion else { return .keep(.noConversion) }

        let originalRecognitionToken = OrthographicWordShape.recognitionToken(
            for: conversion.original,
            language: conversion.source
        )
        let original = originalRecognitionToken.map {
            originalScorer.evidence(for: $0, language: conversion.source)
        }
        if let original {
            switch original.status {
            case .recognized:
                guard conversion.hasAuthoritativePhysicalEvidence else {
                    return .keep(.originalRecognized)
                }
            case .unavailable:
                return .keep(.recognitionUnavailable)
            case .unknown:
                break
            }
        }

        guard let candidateRecognitionToken = OrthographicWordShape.recognitionToken(
            for: conversion.candidate,
            language: conversion.target
        ) else { return .keep(.excluded) }
        let candidate = candidateScorer.evidence(
            for: candidateRecognitionToken,
            language: conversion.target
        )
        switch candidate.status {
        case .recognized:
            break
        case .unknown:
            return .keep(.candidateUnknown)
        case .unavailable:
            return .keep(.recognitionUnavailable)
        }
        if !conversion.hasAuthoritativePhysicalEvidence {
            guard candidate.score - (original?.score ?? 0) >= 60 else {
                return .keep(.ambiguous)
            }
        }

        return .correct(.init(
            original: conversion.original,
            replacement: conversion.candidate,
            target: conversion.target
        ))
    }

    public func forcedDecision(
        for token: String,
        sourceHint: Language? = nil,
        keyStrokes: [ObservedKeyStroke] = []
    ) -> CorrectionDecision {
        let conversion = layoutMap.convert(
            token,
            sourceHint: sourceHint,
            keyStrokes: keyStrokes
        )
        guard !excluder.shouldExclude(token, conversion: conversion) else {
            return .keep(.excluded)
        }
        guard let conversion else { return .keep(.noConversion) }
        let hasTargetWordShape = OrthographicWordShape.recognitionToken(
            for: conversion.candidate,
            language: conversion.target
        ) != nil
        let hasCompleteAlphabeticPhysicalEvidence =
            conversion.physicalEvidence?.hasAlphabeticKey == true
        guard hasTargetWordShape || hasCompleteAlphabeticPhysicalEvidence else {
            return .keep(.excluded)
        }

        return .correct(.init(
            original: conversion.original,
            replacement: conversion.candidate,
            target: conversion.target
        ))
    }
}
