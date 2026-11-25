import 'dart:typed_data';

import 'package:fashion_agent/services/mouth_finder.dart';
import 'package:fashion_agent/services/turn_api.dart';

/// 서버(agent)가 준 것 같은 한 차례 답을 만든다.
TurnReply reply(String speech, TurnNext next, {String id = 's_1'}) =>
    TurnReply(sessionId: id, speech: speech, next: next);

/// agent 흉내. 받은 요청을 적어 두고 정해 둔 답을 차례로 준다.
class FakeTurnApi implements TurnApi {
  FakeTurnApi(this.replies, {this.signedIn = true});

  final List<Object> replies;
  bool signedIn;
  final sent = <String>[];
  final sessions = <String?>[];
  final locations = <TurnLocation?>[];
  final mouthBoxes = <MouthBox?>[];
  final faceLandmarks = <Map<String, Object>?>[];
  final warmed = <TurnLocation?>[];

  @override
  Future<bool> get available async => signedIn;

  @override
  Future<void> warm({TurnLocation? location}) async {
    warmed.add(location);
  }

  Future<TurnReply> _next() async {
    final r = replies.removeAt(0);
    if (r is TurnReply) return r;
    throw r;
  }

  @override
  Future<TurnReply> say(String? sessionId, String utterance,
      {TurnLocation? location}) {
    sent.add('say:$utterance');
    sessions.add(sessionId);
    locations.add(location);
    return _next();
  }

  @override
  Future<TurnReply> show(String? sessionId, ImageKind kind, Uint8List jpeg,
      {TurnLocation? location,
      MouthBox? mouthBox,
      Map<String, Object>? faceLandmarks}) {
    mouthBoxes.add(mouthBox);
    this.faceLandmarks.add(faceLandmarks);
    sent.add('show:${kind.name}:${jpeg.length}');
    sessions.add(sessionId);
    locations.add(location);
    return _next();
  }
}
