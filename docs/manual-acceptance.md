# Akuo v1 Manual Acceptance

Use this checklist only with the exact release candidate you intend to accept. Build and install Akuo in `/Applications` before granting Accessibility permission so macOS associates permission with a stable local identity. Do not mark an item passed without recording observable evidence.

## Release identity and evidence

| Field | Value |
|---|---|
| Tester | |
| Date and time | |
| Mac model | |
| macOS version and build | |
| Akuo version | |
| Akuo `CFBundleVersion` | |
| Git commit | |
| Installed app path | `/Applications/Akuo.app` |
| Executable SHA-256 | |
| English input source and identifier | |
| Hebrew input source and identifier | |
| macOS spelling languages (English: `en` or `en_US`; Hebrew: `he` or `he_IL`) | |
| Electron editor and version | |
| Evidence folder or link | |
| Overall result | `PENDING` |

For each checkbox, write `PASS`, `FAIL`, or `BLOCKED` in **Result** and add concise evidence such as a screenshot name, screen recording timestamp, observed text/source, Console export, or command output. Redact unrelated private content.

Run this local inspection command and record whether each required language is
advertised by either its base identifier or its locale-specific identifier:

```bash
xcrun swift -e 'import AppKit; print(NSSpellChecker.shared.availableLanguages.sorted())'
```

English is available when the list contains `en` or `en_US`; Hebrew is available
when it contains `he` or `he_IL`. If neither accepted identifier is present for a
language, its non-seed recognition checks are `BLOCKED`; seed recognition remains
testable, but the release cannot claim general dictionary coverage for that language.

## Release-blocker and stop rules

Stop testing, set the overall result to `BLOCKED`, preserve evidence, and do not accept the release if any test causes:

- Input loss, partial replacement, duplicated boundaries, or text inserted in the wrong field.
- Observation or modification of a password/secure field, or activity while Secure Input is active.
- Recursive handling of Akuo-generated events, repeated replacement, or an event loop.
- Command-Z interception outside the one immediate eligible correction, or failure to preserve normal application undo.

Record the blocker here before stopping:

| Time | App and field | Input/action | Expected | Actual | Evidence |
|---|---|---|---|---|---|
| | | | | | |

## 1. Build, install, and metadata

- [ ] **Release bundle built.** Run `swift test` and `Scripts/build-app.sh release`; record the passing test count, bundle path, and printed executable SHA-256. **Result:**
  **Evidence:**
- [ ] **Bundle identity verified.** Confirm `CFBundleIdentifier = app.akuo.Akuo`, version `0.3.0`, build `3`, `LSMinimumSystemVersion = 13.0`, and `LSUIElement = true`. **Result:**
  **Evidence:**
- [ ] **Installed before permission.** Move the release candidate to `/Applications/Akuo.app`, confirm its executable hash matches the built candidate, and launch only that copy. **Result:**
  **Evidence:**
- [ ] **Menu-bar-only behavior.** Confirm Akuo appears in the menu bar and does not appear in the Dock. **Result:**
  **Evidence:**

## 2. Permission setup, revocation, and input sources

- [ ] **Permission begins explicit.** With Accessibility disabled for Akuo, launch it and confirm it remains inactive and explains that permission is needed without prompting until **Request Accessibility Access** is pressed. **Result:**
  **Evidence:**
- [ ] **Permission grant.** Grant Accessibility to the exact `/Applications/Akuo.app` entry, return to Akuo, recheck setup, and confirm permission becomes ready. **Result:**
  **Evidence:**
- [ ] **English source detection.** With standard ABC or U.S. installed, confirm Akuo reports English input ready and identifies the current source as English when selected. **Result:**
  **Evidence:**
- [ ] **Hebrew source detection.** With standard Hebrew installed, confirm Akuo reports Hebrew input ready and identifies the current source as Hebrew when selected. **Result:**
  **Evidence:**
- [ ] **Unsupported Hebrew – QWERTY.** Temporarily verify Hebrew – QWERTY alone does not satisfy Hebrew readiness; restore standard Hebrew before continuing. **Result:**
  **Evidence:**
- [ ] **Permission revocation fails open.** Revoke Accessibility while Akuo is on. Confirm status changes to permission needed, monitoring stops, and ordinary typing remains unchanged. Regrant permission to the same installed copy before continuing. **Result:**
  **Evidence:**

## 3. Core English/Hebrew correction

Perform these first in TextEdit with a new empty plain-text document.

Version 1 completes a token only at Space or Return/Enter. Tab and Shift-Tab pass through untouched and clear the unfinished token so application-owned completion and focus navigation remain in control. Printable punctuation does not trigger correction and remains part of the unfinished token until one of the correction boundaries arrives. Each live key is translated through the installed Apple target layout with its Shift/Caps Lock state. At the boundary, punctuation is eligible only when the complete trace still matches the visible token and converts to a valid target-language lexical core, optionally surrounded by supported terminal punctuation or balanced wrappers. Structured and unsupported punctuation remains excluded.

- [ ] **Tab and Shift-Tab pass through.** In an editable control where the application's native Tab and Shift-Tab behavior is observable, select English and type `akuo`, then press each key in a fresh field. Confirm Akuo leaves `akuo` unchanged, does not switch the input source, and the application performs its own completion or focus navigation. After a separate Akuo correction, press Tab and confirm Command-Z is passed to the application instead of undoing that earlier correction. After each case, type a fresh `akuo ` and confirm Space still produces exactly `שלום ` and selects standard Hebrew. **Result:**
  **Evidence:**

