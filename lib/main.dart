import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_badger_plus/flutter_app_badger_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/models/common/queued_sms.dart';
import 'package:pasella/models/common/sms_event.dart';
import 'package:pasella/pages/reports/business_report/business_report.dart';
import 'package:pasella/pages/sales/sales.dart';
import 'package:pasella/pages/settings/chat/chat_page.dart';
import 'package:pasella/pages/settings/delete/delete_account_page.dart';
import 'package:pasella/pages/settings/privacy/privacy_page.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/billing/wallet_balance_provider.dart';
import 'package:pasella/services/consent_service.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/templates/sms_message.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/widgets/consent_modal.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import './app_imports.dart';
import 'pages/auth/registerAnonymous/register_anonymous.dart';
import 'pages/ledger/view_model/ledger_view_model.dart';
import 'pages/promote/promote_intent_bus.dart';
import 'pages/promote/promotions_page.dart';
import 'pages/promote/view_model/promotions_view_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/merchant_heartbeat.dart';
import 'package:package_info_plus/package_info_plus.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message: ${message.messageId}');
}

Future<void> setupFlutterNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        // handle notification tapped logic here
      },
    );
}

Future<void> createNotificationChannel() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'default_channel', // matches manifest EXACTLY
    'Default Notifications',
    description: 'Default notification channel for Pasella app.',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

void showLocalNotification(RemoteMessage message) async {
  if (message.data.containsKey('unreadOrdersCount')) {
    final n = int.tryParse(message.data['unreadOrdersCount'] ?? '') ?? 0;
    FlutterAppBadger.updateBadgeCount(n);
  }

  // (kept) Chats badge count from FCM data
  if (message.data.containsKey('unreadCount')) {
    final n = int.tryParse(message.data['unreadCount'] ?? '') ?? 0;
    FlutterAppBadger.updateBadgeCount(n);
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

    const notificationDetails =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    message.notification?.title,
    message.notification?.body,
    notificationDetails,
  );
}

Future<void> _firebaseMessagingOnMessageOpenedAppHandler(
    RemoteMessage message) async {
  _handleNotificationRoute(message);
}

Future<void> _firebaseMessagingGetInitialMessage(RemoteMessage? message) async {
  if (message != null) _handleNotificationRoute(message);
}

/// Routes a notification tap to the correct screen.
///
/// Recognises the `route` data field. For the `/promotionsPage` family of
/// routes, query parameters (`tab`, `templateId`, `action`) are stashed in
/// [PromoteIntentBus] so the destination page can react after first build —
/// this avoids needing a full deep-link router for what is currently a small
/// number of routes.
void _handleNotificationRoute(RemoteMessage message) {
  final route = message.data['route'] as String?;
  if (route == null || route.isEmpty) return;

  final uri = Uri.tryParse(route);
  if (uri == null) return;

  if (uri.path == '/promotionsPage') {
    PromoteIntentBus.instance.set(PromoteIntent.fromUri(uri));
  }

  // Strip query params before pushing — the routes table only knows about
  // bare paths. Anything page-specific is delivered via PromoteIntentBus.
  navigatorKey.currentState?.pushNamed(uri.path);
}

Future<void> _initializeRemoteConfigAndSmartlook() async {
  try {
    // Keep Remote Config initialization; Smartlook is disabled/removed.
    await RemoteConfigService.getInstance();
  } catch (e) {
    print("Error initializing Remote Config: $e");
  }
}

void requestNotificationPermission() async {
  NotificationSettings settings =
      await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print('✅ User granted permission');
  } else {
    print('❌ User declined or has not accepted permission');
  }
}

/// Heartbeat: send app version/build once after sign-in and on updates (throttled 24h).
Future<void> setupMerchantHeartbeatBootHook() async {
  // Open a small local box to track last heartbeat
  final box = await Hive.openBox('appBox');

  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;

    // Current app version/build
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;

    // Last sent snapshot
    final lastVersion = box.get('hb_version') as String?;
    final lastBuild = box.get('hb_build') as int?;
    final lastAt = box.get('hb_last_ms') as int?;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final stale = lastAt == null || (nowMs - lastAt) > 24 * 60 * 60 * 1000; // 24h
    final changed =
        lastVersion != currentVersion || lastBuild != currentBuild;

    if (stale || changed) {
      try {
        await MerchantHeartbeat.instance.send(merchantId: user.uid);
        await box.put('hb_version', currentVersion);
        await box.put('hb_build', currentBuild);
        await box.put('hb_last_ms', nowMs);
      } catch (e, st) {
        // Non-blocking by design: heartbeat failures must never block the
        // user. Funnel into Crashlytics as a non-fatal so we still see them.
        await CrashService.instance.recordNonFatal(
          e,
          st,
          reason: 'merchant heartbeat failed',
          context: {'merchant_id': user.uid},
        );
      }
    }
  });
}

