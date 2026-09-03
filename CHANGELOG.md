# Changelog

All notable changes to Akuo are documented in this file.

## Unreleased

### Added

- Add an explicit local-install mode for a caller-selected, already signed
  `Akuo.app` and its previously recorded executable SHA-256, rejecting changed
  candidate bytes before staging and preserving that hash through installation
  without rebuilding the bundle.
- Add a certificate-aware local installer that rejects ad-hoc or code-hash-based
  identities and verifies update compatibility before replacing the installed
  application, allowing Accessibility permission to survive consistently signed
  local updates after a one-time migration.
- Let the user force a safe layout conversion of the unfinished word without
  first pressing Space or Return, or of an eligible word completed by Space
  for up to five seconds. Double-tapping the same Shift key is the default
  gesture; pressing both Shift keys is available from the menu.
- Preserve the automatic policy's structured-token and punctuation-only
  exclusions during forced conversion, then retain source switching,
  aggregate correction counting, and immediate Command-Z restoration.
- Allow an explicit force request to use literal target-layout output, such as
  internal Hebrew final-form letters or the Hebrew W-key geresh, only when a
  complete physical trace contains an alphabetic key. Automatic correction
  retains strict target-word validation.
- Let repeated force gestures toggle the latest Akuo conversion between its
  original and corrected layouts without inflating the correction count.
  Command-Z still performs a one-shot reversal and ends the toggle chain.

### Changed

- Require a focused text control to expose a writable Accessibility value and
  reject it when Accessibility explicitly reports that it is disabled.
  Read-only, disabled, and otherwise unprovable editing contexts remain
  unchanged.
- Keep standard editors such as TextEdit eligible when they omit an optional
  Accessibility subrole or enabled state, while transiently failed, explicitly
  unknown, or malformed reads remain ineligible.
- Require the same frontmost application and focused Accessibility element
  throughout editability inspection and immediately before correction or undo,
  preserving the host boundary or Command-Z if focus changes.

### Fixed

- Revalidate the exact completed token and boundary immediately before a
  delayed force conversion using a bounded Accessibility range query. Caret
  movement, host text substitution, unavailable range evidence, or a changed
  input-source identifier now leave the host text untouched. Return/Enter
  never arms delayed fallback because submitted text may no longer be editable.
- Invalidate physical-layout evidence after editing a tracked word, preventing
  a post-Backspace force request from falling back to an unverified static map.
- Reset the native Shift-key state together with the gesture recognizer after
  focus loss, event-tap recovery, source changes, and other transient resets.
- Restrict automatic correction boundaries to Space and Return/Enter. Tab and
  Shift-Tab now pass through untouched and clear Akuo's transient token and
  immediate-undo state, preserving application-owned completion and
  focus-navigation behavior.
- Require trace-backed word corrections to include at least one alphabetic
  physical key, preventing punctuation-only input such as `.`, `,`, or `;`
  from becoming recognized single Hebrew letters while preserving punctuation
  within words and silent shifted-letter recovery.
- Count Unicode scalars when immediate undo removes a corrected word, preserving
  exact deletion for composite keyboard-layout output.

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
