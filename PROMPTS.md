## Spec Prompt

Here is my project overview: @docs/project-overview.md 
Here is my architecture: @docs/architecture.md 
I want to implement: unit 1 in @docs/specs/00-build-plan.md 
Write a detailed spec file for this feature within the spec directory following this structure:
- Goal (1-2 sentences, specific and concrete)
- Design (visual and structural decisions)
- Implementation (broken into sub-sections)
- Dependencies (packages to install)
- Verification checklist
Be as specific as possible. If anything is unclear,
ask me questions before writing the spec. Dont write the file until i have reviewed it and tell you to write it.


## Spec implementation Prompt

Read @docs/specs/01-frontend-foundation.md .
Update @docs/progress-tracker.md to mark this as
in progress.
Implement it exactly as specified.
Do not go beyond the scope of this unit.


## Spec implementation correction Prompt

The [specific element] does not match the spec.
Expected: [what the spec says].
Current: [what was built].
Fix only this. Do not change anything else.

## Spec implementation close Prompt

Implementation is complete and verified.
Mark unit 01 complete in @docs/progress-tracker.md .
Create a new branch for this unit using the format `feat/01-frontend-foundation` and push to GitHub.
Then create a PR to main.
