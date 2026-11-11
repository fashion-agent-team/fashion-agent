import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/schedule_event.dart';
import 'gateway_auth.dart';

// 일정 전날 저녁과 당일 아침에 폰 알림을 띄운다(2026-11-11 진행 님 요청).
//
// 원격 푸시(FCM·APNs)는 유료 Apple 개발자 계정이 있어야 해서, 지금은 앱이 서버(mcp-schedule)에서
// 앞으로 며칠 일정을 받아 폰 안에 알림을 예약한다. 앱을 열 때, 대화를 마칠 때, 앱으로 돌아올 때마다 다시 맞춘다.
// 그래서 일정을 말로 넣거나 지우면 다음 맞출 때 알림도 따라 바뀐다.

/// 일정을 가져오는 곳. 날짜 하나씩 묻는다(`GET /api/v1/schedules?date=`).
abstract class ScheduleSource {
  Future<List<ScheduleEvent>> on(DateTime day);
}

/// 게이트웨이를 거쳐 mcp-schedule에서 일정을 가져온다.
class GatewayScheduleSource implements ScheduleSource {
  GatewayScheduleSource(this.gateway);

  final GatewayAuth gateway;

  @override
  Future<List<ScheduleEvent>> on(DateTime day) async {
    final path = '/api/v1/schedules?date=${isoDate(day)}';
    final json = await gateway.sendJson('GET', path);
    final events = <ScheduleEvent>[];
    for (final e in (json?['events'] as List?) ?? const []) {
      if (e is Map<String, dynamic>) events.add(ScheduleEvent.fromJson(e));
    }
    return events;
  }
}

/// 2026-11-12
String isoDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// 알림 종류.
enum ReminderKind {
  /// 전날 저녁: 미리 옷을 골라 두라고.
  dayBefore,

  /// 당일 아침: 나가기 전에 옷을 같이 보자고.
  sameDay,
}

/// 예약할 알림 하나. 하루에 종류마다 하나씩만 만든다(일정이 여러 개면 한 알림에 모아 읽는다).
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.kind,
    required this.day,
    required this.at,
    required this.title,
    required this.body,
  });

  /// 날짜와 종류로 정한다(같은 알림은 늘 같은 번호). 예: 2026-11-12 당일 = 202611122.
  final int id;
  final ReminderKind kind;

  /// 일정이 있는 날.
  final DateTime day;

  /// 알림이 뜨는 때.
  final DateTime at;
  final String title;
  final String body;

  /// 알림을 눌렀을 때 앱이 받는 값. 이 앱이 만든 일정 알림인지 이 접두어로 가린다.
  String get payload => '$payloadPrefix${isoDate(day)}:${kind.name}';

  static const payloadPrefix = 'schedule:';

  @override
  String toString() => '$id ${kind.name} $at $body';
}

/// 전날 알림은 저녁 8시.
const dayBeforeHour = 20;

/// 당일 알림은 아침 8시. 첫 일정이 9시보다 이르면 첫 일정 1시간 전.
const sameDayHour = 8;
const sameDayLead = Duration(hours: 1);

/// 너무 이른 새벽에는 깨우지 않는다. 이보다 이르면 당일 알림을 건너뛰고 전날 알림만 남긴다.
const earliestHour = 5;

