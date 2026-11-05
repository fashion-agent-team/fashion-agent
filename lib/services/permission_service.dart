import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'capture_service.dart';
import 'listen_service.dart';

/// 처음 실행할 때 권한 창을 한 번에 띄운다. 쓰는 도중에 갑자기 창이 뜨지 않게 하려는 것.
abstract class PermissionService {
  /// 마이크·음성 인식, 카메라, 위치를 차례로 묻는다. 말을 들을 수 있게 됐는지(마이크·음성 인식 허용) 돌려준다.
  Future<PermissionResult> requestAll();
}

class PermissionResult {
  const PermissionResult({required this.canListen});

  /// 마이크와 음성 인식을 허용했는지. false면 말로 대화할 수 없다.
  final bool canListen;
}

/// 기기 권한. 각 기능이 쓰는 플러그인으로 직접 물어서, 나중에 그 기능을 쓸 때 다시 묻지 않게 한다.
class DevicePermissionService implements PermissionService {
  DevicePermissionService({required this.listen, required this.camera});

  final DeviceListenService listen;
  final CaptureService camera;

  @override
  Future<PermissionResult> requestAll() async {
    // 1. 마이크 + 음성 인식 (창 두 개)
    final canListen = await listen.prepare();

    // 2. 카메라: 한 번 열었다 닫으면 창이 뜬다.
    try {
      await camera.open();
    } on Object catch (e) {
      debugPrint('카메라 권한 없음: $e');
    } finally {
      await camera.close();
    }

    // 3. 위치 (날씨)
    try {
      final current = await Geolocator.checkPermission();
      if (current == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } on Object catch (e) {
      debugPrint('위치 권한 확인 실패: $e');
    }

    return PermissionResult(canListen: canListen);
  }
}

/// 테스트·시뮬레이터용. 창을 띄우지 않는다.
class FakePermissionService implements PermissionService {
  FakePermissionService({this.canListen = true});

  final bool canListen;
  int requests = 0;

  @override
  Future<PermissionResult> requestAll() async {
    requests++;
    return PermissionResult(canListen: canListen);
  }
}
