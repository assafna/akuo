# macOS Dictionary Candidate Recognition Design

## Summary

Akuo will use the local macOS spelling dictionaries to authorize mapped
candidates in both English-to-Hebrew and Hebrew-to-English correction. This
includes words the user has taught macOS. The change removes the current
seed-vocabulary ceiling while preserving deterministic keyboard mapping,
conservative token exclusions, input-source alignment, and immediate undo.

Recognition remains entirely on-device. Akuo will not bundle a third-party
dictionary, call a network service, persist typed words, or add correction
history.

## Problem

The keyboard map already converts arbitrary supported physical-key sequences.
The shipping recognition policy does not: it uses `SeedLexicon` as the sole
candidate authority. A valid candidate outside that small set is therefore
reported as unknown and left unchanged. For example, the map produces `עובד`
from `gucs`, but the current candidate scorer rejects it because `עובד` is not
in the seed set.

Adding individual vocabulary entries would only move the boundary. The product
needs a general local word authority for both supported languages.

## Goals

- Authorize ordinary Hebrew and English candidates recognized by macOS.
- Include user-learned words as valid candidates in both directions.
- Keep seed recognition deterministic when macOS spelling is unavailable or
  varies; correction still passes through when the original cannot be checked
  safely.
- Preserve the rule that a recognized original is never corrected.
- Leave text unchanged whenever dictionary availability or recognition is
  uncertain.
- Preserve all existing secure-input, structured-token, source-switching, and
  immediate-undo behavior.
- Cover the reported mixed-language sentence and the learned-word tradeoff in
  automated and manual acceptance tests.

## Non-goals

- Translation, transliteration, grammar correction, or general spelling repair.
- Sentence-level language detection or contextual language modeling.
- A bundled Hebrew or English dictionary.
- Cloud recognition, telemetry, accounts, or typed-text storage.
- An Akuo UI for teaching or removing macOS dictionary words.
- Guaranteeing recognition of a word macOS neither knows nor has learned.
- Eliminating every false positive introduced by a user-learned dictionary.

## Product Decisions

### Symmetric candidate authority

The original token and the mapped candidate use the same recognition stack:

1. `SeedLexicon` for deterministic product examples and a small stable baseline.
2. `SystemSpellChecker` for the selected macOS language dictionary.

The macOS result includes its user-learned vocabulary. Akuo will not call
`hasLearnedWord` to exclude learned candidates. This is intentional: a learned
name, acronym, slang term, or internal term can authorize a correction in either
direction.

### Accepted learned-word tradeoff

Learned words can also authorize an unwanted correction. If the user teaches
macOS that `zzzz` is valid, properly typed Hebrew `זזזז` maps to a recognized
English candidate and becomes eligible for correction to `zzzz`. This behavior
is accepted in exchange for maximum local-dictionary coverage. Existing
exclusions still apply, and immediate Command-Z remains the recovery path.

### Machine-dependent behavior

The exact recognized vocabulary may vary with the macOS version, installed
language resources, and learned words. That variation is accepted. Tests must
not assert host-specific dictionary contents; production-policy tests inject a
controlled recognizer, while manual acceptance verifies the installed Mac.

## Recognition Model

The current Boolean `WordRecognizing` result cannot distinguish an unknown word
from an unavailable spelling service. Recognition will use three states:

- `recognized`: the word is present in the selected authority.
- `unknown`: the authority completed its check and rejected the word.
- `unavailable`: the authority could not provide a trustworthy answer.

`RecognitionEvidence` will retain the script match and score while carrying the
recognition state. The existing fixed score margin remains in place so policy
behavior stays explicit and can be tuned later without changing the service
boundary.

### Seed behavior

`SeedLexicon` returns `recognized` or `unknown`; it is never unavailable.
English lookup remains case-insensitive, while Hebrew lookup remains unchanged.

### macOS spelling behavior

`SystemSpellChecker` continues to use `NSSpellChecker` with explicit `en_US` or
`he_IL`. Its adapter must expose enough response information to identify a
failed or unsupported check. An unavailable requested language, a negative word
count, or another non-successful service outcome returns `unavailable`, not
`recognized`.

No checked word or result is logged or persisted.

### Composite behavior

The composite recognizer evaluates the deterministic seed first:

- A seed match returns `recognized` without requiring macOS.
- Otherwise, a macOS match returns `recognized`.
- A completed macOS rejection returns `unknown`.
- A macOS failure returns `unavailable`.

This preserves deterministic seed recognition without converting a spelling
service failure into positive evidence.

## Correction Policy

The policy retains its existing mapping, script, exclusion, and confidence
checks. Recognition decisions become:

| Original | Candidate | Decision |
|---|---|---|
| Recognized | Any | Keep the original |
| Unavailable | Any | Keep because recognition is unavailable |
| Unknown | Recognized | Continue through score-margin checks and correct when decisive |
| Unknown | Unknown | Keep because the candidate is unknown |
| Unknown | Unavailable | Keep because recognition is unavailable |

A distinct `recognitionUnavailable` keep reason makes this failure observable in
tests without logging the token. No user-facing error is required for a
transient dictionary miss; the safe behavior is silent pass-through.

