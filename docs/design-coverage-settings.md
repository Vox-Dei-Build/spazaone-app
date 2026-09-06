# Account, setup and shared presentation coverage

Scope: the active named routes in `lib/main.dart`, Settings/Your shop/setup call
sites, and shared presentation called by those flows. The chosen direction is
Clean and approachable. This is a local presentation pass; authentication,
consent persistence, store permissions and external service actions retain their
existing owners.

| Screen family | Result |
| --- | --- |
| Login, number entry, registration, profile completion, OTP | Existing shared AuthShell and controls carry the design. The registered anonymous-account compatibility screen now uses the same shell, visible labels and loading action. Its registration handler and referral value are retained. |
| Business name, required-name gate | Shared BusinessNameForm now uses the readable body scale, 16px gutters and common button. The required-name gate still blocks Back and persists through its existing handler. |
| Business type/category | Replaced four fixed columns with scrollable, selected choice rows. Names can wrap at 200% text; selections still update the same AppModel values and return to the caller. |
| Settings, Your shop, stores/team, deletion | Existing shared rows, actions and card tokens apply. Your shop gutters now match the workspace. Active-store, role, reconnect and deletion confirmation behavior remain intact. |
| Shop setup and first steps | Shared panels/actions use the chosen radii and weight. Existing state, completion rules and action callbacks remain; no new onboarding steps were introduced. |
| Ordering options | Existing production form inherits current controls. Its load/retry/edit/save gates are retained and its preview uses injected local loader/saver callbacks. |
| Ordering link/share | Standard green, muted text, control corners and readable link/code labels replace local colour/size choices. Copy/share/regenerate behavior is unchanged in the authenticated page. |
| Privacy and consent | Grouped privacy choices reuse controlled PrivacySettingsForm; persistence remains in the page. Consent surfaces use shared corners/heading colour. The post-auth choice sheet now scrolls in short views. Defaults, refusal/customization choices and save handlers remain unchanged. |
| Help and tutorials | Grouped HelpMenu retains tutorial IDs, support action and privacy link. Loom/Vimeo share TutorialPageBody, keeping support reachable by scrolling beneath the native player. Hosted video/support content is controlled by those services. |
| Empty states, headers, wallet indicator, separators | Inherit shared type and colours; remaining empty-state and wallet-indicator overrides now use tokens. Low-balance warning colour is retained. |

## Local previews

`settingsDesignPreviews()` provides Finish profile, First steps, Business name,
Business type, Business category, Your shop, Shop setup, Ordering link, Order
options, Active store, Privacy and Help. All reuse production presentation.
Actions stay in local state or show an example-only notice. Active store is a
summary preview; actual store/team access needs an authenticated session.

The shared gallery exercises these at 320px with normal and 200% text, including
return navigation and local privacy controls. Existing setup, consent, ordering,
Your shop and header tests are included in the integration suite. The native
video body has a short-landscape/200% support-action reachability test.

## Unreachable and service-owned surfaces

Call-site/route inspection found no active entry for the old Profile, Security,
Backup, Account, language, subscription, defaulter, standalone coming-soon,
referral dashboard or update-number stubs. Their prototype behavior is not
advertised as implemented. They remain outside active navigation.

Native authentication, notifications, store/team changes, account deletion,
external support/video content and external share sheets require device review
with a configured test account before release. No authenticated action or
external write was performed in the local preview.