- [ ] **English-layout Hebrew correction.** Select English, type `akuo `, and confirm the visible result is exactly `שלום ` with one space and the active input source changes to standard Hebrew. **Result:**
  **Evidence:**
- [ ] **Comma key as a Hebrew letter.** Select English, type only `gcrh,` and pause. Confirm it remains buffered and unchanged. Then press Space and confirm the visible result is exactly `עברית ` with one Space and the active input source changes to standard Hebrew. Confirm `עברית` is recognized by that Mac's Hebrew spelling dictionary. **Result:**
  **Evidence:**
- [ ] **Other punctuation keys as Hebrew letters.** Select English and separately type `tr. ` and `gu; `. Confirm the visible results are exactly `ארץ ` and `עוף ` with one Space each and the active input source changes to standard Hebrew after each recognized candidate. Confirm both Hebrew candidates are recognized on that Mac. **Result:**
  **Evidence:**
- [ ] **Hebrew-layout English correction.** Select Hebrew, type the physical keys that produce `יקךךם `, and confirm the visible result is exactly `hello ` with one space and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **Hebrew-layout terminal exclamation.** Select Hebrew, type the physical keys that produce `יקךךם! `, including Shift+1 and the final Space. Confirm the visible result is exactly `hello! ` and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **English-layout terminal question mark.** Select English, type `knv? `, including Shift+/ and the final Space. Confirm the visible result is exactly `למה? ` and the active input source changes to standard Hebrew. **Result:**
  **Evidence:**
- [ ] **Malformed visible Hebrew shape resolved by its physical trace.** Select Hebrew, type the physical W, O, W keys so the unfinished token is exactly `׳ם׳`, then press Space. Confirm the visible result is exactly `wow ` and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **Remapped terminal punctuation in both directions.** Select English, type `akuo' ` and confirm the exact result `שלום, `. Then select Hebrew and type the physical H, E, L, L, O, comma keys followed by Space; confirm the Hebrew unfinished token ends in `ת` and the exact result is `hello, `. **Result:**
  **Evidence:**
- [ ] **Mirrored wrapper pair.** Select English and type the physical keys whose English text is `)knv?(`, followed by Space. Confirm the exact result is `(למה?) `, with the parentheses in target-language order, and the active input source changes to standard Hebrew. **Result:**
  **Evidence:**
- [ ] **Hebrew-layout English contraction.** Select Hebrew, type the physical D, O, N, apostrophe, T keys and pause. Confirm the visible unfinished token is exactly `גםמ,א`. Press Space and confirm the visible result is exactly `don't ` with one space and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **Hebrew geresh W-key contraction.** Select Hebrew, type the physical W, E, apostrophe, R, E keys and pause. Confirm the visible unfinished token is exactly `׳ק,רק`, beginning with U+05F3 Hebrew punctuation geresh. Press Space and confirm the visible result is exactly `we're ` with one space and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **Shifted contraction keeps physical capitalization.** Select Hebrew, hold Shift while pressing the physical W key, release Shift, then press E, apostrophe, R, E. Confirm the visible unfinished token is exactly `ק,רק`. Press Space and confirm the visible result is exactly `We're ` with one space and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **Visible Shift-D contraction.** Select Hebrew, hold Shift while pressing the physical D key, release Shift, then press O, N, apostrophe, T. Confirm the visible unfinished token is exactly `„םמ,א`, beginning with U+201E. Press Space and confirm the visible result is exactly `Don't ` with one space and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **All-caps contraction with silent Shift keys.** Select Hebrew, hold Shift while pressing D, O, N, and T, and type apostrophe without Shift. Confirm the visible unfinished token is exactly `„,`. Press Space and confirm the visible result is exactly `DON'T ` with one space and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **Silent shifted capital recovery.** Select standard Hebrew, hold Shift while pressing the physical H key, release Shift, then press E, L, L, O. Confirm the visible unfinished token is exactly `קךךם`. Press Space and confirm the visible result is exactly `Hello ` with one space and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **Composite shifted capital recovery.** Select standard Hebrew, hold Shift while pressing the physical C key, release Shift, then press O, O, L. Confirm the visible unfinished token is exactly `לֹםםך`. Press Space and confirm the visible result is exactly `Cool ` with one space and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **Recognized Hebrew fragment does not veto physical case.** Select standard Hebrew, hold Shift while pressing the physical Y key, release Shift, then press E, S. Confirm the visible unfinished token is exactly `קד`. Press Space and confirm the visible result is exactly `Yes ` with one space and the active input source changes to English. Repeat with Shift+N followed by O; confirm the visible unfinished token `ם` becomes exactly `No `. **Result:**
  **Evidence:**
- [ ] **All-caps silent shifted word recovery.** Select standard Hebrew and hold Shift while pressing the physical Y, E, and S keys. Confirm the unfinished token emits no visible text. Press Space and confirm the visible result is exactly `YES ` with one space and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **Standalone A and I recovery.** Select standard Hebrew and test the physical A and I keys separately. Confirm `ש` becomes exactly `a ` and `ן` becomes exactly `i ` after Space. Repeat each key while holding Shift and confirm its shifted Hebrew output becomes exactly `A ` and `I `, respectively. **Result:**
  **Evidence:**
