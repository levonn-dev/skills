---
description: Partition the working tree into a queue of single-line git commit commands for the user to run; every changed file lands in exactly one commit and the partition is verified before hand-off
argument-hint: [grouping hints, e.g. "one commit per service" or "split docs from code"]
---

Build a commit queue for the current working tree. You never run the git writes yourself (the git-safety hook denies them); you produce the commands and the user replays them.

## 1. Collect the change set

Run `git status --porcelain=v1 --untracked-files=all`. If it is empty, say so and stop. Skim `git diff` and `git log --oneline -10` so subjects match the repo's existing message style (prefixes, scopes, tense).

Set aside, and never queue, local editor and OS noise. List them at the end as "not queued" so the user can see they were excluded on purpose.

## 2. Partition

Assign every remaining path to exactly one commit. Rules:

- Final-state replay: each file is committed once, with its final content. Never try to reconstruct intermediate edits.
- One coherent change per commit, in dependency order so every commit builds on its own: schema and data layer, then server or library code, then clients and frontend, then infrastructure and CI.
- Generated code rides with the source that produces it (a generated client goes in the commit that changed the spec).
- Tests ride with the code they test. Docs ride with the change they describe.
- Follow any grouping hints in $ARGUMENTS.

Write the partition as a manifest, one `<commit-number><TAB><path>` line per file, plus one subject per commit number. Keep it outside the repo: the session scratchpad directory if one is listed, otherwise `/tmp`.

## 3. Verify the partition

Before handing anything over, prove no duplicates and no gaps against git's view of the tree:

```bash
git status --porcelain=v1 --untracked-files=all | cut -c4- | sed 's/.* -> //' | sed 's/^"\(.*\)"$/\1/' \
  | grep -vE '^(\.superpowers|docs/superpowers|\.claude)/' | sort > changed.txt
cut -f2 manifest.tsv | sort > queued.txt
sort queued.txt | uniq -d        # duplicates: must print nothing
comm -3 changed.txt queued.txt   # gaps or strays: must print nothing
wc -l changed.txt queued.txt     # counts must match
```

Report the count ("14 files queued, 14 changed"). If anything prints, fix the manifest and rerun. Do not hand over an unverified queue.

## 4. Hand off

Emit the queue as a numbered list of SEPARATE single-line commands, one per commit:

```
git add -- path/a path/b && git commit -m "feat(scope): subject"
```

Never join commits into one multi-line `&& \` chain: a pasted chain can silently corrupt a subject or skip a line while the rest still runs. Quote any path with spaces or shell characters. Also write the same lines to `commit-queue.sh` next to the manifest and give the user its path, so they can run it with `bash` instead of pasting.

Close with the verification step for the user: after replay, compare `git log --oneline -<N>` subjects against the queue and confirm `git status` is clean (apart from the not-queued list) before pushing.
