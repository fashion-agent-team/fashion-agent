import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';
import '../models/user_profile.dart';
import 'account_service.dart';
import 'gateway_auth.dart';

/// 구글 로그인 → Firebase → 게이트웨이 로그인. 회원정보는 게이트웨이(`/api/v1/me/profile`)에 둔다.
///
/// 발표까지는 아이폰·안드로이드 모두 구글 로그인만 쓴다. Apple 로그인은 유료 개발자 계정이 필요해서 앱스토어 출시 때 붙인다.
class FirebaseAccountService implements AccountService {
  FirebaseAccountService({
    required this.gateway,
    FirebaseAuth? auth,
    GoogleSignIn? google,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _google = google ?? GoogleSignIn.instance;

  final GatewayAuth gateway;
  final FirebaseAuth _auth;
  final GoogleSignIn _google;
  Future<void>? _initialized;

  Future<void> _init() => _initialized ??= _google.initialize(
        // 아이폰은 Info.plist의 GIDClientID를, 안드로이드는 이 웹 클라이언트 id로 Firebase용 ID 토큰을 받는다.
        serverClientId: defaultTargetPlatform == TargetPlatform.android
            ? DefaultFirebaseOptions.googleServerClientId
            : null,
      );

  @override
  Future<String?> signIn() async {
    try {
      await _init();
      final account = await _google.authenticate();
      final googleIdToken = account.authentication.idToken;
      if (googleIdToken == null) return null;

      final cred = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: googleIdToken),
      );
      final user = cred.user;
      final firebaseIdToken = await user?.getIdToken();
      if (user == null || firebaseIdToken == null) return null;

      await gateway.login(firebaseIdToken);
      return user.uid;
    } on GoogleSignInException catch (e) {
      // 취소는 정상 흐름이다. 앱은 이 폰에만 저장하고 계속 쓴다.
      if (e.code != GoogleSignInExceptionCode.canceled) {
        debugPrint('구글 로그인 실패: $e');
      }
      return null;
    } on Object catch (e) {
      debugPrint('계정 연결 실패: $e');
      return null;
    }
  }

  @override
  Future<UserProfile?> restore(String accountId) async {
    try {
      final json = await gateway.sendJson('GET', '/api/v1/me/profile');
      return json == null ? null : profileFromGateway(json, accountId);
    } on Object catch (e) {
      debugPrint('회원정보 가져오기 실패: $e');
      return null;
    }
  }

  @override
  Future<void> upload(String accountId, UserProfile profile) async {
    try {
      await gateway.send('PUT', '/api/v1/me/profile', json: profileToGateway(profile));
    } on Object catch (e) {
      // 올리기에 실패해도 폰에는 저장돼 있다. 다음에 다시 올리면 된다.
      debugPrint('회원정보 올리기 실패: $e');
    }
  }
}

/// 게이트웨이 `Profile` 모양. 생년월일은 날짜만(`1990-03-05`) 보낸다.
@visibleForTesting
Map<String, dynamic> profileToGateway(UserProfile p) => {
      'name': p.name,
      'birthDate': p.birthDate == null ? null : _date(p.birthDate!),
      'gender': p.gender,
      'job': p.job,
      'heightCm': p.heightCm,
      'weightKg': p.weightKg,
      'agentName': p.agentName,
    };

@visibleForTesting
UserProfile profileFromGateway(Map<String, dynamic> json, String accountId) =>
    UserProfile.fromJson({...json, 'accountId': accountId});

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
