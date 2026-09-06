import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_badger_plus/flutter_app_badger_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/build_provenance.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/config/firebase_options.dart';
import 'package:pasella/config/firebase_environment.dart';
import 'package:pasella/config/spaza_environment.dart';
import 'package:pasella/models/common/queued_sms.dart';
import 'package:pasella/models/common/sms_event.dart';
import 'package:pasella/pages/contact/contact_management.dart';
import 'package:pasella/pages/reports/business_report/business_report.dart';
import 'package:pasella/pages/sales/sales.dart';
import 'package:pasella/pages/settings/chat/chat_page.dart';
import 'package:pasella/pages/settings/delete/delete_account_page.dart';
import 'package:pasella/pages/settings/privacy/privacy_page.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/pages/stock/stock.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/billing/wallet_balance_provider.dart';
import 'package:pasella/services/activation_nudge_intent_bus.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/consent_service.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/review_prompt_service.dart';
import 'package:pasella/services/fcm_service.dart';
import 'package:pasella/services/environment_contract_service.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/services/startup_session_progress.dart';
import 'package:pasella/services/whatsapp_catalog_status_service.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import './app_imports.dart';
import 'pages/auth/registerAnonymous/register_anonymous.dart';
import 'pages/ledger/view_model/ledger_view_model.dart';
import 'pages/promote/promote_intent_bus.dart';
import 'pages/promote/promotions_page.dart';
import 'pages/promote/view_model/promotions_view_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/merchant_heartbeat.dart';
import 'services/store_session.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final total = int.tryParse(message.data['unreadTotalCount'] ?? '');
  if (total != null) {
    await FlutterAppBadgerPlus.updateBadgeCount(total);
  }
}

Future<void> setupFlutterNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@drawable/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
    // Initializing the local-notifications plugin must not display the iOS
    // permission sheet over Login. FCMService owns the contextual permission
    // flow once a merchant has signed in and completed startup.
    requestAlertPermission: false,
    requestSoundPermission: false,
    requestBadgePermission: false,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (response) {
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map) return;
        final data = decoded.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
        _handleNotificationRouteData(data['route']?.toString(), data);
      } catch (error, stack) {
        CrashService.instance.recordNonFatal(
          error,
          stack,
          reason: 'local notification payload route failed',
        );
      }
    },
  );
}

Future<void> createNotificationChannel() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'default_channel', // matches manifest EXACTLY
    'Default Notifications',
    description: 'Default notification channel for Spaza One app.',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

void showLocalNotification(RemoteMessage message) async {
  if (message.data.containsKey('unreadTotalCount')) {
    final n = int.tryParse(message.data['unreadTotalCount'] ?? '') ?? 0;
    FlutterAppBadgerPlus.updateBadgeCount(n);
  } else {
    if (message.data.containsKey('unreadOrdersCount')) {
      final n = int.tryParse(message.data['unreadOrdersCount'] ?? '') ?? 0;
      FlutterAppBadgerPlus.updateBadgeCount(n);
    }

    // Compatibility for released functions that still send one scalar.
    if (message.data.containsKey('unreadCount')) {
      final n = int.tryParse(message.data['unreadCount'] ?? '') ?? 0;
      FlutterAppBadgerPlus.updateBadgeCount(n);
    }
  }

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'default_channel',
    'Default Notifications',
    channelDescription: 'Default notification channel',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@drawable/ic_launcher',
  );

  const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

  const notificationDetails = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    message.notification?.title,
    message.notification?.body,
    notificationDetails,
    payload: jsonEncode(message.data),
  );
}

Future<void> _firebaseMessagingOnMessageOpenedAppHandler(
  RemoteMessage message,
) async {
  _handleNotificationRoute(message);
}

Future<void> _firebaseMessagingGetInitialMessage(RemoteMessage? message) async {
  if (message != null) _handleNotificationRoute(message);
}

void _handleNotificationRoute(RemoteMessage message) {
  _handleNotificationRouteData(message.data['route']?.toString(), message.data);
}

String? _notificationString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? _firstNotificationString(Iterable<Object?> values) {
  for (final value in values) {
    final text = _notificationString(value);
    if (text != null) return text;
  }
  return null;
}

bool _isCustomerMessageNotification(Uri? uri, Map<String, dynamic> data) {
  final notificationType = _notificationString(data['notificationType']);
  final action = _notificationString(data['action']);
  return uri?.path == '/customerAccount' ||
      notificationType == 'customer_message' ||
      action == 'open_customer_messages';
}