void _onMessageOpenedAppHandler(RemoteMessage message) {
  _firebaseMessagingOnMessageOpenedAppHandler(message);
}

void _onInitialMessage(RemoteMessage? message) {
  _firebaseMessagingGetInitialMessage(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  try {
    // Load environment variables
    await dotenv.load();

    // Initialize Firebase
    await Firebase.initializeApp();

    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: true);

    // Initialize Remote Config
    if (kReleaseMode) {
      await RemoteConfigService.getInstance();
      await _initializeRemoteConfigAndSmartlook();
    }

    await FeatureFlags.loadFlags();
    await SMSMessages.loadTemplates();

    await Hive.initFlutter();
    Hive.registerAdapter(QueuedSMSAdapter());
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
    await CrashService.instance.init();
    await CrashService.instance.applyConsent(ConsentService.instance.state);
    await TelemetryService.instance.init();

    // Tag Crashlytics with the merchant id (and clear it on sign-out) so
    // crash reports can be grouped per merchant without leaking PII.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      CrashService.instance.setMerchantId(user?.uid);
      if (user == null) {
        TelemetryService.instance.reset();
      }
    });

    await setupFlutterNotifications();
    await createNotificationChannel();
    requestNotificationPermission();

    // Firebase Messaging setup
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedAppHandler);
    FirebaseMessaging.instance.getInitialMessage().then(_onInitialMessage);

    // Foreground message listener
    FirebaseMessaging.onMessage
        .listen(showLocalNotification); // ✅ listen and display

    // When app is opened from a notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationRoute);

    // Setup merchant heartbeat boot hook
    await setupMerchantHeartbeatBootHook();
  } catch (error, stack) {
    if (kDebugMode) {
      debugPrint('Initialization error: $error');
    }
    // Funnel boot-time errors into Crashlytics so we don't lose them silently.
    // CrashService is initialised inside this same try-block; it is null-safe
    // and won't throw if it never reached its init step.
    await CrashService.instance.recordNonFatal(
      error,
      stack,
      reason: 'main() initialisation failed',
    );
  }

  runApp(const MyApp());

  // Set up the SMSEvent listener once the app is fully initialized
  WidgetsBinding.instance.addPostFrameCallback((_) {
    eventBus.on<SMSEvent>().listen((event) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        showSMSSnackBar(context, event.message, event.success);
      }
    });

    // Show the consent modal on first launch. Defer to the next frame so
    // navigatorKey.currentContext is populated.
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      ConsentModal.showIfNeeded(ctx);
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    precacheImage(const AssetImage("assets/images/share.png"), context);
    precacheImage(const AssetImage("assets/images/update_number.png"), context);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AppModel()),
        ChangeNotifierProvider(create: (context) => WalletBalanceProvider()),
        ChangeNotifierProvider(create: (context) => BalanceSummaryProvider()),
        ChangeNotifierProvider(
            create: (context) => CustomerBalanceSummaryProvider()),
        ChangeNotifierProvider<LedgerViewModel>(
            create: (context) =>
                LedgerViewModel(Provider.of<AppModel>(context, listen: false))),
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
          theme: kCustomThemeData,
          initialRoute: LoginPage.id,
          navigatorKey: navigatorKey,
          navigatorObservers: [TelemetryService.instance.navigatorObserver],
          routes: {
            LoginPage.id: (context) => const LoginPage(),
            RegisterPage.id: (context) => const RegisterPage(),
            RegisterAnonymousPage.id: (context) => const RegisterAnonymousPage(),
            Dashboard.id: (context) => const Dashboard(),
            AddContactPage.id: (context) => const AddContactPage(),
            SecurityPage.id: (context) => const SecurityPage(),
            ProfilePage.id: (context) => const ProfilePage(),
            BusinessTypePage.id: (context) => const BusinessTypePage(),
            BusinessCategoryPage.id: (context) => const BusinessCategoryPage(),
            BusinessReportPage.id: (context) => const BusinessReportPage(),
            ChatPage.id: (context) => const ChatPage(),
            AccountPage.id: (context) => const AccountPage(),
            SubscriptionPage.id: (context) => const SubscriptionPage(),
            LanguagePage.id: (context) => const LanguagePage(),
            UpdateNumberPage.id: (context) => const UpdateNumberPage(),
            BackupPage.id: (context) => const BackupPage(),
            HelpPage.id: (context) => const HelpPage(),
            SharePage.id: (context) => const SharePage(),
            DeleteAccountPage.id: (context) => const DeleteAccountPage(),
            SalesPage.id: (context) => const SalesPage(),
            WalletPage.id: (context) => const WalletPage(),
            FindDefaulterPage.id: (context) => const FindDefaulterPage(),
            PrivacyPage.id: (context) => const PrivacyPage(),
            PromotionsPage.id: (context) => const PromotionsPage(),
          },
        ),
      ),
    );
  }
}
