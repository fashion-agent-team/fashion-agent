import 'dart:convert';

import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/models/schedule_event.dart';
import 'package:fashion_agent/models/user_profile.dart';
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

ScheduleEvent ev(
  String title,
  DateTime start, {
  String? place,
  bool remind = true,
  int? daysBefore,
}) {
  return ScheduleEvent(
    title: title,
    start: start,
    place: place,
    remind: remind,
    remindDaysBefore: daysBefore,
  );
}

/// 정해 둔 일정 중 물은 기간에 있는 것을 준다.
class FakeScheduleSource implements ScheduleSource {
  FakeScheduleSource(this.events);

  final List<ScheduleEvent> events;
  bool fail = false;
  final asked = <String>[];

  @override
  Future<List<ScheduleEvent>> between(DateTime from, DateTime to) async {
    asked.add('${isoDate(from)}~${isoDate(to)}');
    if (fail) throw GatewayException(502, 'down', '서버 꺼짐');
    bool inRange(ScheduleEvent e) {
      final day = isoDate(e.start);
      return day.compareTo(isoDate(from)) >= 0 &&
          day.compareTo(isoDate(to)) <= 0;
    }

    return events.where(inRange).toList();
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
      expect(plans.first.kind, ReminderKind.before);
      expect(plans.last.kind, ReminderKind.sameDay);
      expect(plans.map((p) => p.id), [202611131, 202611142]);
      expect(plans.first.title, '내일 일정');
      expect(plans.last.title, '오늘 일정');
      expect(plans.first.payload, 'schedule:2026-11-13:before:2026-11-14');
    });

    test('아침 일찍 시작하면 당일 알림은 1시간 전', () {
      final jog = ev('조깅', DateTime(2026, 11, 13, 7, 30));
      final plans = planReminders([jog], now);
      expect(plans.last.at, DateTime(2026, 11, 13, 6, 30));
    });

    test('새벽 5시보다 이르면 당일 알림은 건너뛰고 전날 알림만', () {
      final flight = ev('공항 가기', DateTime(2026, 11, 13, 5, 30));
      final plans = planReminders([flight], now);
      expect(plans.map((p) => p.kind), [ReminderKind.before]);
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

  group('일정마다 정한 알림', () {
    test('알림을 끈 일정은 예약하지 않는다', () {
      final off = ev('회의', DateTime(2026, 11, 13, 10), remind: false);
      expect(planReminders([off], now), isEmpty);
    });

    test('사흘 전 저녁 8시와 당일 아침', () {
      final wedding = ev(
        '친구 결혼식',
        DateTime(2026, 11, 14, 14),
        place: '더채플앳청담',
        daysBefore: 3,
      );
      final plans = planReminders([wedding], now, agentName: '심청이');
      expect(plans.map((p) => p.at), [
        DateTime(2026, 11, 11, 20),
        DateTime(2026, 11, 14, 8),
      ]);
      expect(plans.first.title, '다가오는 일정');
      final body = plans.first.body;
      const head = '사흘 뒤 11월 14일 토요일 오후 2시, 더채플앳청담에서 친구 결혼식이 있어요.';
      expect(body, startsWith(head));
      expect(body, contains('빨래나 수선이 필요하면 지금 해 두세요.'));
      expect(body, endsWith('부른 뒤 "11월 14일에 뭐 입지?"라고 물어보세요.'));
    });

    test('0일이면 당일 아침에만', () {
      final meeting = ev('회의', DateTime(2026, 11, 13, 10), daysBefore: 0);
      final plans = planReminders([meeting], now);
      expect(plans.map((p) => p.kind), [ReminderKind.sameDay]);
    });

    test('모레 일정은 "모레 뭐 입지?"', () {
      final interview = ev('면접', DateTime(2026, 11, 14, 10), daysBefore: 2);
      final plans = planReminders([interview], now);
      expect(plans.first.at, DateTime(2026, 11, 12, 20));
      expect(plans.first.body, startsWith('모레 오전 10시, 면접이 있어요.'));
      expect(plans.first.body, contains('"모레 뭐 입지?"'));
    });

    test('같은 저녁에 뜨는 다른 날 일정은 하나로 모은다', () {
      final events = [
        ev('회의', DateTime(2026, 11, 13, 10)),
        ev('결혼식', DateTime(2026, 11, 15, 12), daysBefore: 3),
      ];
      final plans = planReminders(events, now);
      final eve = plans.where((p) => p.kind == ReminderKind.before);
      expect(eve, hasLength(1));
      expect(eve.single.at, DateTime(2026, 11, 12, 20));
      const items = '내일 오전 10시 회의, 사흘 뒤 11월 15일 일요일 오후 12시 결혼식.';
      expect(eve.single.body, startsWith('다가오는 일정이 2개 있어요. $items'));
    });

    test('서버가 준 remind·remindDaysBefore를 읽는다', () {
      final e = ScheduleEvent.fromJson({
        'title': '면접',
        'start': '2026-11-14T10:00:00+09:00',
        'remind': true,
        'remindDaysBefore': 3,
      });
      expect(e.remind, isTrue);
      expect(e.remindDaysBefore, 3);
      final old = ScheduleEvent.fromJson({
        'title': '면접',
        'start': '2026-11-14T10:00:00+09:00',
      });
      expect(old.remind, isTrue);
      expect(old.remindDaysBefore, isNull);
    });
  });

  group('알림 문장', () {
    test('전날: 장소·시간을 읽고 내일 옷을 고르자고', () {
      final wedding = ev(
        '친구 결혼식',
        DateTime(2026, 11, 14, 14),
        place: '더채플앳청담',
      );
      final body = beforeBody(
        [wedding],
        DateTime(2026, 11, 13),
        agentName: '심청이',
      );
      expect(body, startsWith('내일 오후 2시, 더채플앳청담에서 친구 결혼식이 있어요. '));
      expect(body, contains('입고 갈 옷을 오늘 미리 골라 두면 아침이 편해요.'));
      expect(body, endsWith('"심청이" 하고 부른 뒤 "내일 뭐 입지?"라고 물어보세요.'));
    });

    test('당일: 장소가 없으면 빼고, 받침 없는 말은 "가"', () {
      final meeting = ev('회의', DateTime(2026, 11, 14, 10, 30));
      final body = sameDayBody([meeting]);
      expect(body, startsWith('오늘 오전 10시 30분, 회의가 있어요. 나가기 전에'));
      expect(body, contains('앱을 열고 "오늘 뭐 입지?"라고 물어보시면'));
      expect(body, endsWith('옷을 같이 봐 드릴게요.'));
    });
  });

  group('서버 일정으로 맞추기', () {
    test('오늘부터 16일 일정을 한 번에 받아 예약을 통째로 바꾼다', () async {
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
      expect(source.asked, ['2026-11-11~2026-11-26']);
      final ids = scheduler.scheduled.map((p) => p.id);
      expect(ids, [202611111, 202611122, 202611131, 202611142]);

      // 결혼식을 지우면 다음에 맞출 때 그 알림도 빠진다.
      source.events.removeLast();
      await reminders.sync();
      final after = scheduler.scheduled.map((p) => p.id);
      expect(after, [202611111, 202611122]);
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

    test('게이트웨이로 GET /api/v1/schedules?date=&endDate=를 부른다', () async {
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

      final events = await GatewayScheduleSource(gateway).between(
        DateTime(2026, 11, 11),
        DateTime(2026, 11, 26),
      );
      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, '/api/v1/schedules');
      expect(seen.single.url.queryParameters, {
        'date': '2026-11-11',
        'endDate': '2026-11-26',
      });
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

  group('알림을 누르면 그날 옷 추천', () {
    test('알림 값에서 일정 날을 꺼낸다', () {
      expect(reminderEventDay('schedule:2026-11-13:before:2026-11-14'),
          DateTime(2026, 11, 14));
      // 예전 모양(일정 날 없음)은 알림 날
      expect(reminderEventDay('schedule:2026-11-14:sameDay'),
          DateTime(2026, 11, 14));
      expect(reminderEventDay('other:1'), isNull);
      expect(reminderEventDay(null), isNull);
    });

    test('가까운 날은 오늘·내일·모레, 먼 날은 날짜로 묻는다', () {
      final at = DateTime(2026, 11, 13, 20);
      expect(reminderAsk(DateTime(2026, 11, 13), at), '오늘 뭐 입지?');
      expect(reminderAsk(DateTime(2026, 11, 14), at), '내일 뭐 입지?');
      expect(reminderAsk(DateTime(2026, 11, 15), at), '모레 뭐 입지?');
      expect(reminderAsk(DateTime(2026, 11, 20), at), '11월 20일 뭐 입지?');
    });

    test('여러 날 미리 알림은 가장 이른 일정 날로', () {
      final plans = planReminders([
        ev("면접", DateTime(2026, 11, 16, 10), daysBefore: 3),
      ], now);
      expect(plans.first.payload, endsWith(':2026-11-16'));
    });

    test('누르면 인사 없이 바로 그날 옷 추천을 agent에 보낸다', () async {
      final speech = FakeSpeech();
      final turns = FakeTurnApi([reply('내일 입을 옷을 추천해 드릴게요.', TurnNext.done)]);
      final agent = AgentController(
        speech: speech,
        listen: ScriptedListen(const []),
        profiles: InMemoryProfileStore(),
        onboarding: onboardingWith(speech, const []),
        weatherService: FakeWeatherService(),
        turns: turns,
      );
      agent.profile =
          const UserProfile(agentName: '하늘', consent: consentVersion);

      await agent.askFromReminder('내일 뭐 입지?');
      await settle();
      expect(turns.sent, ['say:내일 뭐 입지?']);
      expect(speech.spoken.first, AgentController.reminderIntro);
    });

    test('앱이 알림으로 막 켜져 정보를 아직 안 불러왔으면 시작 인사 뒤 듣지 않고 보낸다', () async {
      final speech = FakeSpeech();
      final turns = FakeTurnApi([reply('추천해 드릴게요.', TurnNext.done)]);
      final agent = AgentController(
        speech: speech,
        listen: ScriptedListen(const []),
        profiles: InMemoryProfileStore(
            const UserProfile(agentName: '하늘', consent: consentVersion)),
        onboarding: onboardingWith(speech, const []),
        weatherService: FakeWeatherService(),
        turns: turns,
      );
      await agent.askFromReminder('오늘 뭐 입지?');
      await agent.start();
      await settle();
      await settle();
      expect(turns.sent, ['say:오늘 뭐 입지?']);
      expect(speech.spoken, isNot(contains(startsWith('앗'))));
    });
  });
}
