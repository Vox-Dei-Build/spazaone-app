    You are working in the Pasella app repo.

    Repo path:
    `/Users/admin/Sites/vox-dei/pasella-app-worktrees/whatsapp-magic-link-community`

    Branch:
    `audit/pas-net-01-whatsapp-magic-link-community`

    Lane:
    `PAS-NET-01 — WhatsApp / magic-link customer onboarding + community discovery`

    Context:
    This lane was created from the Pasella campaign-readiness + customer-feedback packet on 2026-06-01. The immediate business context is that Pasella may need a release by tomorrow to support upcoming campaigns, while parallel feedback and network-effects discovery lanes are being prepared.

    Goal:
    Explore merchant-led customer onboarding and lightweight community/store-locator network effects using WhatsApp, magic links, and related surfaces.

    Inspect first:
    - `lib/pages/contact/`
- `lib/pages/promote/`
- `lib/pages/ecommerce/`
- `/Users/admin/Sites/vox-dei/pasella-botpress`
- `/Users/admin/Sites/vox-dei/pasella-marketing-website`
- `/Users/admin/.openclaw/workspace/voxdei-os/04-Entities/Pasella/entity-profile.md`

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
    Do not jump straight to a broad marketplace/community build. Keep the recommendation tied to merchant value, onboarding conversion, and trust-based commerce.

    Verification:
    - Write a concise discovery memo in this worktree with recommended first slice, major dependencies, and what should wait.

    Deliverable:
    Return a concise handover with:
    - what you found
    - what changed (or what you recommend)
    - exact files changed/reviewed
    - verification performed
    - remaining risks / follow-ups
