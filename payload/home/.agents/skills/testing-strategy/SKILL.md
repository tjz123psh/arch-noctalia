---
name: testing-strategy
description: "Design regression tests, boundaries, mocks, and test organization, and prove tests can fail. Use for Rust, Python, Node, or Kotlin testing decisions."
when-to-use: "Use when fixing a bug that needs a failing test first, adding a feature where you need to decide what to test, a test passes but is untrustworthy, or you need to judge the verification strength of a change. Do not use when only running existing tests, configuring CI pipelines, or the problem is purely design/UI choice."
---

# Testing Strategy

The global rule requires "fix bugs by first adding a regression test that fails before the fix." This skill provides practical criteria: what to test, how to guarantee it actually fails, and at what verification level to stop.

## Regression Test Hard Order

1. **Reproduce first, then act.** Write a check that currently fails, run it, and confirm the failure message matches the reported symptom. A test that hasn't been seen failing is not a regression test.
2. **Target the root cause layer.** If the symptom is in the UI but the root cause is in the parsing layer, write the test in the parsing layer; a UI-only assertion produces a fragile test that doesn't explain why.
3. **Change the code, rerun.** The same test going from fail to pass is the only proof of causality.
4. **Add an adjacent boundary.** Fixed `n == 0`, now test `n == 1` or negative values; testing only the reported input does not prevent same-class regressions.

When automated testing is impossible (requires real hardware, graphical sessions, external network), preserve reproducible manual failure conditions: exact command, input, expected vs actual output, written into the commit or HANDOFF; never replace with "manually verified."

## Tests That Lie

The following situations pass but provide no protection; prioritize inspection when evaluating changes:

- Assertions weaker than behavior: only asserting "no exception thrown," "returned non-null," "length > 0."
- Tests changed to match implementation: modifying the assertion to fit new behavior during the fix is equivalent to deleting the regression protection.
- Mocking away the logic under test itself: mocks should replace boundaries (network, clock, filesystem, privileged operations), not the branch being verified.
- Depending on execution order or shared mutable state: passes alone, fails in the full suite, or vice versa.
- Time, random numbers, paths, locale not fixed: sporadic failures get ignored as noise long-term.

Do not delete valid tests, relax assertions, expand `any`/ignore rules, or skip cases just to get green results.

## Boundary Checklist

Choose by data shape; do not mechanically apply all:

- Quantity: 0, 1, many, cap, over-cap.
- String: empty, whitespace-only, very long, multi-byte/emoji, with newlines, with delimiters.
- Numeric: 0, negative, min/max, overflow, precision boundary.
- Time: cross-day, cross-timezone, leap year, DST, clock rollback.
- State machine: illegal transition, repeated trigger, concurrent entry to same state.
- External failure: timeout, partial write, connection drop, permission denied, disk full.

When involving concurrency, caching, filesystem, network, auth, or persistence, there must be at least one test covering a failure path, not just the success path.

## Language-Specific Landing

Follow the project's existing organization; do not introduce new frameworks:

| Project Type | Location | Run |
|--------------|----------|-----|
| Rust unit | Same file `#[cfg(test)] mod tests` | `cargo test` |
| Rust integration | `tests/*.rs`, public API only | `cargo test --test <name>` |
| Python | `tests/test_*.py`, `unittest.TestCase` | `python -m unittest discover -s tests` or `meson test` |
| Node | `node:test` built-in module, no new dependencies | `node --test` |
| Kotlin/Android | `app/src/test` (JVM) and `androidTest` (device) | `./gradlew test` |

Detailed criteria (pure functions vs side effects, GTK/TUI testing, privileged operation isolation, coverage usage) are in:

```text
~/.agents/skills/testing-strategy/references/patterns.md
```

## Verification Strength Tiers

Choose by risk and state what level was actually run in the conclusion:

- **Minimal** — Local pure logic changes: unit test at the change point + full module tests.
- **Module** — Cross-function or state-involving: add adjacent module tests and one failure path case.
- **Integration** — Shared contracts, data formats, migrations, permissions, or persistence: add end-to-end path, old data compatibility, and rollback verification.

After adding or upgrading dependencies, run ecosystem audits (Rust `cargo audit`, Node `npm audit`). Report findings and recommendations; do not self-downgrade or lock versions just because there are warnings.

When done, state: what commands were run, which test failed before the fix, and which paths were not covered. Checks not run must be explicitly noted as not run.
