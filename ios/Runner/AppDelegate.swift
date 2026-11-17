import AppIntents
import AVFoundation
import AudioToolbox
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FramingBeepPlugin") {
      FramingBeepPlugin.register(with: registrar)
    }
  }
}

// MARK: - 소리 구도 안내 톡톡 소리 (2026-11-17 정지원: "소리 전혀 안 나")
//
// 카메라가 켜진 동안 손 안 쓰고 듣기(마이크 녹음)가 계속 켜져 있다. iOS는 녹음 중에는 시스템 소리와 진동을
// 기본으로 막아서(allowHapticsAndSystemSoundsDuringRecording = false), Flutter SystemSound.click·HapticFeedback이
// 아무 소리도 진동도 내지 않았다. 또 click(1104)은 "키보드 클릭 소리" 설정이 꺼져 있으면 안 난다.
// 그래서 녹음 중에도 시스템 소리·진동을 허용하고, 키보드 설정과 상관없는 짧은 소리(1057)와 진동을 낸다.
// 오디오 세션을 켜거나 끄지 않아서 듣기를 방해하지 않는다. 무음 모드(옆 스위치)면 소리는 안 나고 진동만 난다.
final class FramingBeepPlugin: NSObject, FlutterPlugin {
  private let haptic = UIImpactFeedbackGenerator(style: .light)

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "simcheong/beep", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(FramingBeepPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "tick" else {
      result(FlutterMethodNotImplemented)
      return
    }
    try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
    AudioServicesPlaySystemSound(1057)
    haptic.impactOccurred()
    result(nil)
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