- [ ] **Correct English unchanged.** Type `hello ` using English; confirm text and input source are unchanged. **Result:**
  **Evidence:**
- [ ] **Recognized English with punctuation unchanged.** Type `hello, ` using English; confirm the text remains exactly `hello, ` and the input source remains English. **Result:**
  **Evidence:**
- [ ] **Correct Hebrew unchanged.** Type `שלום ` using Hebrew; confirm text and input source are unchanged. **Result:**
  **Evidence:**
- [ ] **Ambiguous forms unchanged.** Type `go ` using English and `עם ` using Hebrew; confirm both remain exactly as typed. **Result:**
  **Evidence:**
- [ ] **Unknown forms unchanged.** Type at least one unrecognized English-shaped token and one unrecognized Hebrew-shaped token; record the exact test tokens and confirm both remain unchanged. **Result:**
  **Evidence:**
- [ ] **Non-seed Hebrew dictionary correction.** Select English, type `gucs `, and confirm the visible result is exactly `עובד ` with one Space and the active input source changes to standard Hebrew. Record the macOS version and confirm `עובד` is recognized by that Mac's Hebrew spelling dictionary. **Result:**
  **Evidence:**
- [ ] **Non-seed English dictionary correction.** Select standard Hebrew, type the physical keys that produce `בםצפואקר `, and confirm the visible result is exactly `computer ` with one Space and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **Reported mixed sentence.** Start with English and continuously press the physical keys for `this is not always gucs utbh kt cyuj knv `, including the final Space. Confirm the visible result is exactly `this is not always עובד ואני לא בטוח למה ` and the active source is Hebrew. **Result:**
  **Evidence:**
- [ ] **Alternating-language sentence.** In one sentence, alternate correct and wrong-layout English/Hebrew words. Confirm each completed word is evaluated independently, intended corrections occur, correct words remain, boundaries are preserved, and the source aligns after each correction. **Result:**
  **Evidence:**
- [ ] **Repeated source-switch decoding.** Start with English and continuously
  press the physical keys for `Hello world akuo guko hello world akuo guko `,
  including the final Space. Confirm the visible result is exactly
  `Hello world שלום עולם hello world שלום עולם ` and the active
  source is standard Hebrew. **Result:**
  **Evidence:**

### Force the current or previous eligible word

Run these in a new empty TextEdit document. A force request deliberately bypasses
automatic dictionary ambiguity, but it must retain every token-shape, focus,
security, and timing safeguard.

- [ ] **Double Shift converts the unfinished word by default.** With **Force
  conversion** set to **Double-tap Shift**, select English, type `go` without
  Space or Return, and confirm it remains exactly `go` because both `go` and its
  Hebrew mapping `עם` are recognized. Tap and release the same physical Shift
  key twice. Confirm the text becomes exactly `עם`, the source changes to
  standard Hebrew, the correction count increases once, and every Shift press
  still reaches macOS. Repeat double-Shift twice and confirm the text and source
  alternate exactly `go`/ABC, then `עם`/Hebrew, while the correction count does
  not increase again. **Result:**
  **Evidence:**
- [ ] **Literal layout output survives realistic mixed context.** In one
  continuous TextEdit sentence, force English `go`, `hello`, `world`, and
  `test`; type the physical Hebrew-layout H, E, L, L, O keys and force the
  resulting `יקךךם` back to `hello`; force English `knv?`; challenge
  `https://akuo.app`, `me@example.com`, and `file_name`; then type the physical
  Hebrew-layout G and O keys and force `עם` back to `go`. Include ordinary
  numbers, operators, wrappers, and terminal punctuation between those tokens.
  Vary source-to-key delay from immediate to 250 ms, last-key-to-gesture delay
  from immediate to 500 ms, and valid press/gap timing below the 400 ms gesture
  limit. Confirm the exact final sentence is
  `Mix: עם, יקךךם; ׳םרךג! אקדא | 123 + 45 = 168 | hello, למה? | https://akuo.app | me@example.com | file_name | go; symbols []{}!? #42.`,
  the protected structural tokens remain unchanged, and ABC is selected.
  **Result:**
  **Evidence:**
- [ ] **Completed-word fallback remains available.** Select English, type `go `,
  and within five seconds double-tap the same Shift key. Confirm the text becomes
  exactly `עם `, the source changes to standard Hebrew, the
  correction count increases once, and every Shift press still reaches macOS.
  **Result:**
  **Evidence:**
- [ ] **Completed-word fallback requires the exact caret suffix.** In disposable
  editable fields, type `go ` and separately test (a) moving the caret without
  typing, (b) letting the host substitute or replace the completed text, and
  (c) pressing Return in a single-line field that submits or clears its value
  while reusing the same control. Then perform the configured gesture. Confirm
  Akuo never deletes unrelated text, switches the source, or increases the
  correction count. **Result:**
  **Evidence:**
- [ ] **A manual source change invalidates completed-word fallback.** Select ABC,
  type `go `, manually switch first to U.S. in one fresh case and to Hebrew in
  another, then perform the configured gesture within five seconds. Confirm
  `go ` remains exact and Akuo does not switch the source or increase the count.
  **Result:**
  **Evidence:**
- [ ] **Backspace invalidates an edited word's physical trace.** Select English,
  type `akuo`, delete the final `o`, and perform the configured gesture. Confirm
  the visible `aku` remains exact rather than becoming its static Hebrew mapping
  `שלו`, and no source switch or count increase occurs. At an empty caret, press
  Backspace, type a fresh `go`, and confirm the gesture still converts that new
  unedited word to `עם`. **Result:**
  **Evidence:**
