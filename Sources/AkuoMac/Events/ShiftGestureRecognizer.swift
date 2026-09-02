import Foundation

public enum ForceConversionGesture: String, CaseIterable, Sendable {
    case doubleShift
    case bothShifts
}

enum ShiftKeySide: Hashable, Sendable {
    case left
    case right
}

enum ShiftKeyPhase: Equatable, Sendable {
    case down
    case up
}

struct ShiftGestureRecognizer: Sendable {
    private struct CompletedTap: Sendable {
        let side: ShiftKeySide
        let completedAt: TimeInterval
    }

    private let activationInterval: TimeInterval
    private var activeGesture: ForceConversionGesture?
    private var pressedAt: [ShiftKeySide: TimeInterval] = [:]
    private var lastCompletedTap: CompletedTap?
    private var doubleShiftWasInterrupted = false
    private var bothShiftsTriggered = false

    init(activationInterval: TimeInterval) {
        self.activationInterval = activationInterval
    }

    mutating func consume(
        side: ShiftKeySide,
        phase: ShiftKeyPhase,
        timestamp: TimeInterval,
        gesture: ForceConversionGesture
    ) -> Bool {
        guard timestamp.isFinite else {
            reset()
            return false
        }
        if let activeGesture, activeGesture != gesture {
            reset()
        }
        activeGesture = gesture

        switch gesture {
        case .doubleShift:
            return consumeDoubleShift(side: side, phase: phase, timestamp: timestamp)
        case .bothShifts:
            return consumeBothShifts(side: side, phase: phase, timestamp: timestamp)
        }
    }

    mutating func reset() {
        activeGesture = nil
        pressedAt.removeAll(keepingCapacity: true)
        lastCompletedTap = nil
        doubleShiftWasInterrupted = false
        bothShiftsTriggered = false
    }

    private mutating func consumeDoubleShift(
        side: ShiftKeySide,
        phase: ShiftKeyPhase,
        timestamp: TimeInterval
    ) -> Bool {
        switch phase {
        case .down:
            guard pressedAt[side] == nil else { return false }
            if !pressedAt.isEmpty {
                lastCompletedTap = nil
                doubleShiftWasInterrupted = true
            }
            pressedAt[side] = timestamp
            return false

        case .up:
            guard let startedAt = pressedAt.removeValue(forKey: side) else {
                lastCompletedTap = nil
                return false
            }
            guard pressedAt.isEmpty else {
                lastCompletedTap = nil
                return false
            }
            if doubleShiftWasInterrupted {
                doubleShiftWasInterrupted = false
                lastCompletedTap = nil
                return false
            }
            let pressDuration = timestamp - startedAt
            guard pressDuration >= 0,
                  pressDuration <= activationInterval else {
                lastCompletedTap = nil
                return false
            }

            if let lastCompletedTap,
               lastCompletedTap.side == side {
                let gap = startedAt - lastCompletedTap.completedAt
                if gap >= 0, gap <= activationInterval {
                    self.lastCompletedTap = nil
                    return true
                }
            }
            lastCompletedTap = .init(side: side, completedAt: timestamp)
            return false
        }
    }

    private mutating func consumeBothShifts(
        side: ShiftKeySide,
        phase: ShiftKeyPhase,
        timestamp: TimeInterval
    ) -> Bool {
        lastCompletedTap = nil
        switch phase {
        case .down:
            guard pressedAt[side] == nil else { return false }
            pressedAt[side] = timestamp
            guard !bothShiftsTriggered,
                  pressedAt.count == 2,
                  let firstStartedAt = pressedAt
                      .filter({ $0.key != side })
                      .first?.value else {
                return false
            }
            let gap = timestamp - firstStartedAt
            guard gap >= 0, gap <= activationInterval else { return false }
            bothShiftsTriggered = true
            return true

        case .up:
            pressedAt.removeValue(forKey: side)
            if pressedAt.isEmpty {
                bothShiftsTriggered = false
            }
            return false
        }
    }
}
