import '../models/garment.dart';
import '../models/weather.dart';
import 'korean.dart';

/// 체감 온도에 맞는 겉옷 안내. 기온 구간은 [Weather.clothingAdvice]와 같다.
String? outerAdvice(Weather weather) {
  final t = weather.apparentTemperature;
  final why = '체감 온도가 ${ira(spokenDegrees(t))}서';
  if (t >= 20) return null;
  if (t >= 17) return '$why 얇은 가디건을 챙기면 좋아요.';
  if (t >= 12) return '$why 자켓이나 가디건을 걸치세요.';
  if (t >= 9) return '$why 트렌치코트나 야상 같은 겉옷이 필요해요.';
  if (t >= 5) return '$why 코트처럼 따뜻한 겉옷이 필요해요.';
  return '$why 패딩처럼 아주 따뜻한 겉옷이 필요해요.';
}

/// 고른 옷이 오늘 날씨에 맞지 않을 때의 주의. 재질은 사진 추정이라 단정하지 않는다.
List<String> weatherWarnings(Weather weather, List<Garment> garments) {
  final t = weather.apparentTemperature;
  final warnings = <String>[];
  for (final g in garments) {
    final material = g.material ?? '';
    final warm = material.contains('니트') ||
        material.contains('패딩') ||
        material.contains('울');
    final cool = material.contains('린넨') ||
        g.name.contains('반팔') ||
        g.name.contains('반바지');
    if (warm && t >= 23) {
      warnings.add('${iGa(g.name)} 따뜻한 소재 같아서 오늘은 더울 수 있어요.');
    } else if (cool && t < 15) {
      warnings.add('${eunNeun(g.name)} 오늘 기온에 추울 수 있어요.');
    }
  }
  if (weather.needsUmbrella) warnings.add('비 소식이 있으니 우산을 챙기세요.');
  return warnings;
}
