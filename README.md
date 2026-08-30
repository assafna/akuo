# Akuo

Akuo 0.2.0 is an early development preview of a local, private-by-design native macOS menu-bar utility that corrects completed English and Hebrew words typed with the wrong keyboard layout. The name comes from typing `שלום` while the English layout is active: `akuo`.

This repository currently publishes source and local build instructions only. It does not provide a Developer ID-signed or notarized public binary.

Akuo observes an unfinished token until you type whitespace or Return, the only correction boundaries in version 1. Printable punctuation remains part of that token so URLs, email addresses, paths, domains, and identifiers reach the exclusion policy intact. While the token is unfinished, Akuo also keeps its transient physical key positions in memory so recoverable English capitals are not lost when Apple's Hebrew Shift layer emits different or no visible text. At a whitespace or Return boundary, Akuo maps the complete token through the other layout once. Structured text and unsupported or punctuation-dominated shapes remain excluded, while punctuation-shaped physical keys may remain eligible when the complete conversion contains only letters in the target layout. Akuo then corrects only when the original is unknown and the mapped candidate is recognized by Akuo's seed vocabulary or the selected local macOS spelling dictionary. macOS user-learned words participate in both directions. Recognition remains local, but exact coverage can vary by macOS version, installed language resources, and learned vocabulary. After a successful correction, Akuo selects the matching macOS input source so the next word starts in the intended language. If that source switch fails, the visible correction remains and the menu asks you to select a language manually. Every completed token is considered independently, so one sentence may alternate naturally between English and Hebrew.

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

With Akuo active, try `akuo ` using the English layout; it should become `שלום ` and select Hebrew. A wrong-layout word may include a punctuation-shaped physical key: `gcrh, ` becomes `עברית ` because the comma key maps to the Hebrew letter `ת`. Using the Hebrew layout, `יקךךם ` should become `hello ` and select English. Capitalized English words are recovered when the live physical keys make the case knowable: Shift+H followed by E, L, L, O produces the visible Hebrew token `קךךם` and becomes `Hello`, while Shift+C followed by O, O, L produces `לֹםםך` and becomes `Cool`.

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
- Non-text controls and editing contexts whose text-entry role macOS cannot prove.
- URLs, email addresses, file paths, domains, and numbers.
- Shortcuts and modified key combinations.
- Source-code-like identifiers, mixed-script tokens, and punctuation-dominated tokens.
- Ambiguous or unknown words and low-confidence candidates.
- Unsupported navigation or editing sequences.

Some applications block global observation or synthetic keyboard events. Akuo fails open before emission: uncertainty in policy, focus context, security state, or preparation leaves the original input untouched. After Akuo posts a fully prepared delete/insert/boundary event batch, however, Core Graphics does not acknowledge delivery as a transaction, so Akuo cannot guarantee that another application accepts every event atomically. This is a platform boundary, not a known replacement failure. Any partial replacement or input loss is a release blocker: turn Akuo off in that application or context, preserve the evidence, and do not accept that release.

## Release acceptance

After building and installing the exact copy you intend to use, follow [the manual acceptance checklist](docs/manual-acceptance.md). Record evidence for every item and stop immediately on any input loss, secure-input observation, recursive event, or incorrect Command-Z behavior.

## License

Akuo is available under the [MIT License](LICENSE), Copyright (c) 2026 Assaf Nahum.
