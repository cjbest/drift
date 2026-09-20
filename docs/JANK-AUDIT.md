# Jank Audit

**Jank kills joy.** Audit responsiveness, motion, continuity, stability, and
visual polish. Functional correctness is necessary but does not establish feel.
The durable design/build principles live in [AGENTS.md](../AGENTS.md).

## When to run

- After rendering, navigation, editing, loading, focus, or appearance changes:
  audit the changed route and its transitions in and out.
- Before release: cover the platform's core routes and relevant open findings.
- On request: “Run a Jank Audit” or “Jank Audit this recording.”

These are workflow checkpoints, not a timer or automatic CI gate. An audit alone
requests neither fixes nor publication.

## Prepare

Read the relevant [iOS](../drift-ios/DESIGN.md) or [desktop](DESKTOP-DESIGN.md)
interaction reference. Preserve intentional gestures, motion, and visual character.

- Use `scripts/preview-ios.sh` for the separate simulator app and disposable
  notes (`SIMULATOR_ID` selects a device); `scripts/preview-desktop.sh` enforces
  the copied desktop notebook. Normal installation follows [INSTALL.md](INSTALL.md).
- On a phone, create fixtures inside the **tested app's** container. The runner
  has a different container; transferred folders may be readable but unwritable.
  Verify atomic save/reopen first. Preserve edited fixtures rather than resetting
  them. Never test writing in the live notebook.
- Capture appearance, automatic scheduling, and accessibility settings before
  changing them; verify restoration. An unset framework override is not evidence
  of the underlying preference.
- Record build, device/OS, appearance, text size, fixture size, and evidence type.
  Unknown facts stay unknown. Use blank, short, and long notes; add a large
  catalogue when testing loading/search.
- Confirm the actual software keyboard has usable letter keys. Hardware-keyboard
  mode and introductory overlays can satisfy a keyboard-exists assertion without
  exercising typing. Check the rendered app frame, not Portrait versus Face Up.

## Core routes

Repeat key transitions three times total, retaining first use. Then try quick
chains, interruptions, cancellations, and reversals. Include a second after
settling: a delayed second movement is still jank. Automation waits are not app
latency and do not establish immediate-action coverage.

| Route | iPhone / iPad | Mac | Watch for |
| --- | --- | --- | --- |
| Arrive | Cold launch, warm return, list previews arriving | Launch, restore note, new window | Empty flashes, late text, moving rows, wrong initial appearance |
| Start writing | Compose, type immediately, back, compose again; delete the last character and immediately return; open an empty note | New note, type title/body, close/reopen | Focus delay, first-character reflow, cursor or surface changes, staggered arrival, delayed empty-row removal |
| Open and return | Populated note, back, completed and cancelled edge-back | Quick-open, switch notes, return to previous position | Late title/body, lost feedback, scroll jumps, unfinished transition states |
| Write and select | Focus a long note in the middle and at the end, type, select across lines, drag keyboard down, resume editing | Long wrapped selection, scroll while selecting, checklist toggle, undo, edit a link | Input lag, uneven selection, caret jumps, reflow, discontinuous dismissal |
| Read | Scroll both ways, controls retreat/return, pull into/out of Read Mode | Scroll long note, resize wide/narrow, find text | Stutters, bad easing, clipping, overlays, surprise focus or layout shifts |
| Search and menus | Search, clear/cancel, open result; keep options open while previews arrive | Quick-open/filter, arrow selection, escape; open native menus | Moving targets, menu dismissal, mismatched focus, late result layout |
| Change context | Background/return; light/dark; rotate and iPad layout when relevant | Switch windows; light/dark; resize and quit/relaunch | Color flashes, detached controls, stale state, broken continuity |

For a change audit, run the affected route and neighbors. A release audit adds
light/dark, short/long notes, large-catalogue loading, increased text size, Reduce
Motion, and iPad layout for an iPad release. Record which routes each condition
actually covered; do not assume a full cross-product. Physical keyboard/touch
and frame-pacing sign-off require physical evidence. Missing access is a coverage
gap, not a pass.

