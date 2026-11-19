import '../models/user_profile.dart';

/// 폰을 바꿔도 정보를 이어 쓰게 해 주는 계정.
///
/// 구글 로그인 → Firebase → 게이트웨이 로그인(`FirebaseAccountService`). 설정은 `docs/ACCOUNT.md`.
abstract class AccountService {
  /// 로그인하고 계정 id를 돌려준다. 취소하거나 실패하면 null.
  Future<String?> signIn();

  /// 계정에 저장된 정보를 가져온다. 새 폰에서 로그인했을 때 쓴다.
  Future<UserProfile?> restore(String accountId);

  /// 계정에 정보를 올린다.
  Future<void> upload(String accountId, UserProfile profile);
}

/// 게이트웨이 주소가 없을 때(`GATEWAY_URL` 미지정) 쓰는 구현. 로그인하지 않고 이 폰에만 저장한다.
class DeviceOnlyAccountService implements AccountService {
  @override
  Future<String?> signIn() async => null;

  @override
  Future<UserProfile?> restore(String accountId) async => null;

  @override
  Future<void> upload(String accountId, UserProfile profile) async {}
}
