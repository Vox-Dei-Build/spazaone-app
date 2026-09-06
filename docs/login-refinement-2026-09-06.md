# Login refinement — 6 September 2026

## Result

The phone entry experience now uses a restrained business layout: a flat page, clear hierarchy, compact fields and buttons, and no decorative shop emblem or floating card. Returning merchants see **Sign in** and first-time merchants see **Get started**.

The iOS app no longer presents the system notification-permission sheet during unauthenticated startup. Local notifications initialize without asking for alert, sound, or badge access, and eager remote-notification registration was removed from the app delegate. Firebase Auth still requests its APNs token when phone verification begins; the merchant notification prompt remains behind the contextual in-app explanation after sign-in.

## Simulator verification

- Build: `4.8.4-dev.2 (101)`
- Bundle: `com.tsepo.spazaone.dev`
- Device: `SpazaOne Login QA`, iOS 18.3 simulator
- Verification: erased simulator, installed the development build, launched from a clean state, and visually inspected the first phone-entry screen
- Result: the redesigned screen rendered without the notification prompt

## Automated checks

- 28 focused authentication, preview, OTP lifecycle, and Firebase configuration tests passed
- Static analysis reported no errors or warnings in the changed surface; two existing style infos remain in `lib/main.dart`
- Xcode simulator build completed successfully
