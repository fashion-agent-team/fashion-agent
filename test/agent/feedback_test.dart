import 'dart:io';
import 'dart:typed_data';

import 'package:fashion_agent/agent/acknowledge.dart';
import 'package:fashion_agent/agent/command_listener.dart';
import 'package:fashion_agent/agent/intent_router.dart';
import 'package:fashion_agent/agent/utterance_end.dart';
import 'package:fashion_agent/agent/voice_picker.dart';
import 'package:fashion_agent/services/cloud_tts.dart';
import 'package:fashion_agent/services/speech_service.dart';
import 'package:fashion_agent/services/voices.dart';
import 'package:fashion_agent/agent/answer_parsing.dart';
import 'package:fashion_agent/services/server_stt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fashion_agent/agent/onboarding_flow.dart';

import 'agent_test.dart' show FakeSpeech, ScriptedListen;

/// 2026-11-09 발표 피드백 반영 시험.
void main() {
  group('말이 끝났는지', () {
    test('명령으로 끝난 말은 바로 처리한다', () {
      for (final s in [
        '내일 옷 추천해 줘',
        '오늘 날씨 어때',
        '일정 알려 주세요',
        '뭐 입지',
        '이걸로 할게',
        '11월 20일 일정 뭐야?',
        '첫 화면',
        '응',
        '어 봐줘',
      ]) {
        expect(utteranceEnd(s), UtteranceEnd.complete, reason: s);
      }
    });

    test('이어질 말로 끊기면 더 말할지 묻는다', () {
      for (final s in [
        '내일 결혼식이 있는데',
        '오늘 날씨 좋으면',
        '그리고',
        '내일 일정에',
        '흰 셔츠랑',
        '옷을',
        '추워서 겉옷 입고',
      ]) {
        expect(utteranceEnd(s), UtteranceEnd.incomplete, reason: s);
      }
    });

    test('잘 모르면 조용해질 때까지 기다린다', () {
      expect(utteranceEnd('날씨'), UtteranceEnd.unsure);
      expect(utteranceEnd('내일 옷'), UtteranceEnd.unsure);
      expect(utteranceEnd(''), UtteranceEnd.unsure);
    });

    test('"없어"는 더 할 말이 없다는 뜻', () {
      for (final s in ['없어', '아니요', '아니 없어요', '그게 다야', '괜찮아', '됐어']) {
        expect(isNothingMore(s), isTrue, reason: s);
      }
      expect(isNothingMore('그리고 일정도 알려 줘'), isFalse);
    });
  });

  group('더 말하실 내용', () {
    test('덜 끝난 말이면 묻고, 더 말하면 이어 붙인다', () async {
      final speech = FakeSpeech();
      final listen = ScriptedListen(['내일 결혼식이 있는데', '뭐 입을지 추천해 줘']);
      final c = CommandListener(listen, ask: speech.speak);
      expect(await c.hear(), '내일 결혼식이 있는데 뭐 입을지 추천해 줘');
      expect(speech.spoken, [askMore]);
    });

    test('"없어"면 들은 말 그대로', () async {
      final speech = FakeSpeech();
      final listen = ScriptedListen(['내일 결혼식이 있는데', '없어']);
      final c = CommandListener(listen, ask: speech.speak);
      expect(await c.hear(), '내일 결혼식이 있는데');
    });

    test('끝난 말이면 묻지 않는다', () async {
      final speech = FakeSpeech();
      final c =
          CommandListener(ScriptedListen(['내일 옷 추천해 줘']), ask: speech.speak);
      expect(await c.hear(), '내일 옷 추천해 줘');
      expect(speech.spoken, isEmpty);
    });
  });

  group('추임새', () {
    test('들은 날짜와 기능을 되짚는다', () {
      expect(acknowledgementFor('내일 입을 옷 추천해 줘'),
          '좋아요, 내일 입을 옷 같이 골라 볼게요. 잠깐만 기다려 주세요.');
      expect(acknowledgementFor('11월 20일 뭐 입지?'),
          '좋아요, 11월 20일 입을 옷 같이 골라 볼게요. 잠깐만 기다려 주세요.');
      expect(acknowledgementFor('오늘 날씨 어때?'), '네, 오늘 날씨 금방 알아봐 드릴게요.');
      expect(acknowledgementFor('다음 주 토요일 일정 알려 줘'),
          '네, 다음 주 토요일 일정 같이 볼게요. 잠깐만요.');
    });

    test('모르는 말에는 어디에나 맞는 말만, 짧은 대답에는 하지 않는다', () {
      expect(acknowledgementFor('오늘 기분이 좀 그래'), '네, 잘 들었어요. 잠깐만요.');
      expect(acknowledgementFor('응'), isNull);
      expect(acknowledgementFor('어 봐줘'), isNull);
    });
  });

  group('목소리 고르기', () {
    test('말을 뜻으로 바꾼다', () {
      VoiceAnswerKind? kind(String s) => parseVoiceAnswer(s, 7)?.kind;
      expect(kind('다음'), VoiceAnswerKind.next);
      expect(kind('처음부터'), VoiceAnswerKind.first);
      expect(kind('지금 목소리 좋아'), VoiceAnswerKind.choose);
      expect(kind('별로야'), VoiceAnswerKind.next);
      expect(kind('그만'), VoiceAnswerKind.cancel);
      expect(parseVoiceAnswer('처음부터 해서 3번 목소리가 좋아', 7)?.number, 3);
      expect(parseVoiceAnswer('세 번째 목소리로 할게', 7)?.number, 3);
      expect(parseVoiceAnswer('2번 들려줘', 7)?.kind, VoiceAnswerKind.listen);
      expect(parseVoiceAnswer('이번 목소리 좋아', 7)?.number, isNull);
    });

    test('"목소리 순서대로 들려줘"는 목소리 고르기', () {
      expect(routeSetting('목소리 순서대로 들려줘'), Setting.voice);
      expect(routeSetting('목소리 바꿔 줘'), Setting.voice);
      expect(routeSetting('내 키 바꿔 줘'), Setting.profile);
    });

    test('다음, 다음, 처음부터 들은 뒤 2번을 고른다', () async {
      final speech = FakeSpeech();
      final listen = ScriptedListen(['다음', '다음', '처음부터', '2번 목소리가 좋아']);
      final chosen =
          await VoicePicker(speech: speech, listen: listen).run(speech.speak);
      expect(chosen, cloudVoices[1]);
      expect(speech.chosen, cloudVoices[1]);
      expect(speech.sampled.whereType<Voice>().take(4).toList(),
          [cloudVoices[0], cloudVoices[1], cloudVoices[2], cloudVoices[0]]);
      expect(speech.spoken.last, '좋아요. 이제부터 2번 목소리로 말할게요.');
    });

    test('듣던 목소리에서 "이 목소리 좋아"', () async {
      final speech = FakeSpeech();
      final listen = ScriptedListen(['다음', '이 목소리 좋아']);
      final chosen =
          await VoicePicker(speech: speech, listen: listen).run(speech.speak);
      expect(chosen, cloudVoices[1]);
    });
  });

  group('구글 목소리', () {
    test('긴 안내를 문장으로 나눈다', () {
      expect(splitSentences('안녕하세요. 오늘은 맑아요! 겉옷을 챙기세요'),
          ['안녕하세요.', '오늘은 맑아요!', '겉옷을 챙기세요']);
      expect(splitSentences('네. 좋아요.'), ['네. 좋아요.']);
    });

    test('첫 문장만 따로, 나머지는 이어서 받는다', () {
      expect(speechChunks('안녕하세요. 오늘은 맑아요! 겉옷을 챙기세요'),
          ['안녕하세요.', '오늘은 맑아요! 겉옷을 챙기세요']);
      expect(speechChunks('네. 좋아요.'), ['네. 좋아요.']);
      final long = List.filled(10, '오늘은 날씨가 맑고 따뜻해요.').join(' ');
      final chunks = speechChunks('첫 문장이에요. $long', max: 60);
      expect(chunks.first, '첫 문장이에요.');
      expect(chunks.skip(1).every((c) => c.length <= 60), isTrue);
      expect(chunks.skip(1).join(' '), long);
    });

    test('마침표 없이 긴 문장도 500자 넘지 않게 자른다', () {
      final long = List.filled(40, '오늘은 날씨가 맑고, 바람이 조금 불어요').join(' ');
      expect(long.length, greaterThan(500));
      final chunks = speechChunks(long);
      expect(chunks.length, greaterThan(2));
      expect(chunks.first.length, lessThanOrEqualTo(100));
      expect(chunks.every((c) => c.length <= 120), isTrue);
      expect(chunks.join(' ').replaceAll(' ', ''), long.replaceAll(' ', ''));
      expect(splitLong('짧아요', 10), ['짧아요']);
      expect(splitLong('가나다라마바사아자차카타', 5), ['가나다라마', '바사아자차', '카타']);
    });

    test('같은 목소리·문장은 같은 이름으로 기억한다', () {
      expect(
          TtsCache.cacheKey('Aoede', '안녕'), TtsCache.cacheKey('Aoede', '안녕'));
      expect(TtsCache.cacheKey('Aoede', '안녕'),
          isNot(TtsCache.cacheKey('Kore', '안녕')));
    });

    test('처음 받는 문장과 파일에서 다시 읽는 문장 모두 끝난다', () async {
      final dir = await Directory.systemTemp.createTemp('tts');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = Uint8List.fromList([1, 2, 3]);
      var loads = 0;
      Future<Uint8List> load() async {
        loads++;
        return bytes;
      }

      final first = TtsCache(dir: () async => dir);
      expect(
          await first
              .get('YuJin', '안녕.', load)
              .timeout(const Duration(seconds: 2)),
          bytes);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // 새로 켠 앱처럼 메모리는 비고 파일만 남은 상태
      final second = TtsCache(dir: () async => dir);
      expect(
          await second
              .get('YuJin', '안녕.', load)
              .timeout(const Duration(seconds: 2)),
          bytes);
      expect(loads, 1);
    });

    test('신호음은 WAV다', () {
      final wav = toneWav(const [880], ms: 50);
      expect(audioMime(wav), 'audio/wav');
      expect(wav.length, 44 + 22050 * 50 ~/ 1000 * 2);
    });
  });

  group('이름 잘못 듣기', () {
    test('많이 쓰는 이름과 한 끗 차이면 그 이름인지 묻는다', () {
      expect(knownNameLike('신청이'), '심청이');
      expect(knownNameLike('신청'), '심청');
      expect(knownNameLike('심청이'), isNull);
      expect(knownNameLike('바다'), isNull);
    });
    test('한 글자씩 끊어 말하면 붙인다', () {
      expect(joinSpelled('심, 청, 이'), '심청이');
      expect(joinSpelled('심 청 이'), '심청이');
      expect(joinSpelled('패션 에이전트'), '패션 에이전트');
    });
  });

  group('서버 음성 인식 힌트 따라 적기', () {
    final hint = sttHint('심청이');
    test('힌트 낱말이 줄줄이 나오면 버린다', () {
      expect(looksLikeHintEcho('심청이 옷 추천 날씨 일정 옷 검사', hint, '어'), isTrue);
      expect(
          looksLikeHintEcho('시각장애인용 패션 도우미 앱과 나누는 한국어 대화', hint, '음'), isTrue);
    });
    test('폰은 "응"만 들었는데 서버 글이 길면 버린다', () {
      expect(looksLikeHintEcho('응 그리고 오늘 날씨는 맑고 따뜻합니다', hint, '응'), isTrue);
    });
    test('보통 말은 그대로 쓴다', () {
      expect(
          looksLikeHintEcho('심청이 내일 날씨 알려 줘', hint, '신청이 내일 날씨 알려 줘'), isFalse);
      expect(looksLikeHintEcho('응', hint, '응'), isFalse);
      expect(parseYesNo('웅'), isTrue);
      expect(parseYesNo('넵'), isTrue);
    });
  });
}
