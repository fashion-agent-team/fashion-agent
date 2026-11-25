import 'package:fashion_agent/models/user_profile.dart';
import 'package:fashion_agent/services/account_service.dart';

/// 가짜 계정 연결. [id]가 null이면 로그인을 건너뛴(또는 실패한) 경우다.
class FakeAccount implements AccountService {
  FakeAccount({this.id, this.saved});

  final String? id;

  /// 서버에 이미 저장돼 있는 프로필(다른 폰에서 쓰던 계정).
  final UserProfile? saved;

  /// 앱이 서버로 올린 프로필.
  UserProfile? uploaded;

  @override
  Future<String?> signIn() async => id;

  @override
  Future<UserProfile?> restore(String accountId) async => saved;

  @override
  Future<void> upload(String accountId, UserProfile profile) async =>
      uploaded = profile;
}
