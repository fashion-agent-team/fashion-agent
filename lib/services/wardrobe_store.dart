import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/garment.dart';

/// 찍을 때마다 본 옷의 설명을 폰 안에 쌓아 둔다. 사진은 저장하지 않는다.
///
/// v0.2에서 이 목록으로 바로 추천하고, 같은 옷 중복을 합친다.
abstract class WardrobeStore {
  Future<void> addAll(List<Garment> garments);
  Future<List<Garment>> all();
}

class LocalWardrobeStore implements WardrobeStore {
  static const _key = 'wardrobe.garments';

  @override
  Future<void> addAll(List<Garment> garments) async {
    if (garments.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_key) ?? [];
    final now = DateTime.now().toIso8601String();
    saved.addAll(
        garments.map((g) => jsonEncode({...g.toJson(), 'seenAt': now})));
    await prefs.setStringList(_key, saved);
  }

  @override
  Future<List<Garment>> all() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? [])
        .map((s) => Garment.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }
}

class InMemoryWardrobeStore implements WardrobeStore {
  final garments = <Garment>[];

  @override
  Future<void> addAll(List<Garment> list) async => garments.addAll(list);

  @override
  Future<List<Garment>> all() async => List.of(garments);
}
