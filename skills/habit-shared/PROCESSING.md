# Habit Processing Rules

Invoke every command as `bash ~/.claude/habits/bin/habit-tools.sh <command> ...`. All habit commands that create, modify, or inspect habits follow these rules. Do not announce internal operations to the user. Show only the final result.

## 1. Interpretation

When capturing a habit from any source:

- **Extract the principle, not the instance.** Strip session-specific details (file names, line numbers). Instruction must work in any future context.
- **Expand terse instructions into clear steps.** Only include steps the user said or directly implied.
- **Tighten verbose instructions** without losing intent or steps.
- **Infer 1-3 tags.** Lowercase singular nouns (`typescript` not `TS`).
- **Generate description.** Max 120 chars, starts with verb.
- **Instruction must be self-contained.** No references to conversation. Use "in the specified scope" for overrideable targets.
- **Cut dead weight.** For each step in a habit instruction: if removed, would it change how the agent behaves? If no, remove it.

## 2. Classification

A prompt is **reusable** if it:

- Describes how the user wants work done: a preference, constraint, workflow, or quality standard
- Applies to a category of tasks, not one specific instance
- Would be useful in a future session
- The user framed it as a general rule or repeated it across sessions ("I always", "whenever", "never", "from now on")

A prompt is **one-off** if it:

- References specific files, errors, or context only meaningful in that moment
- Is a question or conversational reply
- Is a one-time action ("fix the typo on line 42")
- Is a tool bug or temporary issue unrelated to how the user works

## 3. Kind

Each habit has a `kind` in its frontmatter; give every habit you create or rewrite one. A missing kind means `procedure`.

- **rule:** a standing preference that should hold in every session and fits in a few sentences. Every session loads the active rules automatically, so a rule body is the rule itself: plain text with no heading, about 300 characters, never more than 600 (`write-habit` rejects a longer one).
- **procedure:** a workflow the user runs on demand, or anything that needs steps or long detail. Procedures load only when a request calls for them.

A rule that needs long detail is a procedure. Interpretation applies to rules too, but a rule stays terse instead of growing into steps. The user can set any habit back to `procedure`.

## 4. Deduplication

Compare new candidate against the preloaded index (descriptions + tags) by intent, not wording. Only load full content via `read-habit <id>` when two habits look close enough that the description alone cannot distinguish them.

- **Skip:** Candidate and existing habit would produce the same agent behavior. Only wording differs. Note in the summary that it's already covered.
- **Merge:** Candidate adds steps or context the existing habit lacks, but they target the same workflow. Preserve intent from both. Keep the id. Update `updated` timestamp.
- **Create new:** Candidate targets a different workflow, even if it shares the same domain.
- **Covered elsewhere:** The user already states the candidate in an instruction file they keep (`CLAUDE.md`, `AGENTS.md`, or a memory index). Skip it and note in the summary where it is covered.

## 5. Override Patterns

From the usage log: group by id, collect the non-empty notes (each is an override the user gave when running the habit), normalize (lowercase, trim). **3+ similar = pattern:**

- Scope-narrowing → create variant (e.g., `fix-types-auth`).
- Behavior-adding → update base habit.

## 6. Scope Detection

- References relative paths, project scripts, or project config → `project` (the project the prompt came from)
- Generic → `global` → `~/.claude/habits/`