Future<User?> _notificationCurrentUser() async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) return currentUser;

  return FirebaseAuth.instance
      .authStateChanges()
      .firstWhere((user) => user != null)
      .timeout(const Duration(seconds: 3), onTimeout: () => null);
}

void _pushCustomerAccountWhenReady({
  required String customerId,
  required String customerName,
  String? mobileNumber,
  required int initialTabIndex,
}) {
  void push() {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => CustomerManagementPage(
          customerName: customerName,
          customerId: customerId,
          mobileNumber: mobileNumber,
          initialTabIndex: initialTabIndex,
        ),
      ),
    );
  }

  if (navigatorKey.currentState != null) {
    push();
    return;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => push());
}

Future<void> _openCustomerFromMessageNotification(
  Uri? uri,
  Map<String, dynamic> data,
) async {
  final initialTabIndex = customerNotificationTabIndex(data);
  final query = uri?.queryParameters ?? const <String, String>{};
  final customerId = _firstNotificationString([
    data['customerId'],
    query['customerId'],
  ]);
  final payloadCustomerName = _firstNotificationString([
    data['customerName'],
    query['customerName'],
  ]);
  final payloadCustomerNumber = _firstNotificationString([
    data['customerNumber'],
    query['customerNumber'],
  ]);

  try {
    final user = await _notificationCurrentUser();
    if (user == null) {
      CrashService.instance.recordNonFatal(
        StateError('Customer message notification opened without a user'),
        StackTrace.current,
        reason: 'customer message notification missing signed-in user',
      );
      return;
    }

    final customerCollection = FirebaseFirestore.instance
        .collection('users')
        .doc(StoreSession.instance.storeId)
        .collection('customers');

    if (customerId != null) {
      final customerDoc = await customerCollection.doc(customerId).get();
      final customerData = customerDoc.data();
      if (customerDoc.exists && customerData != null) {
        _pushCustomerAccountWhenReady(
          customerId: customerDoc.id,
          customerName: _firstNotificationString([
                customerData['name'],
                payloadCustomerName,
              ]) ??
              'Customer',
          mobileNumber: _firstNotificationString([
            customerData['number'],
            payloadCustomerNumber,
          ]),
          initialTabIndex: initialTabIndex,
        );
        return;
      }

      if (payloadCustomerName != null) {
        _pushCustomerAccountWhenReady(
          customerId: customerId,
          customerName: payloadCustomerName,
          mobileNumber: payloadCustomerNumber,
          initialTabIndex: initialTabIndex,
        );
        return;
      }
    }

    final normalizedNumber = normalizePhoneNumber(payloadCustomerNumber);
    if (normalizedNumber.isNotEmpty) {
      final snapshot = await customerCollection
          .where('number', isEqualTo: normalizedNumber)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final customerDoc = snapshot.docs.first;
        final customerData = customerDoc.data();
        _pushCustomerAccountWhenReady(
          customerId: customerDoc.id,
          customerName: _firstNotificationString([
                customerData['name'],
                payloadCustomerName,
              ]) ??
              'Customer',
          mobileNumber: _firstNotificationString([
            customerData['number'],
            normalizedNumber,
          ]),
          initialTabIndex: initialTabIndex,
        );
        return;
      }
    }

    CrashService.instance.recordNonFatal(
      StateError('Customer message notification could not resolve customer'),
      StackTrace.current,
      reason: 'customer message notification customer lookup failed',
      context: {
        'customerId': customerId ?? '',
        'hasCustomerNumber': (payloadCustomerNumber != null).toString(),
      },
    );
  } catch (error, stack) {
    CrashService.instance.recordNonFatal(
      error,
      stack,
      reason: 'customer message notification navigation failed',
    );
  }
}

@visibleForTesting
int customerNotificationTabIndex(Map<String, dynamic> data) {
  final notificationType = _notificationString(data['notificationType']);
  final action = _notificationString(data['action']);
  return notificationType == 'commerce_order' ||
          action == 'open_customer_orders'
      ? 1
      : 2;
}

@visibleForTesting
bool isOnlinePaymentsNotificationRoute(Uri? uri) {
  return uri?.path == WalletPage.id &&
      uri?.queryParameters['destination'] == 'online_payments';
}

