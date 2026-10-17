---
name: before-you-build
description: "Test product or feature viability through pre-mortem, demand, positioning, monetization, and MVP scope. Use before a build decision, not for defined implementation work."
when-to-use: "Use ONLY when the user asks for demand/positioning/monetization validation, a pre-mortem, or has not yet decided whether/what to build. Do not use when the user has clearly requested implementation of a defined page, app, feature, or landing page."
---

# Before You Build

Run a compact pre-mortem before implementation. The goal is not to block building; it is to identify the highest-risk assumption, the smallest validation step, and the build scope that should be delayed until evidence improves.

## When To Use

Use this skill only when a user explicitly asks to validate, decide, de-risk, or pre-mortem a proposal before build, especially for:

- A new product, MVP, prototype, landing page, SaaS app, marketplace, content site, agent workflow, or internal tool
- A major feature with unclear adoption, revenue, retention, trust, or distribution impact
- A public launch asset where weak positioning could waste development or promotion effort

Skip this skill when the user has committed to implementation with clear direction, including a new landing page, MVP, SaaS app, internal tool or major feature; use the relevant design/implementation workflow instead. Also skip narrow fixes, refactors, test repairs, dependency updates and already-validated changes.

## Risk Checklist

Review the idea across these risks:

- **Demand:** Is there evidence that a specific buyer or user urgently wants this?
- **Positioning:** Can the target user understand what it is and why it matters in one sentence?
- **Monetization:** Is there a credible path to payment, budget, or strategic value?
- **Retention:** Is there a reason users would return after the first try?
- **Trust:** Does the product require credibility, data access, integrations, or behavior change that users may resist?
- **Distribution:** Is there a repeatable way to reach the target user?
- **Feature adoption:** For feature work, will the feature change user behavior or just add surface area?

If the verdict is not obvious, use `references/risk-checklist.md` for deeper questions.

## Output Format

Keep the response short and decision-oriented:

1. **Risk verdict:** Low, medium, or high risk, with one sentence explaining why.
2. **Main assumption:** The single assumption most likely to break the project.
3. **Evidence to find first:** The smallest useful signal before building more.
4. **Do next:** One concrete validation step or reduced build scope.
5. **Delay:** What not to build yet.

## Guidance

- Be direct about weak evidence, but avoid dismissing the user's idea.
- Prefer smaller validation steps over large research plans.
- Separate product risk from engineering difficulty.
- If the idea is already validated, say what evidence makes it lower risk and suggest the smallest implementation slice.
- If facts are missing, name the missing evidence instead of inventing market claims.
