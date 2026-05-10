/// PAS-UX-10: canonical external URLs the app links to.
///
/// Centralised so trust-surface assets (privacy policy, ToS, support
/// pages) can move from temporary public-Google-Doc hosting to
/// pasella.co.za-owned routes by editing one constant per asset
/// instead of grepping the codebase.
///
/// The audit flagged the privacy policy specifically: at audit time it
/// pointed at a public Google Doc, which is unprofessional on a
/// merchant-payments surface (mixed-content fingerprint, anyone can
/// suggest edits, no version history surfaces to users). The constant
/// below is the single source of truth for that link.
class AppUrls {
  const AppUrls._();

  /// Privacy policy.
  ///
  /// TODO(PAS-UX-10): once `https://pasella.co.za/privacy-policy` is
  /// live, swap the value here. Hosting the publish step is out of
  /// scope for this commit; the indirection is the in-app fix.
  static const String privacyPolicy =
      'https://docs.google.com/document/d/1Oz4M_j8u0YwQBzIyDB-IAl_wYBNdrQ5k_Fx6qR7uPAQ/edit?tab=t.0';

  /// Marketing site root, used by share/referral copy.
  static const String marketingSite = 'https://pasella.co.za';
}
