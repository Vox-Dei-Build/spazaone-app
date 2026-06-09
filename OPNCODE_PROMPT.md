    You are working in the Pasella app repo.

    Repo path:
    `/Users/admin/Sites/vox-dei/pasella-app-worktrees/supplier-network-effects`

    Branch:
    `audit/pas-inv-01-supplier-network-effects`

    Lane:
    `PAS-INV-01 — Supplier inventory & merchant network effects discovery`

    Context:
    This lane was created from the Pasella campaign-readiness + customer-feedback packet on 2026-06-01. The immediate business context is that Pasella may need a release by tomorrow to support upcoming campaigns, while parallel feedback and network-effects discovery lanes are being prepared.

    Goal:
    Define where Pasella should start on supplier-to-merchant inventory and BNPL network effects without breaking trust or stock truth.

    Inspect first:
    - `/Users/admin/.openclaw/workspace/voxdei-os/04-Entities/Pasella/pasella-merchant-commerce-scope-plan-2026-05-10.md`
- `/Users/admin/.openclaw/workspace/voxdei-os/04-Entities/Pasella/open-items.md`
- `lib/pages/stock/`
- `lib/pages/contact/`
- `functions/`

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
    Anchor on the existing recommendation in VentureOS: start with a legible supplier surface before automatic inheritance. Use the user's OkCredit reference as a directional benchmark, not a copy instruction.

    Verification:
    - Produce a scored discovery note with a phase-based roadmap and first-ticket recommendation.

    Deliverable:
    Return a concise handover with:
    - what you found
    - what changed (or what you recommend)
    - exact files changed/reviewed
    - verification performed
    - remaining risks / follow-ups
