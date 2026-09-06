# Window-Stack Focus Ownership Design

## Problem

Akuo currently assumes that a keyboard event's target process identifies the
application receiving text. Live tracing disproved that assumption for
non-activating panels: while Raycast visibly accepted two `akuo ` sequences,
both `NSWorkspace.frontmostApplication` and
`CGEventField.eventTargetUnixProcessID` identified Codex. Raycast and Codex also
simultaneously exposed focused Accessibility text elements, so neither event
routing nor AX focus alone uniquely identifies the text recipient.

WindowServer supplied the missing ordering evidence. During the same live
state, Raycast's visible layer-8 window was ordered ahead of Codex's layer-0
window. Every intervening visible overlay process lacked a focused AX element.
This design combines window ordering with AX evidence instead of recognizing a
specific application.

## Requirements

- Support non-activating launchers, command palettes, and floating or modal text
  panels without bundle identifiers, application names, window names, or AX
  subrole allowlists specific to an application.
- Preserve the existing frontmost/event-target behavior for ordinary activated
  applications.
- Never require Screen Recording permission. Read only WindowServer metadata
  needed for ordering and ownership: process ID, order, level, and alpha.
- Preserve Akuo's fail-open boundary: ambiguity, missing evidence, secure or
  ineligible controls, changed focus, changed ordering, changed input source,
  or text mismatch must leave the original event and text untouched.
- Keep WindowServer and AX reads bounded enough to avoid event-tap timeout.
- Install the exact stable-signed candidate locally before merge and require a
  successful Raycast acceptance check.

## Considered Approaches

### Window ordering corroborated by Accessibility — selected

Treat the event target as an activation owner. Examine visible application
windows ordered ahead of that owner's first visible window, then use AX to find
whether exactly one ahead process exposes a focused element. This directly
models a non-activating panel layered above an activated application and uses
only application-neutral evidence.

### Cross-application Accessibility observers — rejected

Registering focus and value-change observers across running applications could
infer which field changes after each event. It introduces asynchronous state,
process-lifecycle subscriptions, delayed ownership, and more global AX access.
It is larger and less deterministic than the synchronous evidence already
available at correction time.

### Application-specific exceptions — rejected

Recognizing Raycast by bundle identifier, window level, or subrole would fix one
application but not the underlying non-activating-panel behavior.

## Architecture

### Window ordering provider

Add a small injected provider that returns distinct process identifiers whose
visible windows are ordered in front of an activation owner. Its system
implementation uses `CGWindowListCopyWindowInfo` with on-screen and
desktop-exclusion options.

The provider accepts only well-formed entries with:

- a positive PID representable by `Int32`;
- a finite, positive alpha;
- a public window level from normal through modal-panel level;
- an occurrence before the activation owner's first accepted window.

It excludes Akuo's own PID and deduplicates processes while preserving
front-to-back order. Individual malformed entries are skipped. A missing owner
window or unavailable window list returns an explicit resolution failure,
distinct from a successful empty list, rather than a guessed result. Window
names and contents are never read.

### Interaction context resolver

Extend the focus provider with an interaction-context operation accepting the
activation-owner PID. For each ordered process ahead of that owner, request the
same stable AX focused-element snapshot already used by Akuo.

- No ahead process exposes a focused AX element: use the activation owner's
  context.
- Exactly one ahead process exposes a focused AX element: use that process's
  context, including secure/read-only/ineligible status.
- More than one ahead process exposes a focused AX element: return no context.

An ahead process with an explicitly focused secure or non-editable control is
not skipped in favor of the activation owner. Returning that ineligible context
lets the monitor clear transient state and preserve the user's input.

### Event monitor

For a valid event-target PID, resolve the interaction context through the new
operation. When the event target is unavailable or malformed, resolve the
frontmost PID first and apply the same window/AX corroboration. If no activation
owner can be established, fail open.

Capture the resolution mode with the event. Every coordinator closure must run
the same resolver again and require exact equality of process identifier,
focused-element identifier, editability, and security state. Existing exact
visible-text and exact input-source checks remain mandatory after this context
revalidation and immediately before mutation.

## State and Timing

The resolved interaction PID feeds the existing process-transition and
launch-recovery state. Switching between an activated application and an ahead
panel therefore clears unrelated buffered text. If an ahead panel exposes its
window before a usable focused element, Akuo remains fail-open; subsequent
stable context may use the existing bounded recovery path only when all of that
path's process, source, time, document-start, and exact-text requirements hold.

The system provider performs one window-list read per hardware event and only
queries AX for distinct accepted processes ahead of the owner until ambiguity
is established. Tests will enforce deduplication and early ambiguity handling.
Synthetic Akuo events remain excluded before ownership resolution.

## Error and Privacy Behavior

- Window-list failure, malformed values, missing activation owner, or multiple
  focused ahead processes: pass through unchanged and clear transient state.
- Secure or known ineligible ahead control: treat it as the interaction context
  and suppress observation/correction.
- Focus or window-order drift during validation: reject correction or undo.
- Exact suffix or input-source drift: retain the existing rejection behavior.
- No window titles, AX values, typed text, or bundle identities are collected
  for ownership discovery.

## Testing

Use focused RED/GREEN regressions for:

- a layer-8 non-activating panel ahead of a layer-0 activation owner;
- ordinary activated input with no focused ahead process;
- multiple focused ahead processes failing open;
- secure and read-only ahead controls blocking fallback;
- malformed/missing window metadata and missing owner windows;
- PID deduplication and front-to-back ordering;
- panel dismissal or ordering changes during coordinator revalidation;
- automatic correction, immediate undo, and forced correction using the same
  resolved interaction process;
- existing launch-recovery, source-provenance, and synthetic-event behavior.

Run the complete Swift suite, independent code review, and `Scripts/verify.sh`.
Advance the candidate identity to `0.4.0 (27)`, build from the clean reviewed
commit, sign with the established Apple Development team, verify the manifest,
signature, source revision, and executable hash, then install
`/Applications/Akuo.app`.
Do not merge until repeated cold and warm Raycast tests correct `akuo ` exactly
once and do not modify adjacent or unrelated text.
