import 'package:fashion_agent/services/turn_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../agent/turn_test.dart' show FakeTurnApi;

/// 미리 준비가 실패하는 agent 흉내.
class _FailingWarm extends FakeTurnApi {
  _FailingWarm() : super([]);

  @override
  Future<void> warm({TurnLocation? location}) async {
    warmed.add(location);
    throw StateError('서버 꺼짐');
  }
}

void main() {
  var now = DateTime(2026, 11, 15, 8);
  final location =
      LocationProvider(read: () async => const TurnLocation(37.5, 127.0));

  setUp(() => now = DateTime(2026, 11, 15, 8));

  test('5분 안에는 다시 보내지 않고, 5분이 지나면 다시 보낸다', () async {
    final api = FakeTurnApi([]);
    final warmer = TurnWarmer(api, location, now: () => now);

    expect(await warmer.warm(), isTrue);
    now = now.add(const Duration(minutes: 4));
    expect(await warmer.warm(), isFalse);
    now = now.add(const Duration(minutes: 2));
    expect(await warmer.warm(), isTrue);
    expect(api.warmed.map((l) => l!.lat), [37.5, 37.5]);
  });

  test('위치 권한이 없으면 대화와 같이 서울로 보낸다', () async {
    final api = FakeTurnApi([]);
    final noLocation = LocationProvider(read: () async => null);
    await TurnWarmer(api, noLocation, now: () => now).warm();
    expect(api.warmed.single, same(TurnLocation.seoul));
  });

  test('로그인하지 않았으면 보내지 않고, 로그인하면 바로 다시 보낼 수 있다', () async {
    final api = FakeTurnApi([], signedIn: false);
    final warmer = TurnWarmer(api, location, now: () => now);
    expect(await warmer.warm(), isFalse);
    expect(api.warmed, isEmpty);

    api.signedIn = true;
    expect(await warmer.warm(), isTrue);
  });

  test('서버가 실패해도 예외를 내지 않는다', () async {
    final api = _FailingWarm();
    expect(await TurnWarmer(api, location, now: () => now).warm(), isFalse);
    expect(api.warmed, hasLength(1));
  });
}