- [ ] **Automatic corrections toggle too.** Select English, type `akuo ` and
  confirm the automatic result is exactly `שלום ` with Hebrew selected.
  Double-tap the same Shift key three times in succession and confirm the exact
  states alternate `akuo `/ABC, `שלום `/Hebrew, and `akuo `/ABC. Confirm the
  correction count increased only for the original automatic correction.
  **Result:**
  **Evidence:**
- [ ] **Reverse-direction force and immediate undo.** Select standard Hebrew,
  type the physical G and O keys without a boundary so the text is exactly `עם`.
  Double-tap the same Shift key and confirm the exact result is `go` with the
  English source selected. Double-tap again to restore `עם`/Hebrew, then press
  Command-Z and confirm Akuo restores exactly `go` and ABC. Double-tap once more
  and confirm nothing changes because Command-Z ended the toggle chain. **Result:**
  **Evidence:**
- [ ] **Return never arms delayed fallback.** Select English, type `go`, press
  Return, and confirm the host receives exactly one newline or performs its
  normal submission. Double-tap the same Shift key within five seconds and
  confirm Akuo does not alter the submitted `go`, insert text at the new caret,
  switch the source, or increase the correction count. In a fresh case, type
  `go` and double-tap before Return to confirm unfinished-word force still
  produces exactly `עם`. **Result:**
  **Evidence:**
- [ ] **Both Shift keys alternative.** From the menu choose **Press both Shift
  keys**. Type a fresh `go`, then press the left and right Shift keys so they
  overlap within a short chord. Confirm exactly one `עם` conversion occurs.
  Type another fresh `go` and double-tap only one Shift key; confirm no force
  occurs. Restore **Double-tap Shift** before continuing. **Result:**
  **Evidence:**
- [ ] **Completed-word eligibility expires.** In separate fresh cases, type
  `go ` and then (a) wait more than five seconds, (b) type one ordinary character,
  (c) click elsewhere in the same editor, and (d) change applications or fields.
  Perform the configured gesture after each invalidation. Confirm no old word is
  changed, no source switch or count increase occurs, and the Shift events retain
  their normal behavior. **Result:**
  **Evidence:**
- [ ] **Structural exclusions cannot be forced.** In fresh cases type
  `https://akuo.app`, `me@example.com`, `/tmp/file`, `file_name`, and `.` without
  a boundary. Perform the configured gesture after each value. Confirm every
  value remains exact, the input source does not change, and the correction count
  does not increase. **Result:**
  **Evidence:**
- [ ] **No pending word is harmless.** In an empty document, perform the
  configured gesture. Confirm no text is deleted or inserted and no source
  switch or correction-count increase occurs. **Result:**
  **Evidence:**

### Learned-word candidate authority

Use TextEdit's spelling menu to learn and later unlearn only the disposable values below. Before learning, confirm macOS marks each value unknown. If either value is already built in or previously learned, choose a new harmless value whose physical-key mapping contains only letters and record both forms.

- [ ] **Learned Hebrew candidate.** Learn `אבזח`, select English, type `tczj `, and confirm Akuo changes it to `אבזח ` and selects Hebrew. **Result:**
  **Evidence:**
- [ ] **Learned English candidate.** Learn `blorf`, select Hebrew, type the physical keys that produce `נךםרכ `, and confirm Akuo changes it to `blorf ` and selects English. **Result:**
  **Evidence:**
- [ ] **Learned original veto.** Type each learned value using its correct input source and confirm Akuo leaves it unchanged. **Result:**
  **Evidence:**
- [ ] **Learned-word cleanup.** Unlearn both disposable values, repeat their wrong-layout forms, and confirm neither correction occurs unless macOS now recognizes the value independently of the learned entry. **Result:**
  **Evidence:**

## 4. Immediate Command-Z and normal undo

Run separately in TextEdit and one other supported application.

- [ ] **Immediate correction undo.** Cause `gcrh, ` → `עברית ` and immediately press Command-Z in the same field. Confirm Akuo restores exactly `gcrh, ` and the prior English source. **Result:**
  **Evidence:**
- [ ] **Reverse-direction immediate undo.** Cause `יקךךם ` → `hello ` and immediately press Command-Z. Confirm Akuo restores exactly `יקךךם ` and the prior Hebrew source. **Result:**
  **Evidence:**
- [ ] **Intervening typing expires Akuo undo.** Cause a correction, type one ordinary character, then press Command-Z. Confirm Command-Z reaches the host application and performs its normal undo; it must not restore Akuo’s original wrong-layout word. **Result:**
  **Evidence:**
- [ ] **Focus/context change expires Akuo undo.** Cause a correction, move focus to another field or app, then press Command-Z. Confirm Akuo does not intercept it. **Result:**
  **Evidence:**
- [ ] **Same-editor mouse relocation expires Akuo undo.** In a document with harmless existing text, cause a correction, click a different insertion point inside the same editor, and press Command-Z. Confirm Akuo does not restore the wrong-layout word at the old location, does not replace text at the new location, and leaves the host application to perform its native undo behavior. **Result:**
  **Evidence:**
- [ ] **Undo timeout.** Cause a correction, wait more than five seconds without typing, then press Command-Z. Confirm Akuo does not intercept the host application’s undo. **Result:**
  **Evidence:**

