    You are working in the Pasella app repo.

    Repo path:
    `/Users/admin/Sites/vox-dei/pasella-app-worktrees/customer-feedback-synthesis`

    Branch:
    `audit/pas-res-01-customer-feedback-synthesis`

    Lane:
    `PAS-RES-01 — Customer feedback synthesis and triage pack`

    Context:
    This lane was created from the Pasella campaign-readiness + customer-feedback packet on 2026-06-01. The immediate business context is that Pasella may need a release by tomorrow to support upcoming campaigns, while parallel feedback and network-effects discovery lanes are being prepared.

    Goal:
    Turn the latest Pasella customer feedback into a usable, prioritized product and delivery packet instead of scattered notes.

    Inspect first:
    - `/Users/admin/.openclaw/workspace/voxdei-os/04-Entities/Pasella/open-items.md`
- `/Users/admin/.openclaw/workspace/voxdei-os/04-Entities/Pasella/entity-profile.md`
- `/Users/admin/.openclaw/workspace/voxdei-os/04-Entities/Pasella/pasella-merchant-commerce-scope-plan-2026-05-10.md`
- `/Users/admin/.openclaw/workspace/voxdei-os/04-Entities/Pasella/artifacts/pasella-google-bootcamp-day4-workbook-completed-2026-05-21.md`

    What to do:
    1. Identify the real current-state behavior first. Do not assume the notes are fully accurate.
    2. Trace the smallest surface area that explains the issue or unlocks the decision.
    3. If this is an implementation lane, make the smallest production-safe change.
    4. If this is a discovery lane, produce a tight recommendation packet with explicit scope boundaries and next-slice guidance.
    5. Keep the output merchant-trust focused, mobile-aware, and practical.

    Constraints:
    - Stay inside this lane.
    - Do not do broad refactors unless absolutely required for correctness.
    - Preserve existing working flows.
    - Include concise verification notes.
    - If a requested direction is not safe or not worth shipping now, say so plainly.

    Specific guidance:
    This is a synthesis lane. Prefer clarity and prioritization over long prose. Include explicit scores and a phase-based roadmap, not dates.

    Verification:
    - Produce a concise markdown packet in this worktree summarizing the synthesis, scores, and recommended next slices.

    Deliverable:
    Return a concise handover with:
    - what you found
    - what changed (or what you recommend)
    - exact files changed/reviewed
    - verification performed
    - remaining risks / follow-ups