## Inspect and investigate

1. Observe normal-speed feel, then slow down to locate discontinuities. Inspect
   the first visible frame, movement, surface handoffs, and settled tail; track
   color, text, caret, controls, and geometry. Also inspect settled typography,
   spacing, contrast, and clipping.
2. Compare first, repeated, and interrupted attempts. Preserve useful differences
   between populated and empty notes. A cancellation counts only if it visibly
   begins; a background table existing does not prove Back completed.
3. Reproduce the symptom before explaining it. Keep observed behavior, suspected
   cause, and measured mechanism distinct. Save the failing route; change one
   causal hypothesis, then retest the same conditions and neighboring transitions.
4. If only frames are available, inspect a whole-clip overview and every source
   frame around candidates; disclose that normal-speed feel was not assessed.
   Record native resolution/cadence/gaps. Do not infer device FPS, dropped frames,
   or input latency from recording cadence, repeated frames, automation timings,
   or unrecorded input events. Check original frames before blaming a contact
   sheet or system overlay on the app.

Reuse [JankAuditUITests](../drift-ios/DriftUITests/JankAuditUITests.swift) for
compose/Search/neighbors and [EmptyComposerAuditUITests](../drift-ios/DriftUITests/EmptyComposerAuditUITests.swift)
for delete/return/cancel. Hosted tests cover races too quick for automation;
recordings establish visual continuity separately. See the [iOS test workflow](../drift-ios/README.md#test)
and desktop `drift-mac/e2e`; run npm/Cargo from `drift-mac`.

Retain successful recordings too. Export an existing result without rerunning:

```sh
xcrun xcresulttool get test-results summary --path "$RESULT" > "$AUDIT/summary.json"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$AUDIT/attachments"
```

Set `RESULT` to the recorded `.xcresult`; create a new local directory for
`AUDIT` first. Attachments must have been retained during the run: export cannot
recover uncaptured video. The manifest maps media to tests.

Reuse built bundles for focused reruns. Diagnose setup failures separately; do
not repeat an unchanged failed startup. Once behavior and motion pass, broaden
coverage only for a new change, failure, or unresolved concern.

## Report and close

Keep private/raw evidence in ignored `output/jank-audits/<date>-<scope>/`.
Reports identify build, environment, inspected routes/conditions, and gaps.
Outcome: **Jank found**, **No jank observed in tested scope**, or **Inconclusive**.
No aggregate score should hide one ugly core transition.

Each finding needs a stable ID, trigger, observed versus expected experience,
clip timestamp/source frames, observed frequency, confidence, and concrete retest.
Label implementation hypotheses and recording limitations explicitly.

- **Major:** disrupts the core flow; holds polish sign-off.
- **Noticeable:** clear everyday roughness; fails that interaction until fixed
  or explicitly accepted.
- **Minor:** small polish issue, still recorded.

“Fixed” requires new evidence from the same route and conditions, including
repetition and interruption where relevant; passing source/tests alone is not
closure. Do not call the whole app smooth from bounded coverage.

To validate the audit itself, give a fresh reviewer the process and raw input,
withholding the expected defect, suggestive filenames, prior reports, and code.
Preserve their result before comparison. Catching one example establishes only
that example's detection, not complete coverage or a false-positive rate.

## Keep the learning small

Keep only insight that changes a future decision: **trigger → mechanism → rule**,
plus a nearby regression or removal check. Unconfirmed causes stay hypotheses.

- General UI/build rule: sharpen one of the five principles in `AGENTS.md`.
  Keep at most five; merge or replace instead of adding a rule per bug.
- Platform exception: put its reason and removal condition beside the code or
  in its design reference. An OS workaround must not become universal doctrine.
- Test/setup trap: update this procedure once. Timelines, failed experiments,
  recordings, and machine-specific paths stay in local evidence.

No parallel lessons log. Link to the owner instead of copying it. Remove advice
when its implementation or evidence no longer supports it.
