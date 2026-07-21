import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/pages/profile/business_name_page.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/utils/phone_util.dart';

/// PAS-UX-09 follow-up: a soft-gate that ensures the merchant has a
/// `shopName` set before they can interact with the dashboard.
///
/// The field is required at signup again (see `register.dart`), but a long
/// tail of merchants signed up under the optional regime and have empty /
/// missing values today. Rather than running a backfill migration, this gate
/// catches them on next dashboard entry and forces a one-field setup.
///
/// Behaviour:
///   * While the check is in flight, shows the wrapped child wrapped in a
///     loading overlay (we don't want to flash an empty Scaffold).
///   * If shopName is present, renders `child` unchanged — zero overhead for
///     the 95% case after first frame.
///   * If shopName is missing/blank, replaces the child with a non-skippable
///     [BusinessNamePage] in `requireValue` mode. Once the merchant saves,
///     the gate flips and reveals `child`.
///   * If the user is not signed in, falls through (auth flow handles it).
///   * If the read fails (offline, transient), we let the merchant through
///     rather than locking them out — defensive reads further downstream
///     already substitute fallbacks for missing names.
class BusinessNameGate extends StatefulWidget {
  const BusinessNameGate({super.key, required this.child});

  final Widget child;

  @override
  State<BusinessNameGate> createState() => _BusinessNameGateState();
}

class _BusinessNameGateState extends State<BusinessNameGate> {
  bool _checking = true;
  bool _needsName = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _needsName = false;
      });
      return;
    }
    try {
      // `fetchShopNameForUser` already trims and treats empty as null
      // (PAS-UX-09 follow-up — see lib/utils/phone_util.dart).
      final existing =
          await fetchShopNameForUser(StoreSession.instance.storeId);
      if (!mounted) return;
      setState(() {
        _checking = false;
        _needsName = existing == null;
      });
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'BusinessNameGate check failed',
      );
      if (!mounted) return;
      // Fail-open: don't lock the merchant out on a transient read error.
      setState(() {
        _checking = false;
        _needsName = false;
      });
    }
  }

  void _onSaved() {
    if (!mounted) return;
    setState(() => _needsName = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_needsName) {
      return BusinessNamePage(
        requireValue: true,
        onSaved: _onSaved,
      );
    }
    return widget.child;
  }
}
