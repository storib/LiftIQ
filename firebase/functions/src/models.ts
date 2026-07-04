// Single source of truth for the Claude model used by all AI functions.
// claude-sonnet-4-20250514 was retired 2026-06-15; claude-sonnet-5 is its
// official replacement. Its tokenizer produces ~30% more tokens for the same
// text, so max_tokens values are baselined against it, and adaptive thinking
// is on by default when the `thinking` field is omitted — every call must
// pass THINKING_DISABLED explicitly to keep pre-migration behavior and stop
// thinking tokens from eating into max_tokens.
export const CLAUDE_MODEL = "claude-sonnet-5";

// Cheaper model for the lighter analysis/suggestion functions (analyzePlateau,
// suggestExerciseSwap). Haiku does not take a `thinking` parameter — omit it
// entirely on calls that use this model (do NOT pass THINKING_DISABLED).
export const CLAUDE_MODEL_SMALL = "claude-haiku-4-5";

export const THINKING_DISABLED = { type: "disabled" as const };
