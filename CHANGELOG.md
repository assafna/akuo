# Changelog

All notable changes to Akuo are documented in this file.

## 0.2.0 - 2026-08-30

### Added

- Local macOS English and Hebrew spelling dictionaries can authorize
  wrong-layout corrections in both directions, including user-learned words.
- Recognition distinguishes recognized, unknown, and unavailable results so a
  missing or failed spelling service leaves the original text unchanged.

### Fixed

- Accept the base language identifiers `en` and `he` that macOS may advertise
  while continuing to perform spelling checks with `en_US` and `he_IL`.
- Correct words whose physical English-layout keys include punctuation-shaped
  keys that map to Hebrew letters, such as `gcrh,` to `עברית`, while preserving
  structured-token exclusions.

## 0.1.0 - 2026-08-30

### Added

- Initial local, private-by-design macOS menu-bar preview for completed-word
  English and Hebrew keyboard-layout correction.
- Conservative structured-text, editable-context, and Secure Input safeguards.
- Input-source switching, aggregate-only correction counting, and immediate
  Command-Z restoration of the original text and input source.
