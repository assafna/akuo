# Changelog

All notable changes to Akuo are documented in this file.

## Unreleased

### Fixed

- Require trace-backed word corrections to include at least one alphabetic
  physical key, preventing punctuation-only input such as `.`, `,`, or `;`
  from becoming recognized single Hebrew letters while preserving punctuation
  within words and silent shifted-letter recovery.

## 0.3.0 - 2026-09-01

### Fixed

- Translate every captured key through the installed Apple target layout with
  its Shift/Caps Lock state, fixing terminal punctuation in both directions
  (`יקךךם!` to `hello!` and `knv?` to `למה?`), remapped punctuation, and
  directionally mirrored wrapper pairs without a punctuation-specific map.
- Recognize only the lexical core of a trace-backed punctuated candidate while
  preserving its punctuation in the replacement, and let a valid complete
  physical trace resolve malformed source shapes such as `׳ם׳` to `wow`.
- Keep punctuation-dominated translated candidates excluded, and suppress the
  remainder of a token after any target-layout translation failure.
- Re-translate captured physical key events with AppKit's current input source
  and require the same supported source before and after decoding, fixing
  repeated corrections after source switches without trusting stale Core
  Graphics Unicode payloads.
- Reconstruct English capitalization per physical key when using the standard
  Hebrew input source, including silent shifted keys, all-caps words, and
  composite niqqud output.
- Prefer a recognized trace-backed English candidate over a recognized visible
  Hebrew fragment, fixing `קד` to `Yes`, an all-silent trace to `YES`, `ם` to
  `No`, and the standalone A and I keys to `a`/`A` and `i`/`I`.
- Correct recognized English words with internal apostrophes typed using the
  Hebrew layout, including contractions such as `גםמ,א` to `don't`, while
  rejecting leading, trailing, doubled, unknown, and structured punctuation.
- Preserve complete physical-key evidence across the apostrophe key so shifted
  contractions such as `We're` retain their recoverable capitalization.
- Trust a valid recognized joined-English candidate when its complete physical
  trace proves Apple's silent or composite Hebrew Shift output, fixing
  `„םמ,א` to `Don't` and `„,` to `DON'T` without relaxing text-only or
  malformed punctuation handling.
- Recognize the Hebrew punctuation geresh emitted by the standard Apple Hebrew
  W key, fixing `׳ק,רק` to `we're`, while retaining straight apostrophe as a
  compatibility alias.

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