/// [events]로 [now] 뒤에 띄울 알림을 정한다. 이미 지난 알림, 이미 시작한 일정은 뺀다.
///
/// [agentName]이 있으면 "심청이" 하고 부르라고 알려 준다(화면을 누르지 않고 이름을 불러 말하는 앱이라서).
List<PlannedReminder> planReminders(
  List<ScheduleEvent> events,
  DateTime now, {
  String? agentName,
}) {
  final byDay = <DateTime, List<ScheduleEvent>>{};
  for (final e in events) {
    final start = e.start.toLocal();
    if (!start.isAfter(now)) continue;
    final day = DateTime(start.year, start.month, start.day);
    byDay.putIfAbsent(day, () => []).add(e);
  }
  final plans = <PlannedReminder>[];
  for (final day in byDay.keys) {
    final list = byDay[day]!;
    list.sort((a, b) => a.start.compareTo(b.start));
    final dayNumber = day.year * 10000 + day.month * 100 + day.day;

    final eve = DateTime(day.year, day.month, day.day - 1, dayBeforeHour);
    if (eve.isAfter(now)) {
      plans.add(PlannedReminder(
        id: dayNumber * 10 + 1,
        kind: ReminderKind.dayBefore,
        day: day,
        at: eve,
        title: '내일 일정',
        body: reminderBody(list, ReminderKind.dayBefore, agentName: agentName),
      ));
    }

    var morning = DateTime(day.year, day.month, day.day, sameDayHour);
    final lead = list.first.start.toLocal().subtract(sameDayLead);
    if (lead.isBefore(morning)) morning = lead;
    final tooEarly = DateTime(day.year, day.month, day.day, earliestHour);
    if (!morning.isBefore(tooEarly) && morning.isAfter(now)) {
      plans.add(PlannedReminder(
        id: dayNumber * 10 + 2,
        kind: ReminderKind.sameDay,
        day: day,
        at: morning,
        title: '오늘 일정',
        body: reminderBody(list, ReminderKind.sameDay, agentName: agentName),
      ));
    }
  }
  plans.sort((a, b) => a.at.compareTo(b.at));
  return plans;
}

/// 화면 읽기(VoiceOver·TalkBack)로 들어도 알기 쉽게 짧은 문장으로 쓴다. 기호·이모지는 넣지 않는다.
///
/// - 하나: "내일 오후 2시, 더채플앳청담에서 친구 결혼식이 있어요. …"
/// - 여러 개: "내일 일정이 2개 있어요. 오전 10시 회의, 오후 7시 친구 생일 모임. …"
String reminderBody(
  List<ScheduleEvent> events,
  ReminderKind kind, {
  String? agentName,
}) {
  final when = kind == ReminderKind.dayBefore ? '내일' : '오늘';
  final String what;
  if (events.length == 1) {
    final e = events.single;
    final time = spokenTime(e.start.toLocal());
    final place = (e.place ?? '').trim();
    final where = place.isEmpty ? '' : '$place에서 ';
    final subject = '${e.title}${_subjectParticle(e.title)}';
    what = '$when $time, $where$subject 있어요.';
  } else {
    final items = <String>[];
    for (final e in events) {
      items.add('${spokenTime(e.start.toLocal())} ${e.title}');
    }
    what = '$when 일정이 ${events.length}개 있어요. ${items.join(', ')}.';
  }
  final name = (agentName ?? '').trim();
  final call = name.isEmpty ? '' : '"$name" 하고 부른 뒤 ';
  if (kind == ReminderKind.dayBefore) {
    const early = '입고 갈 옷을 오늘 미리 골라 두면 아침이 편해요.';
    return '$what $early 앱을 열고 $call"내일 뭐 입지?"라고 물어보세요.';
  }
  const help = '옷을 같이 봐 드릴게요.';
  return '$what 나가기 전에 앱을 열고 $call"오늘 뭐 입지?"라고 물어보시면 $help';
}

/// 받침이 있으면 "이", 없으면 "가". 한글로 끝나지 않으면 "이".
String _subjectParticle(String word) {
  final w = word.trim();
  if (w.isEmpty) return '이';
  final c = w.codeUnitAt(w.length - 1);
  if (c < 0xAC00 || c > 0xD7A3) return '이';
  return (c - 0xAC00) % 28 == 0 ? '가' : '이';
}

/// 폰에 알림을 예약하는 곳.
abstract class ReminderScheduler {
  /// 알림 권한을 묻는다. 이미 답했으면 창 없이 결과만 준다. 허용했으면 true.
  Future<bool> requestPermission();

  /// 이 앱이 예약한 일정 알림을 모두 지우고 [plans]로 바꾼다. 다른 알림은 건드리지 않는다.
  Future<void> replace(List<PlannedReminder> plans);
}

