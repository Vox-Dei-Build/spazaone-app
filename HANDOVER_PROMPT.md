    You are working in the Pasella app repo.

    Repo path:
    `/Users/admin/Sites/vox-dei/pasella-app-worktrees/staff-role-management`

    Branch:
    `audit/pas-ops-02-staff-role-management`

    Lane:
    `PAS-OPS-02 — Staff operators / role management discovery`

    Context:
    This lane was created from the Pasella campaign-readiness + customer-feedback packet on 2026-06-01. The immediate business context is that Pasella may need a release by tomorrow to support upcoming campaigns, while parallel feedback and network-effects discovery lanes are being prepared.

    Goal:
    Assess how Pasella could support staff operators safely, with a recommended V1 role model and implementation path.

    Inspect first:
    - `lib/main.dart`
- `lib/utils/auth_util.dart`
- `lib/pages/auth/`
- `functions/`
- `/Users/admin/.openclaw/workspace/voxdei-os/04-Entities/Pasella/open-items.md`

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
    Do not invent enterprise RBAC complexity. The goal is a practical merchant-team V1, not a corporate permissions matrix.

    Verification:
    - Write a scoped discovery note in this worktree with recommended first implementation slice and major risks.

    Deliverable:
    Return a concise handover with:
    - what you found
    - what changed (or what you recommend)
    - exact files changed/reviewed
    - verification performed
    - remaining risks / follow-ups