@visibleForTesting
bool isPaymentOperationsWorkspaceNotification(
  Uri? uri,
  Map<String, dynamic> data,
) {
  return data['notificationType'] == 'payment_operations' &&
      uri?.scheme == 'https' &&
      uri?.host == 'workspace.spazaone.com' &&
      ((uri?.path.isEmpty ?? false) || uri?.path == '/');
}

/// Routes a notification tap to the correct screen.
///
/// Recognises the `route` data field. For the `/promotionsPage` family of
/// routes, query parameters (`tab`, `templateId`, `action`) are stashed in
/// [PromoteIntentBus] so the destination page can react after first build —
/// this avoids needing a full deep-link router for what is currently a small
/// number of routes.
void _handleNotificationRouteData(String? route, Map<String, dynamic> data) {
  final uri = route == null || route.isEmpty ? null : Uri.tryParse(route);

  if (_isCustomerMessageNotification(uri, data)) {
    unawaited(_openCustomerFromMessageNotification(uri, data));
    return;
  }

  if (uri == null) return;

  if (isPaymentOperationsWorkspaceNotification(uri, data)) {
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    return;
  }

  if (uri.path == '/promotionsPage') {
    PromoteIntentBus.instance.set(PromoteIntent.fromUri(uri));
  }

  if (uri.path == Dashboard.id) {
    final activationIntent = ActivationNudgeIntent.fromUri(uri, data: data);
    if (activationIntent != null) {
      ActivationNudgeIntentBus.instance.set(activationIntent);
      final nudgeType =
          activationIntent.nudgeType ?? data['nudgeType'] ?? 'unknown';
      TelemetryService.instance.capture(
        ActivationNudgeOpened(
          nudgeType: nudgeType.toString(),
          action: activationIntent.action.name,
          channel: 'fcm',
        ),
      );
    }
  }

  if (isOnlinePaymentsNotificationRoute(uri)) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const WalletPage(initialTab: WalletInitialTab.withdraw),
      ),
    );
    return;
  }

  // Strip query params before pushing — the routes table only knows about
  // bare paths. Anything page-specific is delivered via PromoteIntentBus.
  //
  // IMPORTANT: pushing an unknown route triggers MaterialApp's default
  // onUnknownRoute path which asserts `onUnknownRoute!`, crashing with
  // "Null check operator used on a null value" when no handler is set.
  // Guard against unknown routes from FCM payloads (typos, stale links,
  // routes from newer app versions) by checking against the known routes
  // table before pushing. Also funnel any miss into Crashlytics so we can
  // see which routes are being sent that we don't handle.
  final path = uri.path;
  if (!MyApp.knownRoutes.contains(path)) {
    CrashService.instance.recordNonFatal(
      StateError('Unknown notification route'),
      StackTrace.current,
      reason: 'notification route not registered',
      context: {'route': route ?? ''},
    );
    return;
  }

  navigatorKey.currentState?.pushNamed(path);
}

Future<void> _initializeRemoteConfigAndSmartlook() async {
  try {
    // Keep Remote Config initialization; Smartlook is disabled/removed.
    await RemoteConfigService.getInstance();
  } catch (e) {
    print("Error initializing Remote Config: $e");
  }
}

