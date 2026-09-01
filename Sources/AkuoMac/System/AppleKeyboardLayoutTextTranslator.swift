import Carbon
import Foundation
import AkuoCore

protocol KeyboardLayoutTextTranslating {
    func characters(
        keyCode: Int,
        modifiers: ObservedKeyModifiers,
        inputSourceIdentifier: String
    ) -> String?
}

final class AppleKeyboardLayoutTextTranslator: KeyboardLayoutTextTranslating {
    private var layoutDataByIdentifier: [String: Data] = [:]
    private var unavailableIdentifiers: Set<String> = []

    func characters(
        keyCode: Int,
        modifiers: ObservedKeyModifiers,
        inputSourceIdentifier: String
    ) -> String? {
        guard let keyCode = UInt16(exactly: keyCode),
              let layoutData = layoutData(for: inputSourceIdentifier) else {
            return nil
        }

        return layoutData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }
            let layout = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var output = [UniChar](repeating: 0, count: 16)
            var outputLength = 0
            var carbonModifiers: UInt32 = 0
            if modifiers.contains(.shift) {
                carbonModifiers |= UInt32(shiftKey)
            }
            if modifiers.contains(.capsLock) {
                carbonModifiers |= UInt32(alphaLock)
            }

            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDown),
                carbonModifiers >> 8,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                output.count,
                &outputLength,
                &output
            )
            guard status == noErr, outputLength <= output.count else { return nil }
            return String(utf16CodeUnits: output, count: outputLength)
        }
    }

    private func layoutData(for identifier: String) -> Data? {
        if let cached = layoutDataByIdentifier[identifier] { return cached }
        guard !unavailableIdentifiers.contains(identifier) else { return nil }

        let condition = [
            kTISPropertyInputSourceID as String: identifier,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(condition, false)?.takeRetainedValue(),
              let source = (list as NSArray as? [TISInputSource])?.first,
              let pointer = TISGetInputSourceProperty(
                  source,
                  kTISPropertyUnicodeKeyLayoutData
              ) else {
            unavailableIdentifiers.insert(identifier)
            return nil
        }
        let data = Unmanaged<CFData>
            .fromOpaque(pointer)
            .takeUnretainedValue() as Data
        layoutDataByIdentifier[identifier] = data
        return data
    }
}
