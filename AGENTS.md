# Whisper Reconstruction — Operating Rules

## Purpose

This file is the persistent operating contract for any AI agent/assistant working on this repository. It exists so project history, constraints, decisions, and working conventions do not depend on conversation memory.

## Mandatory rules

1. **Document every meaningful change.**
   - Code changes require a Git commit with a descriptive message.
   - Architectural decisions, discoveries, bugs, test results, and changes in project status must be recorded in Markdown under `docs/` when they are not self-evident from the code/commit.
   - Do not rely on the chat transcript as the sole record of project state.

2. **Maintain a persistent project state/checkpoint.**
   - Before starting a new significant phase, read the project-state documentation and relevant decision/findings documents.
   - Update the state document when a phase, implementation, validation status, or important constraint changes.

3. **Preserve validated behavior.**
   - Do not modify already-validated reconstruction logic merely to accommodate a new ASR adapter unless a regression is demonstrated.
   - Prefer adapters at system boundaries over changing established internal modules.

4. **Test before advancing.**
   - A change is not considered validated merely because the code looks correct.
   - Run the relevant local PowerShell tests and record their results.
   - Never claim a local test passed unless the user has actually run it or an equivalent executable test was available.

5. **Use small, isolated changes.**
   - Prefer one logical change per commit.
   - Avoid unrelated cleanup, refactoring, formatting, or deletion of user-created files.
   - Do not delete or overwrite untracked project artifacts without an explicit reason and user approval.

6. **Do not use the conversation as hidden state.**
   - If a fact is important enough that future work depends on it, put it in the repository.
   - When resuming work, reconstruct context from Git history and repository documentation rather than guessing from memory.

7. **Record failures as well as successes.**
   - Failed approaches and the reason they failed are valuable project knowledge.
   - Document significant failed experiments so they are not repeated later.

8. **Do not invent test infrastructure.**
   - Use the actual tests present in `tests/`.
   - If a proposed runner/script does not exist, inspect the repository and use the real test files instead of assuming a conventional filename.

9. **Do not silently change architecture.**
   - Any architectural change must be explicitly documented with rationale and affected components.
   - Keep the separation between ASR/import, word construction, alignment, windowing, and reconstruction clear.

10. **Keep the user informed of repository state.**
    - After repository changes, report the commit SHA(s), what changed, what remains unvalidated, and the exact next local command(s) when applicable.

## Current project invariants

- Main working branch: `reconstruction-fixes`.
- Repository: `Drworm82/whisper-reconstruction-a3-audit`.
- Existing reconstruction fixes have been validated by the project's regression suite; preserve them unless a new regression requires change.
- `whisper.cpp` with Vulkan is the current ASR candidate for the AMD RX 6600 XT environment.
- `Convert-WhisperCpp.ps1` is an adapter boundary; it should not require changing `Build-WhisperWords.ps1` or `Reconstruct-WhisperWindows.ps1` merely to accept whisper.cpp data.
- Whisper.cpp `-ojf` output contains segment timestamps as formatted `HH:MM:SS,mmm` strings and token offsets in milliseconds.
- Zero-duration control/timestamp tokens such as `[_BEG_]` and `[_TT_nnn]` are excluded by the adapter.

## Required workflow for future work

### Before editing

1. Read this file.
2. Read the current project-state/checkpoint document under `docs/`.
3. Inspect the relevant source and tests.
4. State the intended logical change before implementing it.

### During editing

1. Make the smallest change that addresses the demonstrated problem.
2. Add or update a regression test where practical.
3. Update relevant documentation.

### After editing

1. Review the diff.
2. Commit the logical change.
3. Push to the working branch when authorized/appropriate.
4. Tell the user the exact commit SHA.
5. Give exact local commands for validation.
6. Do not proceed to dependent work until the required validation result is known.

## Rule reminder

The user may remind the assistant of these rules at any time. Such reminders are consistent with this document and should result in the repository documentation being updated if a new rule or clarification is introduced.