## Runtime Data Flow

```text
Completed token
  -> structured-token and security exclusions
  -> deterministic opposite-layout mapping
  -> seed plus macOS recognition of original
  -> seed plus macOS recognition of candidate
  -> recognition-state and score-margin policy
  -> keep, or replace and select the candidate language
  -> retain one transient immediate-undo record
```

The buffer, replacement emitter, input-source controller, and undo controller
do not change. Each word remains independent; a successful correction changes
the input source so later physical keys are decoded in the intended language.

## Failure and Privacy Behavior

- Missing language resources, spelling-service failure, or an indeterminate
  result leaves the original text unchanged.
- Secure Input, secure fields, unknown editing contexts, and replacement
  preparation failures continue to leave the original text unchanged.
- URLs, email addresses, paths, numbers, identifiers, mixed scripts, unsupported
  punctuation, and other existing excluded shapes remain excluded before
  recognition can authorize a correction.
- Recognition stays synchronous with the current completed-token path; no word
  is queued, retained, or replayed after a service failure.
- No raw token, candidate, learned-word status, recognition result, or undo
  content is written to preferences, files, logs, telemetry, or a network.

## Testing Strategy

### Core tests

- Exercise `recognized`, `unknown`, and `unavailable` recognition evidence.
- Verify seed matches remain deterministic.
- Verify a recognized original vetoes correction.
- Verify a system-recognized candidate can authorize correction in both
  directions.
- Verify a candidate standing in for a learned word is treated exactly like any
  other system-recognized candidate.
- Verify unknown and unavailable candidates remain unchanged.
- Verify unavailable original recognition remains unchanged.
- Retain all mapping, score-margin, and token-exclusion coverage.

### macOS adapter tests

- Test explicit English and Hebrew language selection through a fake backend.
- Test recognized, misspelled, unsupported-language, and failed-service results.
- Do not depend on the build machine's live dictionary contents in automated
  assertions.

### Shipping-composition integration tests

- Use `AppModel.makeRecognitionPolicy` with a controlled macOS recognizer to
  prove non-seed Hebrew and English candidates reach replacement, source
  selection, correction counting, and undo registration.
- Simulate the reported physical-key sentence across the input-source change and
  assert the final text, including the Space that completes the last word, is
  exactly `this is not always עובד ואני לא בטוח למה `.
- Preserve regression coverage for recognized originals and excluded tokens.
- Explicitly prove the selected tradeoff: a fake learned English candidate
  `zzzz` makes Hebrew `זזזז` eligible for correction.
- Prove dictionary unavailability produces no replacement, source selection,
  correction count, or undo record.

### Manual acceptance

On the exact installed build:

- Verify ordinary non-seed Hebrew and English words in both directions.
- Teach macOS one harmless disposable Hebrew word and one harmless disposable
  English word, verify both can authorize correction, then remove both learned
  entries and verify they no longer authorize it unless built in.
- Repeat the reported sentence and verify the exact final text and input source.
- Verify immediate Command-Z after a system-authorized correction.
- Verify an unknown word, structured token, secure field, and Secure Input all
  remain unchanged.
- Record the macOS version and installed language availability because dictionary
  behavior is intentionally machine-dependent.

## Documentation Changes

The README will describe macOS dictionaries, including learned words, as
candidate authorities instead of claiming candidates must belong to the bundled
vocabulary. It will state that coverage and false positives can vary by Mac and
that immediate Command-Z is the recovery path.

The manual acceptance checklist will add non-seed and learned-word cases in both
directions, safe cleanup of disposable learned entries, and the reported
sentence. Dictionary-unavailable pass-through remains an automated adapter and
shipping-composition test because the installed application has no safe control
for deliberately disabling the macOS spelling service.

## Expected Implementation Scope

The implementation is expected to touch:

- `Sources/AkuoCore/Recognition/WordRecognizing.swift`
- `Sources/AkuoCore/Recognition/SeedLexicon.swift`
- `Sources/AkuoCore/Recognition/WordScorer.swift`
- `Sources/AkuoCore/Policy/CorrectionPolicy.swift`
- `Sources/AkuoMac/Recognition/SystemSpellChecker.swift`
- `Sources/AkuoMac/Application/AppModel.swift`
- Focused `AkuoCoreTests` and `AkuoMacTests`
- `README.md`
- `docs/manual-acceptance.md`

No UI, preference, network, telemetry, keyboard-map, event-emission, or
persistent-storage changes are expected.

## Acceptance Criteria

- Non-seed words recognized by macOS can authorize corrections in both
  directions.
- User-learned words can authorize corrections in both directions.
- Recognized originals, unknown candidates, unavailable recognition, and all
  existing excluded contexts remain unchanged.
- The reported sentence produces the expected mixed English/Hebrew output with
  exactly one trailing boundary Space.
- Source switching, correction counting, and immediate undo remain correct.
- No typed text or recognition result is persisted or logged.
- Focused tests, the full Swift test suite, a release bundle build, and the
  updated manual acceptance subset pass before completion is claimed.