## 5. Conservative exclusions and editing safety

Use recognizable test data that contains no real credentials or personal information.

- [ ] **Return is a correction boundary.** In a new empty TextEdit document, select English, type `akuo`, and press Return. Confirm the document contains exactly `שלום\n` (the first line is `שלום` and the insertion point is on the empty second line) and the active input source is standard Hebrew. **Result:**
  **Evidence:**
- [ ] **Layout punctuation with Return boundary.** In a new empty TextEdit document, select English, type `gcrh,`, and press Return. Confirm the document contains exactly `עברית\n`, Return occurs exactly once, and the active input source is standard Hebrew. **Result:**
  **Evidence:**
- [ ] **Unknown punctuation conversion unchanged.** In a new empty TextEdit document, select English, type `akuo. `, and confirm the visible text is exactly `akuo. `: the dot remains buffered until Space, the mapped candidate `שלוםץ` is unknown, and the active input source remains English. **Result:**
  **Evidence:**
- [ ] **Punctuation-only keys unchanged.** In a new empty TextEdit document,
  select English and type `. `, `, `, and `; ` separately. Repeat each with
  Return instead of Space. Confirm every punctuation mark and boundary remains
  exactly as typed, the input source remains English, and Command-Z retains the
  host application's normal behavior because Akuo created no correction or
  undo record. **Result:**
  **Evidence:**
- [ ] **URLs unchanged.** Type `https://akuo.app ` and confirm exact pass-through. **Result:**
  **Evidence:**
- [ ] **Emails unchanged.** Type `me@example.com ` and confirm exact pass-through. **Result:**
  **Evidence:**
- [ ] **Paths unchanged.** Type `/tmp/file ` and confirm exact pass-through. **Result:**
  **Evidence:**
- [ ] **Numbers unchanged.** Type `abc123 ` and `12345 ` and confirm exact pass-through. **Result:**
  **Evidence:**
- [ ] **Shortcuts unchanged.** Exercise Command-C, Command-V with harmless text, Command-A, and a representative Option/Control chord. Confirm Akuo does not correct or swallow them. **Result:**
  **Evidence:**
- [ ] **Identifiers unchanged.** Type `file_name `, `camelCase `, and `PascalCase ` and confirm exact pass-through. **Result:**
  **Evidence:**
- [ ] **Exact cascading exclusion sequence.** In a new empty TextEdit document, select English and type `hello go qqqq abc123 file_name camelCase me@example.com https://akuo.app /tmp/file `. Confirm the visible text is exactly `hello go qqqq abc123 file_name camelCase me@example.com https://akuo.app /tmp/file `, no replacement occurs anywhere in the sequence, and the active input source remains English. **Result:**
  **Evidence:**
- [ ] **Fresh correction after an excluded token.** In a new empty TextEdit document, select English and type `akuo.app akuo `. Confirm the visible text is exactly `akuo.app שלום `: the excluded domain remains unchanged, the subsequent fresh `akuo ` corrects once, and the active input source changes to standard Hebrew only after that fresh correction. **Result:**
  **Evidence:**
- [ ] **Mirrored Hebrew domain shape unchanged.** In a new empty TextEdit document, select standard Hebrew and type the physical keys that produce `יקךךם.בםצ `. Confirm the visible text remains exactly `יקךךם.בםצ `, no partial `hello` correction occurs, and the active input source remains standard Hebrew. **Result:**
  **Evidence:**
- [ ] **Leading mapped punctuation remains eligible.** In a new empty TextEdit document, select standard Hebrew and type the physical keys that produce `/וןבל `. Confirm the visible result is exactly `quick ` with one space and the active input source changes to English. **Result:**
  **Evidence:**
- [ ] **Navigation unchanged.** While partway through a token, use Left/Right arrows and Home/End where supported; confirm navigation is preserved and no stale token is later corrected. **Result:**
  **Evidence:**
- [ ] **Same-editor mouse relocation clears partial input.** In a TextEdit document containing harmless marker text on two lines, type only `a` at the first marker, click after the second marker in the same editor, then type `kuo `. Confirm no correction occurs, neither marker nor the earlier `a` is deleted, and the second location contains exactly `kuo `. **Result:**
  **Evidence:**
- [ ] **Non-text controls are untouched.** Focus a local list, outline row, static label, and ordinary button next to a disposable text field. Exercise a harmless letter, Space, and Return only where the control's documented native action is safe. Confirm the native control action is preserved and Akuo does not delete or insert anything in the adjacent field. **Result:**
  **Evidence:**
- [ ] **Read-only and disabled text controls are untouched.** Open a disposable local or `data:` form containing a read-only textarea, a disabled textarea, and an ordinary textarea. Select English, focus the read-only textarea, type `akuo `, and confirm its value, the input source, and the correction count remain unchanged. Confirm keyboard focus skips the disabled textarea; this proves only the host's native skip behavior. Claim live `AXEnabled=false` gate coverage only with Accessibility Inspector or a disposable local harness that can keep such a control focused. Then focus the ordinary textarea and type a fresh `akuo `; confirm it becomes exactly `שלום ` and the input source changes to standard Hebrew. **Result:**
  **Evidence:**
