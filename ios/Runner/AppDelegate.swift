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

// MARK: - 시리 단축어 ("시리야, 심청이 옷 골라 줘")
//
// 2026-11-20: "심청이한테 …"는 시리가 연락처로, "… 오늘 뭐 입지/입을까"는 시리 날씨 답으로 가로채서
// 날씨·연락처와 겹치지 않는 앱 고유 말로 바꿨다. 앱에 보내는 말은 그대로 "오늘 뭐 입지?".
//
// 시리나 단축어 앱에서 부르면 앱을 열고, 할 말을 UserDefaults에 남긴다.
// Flutter 쪽(lib/services/shortcut_ask.dart)이 shared_preferences로 `siri.ask`를 읽어 agent에 보내고 지운다.
// (shared_preferences는 키 앞에 "flutter."를 붙여 UserDefaults에 저장한다.)
// 시리 말이 한국어로 안 맞으면 단축어 앱에서 이 동작("옷 골라 줘")을 골라 원하는 말로 부를 수 있다.

@available(iOS 16.0, *)
struct AskOutfitIntent: AppIntent {
  static var title: LocalizedStringResource = "옷 골라 줘"
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
        "\(.applicationName)에서 옷 골라 줘",
        "\(.applicationName) 옷 골라 줘",
        "\(.applicationName) 옷 골라줘",
        "\(.applicationName) 코디해 줘",
        "\(.applicationName) 코디 시작",
        "\(.applicationName) 켜고 옷 추천해 줘",
        "\(.applicationName)로 옷 고르기",
      ]
    )
  }
}