/// Heartbeat: report the active store's app version/build after sign-in,
/// store switches and app updates (throttled per store for 24 hours).
Future<void> setupMerchantHeartbeatBootHook() async {
  final box = await Hive.openBox('appBox');
  final info = await PackageInfo.fromPlatform();
  final currentVersion = info.version;
  final currentBuild = int.tryParse(info.buildNumber) ?? 0;
  final currentCommit = BuildProvenance.hasCommitSha
      ? BuildProvenance.commitSha.toLowerCase()
      : '';
  final platform = defaultTargetPlatform.name;
  final inFlightStores = <String>{};

  Future<void> sendForActiveStore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final storeId = StoreSession.instance.storeId.trim();
    if (storeId.isEmpty || !inFlightStores.add(storeId)) return;

    final keyPrefix = 'hb_${user.uid}_${storeId}_$platform';
    final lastVersion = box.get('${keyPrefix}_version') as String?;
    final lastBuild = box.get('${keyPrefix}_build') as int?;
    final lastCommit = box.get('${keyPrefix}_commit') as String?;
    final lastAt = box.get('${keyPrefix}_last_ms') as int?;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final stale = lastAt == null || (nowMs - lastAt) > 24 * 60 * 60 * 1000;
    final changed = merchantHeartbeatBuildChanged(
      lastVersion: lastVersion,
      lastBuild: lastBuild,
      lastCommit: lastCommit,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      currentCommit: currentCommit,
    );

    try {
      if (stale || changed) {
        await MerchantHeartbeat.instance.send(
          merchantId: storeId,
        );
        await box.put('${keyPrefix}_version', currentVersion);
        await box.put('${keyPrefix}_build', currentBuild);
        if (currentCommit.isNotEmpty) {
          await box.put('${keyPrefix}_commit', currentCommit);
        }
        await box.put('${keyPrefix}_last_ms', nowMs);
      }
    } catch (error, stack) {
      await CrashService.instance.recordNonFatal(
        error,
        stack,
        reason: 'merchant heartbeat failed',
        context: {
          'store_state': 'present',
          'platform': platform,
          'build': currentBuild,
        },
      );
    } finally {
      inFlightStores.remove(storeId);
    }
  }

  void scheduleHeartbeat() {
    unawaited(sendForActiveStore());
  }

  FirebaseAuth.instance.authStateChanges().listen((_) {
    scheduleHeartbeat();
  });
  StoreSession.instance.addListener(scheduleHeartbeat);
  scheduleHeartbeat();
}

void _onMessageOpenedAppHandler(RemoteMessage message) {
  _firebaseMessagingOnMessageOpenedAppHandler(message);
}

void _onInitialMessage(RemoteMessage? message) {
  _firebaseMessagingGetInitialMessage(message);
}

