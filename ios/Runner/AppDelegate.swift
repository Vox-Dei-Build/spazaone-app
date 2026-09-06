import UIKit
import Flutter
import FirebaseAuth
import FirebaseMessaging
// Branch plugin handles app delegate callbacks internally.

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Firebase App Check installs its provider factory during plugin
    // registration. Let FlutterFire configure the default Firebase app after
    // this point so it never captures DeviceCheck before Dart selects the
    // debug provider (simulators) or App Attest (release builds). Calling
    // FirebaseApp.configure() here would configure the default app twice.
    GeneratedPluginRegistrant.register(with: self)
    UNUserNotificationCenter.current().delegate = self
    // Do not register for remote notifications during unauthenticated startup.
    // Firebase Auth requests its APNs token when phone verification begins,
    // while FCM permission remains behind the in-app explanation after login.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Forward APNs token to FirebaseAuth so phone-number verification can use
    // silent APNs (avoiding reCAPTCHA fallback) on iOS.
    #if DEBUG
    Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
    #else
    Auth.auth().setAPNSToken(deviceToken, type: .prod)
    #endif
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // Let FirebaseAuth consume silent push verification notifications first.
    if Auth.auth().canHandleNotification(userInfo) {
      completionHandler(.noData)
      return
    }
    super.application(application,
                      didReceiveRemoteNotification: userInfo,
                      fetchCompletionHandler: completionHandler)
  }

  // Branch deep-link handling is implemented inside the flutter_branch_sdk plugin via
  // registrar.addApplicationDelegate(...). No explicit forwarding is required here.
}
