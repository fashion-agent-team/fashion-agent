import 'dart:typed_data';

import 'package:fashion_agent/services/auto_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List jpeg(int w, int h) {
  final src = img.Image(width: w, height: h);
  for (final p in src) {
    p
      ..r = p.x * 255 ~/ w
      ..g = 80
      ..b = p.y * 255 ~/ h;
  }
  return Uint8List.fromList(img.encodeJpg(src, quality: 95));
}

void main() {
  test('큰 가로 사진은 긴 변 1280으로 줄이고 비율을 지킨다', () {
    final big = jpeg(1920, 1080);
    final out = shrinkJpeg((jpeg: big, maxSide: sendMaxSide));
    final d = img.decodeJpg(out)!;
    expect(d.width, 1280);
    expect(d.height, 720);
    expect(out.length, lessThan(big.length));
  });

  test('세로 사진은 높이를 긴 변으로 본다', () {
    final d = img.decodeJpg(
        shrinkJpeg((jpeg: jpeg(1080, 1920), maxSide: sendMaxSide)))!;
    expect(d.height, 1280);
    expect(d.width, 720);
  });

  test('이미 작은 사진은 그대로 보낸다', () {
    final small = jpeg(1280, 720);
    expect(shrinkJpeg((jpeg: small, maxSide: sendMaxSide)), same(small));
  });

  test('이 사진은 1600까지 둔다', () {
    final d = img.decodeJpg(
        shrinkJpeg((jpeg: jpeg(1920, 1080), maxSide: sendMaxSideTeeth)))!;
    expect(d.width, 1600);
  });

  test('JPEG가 아니면 그대로 둔다', () {
    final junk = Uint8List.fromList([1, 2, 3]);
    expect(shrinkJpeg((jpeg: junk, maxSide: sendMaxSide)), same(junk));
  });
}
