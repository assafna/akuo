# Akuo

Akuo 0.3.0 is an early development preview of a local, private-by-design native macOS menu-bar utility that corrects completed English and Hebrew words typed with the wrong keyboard layout. The name comes from typing `שלום` while the English layout is active: `akuo`.

This repository currently publishes source and local build instructions only. It does not provide a Developer ID-signed or notarized public binary.

Akuo observes an unfinished token until you type whitespace or Return, the only correction boundaries in version 1. Printable punctuation remains part of that token so URLs, email addresses, paths, domains, and identifiers reach the exclusion policy intact. While the token is unfinished, Akuo keeps a transient trace of each physical key and its Shift/Caps Lock state. For every key it asks the installed Apple target layout for the exact output, rather than relying on a second hand-written punctuation map. At a whitespace or Return boundary, Akuo accepts that physical conversion only when the trace is complete, still matches the visible token, and contains at least one alphabetic physical key. This covers unchanged terminal symbols such as `!`, `?`, and `:`, punctuation keys within words that become letters or different punctuation, silent or composite Hebrew Shift output, and mirrored pairs such as parentheses, brackets, braces, and angle brackets, while leaving punctuation-only input unchanged. Recognition checks the lexical core while preserving valid terminal punctuation and balanced wrappers in the replacement. Structured text, unsupported or punctuation-dominated shapes, malformed wrappers, edited or incomplete traces, and unsafe text-only punctuation remain excluded. Akuo normally corrects only when the original core is unknown and the mapped core is recognized by Akuo's seed vocabulary or the selected local macOS spelling dictionary. A complete physical trace with recovered Shift can also authorize a recognized English candidate when the visible Hebrew fragment is itself recognized, and a complete trace resolves the standalone English words `a` and `i`. An invalid source-language shape such as `׳ם׳` cannot veto the valid trace-backed candidate `wow`; ordinary ambiguity between two valid words remains unchanged. macOS user-learned words participate in both directions. Recognition remains local, but exact coverage can vary by macOS version, installed language resources, and learned vocabulary. After a successful correction, Akuo selects the matching macOS input source so the next word starts in the intended language. If either supported target layout cannot translate a key, or the exact source changes while a key is decoded, Akuo discards partial token state and suppresses correction for the rest of that visible token until whitespace or Return. If a requested source switch fails, the visible correction remains and the menu asks you to select a language manually. Every completed token is considered independently, so one sentence may alternate naturally between English and Hebrew.

Akuo remains conservative about token shape, editing context, and unavailable recognition, but trusting learned words increases correction coverage and false-positive risk. A learned mapped candidate can authorize an unwanted correction; use immediate Command-Z to restore the original word and input source.

## Requirements and supported layouts

- macOS 13 Ventura or newer.
- Apple’s standard **ABC** or **U.S.** English input source.
- Apple’s standard **Hebrew** input source (`com.apple.keylayout.Hebrew`). **Hebrew – QWERTY** is not supported in version 1.
- Accessibility permission for the installed Akuo application.

Akuo is menu-bar-only and does not appear in the Dock. It works through the same global event path in native, browser, Electron, and terminal apps where macOS permits safe observation and synthetic input.

## Build and test

The project uses Swift Package Manager and the command-line tools included with Xcode.

```bash
swift test
Scripts/build-app.sh release
```

The packaging script accepts exactly `debug` or `release`, creates `dist/Akuo.app`, validates its property list, ad-hoc signs and verifies the bundle, and prints the SHA-256 digest of its final executable.

## Install before granting permission

For a stable local code identity, build first and then move `dist/Akuo.app` to `/Applications/Akuo.app` **before** granting Accessibility permission. Rebuilding or moving a previously authorized copy can cause macOS to treat it as a different application.

1. Build the release bundle with `Scripts/build-app.sh release`.
2. Move `dist/Akuo.app` to `/Applications/Akuo.app`.
3. Open the installed copy. Akuo appears in the menu bar and presents setup on first launch.
4. In **System Settings → Privacy & Security → Accessibility**, enable the exact `/Applications/Akuo.app` copy when prompted.
5. In **System Settings → Keyboard → Text Input → Edit**, add **ABC** (preferred) or **U.S.**, and **Hebrew**. Do not choose Hebrew – QWERTY for version 1.
6. Return to Akuo, recheck setup, complete onboarding, and turn Akuo on.

Akuo requests Accessibility only after you press the setup button. It does not need contacts, files, microphone, camera, or location access.

## Use and immediate undo