/// `flutter_local_notifications`로 폰에 예약한다. 앱이 꺼져 있어도 정한 때에 뜬다.
class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;

  /// 긴 문장도 잘리지 않게 펼쳐 보여 준다(화면 읽기는 본문 전체를 읽는다).
  static NotificationDetails _details(String body) {
    final android = AndroidNotificationDetails(
      'schedule',
      '일정 알림',
      channelDescription: '일정 전날 저녁과 당일 아침에 옷을 같이 고르자고 알려 줘요.',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(body),
    );
    const ios = DarwinNotificationDetails(
      presentBanner: true,
      presentList: true,
      presentSound: true,
    );
    return NotificationDetails(android: android, iOS: ios);
  }

  Future<void> _init() => _ready ??= _initOnce();

  Future<void> _initOnce() async {
    tzdata.initializeTimeZones();
    // 서버(mcp-schedule)도 Asia/Seoul로 날짜를 나눈다. 예약 시각은 순간(instant)으로 바꿔 넣으므로
    // 폰 시간대가 달라도 정한 때에 뜬다.
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    // 권한 창은 처음 실행의 "허용 창 한 번에"에서 띄운다. 여기서는 묻지 않는다.
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings: settings);
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await _init();
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final allowed = await ios.requestPermissions(alert: true, sound: true);
        return allowed ?? false;
      }
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final allowed = await android.requestNotificationsPermission();
        return allowed ?? false;
      }
    } on Object catch (e) {
      debugPrint('알림 권한 확인 실패: $e');
    }
    return false;
  }

  @override
  Future<void> replace(List<PlannedReminder> plans) async {
    await _init();
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      final payload = p.payload ?? '';
      if (payload.startsWith(PlannedReminder.payloadPrefix)) {
        await _plugin.cancel(id: p.id);
      }
    }
    for (final plan in plans) {
      await _plugin.zonedSchedule(
        id: plan.id,
        title: plan.title,
        body: plan.body,
        payload: plan.payload,
        scheduledDate: tz.TZDateTime.from(plan.at, tz.local),
        notificationDetails: _details(plan.body),
        // 정확한 알람 권한 없이 예약한다. 몇 분 늦을 수 있지만 권한을 따로 묻지 않아도 된다.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

/// 테스트용. 예약한 것을 적어 두기만 한다.
class MemoryReminderScheduler implements ReminderScheduler {
  MemoryReminderScheduler({this.allowed = true});

  bool allowed;
  int permissionRequests = 0;
  List<PlannedReminder> scheduled = [];
  int replaces = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return allowed;
  }

  @override
  Future<void> replace(List<PlannedReminder> plans) async {
    replaces++;
    scheduled = [...plans];
  }
}

/// 서버 일정을 받아 알림을 다시 맞춘다.
class ScheduleReminders {
  ScheduleReminders({
    required this.source,
    required this.scheduler,
    this.days = 8,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ScheduleSource source;
  final ReminderScheduler scheduler;

  /// 오늘부터 며칠 일정을 볼지. 앱을 열 때마다 다시 맞추므로 일주일 남짓이면 된다.
  final int days;
  final DateTime Function() _now;

  /// 동시에 여러 번 불러도 한 번만 돈다.
  Future<int?>? _running;

  /// 일정을 받아 알림을 바꾼다. 예약한 알림 수를 돌려준다.
  /// 일정을 못 받으면(서버 꺼짐 등) 예약해 둔 알림은 그대로 두고 null.
  Future<int?> sync({String? agentName}) {
    return _running ??= _sync(agentName).whenComplete(() => _running = null);
  }

  Future<int?> _sync(String? agentName) async {
    final now = _now();
    final asks = <Future<List<ScheduleEvent>>>[];
    for (var i = 0; i < days; i++) {
      asks.add(source.on(DateTime(now.year, now.month, now.day + i)));
    }
    final events = <ScheduleEvent>[];
    try {
      for (final list in await Future.wait(asks)) {
        events.addAll(list);
      }
    } on Object catch (e) {
      debugPrint('일정 알림: 일정을 못 받아 예약한 알림을 그대로 둡니다: $e');
      return null;
    }
    final plans = planReminders(events, now, agentName: agentName);
    try {
      await scheduler.replace(plans);
    } on Object catch (e) {
      debugPrint('일정 알림 예약 실패: $e');
      return null;
    }
    debugPrint('일정 알림 ${plans.length}개 예약');
    return plans.length;
  }
}
