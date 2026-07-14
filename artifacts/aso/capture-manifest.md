# SpazaOne screenshot capture manifest

Captured locally from the latest released app baseline on 12 July 2026.

- Release baseline: `v4.1.6+70`
- Git baseline: `origin/main` at `06cc054`
- Android: API 36 emulator, 1080 × 2400 source captures
- iOS: iPhone 16 Pro Max simulator, iOS 18.3, 1320 × 2868 source capture
- No asset in this folder has been uploaded or published

## Publish-safe source captures

- `raw/ios/01-login.png`
- `raw/android/02-products.png`
- `raw/android/03-customer-pay-later-sanitized.png`
- `raw/android/04-sales.png`
- `raw/android/05-marketing.png`
- `raw/android/06-templates.png`

Raw captures containing retained emulator customer data were deleted after review. They must be recaptured later with a dedicated demo account if an orders or populated-customer frame is required.

## Sanitised balance frame

The balance frame was edited with OpenAI's built-in image generation mode. The visible retained customer name was replaced with the exact fictional name “Mama Deli”, while preserving the current Flutter UI, layout, typography and colours.

Final prompt:

> Use case: text-localization. Replace the visible customer name “Kabza” with the exact text “Mama Deli” everywhere it appears in the supplied mobile-app screenshot. Preserve the Flutter interface, layout, spacing, typography, colours, icons, status bar and all other visible text exactly. Keep the result as a clean portrait app screenshot with no added marketing frame or decoration.

## Production note

The Android sources are intentionally taller than the final Google Play 9:16 canvases. They should be placed into the approved store frame and cropped there, not resized destructively at source.
