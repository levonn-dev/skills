---
name: manual-work-coordination
description: Use when the user says they will do something by hand, asks you to pause, or says they will verify or validate themselves. Stop cleanly, hand off precisely, and on resume trust their manual work instead of redoing, reverting, or re-verifying it.
---

# Manual Work Coordination

The user frequently takes part of a task into their own hands: editing assets, fixing images, tweaking config, validating results. When that happens, get out of the way cleanly and pick back up without trampling what they did.

## Recognize the handoff

Trigger phrases (not exhaustive):

- "pause work", "stop here", "hold on", "wait"
- "I'll do X manually", "I'm going to fix X myself", "let me handle X"
- "I'll verify", "I'll validate", "stop trying to verify"

When you see one, treat it as an instruction to stop, not a suggestion.

## Stop cleanly

- Finish only the smallest safe unit, then stop. Don't rush extra changes in before pausing.
- State exactly where you stopped and what remains, so resuming is unambiguous.
- Don't start new work, refactors, or "while I'm here" cleanups during a pause.

## On resume, trust their work

- Assume the manual changes are correct and intentional. Don't redo, revert, or "fix" them.
- Re-read the files they touched before continuing, so you build on the current state, not a stale memory of it.
- If something they changed looks wrong, ask before changing it back. Don't silently override.

## When they own verification

- If the user says they will verify or validate, don't insist on running your own checks or loops.
- This overrides the default "define done means verify it yourself" habit from coding-guidelines. Their decision to validate by hand wins.
- You may offer to help verify, but accept "no" the first time.
