# Design contract and current limits

A board stores concept identity, grid position, displayed label, spoken text,
image, optional recording and navigation destination as distinct values. Stable
IDs and explicit cells keep editing one tile from rearranging the rest.

Core source comments reference these design identifiers:

| ID | Contract |
| --- | --- |
| AAC-001 | Communication has no rewards, prerequisites or correctness tests |
| AAC-002 | Existing cells keep their coordinates; expansion uses spare cells |
| AAC-003 | Display label and spoken phrase are independently editable |
| AAC-004 | Scene-based communication is reserved for separate future work |
| AAC-005 | Caregiver authorization gates editing, with checks at the write boundary |
| AAC-006 | A fresh tap replaces old output and uses available local audio |
| AAC-007 | Output uses saved words or a selected recording, without rewriting meaning |
| AAC-008 | Saves are atomic, recovery is explicit, and data is not silently reset |
| AAC-009 | A matching printed fallback is planned |
| AAC-010 | Usage is not treated as evidence of comprehension or clinical benefit |
| AAC-011 | Guided Access and device sleep behavior need physical-device checks |
| AAC-012 | Imported images and recordings retain provenance |

`BoardStore` publishes immutable board/media generations through a manifest.
The previous generation is retained for recovery. The app distinguishes a missing
store from a broken store and verifies an exact readback after saving. A failure
after a successful save is reported as a refresh failure, not as an unsaved edit.

An authenticated caregiver session has a fresh identifier. Saving and returning
from a suspended photo request recheck that identifier and the original draft,
so stale work cannot publish into a new editing session. Going to the background
or entering Guided Access revokes editing access. OS authentication prompts may
temporarily cover the app.

The output controller owns preemption and interruption rules. Native synthesis
and recorded playback share the application audio session. Backgrounding, route
changes and interruptions stop old output; it never automatically replays.
A recording takes priority when its local URL is available. Creation or start
failure falls back to exact saved speech. An asynchronous decoding error after
playback starts does not currently trigger that fallback.

## Limitations

- Export/restore, printable output and general recording import/capture UI are pending.
- The app displays one fixed 3 by 5 board. Navigation fields exist in the schema;
  multi-page navigation is not implemented.
- Landscape is the intended orientation. Some devices may letterbox the interface.
- Simulator tests cannot establish physical speaker behavior, actual biometric or
  passcode flows, Guided Access confinement, or touch behavior in a user's setup.
- The generic demonstration is a software example, not a prescribed vocabulary.