- [ ] **Password fields are neither corrected nor buffered.** In a disposable local password field with no real secret and a safe reveal control, type `akuo ` and the reverse-direction example with their boundaries. Confirm the revealed harmless value is exactly what was typed, no source switch or correction-count increase occurs, and after leaving the field a fresh partial suffix and boundary in a normal editor cannot complete or correct any password-field prefix. **Result:**
  **Evidence:**
- [ ] **Secure Input pause and recovery.** In Terminal, turn on **Terminal → Secure Keyboard Entry** and keep Terminal focused for the protected interval; opening Akuo's menu or switching apps invalidates the tested input context. With standard English selected, type the harmless unexecuted prompt text `akuo ` without pressing Return. Confirm the text remains exactly `akuo ` and the source remains English. Use Control-U to clear the harmless prompt input, turn Secure Keyboard Entry off, wait two seconds, then type a fresh `akuo ` without Return. Confirm it becomes `שלום ` and the source selection changes to Hebrew. Akuo must not observe or modify protected input. **Result:**
  **Evidence:**

## 6. Application matrix

In every row, test both correction directions, one correct word, one excluded token, immediate Command-Z, and ordinary typing after enable/disable. Record exact app version and evidence.

| Done | Application | Version/document context | Result | Evidence |
|---|---|---|---|---|
| [ ] | TextEdit | | | |
| [ ] | Safari | Non-secure text field | | |
| [ ] | Messages | New unsent message | | |
| [ ] | Terminal | Harmless local prompt/input; do not execute test text | | |
| [ ] | Electron editor | Name: | | |

### Native Return identity

For every item below, start from a fresh field and use Return itself as the correction boundary. Confirm the corrected text appears exactly once and the host receives its normal Return action exactly once—no missing submission/newline and no duplicate action.

- [ ] **Terminal Return.** At a harmless local shell, first run `IFS= read -r akuo_acceptance && print -r -- "$akuo_acceptance"`. At the waiting input, select English, type `akuo`, and press Return. Confirm the read completes once and prints exactly `שלום`; do not use a command that executes the corrected text. **Result:**
  **Evidence:**
- [ ] **Browser form Return.** Open a disposable local or `data:` form whose submit handler prevents network navigation and displays the submitted value. Select English, type `akuo`, and press Return. Confirm one submit action displays exactly `שלום`. **Result:**
  **Evidence:**
- [ ] **Messages Return.** In a self-conversation or a designated consenting test conversation, select English, type the harmless text `akuo`, and press Return. Confirm exactly one `שלום` message is sent and no draft fragment remains. **Result:**
  **Evidence:**
- [ ] **Electron editor Return.** In the recorded Electron editor, select English, type `akuo`, and press Return. Confirm the editor contains `שלום` followed by exactly one native newline with the caret on the next line. **Result:**
  **Evidence:**

## 7. Controls, recovery, and lifecycle

- [ ] **Disable pass-through.** Turn Akuo off and repeat both wrong-layout examples; confirm text and source remain unchanged. Turn Akuo back on and confirm correction resumes only from a fresh token. **Result:**
  **Evidence:**
- [ ] **Deterministic source-selection failure.** Do not force a live Carbon failure if doing so could disturb system input-source state. Instead, from the release source run `swift test --filter 'CorrectionCoordinatorTests/testSourceSelectionFailureKeepsVisibleCorrectionAndUndoRecord|CorrectionCoordinatorTests/testForcedSourceSelectionFailureKeepsVisibleCorrectionAndUndo|CorrectionCoordinatorTests/testUndoSelectionFailureKeepsVisibleRestorationWithoutRetry|KeyboardEventMonitorTests/testCorrectionSelectionFailureIsSignaledAfterSuppressingBoundary|KeyboardEventMonitorTests/testForcedCorrectionSelectionFailureIsReportedWithoutSwallowingShift|KeyboardEventMonitorTests/testUndoSelectionFailureIsSignaledAfterSuppressingCommandZ|AppModelTests/testCorrectionSelectionFailureRefreshesDisplayWithoutRestartOrRetry|AppModelTests/testUndoSelectionFailureUsesSameActionableStatusAndRefreshOnly'`. Confirm all injected automatic-correction, forced-correction, and undo failure paths pass: the visible edit/count/eligible undo are retained, selection is not retried, displayed language refreshes, and the menu reports **Input source switch failed — select a language manually** rather than **Active** or a keyboard-monitor failure. **Result:**
  **Evidence:**
