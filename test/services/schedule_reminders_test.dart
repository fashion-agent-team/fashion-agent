import 'dart:convert';

import 'package:fashion_agent/agent/agent_controller.dart';
import 'package:fashion_agent/agent/agent_speech.dart';
import 'package:fashion_agent/models/schedule_event.dart';
import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/services/gateway_auth.dart';
import 'package:fashion_agent/services/profile_store.dart';
import 'package:fashion_agent/services/schedule_reminders.dart';
import 'package:fashion_agent/services/turn_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../agent/agent_test.dart'
    show FakeSpeech, ScriptedListen, FakeWeatherService, onboardingWith;
import '../agent/turn_test.dart' show FakeTurnApi, reply, settle;

ScheduleEvent ev(
  String title,
  DateTime start, {
  String? place,
  bool remind = true,
  int? daysBefore,
  ({int hour, int minute})? time,
}) {
  return ScheduleEvent(
    title: title,
    start: start,
    place: place,
    remind: remind,
    remindDaysBefore: daysBefore,
    remindTime: time,
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
    test('일정 하나: 전날 아침 8시와 당일 아침 8시', () {
      final wedding = ev(
        '친구 결혼식',
        DateTime(2026, 11, 14, 14),
        place: '더채플앳청담',
      );
      final plans = planReminders([wedding], now);
      expect(plans.map((p) => p.at), [
        DateTime(2026, 11, 13, 8),
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
        // 내일: 오늘 아침 8시는 지남, 내일 아침 8시만
        ev('면접', DateTime(2026, 11, 12, 15)),
        // 모레: 내일 아침 8시(전날), 모레 아침 8시
        ev('회의', DateTime(2026, 11, 13, 15)),
      ];
      final plans = planReminders(events, now);
      expect(plans.map((p) => '${p.kind.name} ${p.at}'), [
        'before ${DateTime(2026, 11, 12, 8)}',
        'sameDay ${DateTime(2026, 11, 12, 8)}',
        'sameDay ${DateTime(2026, 11, 13, 8)}',
      ]);
    });

    test('같은 날 일정 여러 개는 알림 하나에 모은다', () {
      final events = [
        ev('친구 생일 모임', DateTime(2026, 11, 13, 19)),
        ev('회의', DateTime(2026, 11, 13, 10)),
      ];
      final plans = planReminders(events, now);
      expect(plans, hasLength(2));
      const list = '좋은 아침이에요. 내일 일정이 2개 있어요. 오전 10시 회의, 오후 7시 친구 생일 모임.';
      expect(plans.first.body, startsWith(list));
    });
  });

  group('일정마다 정한 알림', () {
    test('알림을 끈 일정은 예약하지 않는다', () {
      final off = ev('회의', DateTime(2026, 11, 13, 10), remind: false);
      expect(planReminders([off], now), isEmpty);
    });

    test('사흘 전 아침 8시와 당일 아침', () {
      final wedding = ev(
        '친구 결혼식',
        DateTime(2026, 11, 14, 14),
        place: '더채플앳청담',
        daysBefore: 3,
      );
      // 11-11 오전 10시면 그날 아침 8시가 지났으니 하루 앞에서 본다.
      final plans = planReminders([wedding], DateTime(2026, 11, 10, 21),
          agentName: '심청이');
      expect(plans.map((p) => p.at), [
        DateTime(2026, 11, 11, 8),
        DateTime(2026, 11, 14, 8),
      ]);
      expect(plans.first.title, '다가오는 일정');
      final body = plans.first.body;
      const head = '좋은 아침이에요. 사흘 뒤 11월 14일 토요일 오후 2시, 더채플앳청담에서 친구 결혼식이 있어요.';
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
      expect(plans.first.at, DateTime(2026, 11, 12, 8));
      expect(plans.first.body, startsWith('좋은 아침이에요. 모레 오전 10시, 면접이 있어요.'));
      expect(plans.first.body, contains('"모레 뭐 입지?"'));
    });

    test('같은 아침에 뜨는 다른 날 일정은 하나로 모은다', () {
      final events = [
        ev('회의', DateTime(2026, 11, 13, 10)),
        ev('결혼식', DateTime(2026, 11, 15, 12), daysBefore: 3),
      ];
      final plans = planReminders(events, now);
      final eve = plans.where((p) => p.kind == ReminderKind.before);
      expect(eve, hasLength(1));
      expect(eve.single.at, DateTime(2026, 11, 12, 8));
      const items = '내일 오전 10시 회의, 사흘 뒤 11월 15일 일요일 오후 12시 결혼식.';
      expect(eve.single.body, startsWith('좋은 아침이에요. 다가오는 일정이 2개 있어요. $items'));
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
      expect(body, startsWith('좋은 아침이에요. 내일 오후 2시, 더채플앳청담에서 친구 결혼식이 있어요. '));
      expect(body, contains('입고 갈 옷을 오늘 저녁에 미리 골라 두면 내일 아침이 편해요.'));
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

  // spec 002 US6(2026-11-20 정지원): "29일 저녁 8시 일정을 3일 전에 알려 줘"면 26일 저녁 8시가 아니라
  // 26일 아침에 "사흘 뒤 오후 8시에 일정이 있어요"라고 알려 준다.
  group('며칠 전 알림은 그날 아침 인사로', () {
    final party = ev('친구 모임', DateTime(2026, 11, 29, 20), daysBefore: 3);

    test(
        'Given 29일 오후 8시 일정을 3일 전에 알려 달라고 함 '
        'When 20일에 알림을 맞추면 Then 26일 아침 8시에 미리 알림이 뜬다', () {
      // given
      final today = DateTime(2026, 11, 20, 15);

      // when
      final plans = planReminders([party], today);

      // then
      final before = plans.singleWhere((p) => p.kind == ReminderKind.before);
      expect(before.at, DateTime(2026, 11, 26, 8));
      expect(before.body,
          startsWith('좋은 아침이에요. 사흘 뒤 11월 29일 일요일 오후 8시, 친구 모임이 있어요.'));
      expect(
          plans.map((p) => p.at), isNot(contains(DateTime(2026, 11, 26, 20))));
    });

    test(
        'Given 3일 전에 알려 달라고 한 29일 일정 When 26일 아침에 앱을 열면 '
        'Then 인사 뒤에 "사흘 뒤 … 오후 8시" 일정을 말한다', () {
      // given
      final events = [party];

      // when
      final line = greetingSchedule(events, DateTime(2026, 11, 26, 7, 30));

      // then
      expect(line, '사흘 뒤 11월 29일 일요일 오후 8시, 친구 모임이 있어요.');
    });

    test(
        'Given 3일 전에 알려 달라고 한 29일 일정 When 25일·27일에 앱을 열면 '
        'Then 그 일정은 말하지 않는다', () {
      // given
      final events = [party];

      // when
      final fourDays = greetingSchedule(events, DateTime(2026, 11, 25, 9));
      final twoDays = greetingSchedule(events, DateTime(2026, 11, 27, 9));

      // then
      expect(fourDays, isNull);
      expect(twoDays, isNull);
    });

    test(
        'Given 오늘 회의와 오늘 미리 알릴 며칠 뒤 일정 When 앱을 열면 '
        'Then 오늘 일정 다음에 "그리고"로 며칠 뒤 일정을 말한다', () {
      // given
      final events = [
        party,
        ev('회의', DateTime(2026, 11, 26, 10)),
        ev('알림 끈 약속', DateTime(2026, 11, 26, 12), remind: false),
        ev('이미 끝난 조깅', DateTime(2026, 11, 26, 7)),
      ];

      // when
      final line = greetingSchedule(events, DateTime(2026, 11, 26, 8, 30));

      // then
      expect(
          line, '오늘 오전 10시, 회의가 있어요. 그리고 사흘 뒤 11월 29일 일요일 오후 8시, 친구 모임이 있어요.');
    });

    test(
        'Given 며칠 전인지 정하지 않은 내일 일정 When 오늘 앱을 열면 '
        'Then 전날로 보고 "내일" 일정을 말한다', () {
      // given
      final events = [ev('면접', DateTime(2026, 11, 27, 14))];

      // when
      final line = greetingSchedule(events, DateTime(2026, 11, 26, 9));

      // then
      expect(line, '내일 오후 2시, 면접이 있어요.');
    });
  });

  // spec 002 US6-7(2026-11-20 정지원): "약속 2일 전 오후 4시에 알려 줘"처럼 시각도 정할 수 있다.
  group('알림 시각을 정한 일정', () {
    test(
        'Given 29일 오후 8시 일정을 2일 전 오후 4시에 알려 달라고 함 '
        'When 알림을 맞추면 Then 27일 오후 4시에 뜨고 아침 8시에는 뜨지 않는다', () {
      // given
      final party = ev('친구 모임', DateTime(2026, 11, 29, 20),
          daysBefore: 2, time: (hour: 16, minute: 0));

      // when
      final plans = planReminders([party], DateTime(2026, 11, 20, 15));

      // then
      final before = plans.singleWhere((p) => p.kind == ReminderKind.before);
      expect(before.at, DateTime(2026, 11, 27, 16));
      expect(before.body, startsWith('모레 오후 8시, 친구 모임이 있어요.'));
      expect(before.body, isNot(contains('좋은 아침')));
      expect(
          plans.map((p) => p.at), isNot(contains(DateTime(2026, 11, 27, 8))));
      expect(plans.map((p) => p.at), contains(DateTime(2026, 11, 29, 8)));
    });

    test(
        'Given 같은 날 아침 8시 알림 일정과 오후 4시 알림 일정 When 알림을 맞추면 '
        'Then 두 알림이 따로, 서로 다른 번호로 뜬다', () {
      // given
      final events = [
        ev('회의', DateTime(2026, 11, 28, 10)),
        ev('친구 모임', DateTime(2026, 11, 29, 20),
            daysBefore: 1, time: (hour: 16, minute: 0)),
        ev('면접', DateTime(2026, 11, 29, 9), daysBefore: 1),
      ];

      // when
      final plans = planReminders(events, DateTime(2026, 11, 20, 15));

      // then
      final on28 = plans.where((p) =>
          p.kind == ReminderKind.before && p.day == DateTime(2026, 11, 28));
      expect(on28.map((p) => p.at),
          [DateTime(2026, 11, 28, 8), DateTime(2026, 11, 28, 16)]);
      expect(on28.first.body, contains('면접'));
      expect(on28.last.body, contains('친구 모임'));
      expect(plans.map((p) => p.id).toSet(), hasLength(plans.length));
      expect(on28.first.id, 202611281);
    });

    test(
        'Given 당일 오후 1시에 알려 달라고 한 오후 3시 일정 When 알림을 맞추면 '
        'Then 그날 아침 알림 대신 오후 1시에 한 번 뜬다', () {
      // given
      final talk = ev('발표', DateTime(2026, 11, 25, 15),
          daysBefore: 0, time: (hour: 13, minute: 0));

      // when
      final plans = planReminders([talk], DateTime(2026, 11, 20, 15));

      // then
      expect(plans, hasLength(1));
      expect(plans.single.kind, ReminderKind.sameDay);
      expect(plans.single.at, DateTime(2026, 11, 25, 13));
      expect(plans.single.body, startsWith('오늘 오후 3시, 발표가 있어요.'));
    });

    test('Given 전날 밤 9시 알림 When 문장을 만들면 Then "오늘 저녁에" 없이 내일 옷을 고르자고 한다', () {
      // given
      final e = ev('면접', DateTime(2026, 11, 26, 10),
          daysBefore: 1, time: (hour: 21, minute: 0));

      // when
      final plan = planReminders([e], DateTime(2026, 11, 20, 15))
          .firstWhere((p) => p.kind == ReminderKind.before);

      // then
      expect(plan.at, DateTime(2026, 11, 25, 21));
      expect(plan.body, contains('입고 갈 옷을 오늘 미리 골라 두면 내일 아침이 편해요.'));
    });

    test(
        'Given 서버가 remindTime "16:00"을 줌 When 일정을 읽으면 Then 16시 0분, 없거나 이상하면 null',
        () {
      // given
      Map<String, dynamic> json(Object? time) => {
            'title': '친구 모임',
            'start': '2026-11-29T20:00:00+09:00',
            'remindDaysBefore': 2,
            'remindTime': time,
          };

      // when
      final set = ScheduleEvent.fromJson(json('16:00'));
      final none = ScheduleEvent.fromJson(json(null));
      final bad = ScheduleEvent.fromJson(json('오후 4시'));

      // then
      expect(set.remindTime, (hour: 16, minute: 0));
      expect(set.toJson()['remindTime'], '16:00');
      expect(none.remindTime, isNull);
      expect(bad.remindTime, isNull);
    });
  });

  group('서버 일정으로 맞추기', () {
    test('오늘부터 16일 일정을 한 번에 받아 예약을 통째로 바꾼다', () async {
      final source = FakeScheduleSource([
        ev('면접', DateTime(2026, 11, 12, 15)),
        ev('결혼식', DateTime(2026, 11, 14, 14)),
      ]);
      final scheduler = MemoryReminderScheduler();
      // 아침 8시 전에 열었다.
      final reminders = ScheduleReminders(
        source: source,
        scheduler: scheduler,
        now: () => DateTime(2026, 11, 11, 7),
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
        now: () => DateTime(2026, 11, 11, 7),
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

  test(
      'Given 26일, 3일 전에 알려 달라고 한 29일 오후 8시 일정 When 앱을 열면 '
      'Then 인사 바로 뒤에 그 일정을 말하고, 받은 일정으로 알림도 맞춘다', () async {
    // given
    final speech = FakeSpeech();
    final source = FakeScheduleSource(
        [ev('친구 모임', DateTime(2026, 11, 29, 20), daysBefore: 3)]);
    final scheduler = MemoryReminderScheduler();
    final agent = AgentController(
      speech: speech,
      listen: ScriptedListen(const []),
      profiles: InMemoryProfileStore(
          const UserProfile(agentName: '하늘', consent: consentVersion)),
      onboarding: onboardingWith(speech, const []),
      weatherService: FakeWeatherService(),
      turns: FakeTurnApi(const []),
      reminders: ScheduleReminders(
        source: source,
        scheduler: scheduler,
        now: () => DateTime(2026, 11, 26, 7, 30),
      ),
    );

    // when
    await agent.start();
    await settle();

    // then
    expect(speech.spoken.take(2), [
      returningGreeting('하늘'),
      '사흘 뒤 11월 29일 일요일 오후 8시, 친구 모임이 있어요.',
    ]);
    expect(source.asked, hasLength(1)); // 인사 때 받은 일정을 알림 맞추기에 다시 쓴다
    expect(scheduler.replaces, 1);
    expect(scheduler.scheduled.map((p) => p.at), [
      DateTime(2026, 11, 26, 8),
      DateTime(2026, 11, 29, 8),
    ]);
  });

  test('Given 오늘 말할 일정이 없음 When 앱을 열면 Then 인사만 하고 일정 말은 붙이지 않는다', () async {
    // given
    final speech = FakeSpeech();
    final agent = AgentController(
      speech: speech,
      listen: ScriptedListen(const []),
      profiles: InMemoryProfileStore(
          const UserProfile(agentName: '하늘', consent: consentVersion)),
      onboarding: onboardingWith(speech, const []),
      weatherService: FakeWeatherService(),
      turns: FakeTurnApi(const []),
      reminders: ScheduleReminders(
        source: FakeScheduleSource(
            [ev('친구 모임', DateTime(2026, 11, 29, 20), daysBefore: 3)]),
        scheduler: MemoryReminderScheduler(),
        now: () => DateTime(2026, 11, 25, 9),
      ),
    );

    // when
    await agent.start();
    await settle();

    // then
    expect(speech.spoken, isNot(contains(contains('친구 모임'))));
  });

  test('시리 단축어로 들어온 말을 한 번만 보낸다', () async {
    final speech = FakeSpeech();
    final turns = FakeTurnApi([reply('오늘 옷 추천해 드릴게요.', TurnNext.done)]);
    final agent = AgentController(
      speech: speech,
      listen: ScriptedListen(const []),
      profiles: InMemoryProfileStore(),
      onboarding: onboardingWith(speech, const []),
      weatherService: FakeWeatherService(),
      turns: turns,
    );
    agent.profile = const UserProfile(agentName: '하늘', consent: consentVersion);
    final asks = ['오늘 뭐 입지?'];
    agent.takeShortcutAsk = () async => asks.isEmpty ? null : asks.removeAt(0);

    await agent.checkShortcut();
    await settle();
    await agent.checkShortcut();
    await settle();
    expect(turns.sent, ['say:오늘 뭐 입지?']);
  });
}
