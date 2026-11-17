import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:fashion_agent/services/mouth_finder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('입 박스', () {
    test('입술 안쪽 점을 감싸는 박스를 사진 크기 비율로 준다', () {
      final box = mouthBoxFromLips(
        const [Point(300, 550), Point(500, 540), Point(700, 552)],
        const [Point(300, 552), Point(500, 640), Point(700, 550)],
        width: 1000,
        height: 1000,
      );
      expect(box!.x, closeTo(0.30, 1e-9));
      expect(box.y, closeTo(0.54, 1e-9));
      expect(box.w, closeTo(0.40, 1e-9));
      expect(box.h, closeTo(0.10, 1e-9));
    });

    test('가로세로가 다른 사진은 각 변으로 나눈다', () {
      final box = mouthBoxFromLips(
        const [Point(100, 300)],
        const [Point(300, 400)],
        width: 400,
        height: 800,
      );
      expect(box, const MouthBox(0.25, 0.375, 0.5, 0.125));
    });

    test('사진 밖으로 나간 점은 잘라 낸다', () {
      final box = mouthBoxFromLips(
        const [Point(-50, 900)],
        const [Point(200, 1100)],
        width: 1000,
        height: 1000,
      );
      expect(box!.x, 0);
      expect(box.y, closeTo(0.9, 1e-9));
      expect(box.w, closeTo(0.2, 1e-9));
      expect(box.h, closeTo(0.1, 1e-9));
    });

    test('점이 없거나 사진 크기가 0이면 null', () {
      expect(
          mouthBoxFromLips(const [], const [], width: 10, height: 10), isNull);
      expect(
          mouthBoxFromLips(const [Point(1, 1)], const [], width: 0, height: 10),
          isNull);
    });

    test('계약 모양으로 바꾼다', () {
      expect(const MouthBox(0.3, 0.55, 0.4, 0.2).toJson(),
          {'x': 0.3, 'y': 0.55, 'w': 0.4, 'h': 0.2});
    });
  });

  group('찍은 뒤 입 확인(서버 기준)', () {
    test('기준을 넘으면 그대로 보낸다', () {
      expect(mouthRetakeSpeech(const MouthBox(0.3, 0.55, 0.4, 0.1)), isNull);
    });

    test('못 찾거나, 작거나, 덜 벌렸거나, 잘리면 다시 안내한다', () {
      expect(mouthRetakeSpeech(null), contains('입이 잘 안 보여요'));
      expect(mouthRetakeSpeech(const MouthBox(0.45, 0.5, 0.1, 0.05)),
          contains('가까이'));
      expect(mouthRetakeSpeech(const MouthBox(0.3, 0.55, 0.4, 0.02)),
          contains('벌리고'));
      expect(mouthRetakeSpeech(const MouthBox(0.3, 0.0, 0.4, 0.1)),
          contains('위로'));
      expect(mouthRetakeSpeech(const MouthBox(0.3, 0.9, 0.4, 0.1)),
          contains('아래로'));
      expect(mouthRetakeSpeech(const MouthBox(0.0, 0.5, 0.4, 0.1)),
          contains('정면'));
    });
  });

  group('입 주변만 잘라 보내기', () {
    // 900×1600 세로 사진, 입 자리에만 빨간 상자
    img.Image photo() {
      final p = img.Image(width: 900, height: 1600);
      img.fill(p, color: img.ColorRgb8(200, 200, 200));
      img.fillRect(p,
          x1: 300,
          y1: 1000,
          x2: 600,
          y2: 1080,
          color: img.ColorRgb8(255, 0, 0));
      return p;
    }

    test('입 박스 긴 변 × 2 정사각형으로 자르고 박스를 다시 계산한다', () {
      final jpeg = Uint8List.fromList(img.encodeJpg(photo(), quality: 95));
      const box = MouthBox(300 / 900, 1000 / 1600, 300 / 900, 80 / 1600);
      final out = cropMouth((jpeg: jpeg, box: box));
      final cut = img.decodeJpg(out.jpeg)!;
      expect(cut.width, 600);
      expect(cut.height, 600);
      expect(out.box.x, closeTo(0.25, 0.01));
      expect(out.box.w, closeTo(0.5, 0.01));
      expect(out.box.h, closeTo(80 / 600, 0.01));
      // 다시 계산한 박스 가운데가 빨간 입 자리다
      final px = cut.getPixel(((out.box.x + out.box.w / 2) * 600).round(),
          ((out.box.y + out.box.h / 2) * 600).round());
      expect(px.r, greaterThan(200));
      expect(px.g, lessThan(60));
      expect(out.jpeg.length, lessThan(jpeg.length));
    });

    test('사진 끝에 가까우면 사진 안으로 밀고, 크면 640px로 줄인다', () {
      final jpeg = Uint8List.fromList(img.encodeJpg(photo(), quality: 90));
      const box = MouthBox(0.0, 0.9, 0.6, 0.08);
      final out = cropMouth((jpeg: jpeg, box: box));
      final cut = img.decodeJpg(out.jpeg)!;
      expect(cut.width, lessThanOrEqualTo(640));
      expect(cut.height, lessThanOrEqualTo(640));
      expect(out.box.x, greaterThanOrEqualTo(0));
      expect(out.box.y + out.box.h, lessThanOrEqualTo(1.0001));
    });

    test('읽을 수 없는 사진은 원본과 원래 박스를 그대로 준다', () {
      final raw = Uint8List.fromList([1, 2, 3]);
      const box = MouthBox(0.3, 0.5, 0.4, 0.1);
      final out = cropMouth((jpeg: raw, box: box));
      expect(out.jpeg, raw);
      expect(out.box, box);
    });
  });
}