Future<void> _initializeDeferredServices() async {
  try {
    if (FirebaseEnvironment.useEmulators) {
      await ReviewPromptService.instance.init();
      return;
    }
    await SMSMessages.loadTemplates();
    await ReviewPromptService.instance.init();
    await setupFlutterNotifications();
    await createNotificationChannel();

    // Permission is intentionally not requested here. It should be requested
    // from a notification-related user action with clear benefit and context.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedAppHandler);
    FirebaseMessaging.instance.getInitialMessage().then(_onInitialMessage);
    FirebaseMessaging.onMessage.listen(showLocalNotification);
    await setupMerchantHeartbeatBootHook();
  } catch (error, stack) {
    await CrashService.instance.recordNonFatal(
      error,
      stack,
      reason: 'deferred app initialisation failed',
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Render a useful first frame immediately. Network and storage boot work
  // continues behind a branded loading surface instead of leaving users on
  // the native splash while Remote Config waits for its network timeout.
  runApp(const _AppBootstrap());
}

Future<void> _initializeCoreServices() async {
  // Load environment variables
  await dotenv.load();

  if (Firebase.apps.isEmpty) {
    if (FirebaseEnvironment.shouldUseNativePlatformOptions(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      await Firebase.initializeApp();
    } else {
      await Firebase.initializeApp(
        options: FirebaseEnvironment.options(
          DefaultFirebaseOptions.currentPlatform,
        ),
      );
    }
  }
  await FirebaseEnvironment.connect();

  // Both production apps are registered in Firebase App Check. Keep global
  // Firebase services in monitoring mode while older releases age out; new
  // security-sensitive HTTP functions verify these tokens immediately.
  if (!FirebaseEnvironment.useEmulators) {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );
  }

  await EnvironmentContractService.verify();

  // `useFirestoreEmulator` installs a host + plaintext transport in the SDK
  // settings. Replacing the settings object afterwards resets that host and
  // can silently send an emulator build back toward production Firestore.
  // Mobile persistence is already enabled by default; only apply the explicit
  // production setting when the emulator connection does not own it.
  if (!FirebaseEnvironment.useEmulators) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  }

  // Feature flags must be ready before MyApp selects its initial route. The
  // bootstrap surface remains visible while this potentially network-backed
  // work completes.
  if (kReleaseMode && !FirebaseEnvironment.useEmulators) {
    await _initializeRemoteConfigAndSmartlook();
  }

  if (FirebaseEnvironment.useEmulators) {
    // Remote Config is deliberately unavailable in production-isolated QA.
    // Require every release-relevant flag as a compile-time value before
    // MyApp chooses its initial route.
    FeatureFlags.applyEmulatorQaProfile(
      EmulatorQaFeatureProfile.fromEnvironment(),
    );
  } else {
    await FeatureFlags.loadFlags();
  }

  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(QueuedSMSAdapter());
  }
  await Hive.openBox<QueuedSMS>('smsQueue');
  await Hive.openBox('deepLinkBox');
  await Hive.openBox('appBox');
  await Hive.openBox(ConsentService.boxName);

  // Telemetry boot order matters:
  //   1. ConsentService.init() reads the persisted choice (or seeds first-run
  //      defaults: crash ON, analytics OFF, replay OFF).
  //   2. CrashService.init() wires FlutterError.onError + PlatformDispatcher
  //      error handlers BEFORE any other code can throw, then applies the
  //      consent flag to Crashlytics' native collection.
  //   3. TelemetryService.init() calls PostHog setup() with optOut=true and
  //      then flips opt-out off only if the user previously consented.
  //
  // Anything that throws during initialisation up to this point will not be
  // captured. We accept that trade-off because Crashlytics needs Firebase
  // initialised first.
  await ConsentService.instance.init();
  if (FirebaseEnvironment.useEmulators) return;
  await CrashService.instance.init();
  final crashPackageInfo = await PackageInfo.fromPlatform();
  await CrashService.instance.configureBuild(
    version: crashPackageInfo.version,
    buildNumber: crashPackageInfo.buildNumber,
  );
  await CrashService.instance.setStoreState(
    present: StoreSession.instance.storeId.isNotEmpty,
  );
  StoreSession.instance.addListener(() {
    unawaited(CrashService.instance.setStoreState(
      present: StoreSession.instance.storeId.isNotEmpty,
    ));
  });
  await CrashService.instance.applyConsent(ConsentService.instance.state);
  await CrashService.instance.recordDevelopmentDiagnosticProbe(
    crashReportingConsented: ConsentService.instance.state.effectiveCrash,
  );
  await TelemetryService.instance.init();

  // Review nudge state is local-only (Hive `appBox`), independent of
  // analytics consent: counters and cooldown timestamps are persisted
  // even if the merchant has opted out of telemetry. Init must run after
  // `Hive.openBox('appBox')` above and is safe before sign-in because it
  // does not touch FirebaseAuth.
  // Track only coarse auth state. Account and store identifiers never enter
  // Crashlytics.
  FirebaseAuth.instance.authStateChanges().listen((user) {
    CrashService.instance.setMerchantId(user?.uid);
    if (user == null) {
      TelemetryService.instance.reset();
      unawaited(WhatsAppCatalogStatusService.clearAllCachedStatus());
    }
  });
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  bool _ready = false;
  bool _starting = false;
  bool _deferredServicesStarted = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _errorMessage = null;
    });

    try {
      await _initializeCoreServices();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _starting = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_deferredServicesStarted) return;
        _deferredServicesStarted = true;
        unawaited(_initializeDeferredServices());
        eventBus.on<SMSEvent>().listen((event) {
          final context = navigatorKey.currentContext;
          if (context != null) {
            showSMSSnackBar(context, event.message, event.success);
          }
        });
      });
    } catch (error, stack) {
      if (kDebugMode) debugPrint('Initialization error: $error');
      try {
        await CrashService.instance.recordNonFatal(
          error,
          stack,
          reason: 'app bootstrap failed',
        );
      } catch (_) {
        // Crash reporting may not itself be initialized yet.
      }
      if (!mounted) return;
      setState(() {
        _starting = false;
        _errorMessage =
            'Spaza One could not finish starting. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const MyApp();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: kCustomThemeData,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _errorMessage == null
                          ? 'Preparing Spaza One…'
                          : 'We couldn\'t start Spaza One',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    if (_errorMessage == null)
                      const CircularProgressIndicator()
                    else ...[
                      Text(_errorMessage!, textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _starting ? null : _start,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  /// Static route table. Exposed as a separate map (instead of being inlined
  /// in `build`) so notification handlers can validate a target route exists
  /// before calling `pushNamed`, avoiding the framework's
  /// `onUnknownRoute!` null-check crash.
  static final Map<String, WidgetBuilder> _routes = {
    LoginPage.id: (context) => const LoginPage(),
    RegisterPage.id: (context) => const RegisterPage(),
    RegisterAnonymousPage.id: (context) => const RegisterAnonymousPage(),
    // PAS-UX-22: number-first onboarding surfaces. `/phoneEntryPage` becomes
    // the initial route when `FeatureFlags.enableNumberFirstOnboarding` is
    // true; the legacy `/loginPage` and `/registerPage` stay registered as
    // compat shims for deep links, post-logout navigation, and rollback.
    PhoneEntryPage.id: (context) => const PhoneEntryPage(),
    FinishProfilePage.id: (context) => const FinishProfilePage(),
    // PAS-UX-09 follow-up: wrap Dashboard in BusinessNameGate so
    // legacy merchants whose shopName was never set (when the field
    // was optional) are forced through a one-field recovery before
    // they can interact with the app. New signups already pass the
    // gate because the register validator now requires the field.
    Dashboard.id: (context) => const BusinessNameGate(child: Dashboard()),
    AddContactPage.id: (context) => const AddContactPage(),
    BusinessNamePage.id: (context) => const BusinessNamePage(),
    BusinessTypePage.id: (context) => const BusinessTypePage(),
    BusinessCategoryPage.id: (context) => const BusinessCategoryPage(),
    BusinessReportPage.id: (context) => const BusinessReportPage(),
    ChatPage.id: (context) => const ChatPage(),
    HelpPage.id: (context) => const HelpPage(),
    SharePage.id: (context) => const SharePage(),
    DeleteAccountPage.id: (context) => const DeleteAccountPage(),
    SalesPage.id: (context) => const SalesPage(),
    WalletPage.id: (context) => const WalletPage(),
    PrivacyPage.id: (context) => const PrivacyPage(),
    PromotionsPage.id: (context) => const PromotionsPage(),
    StockPage.id: (context) => const StockPage(),
    // Compatibility for notification payloads sent by the first internal
    // dropshipping build. Orders now live on the customer, so stale taps land
    // safely on Customers instead of reopening the removed Products tab.
    StockPage.legacyCommerceOrdersId: (context) =>
        const BusinessNameGate(child: Dashboard()),
  };

  static Set<String> get knownRoutes => _routes.keys.toSet();

  @override
  State<MyApp> createState() => _MyAppState();

  @visibleForTesting
  static Route<dynamic> buildUnknownRoute(RouteSettings settings) {
    CrashService.instance.recordNonFatal(
      StateError('Unknown route requested'),
      StackTrace.current,
      reason: 'MaterialApp.onUnknownRoute fallback',
      context: {'route': settings.name ?? ''},
    );

    final routeName =
        _hasSignedInUserForRouteFallback() ? Dashboard.id : LoginPage.id;

    return MaterialPageRoute<void>(
      settings: RouteSettings(name: routeName),
      builder: (context) {
        if (routeName == Dashboard.id) {
          return const BusinessNameGate(child: Dashboard());
        }
        return const LoginPage();
      },
    );
  }

  static bool _hasSignedInUserForRouteFallback() {
    try {
      return FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      // Unit tests and very early boot paths can reach this before Firebase
      // Auth is ready. Login is the safer fallback in that case.
      return false;
    }
  }
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSubscription;
  StartupSessionToken? _permissionToken;
  final _startup = StartupSessionProgress.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StoreSession.instance.addListener(_syncStartupSession);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthChange,
      onError: (Object error, StackTrace stack) {
        unawaited(CrashService.instance.recordNonFatal(
          error,
          stack,
          reason: 'notification permission auth listener failed',
        ));
      },
    );
    _handleAuthChange(FirebaseAuth.instance.currentUser);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        FirebaseAuth.instance.currentUser == null) {
      return;
    }
    if (!StoreSession.instance.loading &&
        StoreSession.instance.lastError != null) {
      unawaited(StoreSession.instance.bootstrap());
    }
    // FCM token acquisition is best-effort and can fail during the original
    // login/bootstrap window. Retry on foreground so an already-authorized
    // merchant does not silently stop receiving customer and order alerts.
    if (!FirebaseEnvironment.useEmulators &&
        !StoreSession.instance.loading &&
        StoreSession.instance.storeId.isNotEmpty) {
      unawaited(FCMService().handleToken());
    }
  }

  void _handleAuthChange(User? user) {
    if (user == null) {
      _startup.reset();
      _permissionToken = null;
      StoreSession.instance.clear();
      return;
    }
    _syncStartupSession();
    unawaited(StoreSession.instance.bootstrap());
  }

  void _syncStartupSession() {
    final user = FirebaseAuth.instance.currentUser;
    final token = _startup.bind(
      userId: user?.uid,
      storeId: user == null ? null : StoreSession.instance.storeId,
    );
    if (token == null ||
        FirebaseEnvironment.useEmulators ||
        StoreSession.instance.loading ||
        identical(token, _permissionToken)) {
      return;
    }
    _permissionToken = token;
    unawaited(_requestNotificationPermissionAfterStartup(token));
  }

  Future<void> _requestNotificationPermissionAfterStartup(
    StartupSessionToken token,
  ) async {
    // The in-memory outcome includes actual privacy/intro dismissal, and
    // explicitly allows an offline or operator guide skip. No retired Hive
    // marker can leave this queue waiting forever.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted || !_startup.isCurrent(token)) return;
    if (!await _startup.waitUntilReady(token)) return;
    if (!mounted ||
        !_startup.isCurrent(token) ||
        FirebaseAuth.instance.currentUser?.uid != token.userId ||
        !ConsentService.instance.state.hasDecided) {
      return;
    }
    final appContext = navigatorKey.currentContext;
    if (appContext == null || !appContext.mounted) {
      if (identical(_permissionToken, token)) _permissionToken = null;
      return;
    }
    try {
      await FCMService().requestPermissionIfNeeded(
        appContext,
        shouldContinue: () =>
            mounted &&
            _startup.isCurrent(token) &&
            _startup.ready &&
            ConsentService.instance.state.hasDecided,
      );
    } catch (error, stack) {
      unawaited(CrashService.instance.recordNonFatal(
        error,
        stack,
        reason: 'notification permission request failed',
      ));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StoreSession.instance.removeListener(_syncStartupSession);
    _startup.reset();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    precacheImage(const AssetImage("assets/images/share.png"), context);
    // PAS-UX-10: update_number.png precache removed — UpdateNumberPage
    // is a non-functional stub with no entry point in the app and no
    // backing OTP/data-migration flow, so warming its asset wastes
    // startup work for a screen merchants cannot reach. The route
    // registration is kept below in case a deep link references it.

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AppModel()),
        ChangeNotifierProvider<StoreSession>.value(
          value: StoreSession.instance,
        ),
        ChangeNotifierProvider(create: (context) => WalletBalanceProvider()),
        ChangeNotifierProvider(create: (context) => BalanceSummaryProvider()),
        ChangeNotifierProvider(
          create: (context) => CustomerBalanceSummaryProvider(),
        ),
        ChangeNotifierProvider<LedgerViewModel>(
          create: (context) => LedgerViewModel(
            Provider.of<AppModel>(context, listen: false),
          ),
        ),
        ChangeNotifierProvider<PromotionsViewModel>(
          create: (context) {
            final vm = PromotionsViewModel();
            // defer load until after first frame:
            WidgetsBinding.instance.addPostFrameCallback((_) {
              vm.loadInitialData();
            });
            return vm;
          },
        ),
      ],
      child: PostHogWidget(
        // Capture root for session replay screenshots. No-op when
        // sessionReplay is false in PostHogConfig (which is the case until
        // the user grants consent).
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            unawaited(CrashService.instance.updateUiContext(context));
            final app = child ?? const SizedBox.shrink();
            if (SpazaRuntimeEnvironment.isProduction) return app;
            return Banner(
              message: SpazaRuntimeEnvironment.label,
              location: BannerLocation.topEnd,
              color: SpazaRuntimeEnvironment.isDevelopment
                  ? const Color(0xFFD84315)
                  : const Color(0xFF6A1B9A),
              child: app,
            );
          },
          theme: kCustomThemeData,
          // PAS-UX-22: when the number-first flag is on, launch into the
          // single-field entry screen. Default (flag off) keeps the legacy
          // `/loginPage` as the initial route so a missing / failed Remote
          // Config fetch leaves merchants on the known-good flow.
          initialRoute: FeatureFlags.enableNumberFirstOnboarding
              ? PhoneEntryPage.id
              : LoginPage.id,
          navigatorKey: navigatorKey,
          navigatorObservers: [
            TelemetryService.instance.navigatorObserver,
            CrashService.instance.navigatorObserver,
          ],
          routes: MyApp._routes,
          // Defensive: any code path that pushes a route not present in
          // `_routes` (e.g. stale FCM notification payloads from older app
          // versions) lands here instead of triggering the framework's
          // `onUnknownRoute!` null-check assertion.
          onUnknownRoute: MyApp.buildUnknownRoute,
        ),
      ),
    );
  }
}
