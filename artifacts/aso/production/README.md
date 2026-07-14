# SpazaOne store artwork production pack

This folder contains the reusable artwork system for the SpazaOne App Store and Google Play rebrand.

The visual system is a direct SpazaOne evolution of the supplied Pasella store artwork:

- Apple uses the original deep-navy editorial treatment, white benefit-led copy, warm ambient glow and a realistic phone frame.
- Google Play uses the original soft off-white treatment, dark copy, restrained yellow/pink ambient colour and a realistic phone frame.
- The Google Play feature graphic retains the supplied merchant portrait and replaces the Pasella lockup with SpazaOne.
- Poppins is used for both the bold editorial copy and the italic wordmark, matching the character of the supplied Pasella identity more closely than the earlier generic draft.

## Current status

Everything under `draft/` is a design proof. It must not be submitted or published yet.

- The current screenshots were captured from the latest released baseline before the pending app branch is incorporated.
- Apple frames 2–6 intentionally use the Android captures only to review layout and copy.
- Every screenshot must be replaced with a fresh platform-native capture after the pending app work is merged.
- No store metadata or artwork may be submitted without the user's explicit approval immediately before submission.

## Deliverables

- `source/app-store/`: editable SVG source at 1320 × 2868 px
- `source/google-play/`: editable SVG source at 1080 × 1920 px
- `source/icons/`: editable App Store and Google Play icon source
- `source/logos/`: editable horizontal and square SpazaOne lockups
- `draft/app-store/`: rendered Apple layout proofs
- `draft/google-play/`: rendered Google Play layout proofs and the 1024 × 500 feature graphic
- `draft/00-spazaone-launch-banner.png`: 1200 × 630 launch artwork
- `icons/`: 1024 px Apple and 512 px Google Play icon outputs
- `logos/`: transparent horizontal lockups plus 512 px WhatsApp/social variants
- `review/`: contact sheets for fast visual review
- `scripts/render-store-artwork.mjs`: deterministic renderer

The SVGs are self-contained and can be dragged into Figma when edit access is available. They do not depend on the inaccessible Figma file to render.

## Render again

From the app worktree root:

```bash
/Users/admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node \
  artifacts/aso/production/scripts/render-store-artwork.mjs
```

The renderer uses the fonts and authoritative visual assets stored inside this production folder.

## Final capture gate

Before final rendering:

1. Incorporate the pending app branch into the SpazaOne rebrand branch.
2. Build the resulting app for both Android and iOS.
3. Use a dedicated demo account with fictional customers, orders and balances.
4. Capture the same six story moments on each platform.
5. Replace the source paths in the renderer.
6. Remove the design-proof labels.
7. Render, visually inspect and validate every output dimension.
8. Ask the user for explicit approval before uploading anything to either store.