- [ ] **Event-tap timeout recovery.** Use the controlled procedure below to prove that the installed tap clears a partial token when macOS disables it. Do not post synthetic events or use real user data. **Result:**
  **Evidence:** Exact PID, executable, recorded start fingerprint, and shell transcript or screen-recording timestamp; stop/continue times; unchanged-focus proof; partial-token outcome; fresh-token outcome.

  1. Open a disposable empty TextEdit document, select English, and confirm Akuo is **Active**. Arrange TextEdit and Terminal side-by-side so Terminal output remains visible while the TextEdit field is focused. Leave the insertion point in the empty TextEdit document.
  2. In Terminal, paste the exact zsh block below. It requires exactly one numeric `Akuo` PID, accepts launch arguments but requires the command’s first executable path to be exactly `/Applications/Akuo.app/Contents/MacOS/Akuo`, and records a normalized `lstart` fingerprint. Its single `akuo_identity_matches` function revalidates that same PID, executable, and start fingerprint immediately before `SIGSTOP` and before every `SIGCONT`, including cleanup. The entire block is a subshell, so its strict options, variables, traps, and exits cannot alter the interactive shell.

     ```zsh
     (
     set -euo pipefail

     akuo_expected="/Applications/Akuo.app/Contents/MacOS/Akuo"
     akuo_pid_lines="$(pgrep -x Akuo || true)"
     akuo_pid_count="$(printf '%s\n' "$akuo_pid_lines" | awk 'NF { count += 1 } END { print count + 0 }')"
     if [[ "$akuo_pid_count" -ne 1 ]]; then
         print -u2 "BLOCKED: expected exactly one Akuo PID, found $akuo_pid_count"
         exit 1
     fi

     akuo_pid="$akuo_pid_lines"
     if [[ ! "$akuo_pid" =~ '^[0-9]+$' ]]; then
         print -u2 "BLOCKED: Akuo PID is not numeric"
         exit 1
     fi

     if ! akuo_command="$(ps -p "$akuo_pid" -o command= 2>/dev/null)"; then
         print -u2 "BLOCKED: could not read command for Akuo PID $akuo_pid"
         exit 1
     fi
     akuo_executable="$(printf '%s\n' "$akuo_command" | awk 'NF { print $1; exit }')"
     if [[ "$akuo_executable" != "$akuo_expected" ]]; then
         print -u2 "BLOCKED: PID $akuo_pid executable is '$akuo_executable', not '$akuo_expected'"
         exit 1
     fi

     if ! akuo_start="$(ps -p "$akuo_pid" -o lstart= 2>/dev/null | awk '{$1 = $1; print}')" || [[ -z "$akuo_start" ]]; then
         print -u2 "BLOCKED: could not read start fingerprint for Akuo PID $akuo_pid"
         exit 1
     fi

     akuo_identity_matches() {
         local current_command current_executable current_start
         if ! current_command="$(ps -p "$akuo_pid" -o command= 2>/dev/null)"; then
             return 1
         fi
         current_executable="$(printf '%s\n' "$current_command" | awk 'NF { print $1; exit }')"
         if ! current_start="$(ps -p "$akuo_pid" -o lstart= 2>/dev/null | awk '{$1 = $1; print}')"; then
             return 1
         fi
         [[ "$current_executable" == "$akuo_expected" && "$current_start" == "$akuo_start" ]]
     }

     akuo_may_be_stopped=0
     resume_akuo_best_effort() {
         if [[ "$akuo_may_be_stopped" -eq 1 ]]; then
             if ! akuo_identity_matches; then
                 print -u2 "BLOCKED: cleanup did not signal PID $akuo_pid because its identity no longer matches"
             elif ! kill -CONT "$akuo_pid"; then
                 print -u2 "BLOCKED: cleanup could not continue validated Akuo PID $akuo_pid"
             fi
         fi
     }
     trap resume_akuo_best_effort EXIT
     trap 'exit 130' HUP INT TERM

     print "RECORD PID: $akuo_pid"
     print "RECORD EXECUTABLE: $akuo_executable"
     print "RECORD START: $akuo_start"
     print "SIGSTOP scheduled in 10 seconds at $(date)"
     sleep 10

     if ! akuo_identity_matches; then
         print -u2 "BLOCKED: Akuo identity changed before SIGSTOP; no signal sent"
         exit 1
     fi
     akuo_may_be_stopped=1
     if ! kill -STOP "$akuo_pid"; then
         akuo_may_be_stopped=0
         print -u2 "BLOCKED: failed to stop validated Akuo PID $akuo_pid"
         exit 1
     fi
     print "Akuo PID $akuo_pid stopped at $(date); SIGCONT scheduled in 12 seconds"
     sleep 12

     if ! akuo_identity_matches; then
         print -u2 "BLOCKED: Akuo identity changed before SIGCONT; no signal sent"
         exit 1
     fi
     if ! kill -CONT "$akuo_pid"; then
         print -u2 "BLOCKED: failed to continue validated Akuo PID $akuo_pid"
         exit 1
     fi
     akuo_may_be_stopped=0
     trap - EXIT HUP INT TERM
     print "Akuo PID $akuo_pid continued at $(date)"
     )
     ```

  3. Immediately return focus to the TextEdit field. Before the ten-second delay expires, type only the partial token `a`.
  4. From this point until after the stale-buffer assertion in step 6, do **not** click Terminal, the Akuo menu, another application, or another field. Any app/focus change clears Akuo’s buffer and would make the test invalid. Observe the side-by-side Terminal output without moving focus.
  5. Only after Terminal visibly reports the stopped timestamp, press the physical `k` key once in TextEdit. Do not type another key until Terminal visibly reports the continued timestamp. This physical key makes the unresponsive installed tap time out without posting a synthetic event.
  6. After the visible `SIGCONT` report, keep TextEdit focused, wait a fixed two seconds for callback recovery, then type `uo `. The document must contain exactly `akuo ` and must **not** correct to `שלום `; this proves the timeout callback cleared the stale buffered `a` before processing resumed. Do not inspect or click Akuo’s menu before this assertion—the menu can remain **Active** through a successful recovery.
  7. Type a fresh `akuo `. It must correct normally to `שלום ` and select Hebrew, proving the recovered tap processes new input.
  8. Mark this item `BLOCKED`, not `PASS`, if identity validation, `SIGSTOP`, or `SIGCONT` fails; if the transcript lacks the bounded times; if a click/focus change occurs; if the screen recording cannot prove `k` was pressed during the visibly stopped interval and `uo ` followed the continued timestamp plus two-second recovery delay; if the stale partial token is retained; or if fresh correction does not resume.

  The EXIT trap is best-effort: it revalidates identity before cleanup and cannot run after `SIGKILL`, a Terminal crash, or a system failure. If the block is interrupted or Akuo remains unresponsive, mark the test `BLOCKED`, open a fresh Terminal, and use the rescue block below. Enter the PID and normalized `RECORD START` value printed by the interrupted block. The rescue requires one current Akuo process, the same recorded PID, the exact installed executable as the first command path, and the same start fingerprint before it sends one `SIGCONT`.

     ```zsh
     (
     set -euo pipefail

     read "akuo_recorded_pid?Recorded Akuo PID: "
     read "akuo_recorded_start?Recorded Akuo start fingerprint: "
     if [[ ! "$akuo_recorded_pid" =~ '^[0-9]+$' || -z "$akuo_recorded_start" ]]; then
         print -u2 "BLOCKED: recorded identity is incomplete; no signal sent"
         exit 1
     fi

     akuo_expected="/Applications/Akuo.app/Contents/MacOS/Akuo"
     akuo_pid_lines="$(pgrep -x Akuo || true)"
     akuo_pid_count="$(printf '%s\n' "$akuo_pid_lines" | awk 'NF { count += 1 } END { print count + 0 }')"
     if [[ "$akuo_pid_count" -ne 1 || "$akuo_pid_lines" != "$akuo_recorded_pid" ]]; then
         print -u2 "BLOCKED: current Akuo PID does not uniquely match recorded PID; no signal sent"
         exit 1
     fi

     if ! akuo_command="$(ps -p "$akuo_recorded_pid" -o command= 2>/dev/null)"; then
         print -u2 "BLOCKED: could not read recorded PID; no signal sent"
         exit 1
     fi
     akuo_executable="$(printf '%s\n' "$akuo_command" | awk 'NF { print $1; exit }')"
     if ! akuo_start="$(ps -p "$akuo_recorded_pid" -o lstart= 2>/dev/null | awk '{$1 = $1; print}')"; then
         print -u2 "BLOCKED: could not read start fingerprint; no signal sent"
         exit 1
     fi

     if [[ "$akuo_executable" != "$akuo_expected" || "$akuo_start" != "$akuo_recorded_start" ]]; then
         print -u2 "BLOCKED: executable or start fingerprint differs; no signal sent"
         exit 1
     fi
     if ! kill -CONT "$akuo_recorded_pid"; then
         print -u2 "BLOCKED: failed to continue validated Akuo PID $akuo_recorded_pid"
         exit 1
     fi
     print "Validated Akuo PID $akuo_recorded_pid continued at $(date)"
     )
     ```

  If rescue identity cannot be proven, do not send any signal. In Activity Monitor, find the single Akuo row, use **Inspect → Open Files and Ports** to verify `/Applications/Akuo.app/Contents/MacOS/Akuo`, then use the Stop control to force-quit only that verified row. If there is not one verifiable row, restart macOS instead of guessing. Preserve the transcript/screen recording and keep the acceptance item `BLOCKED`.
