import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_smartlook/flutter_smartlook.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/remote_config.dart';
import 'package:pasella/models/common/queued_sms.dart';
import 'package:pasella/models/common/sms_event.dart';
import 'package:pasella/pages/reports/business_report/business_report.dart';
import 'package:pasella/pages/sales/sales.dart';
import 'package:pasella/pages/settings/chat/chat_page.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/providers/common/balance_summary_provider.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/services/period_filter_services.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import './app_imports.dart';
import 'pages/auth/registerAnonymous/register_anonymous.dart';
import 'pages/ledger/view_model/ledger_view_model.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message: ${message.messageId}');
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _firebaseMessagingOnMessageOpenedAppHandler(
    RemoteMessage message) async {
  if (message.data.containsKey('route')) {
    navigatorKey.currentState?.pushNamed(message.data['route']);
  }
}

Future<void> _firebaseMessagingGetInitialMessage(RemoteMessage? message) async {
  if (message != null && message.data.containsKey('route')) {
    navigatorKey.currentState?.pushNamed(message.data['route']);
  }
}

Future<void> _initializeRemoteConfigAndSmartlook() async {
  try {
    final remoteConfigService = await RemoteConfigService.getInstance();

    String projectKey = remoteConfigService.getString('SMARTLOOK_PROJECT_KEY');

    final Smartlook smartlook = Smartlook.instance;
    smartlook.start();
    smartlook.preferences.setProjectKey(projectKey);
  } catch (e) {
    print("Error initializing Remote Config or Smartlook: $e");
  }
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

    await Hive.initFlutter();
    Hive.registerAdapter(QueuedSMSAdapter());
    await Hive.openBox<QueuedSMS>('smsQueue');
    await Hive.openBox('deepLinkBox');

    // Initialize and configure Remote Config and Smartlook
    if (kReleaseMode) {
      await _initializeRemoteConfigAndSmartlook();
    }

    // Firebase Messaging setup
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedAppHandler);
    FirebaseMessaging.instance.getInitialMessage().then(_onInitialMessage);
  } catch (error) {
    print("Initialization error: $error");
    // Consider showing an error message to the user or sending an error report
  }

  runApp(const MyApp());

  // Set up the SMSEvent listener once the app is fully initialized
  WidgetsBinding.instance.addPostFrameCallback((_) {
    eventBus.on<SMSEvent>().listen((event) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        showSMSSnackBar(context, event.message, event.success);
      } else {
        print("Context is not available yet.");
      }
    });
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
        ChangeNotifierProvider(create: (context) => BalanceSummaryProvider()),
        ChangeNotifierProvider(
            create: (context) => CustomerBalanceSummaryProvider()),
        ChangeNotifierProvider<PeriodFilterService>(
          create: (context) => PeriodFilterService(),
        ),
        ChangeNotifierProvider<LedgerViewModel>(
            create: (context) =>
                LedgerViewModel(Provider.of<AppModel>(context, listen: false))),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: kCustomThemeData,
        initialRoute: LoginPage.id,
        navigatorKey: navigatorKey,
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
          SalesPage.id: (context) => const SalesPage(),
          WalletPage.id: (context) => const WalletPage(),
          FindDefaulterPage.id: (context) => const FindDefaulterPage(),
        },
      ),
    );
  }
}
