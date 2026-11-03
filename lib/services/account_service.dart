import '../models/user_profile.dart';

/// 폰을 바꿔도 정보를 이어 쓰게 해 주는 계정.
///
/// 아이폰은 Apple 로그인, 안드로이드는 구글 로그인을 쓰고, Firebase로 두 로그인을 한 사용자로 묶는다.
/// 설정 방법은 `docs/ACCOUNT.md`를 보라.
abstract class AccountService {
  /// 로그인하고 계정 id를 돌려준다. 취소하거나 실패하면 null.
  Future<String?> signIn();

  /// 계정에 저장된 정보를 가져온다. 새 폰에서 로그인했을 때 쓴다.
  Future<UserProfile?> restore(String accountId);

  /// 계정에 정보를 올린다.
  Future<void> upload(String accountId, UserProfile profile);
}

/// Firebase를 연결하기 전까지 쓰는 구현. 로그인하지 않고 이 폰에만 저장한다.
///
/// TODO(계정 담당): FirebaseAccountService로 교체 (sign_in_with_apple, google_sign_in, firebase_auth, cloud_firestore).
class DeviceOnlyAccountService implements AccountService {
  @override
  Future<String?> signIn() async => null;

  @override
  Future<UserProfile?> restore(String accountId) async => null;

  @override
  Future<void> upload(String accountId, UserProfile profile) async {}
}
