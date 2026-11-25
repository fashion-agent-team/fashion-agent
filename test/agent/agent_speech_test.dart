import 'package:fashion_agent/agent/agent_speech.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-11-10 확정 대본의 문장 만들기(lib/agent/agent_speech.dart).
void main() {
  test('호칭 뒤 님은 겹치지 않는다', () {
    expect(honorific('진행'), '진행님');
    expect(honorific('진행 님'), '진행 님');
    expect(honorific('선생님'), '선생님');
    expect(returningGreeting('하늘', callName: '진행'),
        '반가워요, 진행님. 저 하늘이에요. 오늘도 같이 준비해 봐요. 필요한 게 있으면 편하게 말씀해 주세요.');
    expect(restoredGreeting('심청이', callName: '진행 님'),
        '다시 만나서 반가워요, 진행 님. 저 심청이예요. 오늘은 뭘 같이 해 볼까요?');
  });
}