With Akuo active, try `akuo ` using the English layout; it should become `שלום ` and select Hebrew. Punctuation is converted from the same physical keys: Hebrew-layout `יקךךם! ` becomes `hello! `, English-layout `knv? ` becomes `למה? `, and Hebrew-layout `׳ם׳ ` becomes `wow `. Remapped punctuation also works: English-layout `akuo' ` becomes `שלום, `, while the Hebrew token produced by the H, E, L, L, O, comma keys becomes `hello, `. Mirrored wrappers are preserved in target-language order; for example, English-layout `)knv?( ` becomes `(למה?) `. A wrong-layout word may also include a punctuation-shaped physical key that becomes a letter: `gcrh, ` becomes `עברית ` because the comma key maps to the Hebrew letter `ת`. Using the Hebrew layout, `יקךךם ` should become `hello `, `גםמ,א ` should become `don't `, and `׳ק,רק ` should become `we're `, then select English. The leading `׳` is the Hebrew punctuation geresh emitted by the standard Apple Hebrew W key; a straight apostrophe remains accepted as a compatibility form. Capitalized English words are recovered when the live physical keys make the case knowable: Shift+H followed by E, L, L, O produces the visible Hebrew token `קךךם` and becomes `Hello`, while Shift+C followed by O, O, L produces `לֹםםך` and becomes `Cool`. The apostrophe key remains part of that evidence: Shift+D followed by O, N, apostrophe, T produces `„םמ,א` and becomes `Don't`; Shift+W followed by E, apostrophe, R, E produces `ק,רק` and becomes `We're`; and shifting every letter in `DON'T` produces only `„,` before correction. This applies per physical key across the word: Shift+Y followed by E, S becomes `Yes`; shifting Y, E, and S becomes `YES`; and Shift+N followed by O becomes `No`, even though their visible Hebrew fragments are also recognized words or letters. The standalone Hebrew-layout I key becomes `i`, or `I` while shifted.

Immediately after an Akuo correction, Command-Z in the same application and focused field restores the original word, its boundary, and the previous input source. Akuo keeps only one transient undo record for up to five seconds. Any ordinary typing, mouse click, focus or application change, second correction, timeout, or Secure Input transition invalidates it. Once invalidated, Command-Z is passed to the current application normally.

## Privacy and local storage

All recognition, scoring, correction, and spelling checks run entirely on the Mac. Akuo has no account, cloud service, analytics, telemetry, or typing-related network path. It does not log or persist keystrokes, words, correction candidates, focused-field details, application context, or undo records.

Akuo persists exactly these four preference categories:

1. Enabled state.
2. Onboarding completion.
3. Aggregate correction count.
4. Launch at Login preference.

The correction count is only a number; there is no correction or word history.

## Version 1 limits and exclusions

Version 1 supports only standard English QWERTY and Israeli Hebrew. It does not translate, transliterate, correct grammar or general spelling, correct mid-word, learn from typing, personalize by application, or keep history. Other languages and layouts, including Hebrew – QWERTY, are outside version 1.

Akuo intentionally leaves these unchanged:

- Secure and password fields, and all input while macOS Secure Input is active.
- Non-text, disabled, and read-only controls, plus editing contexts whose
  writable text value macOS Accessibility cannot prove.
- URLs, email addresses, file paths, domains, and numbers.
- Shortcuts and modified key combinations.
- Source-code-like identifiers, mixed-script tokens, and punctuation-dominated tokens.
- Punctuation-only physical-key sequences, even when the other layout maps
  them to recognized letters.
- Ambiguous or unknown words and low-confidence candidates.
- Unsupported navigation or editing sequences.

Some applications block global observation or synthetic keyboard events. Akuo fails open before emission: uncertainty in policy, focus context, security state, or preparation leaves the original input untouched. It verifies a stable frontmost application and focused Accessibility element while inspecting editability, then rechecks the same eligible focus immediately before correction or immediate undo. After Akuo posts a fully prepared delete/insert/boundary event batch, however, Core Graphics does not acknowledge delivery as a transaction, so Akuo cannot guarantee that another application accepts every event atomically. This is a platform boundary, not a known replacement failure. Any partial replacement or input loss is a release blocker: turn Akuo off in that application or context, preserve the evidence, and do not accept that release.

## Release acceptance

After building and installing the exact copy you intend to use, follow [the manual acceptance checklist](docs/manual-acceptance.md). Record evidence for every item and stop immediately on any input loss, secure-input observation, recursive event, or incorrect Command-Z behavior.

## License

Akuo is available under the [MIT License](LICENSE), Copyright (c) 2026 Assaf Nahum.
