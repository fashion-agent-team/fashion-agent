import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

/// 사용자 정보를 저장한다. 계정에 연결되면 [AccountService]가 서버에도 올린다.
abstract class ProfileStore {
  Future<UserProfile?> load();
  Future<void> save(UserProfile profile);
}

class LocalProfileStore implements ProfileStore {
  static const _key = 'user.profile';

  @override
  Future<UserProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(profile.toJson()));
  }
}

class InMemoryProfileStore implements ProfileStore {
  InMemoryProfileStore([this.profile]);

  UserProfile? profile;

  @override
  Future<UserProfile?> load() async => profile;

  @override
  Future<void> save(UserProfile p) async => profile = p;
}