- [ ] **Relaunch persistence.** Record enabled state, onboarding completion, aggregate count, Launch at Login state, and force-conversion gesture; quit and reopen Akuo. Confirm exactly those values are restored or reconciled with macOS. **Result:**
  **Evidence:**
- [ ] **Launch at Login enable.** Turn it on, approve in **System Settings → General → Login Items** if required, log out/in or restart in an appropriate test environment, and confirm Akuo starts menu-bar-only. **Result:**
  **Evidence:**
- [ ] **Launch at Login disable.** Turn it off, repeat the login/restart check, and confirm Akuo does not start. **Result:**
  **Evidence:**
- [ ] **Test Area is ephemeral.** Enter distinctive text in Akuo Test Area, close the window, reopen it, and confirm the editor is empty. **Result:**
  **Evidence:**

## 8. No word history or typed-text logs

Use a unique, non-secret canary token that does not occur elsewhere in the project or evidence names.

- [ ] **No in-app history.** Type the canary and exercise both correction directions. Confirm no word/correction-history UI exists in the menu, setup, or Test Area. **Result:**
  **Evidence:**
- [ ] **Only five preference categories.** After relaunch, inspect Akuo’s preferences and confirm the only Akuo-owned categories are enabled state, onboarding completion, aggregate correction count, Launch at Login preference, and force-conversion gesture choice; no canary, word, candidate, focus, app, or undo data is present. **Result:**
  **Evidence:**
- [ ] **No typed-text logs.** Inspect macOS Console/log output for the Akuo process across typing, correction, undo, secure input, quit, and relaunch. Confirm the canary and all typed test words are absent. **Result:**
  **Evidence:**
- [ ] **No retained Test Area text.** Relaunch Akuo, open Test Area, and confirm it contains no previous user-entered text. **Result:**
  **Evidence:**

## Final disposition

- [ ] Every applicable item above is `PASS`, with no unresolved `FAIL` or `BLOCKED` item.
- [ ] No release-blocker stop rule was triggered.
- [ ] Evidence is stored with private content redacted.

**Overall result:** `PENDING / PASS / FAIL / BLOCKED`
**Accepted by:**
**Date:**
**Residual limitations or notes:**
