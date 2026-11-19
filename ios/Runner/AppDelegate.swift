import AppIntents
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 일정 알림(flutter_local_notifications)이 앱을 보고 있을 때도 뜨게 한다.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

// MARK: - 시리 단축어 (2026-11-13 진행 님: "시리야, 심청이한테 오늘 뭐 입지")
//
// 시리나 단축어 앱에서 부르면 앱을 열고, 할 말을 UserDefaults에 남긴다.
// Flutter 쪽(lib/services/shortcut_ask.dart)이 shared_preferences로 `siri.ask`를 읽어 agent에 보내고 지운다.
// (shared_preferences는 키 앞에 "flutter."를 붙여 UserDefaults에 저장한다.)
// 시리 말이 한국어로 안 맞으면 단축어 앱에서 이 동작("오늘 뭐 입지")을 골라 원하는 말로 부를 수 있다.

@available(iOS 16.0, *)
struct AskOutfitIntent: AppIntent {
  static var title: LocalizedStringResource = "오늘 뭐 입지"
  static var description = IntentDescription("심청이에게 오늘 입을 옷을 물어봐요.")
  static var openAppWhenRun: Bool = true

  @MainActor
  func perform() async throws -> some IntentResult {
    UserDefaults.standard.set("오늘 뭐 입지?", forKey: "flutter.siri.ask")
    return .result()
  }
}

@available(iOS 16.0, *)
struct SimcheongShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: AskOutfitIntent(),
      phrases: [
        "\(.applicationName)한테 오늘 뭐 입지",
        "\(.applicationName)에게 오늘 뭐 입지",
        "\(.applicationName) 오늘 뭐 입지",
      ]
    )
  }
}
