import 'dart:convert';

import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/models/schedule_event.dart';
import 'package:fashion_agent/services/gateway_auth.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/schedule_reminders.dart';
import 'package:fashion_agent/services/turn_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'agent_test.dart'
    show FakeSpeech, ScriptedListen, FakeWeatherService, onboardingWith;
import 'turn_test.dart' show FakeTurnApi, reply, settle;

ScheduleEvent ev(String title, DateTime start, {String? place}) =>
    ScheduleEvent(title: title, start: start, place: place);

/// 날짜별로 정해 둔 일정을 준다.
class FakeScheduleSource implements ScheduleSource {
  FakeScheduleSource(this.events);

  final List<ScheduleEvent> events;
  bool fail = false;
  final asked = <String>[];

  @override
  Future<List<ScheduleEvent>> on(DateTime day) async {
    asked.add(isoDate(day));
    if (fail) throw GatewayException(502, 'down', '서버 꺼짐');
    return events.where((e) => isoDate(e.start) == isoDate(day)).toList();
  }
}

void main() {
  // 2026-11-11(수) 오전 10시
  final now = DateTime(2026, 11, 11, 10);

  group('언제 알릴지', () {
    test('일정 하나: 전날 저녁 8시와 당일 아침 8시', () {
      final wedding = ev(
        '친구 결혼식',
        DateTime(2026, 11, 14, 14),
        place: '더채플앳청담',
      );
      final plans = planReminders([wedding], now);
      expect(plans.map((p) => p.at), [
        DateTime(2026, 11, 13, 20),
        DateTime(2026, 11, 14, 8),
      ]);
      expect(plans.first.kind, ReminderKind.dayBefore);
      expect(plans.last.kind, ReminderKind.sameDay);
      expect(plans.map((p) => p.id), [202611141, 202611142]);
      expect(plans.first.title, '내일 일정');
      expect(plans.last.title, '오늘 일정');
      expect(plans.first.payload, 'schedule:2026-11-14:dayBefore');
    });

    test('아침 일찍 시작하면 당일 알림은 1시간 전', () {
      final jog = ev('조깅', DateTime(2026, 11, 13, 7, 30));
      final plans = planReminders([jog], now);
      expect(plans.last.at, DateTime(2026, 11, 13, 6, 30));
    });

    test('새벽 5시보다 이르면 당일 알림은 건너뛰고 전날 알림만', () {
      final flight = ev('공항 가기', DateTime(2026, 11, 13, 5, 30));
      final plans = planReminders([flight], now);
      expect(plans.map((p) => p.kind), [ReminderKind.dayBefore]);
    });

    test('이미 지난 알림과 시작한 일정은 뺀다', () {
      final events = [
        // 이미 시작
        ev('아침 회의', DateTime(2026, 11, 11, 9)),
        // 오늘 저녁: 전날 알림·아침 알림 모두 지남
        ev('저녁 약속', DateTime(2026, 11, 11, 19)),
        // 내일: 오늘 저녁 8시, 내일 아침 8시
        ev('면접', DateTime(2026, 11, 12, 15)),
      ];
      final plans = planReminders(events, now);
      expect(plans.map((p) => p.at), [
        DateTime(2026, 11, 11, 20),
        DateTime(2026, 11, 12, 8),
      ]);
    });

    test('같은 날 일정 여러 개는 알림 하나에 모은다', () {
      final events = [
        ev('친구 생일 모임', DateTime(2026, 11, 13, 19)),
        ev('회의', DateTime(2026, 11, 13, 10)),
      ];
      final plans = planReminders(events, now);
      expect(plans, hasLength(2));
      const list = '내일 일정이 2개 있어요. 오전 10시 회의, 오후 7시 친구 생일 모임.';
      expect(plans.first.body, startsWith(list));
    });
  });

  group('알림 문장', () {
    test('전날: 장소·시간을 읽고 내일 옷을 고르자고', () {
      final wedding = ev(
        '친구 결혼식',
        DateTime(2026, 11, 14, 14),
        place: '더채플앳청담',
      );
      final body = reminderBody(
        [wedding],
        ReminderKind.dayBefore,
        agentName: '심청이',
      );
      expect(body, startsWith('내일 오후 2시, 더채플앳청담에서 친구 결혼식이 있어요. '));
      expect(body, contains('입고 갈 옷을 오늘 미리 골라 두면 아침이 편해요.'));
      expect(body, endsWith('"심청이" 하고 부른 뒤 "내일 뭐 입지?"라고 물어보세요.'));
    });

    test('당일: 장소가 없으면 빼고, 받침 없는 말은 "가"', () {
      final meeting = ev('회의', DateTime(2026, 11, 14, 10, 30));
      final body = reminderBody([meeting], ReminderKind.sameDay);
      expect(body, startsWith('오늘 오전 10시 30분, 회의가 있어요. 나가기 전에'));
      expect(body, contains('앱을 열고 "오늘 뭐 입지?"라고 물어보시면'));
      expect(body, endsWith('옷을 같이 봐 드릴게요.'));
    });
  });

  group('서버 일정으로 맞추기', () {
    test('오늘부터 8일 일정을 받아 예약을 통째로 바꾼다', () async {
      final source = FakeScheduleSource([
        ev('면접', DateTime(2026, 11, 12, 15)),
        ev('결혼식', DateTime(2026, 11, 14, 14)),
      ]);
      final scheduler = MemoryReminderScheduler();
      final reminders = ScheduleReminders(
        source: source,
        scheduler: scheduler,
        now: () => now,
      );

      expect(await reminders.sync(agentName: '심청이'), 4);
      expect(source.asked, hasLength(8));
      expect(source.asked.first, '2026-11-11');
      expect(source.asked.last, '2026-11-18');
      final ids = scheduler.scheduled.map((p) => p.id);
      expect(ids, [202611121, 202611122, 202611141, 202611142]);

      // 결혼식을 지우면 다음에 맞출 때 그 알림도 빠진다.
      source.events.removeLast();
      await reminders.sync();
      final after = scheduler.scheduled.map((p) => p.id);
      expect(after, [202611121, 202611122]);
    });

    test('서버가 안 되면 예약해 둔 알림을 지우지 않는다', () async {
      final source = FakeScheduleSource([
        ev('면접', DateTime(2026, 11, 12, 15)),
      ]);
      final scheduler = MemoryReminderScheduler();
      final reminders = ScheduleReminders(
        source: source,
        scheduler: scheduler,
        now: () => now,
      );
      await reminders.sync();
      source.fail = true;
      expect(await reminders.sync(), isNull);
      expect(scheduler.replaces, 1);
      expect(scheduler.scheduled, hasLength(2));
    });

    test('게이트웨이로 GET /api/v1/schedules?date=를 부른다', () async {
      final seen = <http.Request>[];
      final body = jsonEncode({
        'events': [
          {
            'eventId': 'e_01',
            'title': '친구 결혼식',
            'start': '2026-11-14T14:00:00+09:00',
            'place': '더채플앳청담',
            'placeCategory': '예식장',
            'occasion': 'wedding',
          },
        ],
      });
      final client = MockClient((req) async {
        seen.add(req);
        return http.Response.bytes(
          utf8.encode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final store = MemoryTokenStore()
        ..tokens = GatewayTokens(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );
      final gateway = GatewayAuth(
        baseUrl: Uri.parse('http://gw:8080'),
        tokens: store,
        client: client,
      );

      final events = await GatewayScheduleSource(gateway).on(
        DateTime(2026, 11, 14),
      );
      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, '/api/v1/schedules');
      expect(seen.single.url.queryParameters, {'date': '2026-11-14'});
      expect(seen.single.headers['authorization'], 'Bearer a');
      expect(events.single.title, '친구 결혼식');
      expect(events.single.place, '더채플앳청담');
      expect(events.single.start.toUtc(), DateTime.utc(2026, 11, 14, 5));
    });
  });

  test('agent와 대화를 마치면 알림을 다시 맞춘다', () async {
    final speech = FakeSpeech();
    final turns = FakeTurnApi([
      reply('토요일 오후 2시 친구 결혼식을 등록했어요.', TurnNext.done),
    ]);
    final scheduler = MemoryReminderScheduler();
    final agent = AgentController(
      speech: speech,
      listen: ScriptedListen(const []),
      profiles: InMemoryProfileStore(),
      onboarding: onboardingWith(speech, const []),
      weatherService: FakeWeatherService(),
      turns: turns,
      reminders: ScheduleReminders(
        source: FakeScheduleSource([]),
        scheduler: scheduler,
      ),
    );

    await agent.handle('토요일 두 시에 친구 결혼식 넣어 줘');
    await settle();
    await settle();
    expect(turns.sent, ['say:토요일 두 시에 친구 결혼식 넣어 줘']);
    expect(scheduler.replaces, 1);
  });
}
