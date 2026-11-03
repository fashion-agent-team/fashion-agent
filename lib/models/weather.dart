/// 오늘의 날씨·기온 정보. 음성 안내 문장과 옷차림 힌트를 만든다.
class Weather {
  const Weather({
    required this.temperature,
    required this.apparentTemperature,
    required this.minTemperature,
    required this.maxTemperature,
    required this.weatherCode,
    required this.precipitationProbability,
    this.isFallbackLocation = false,
  });

  /// Open-Meteo 예보 응답(current + daily)을 읽는다.
  factory Weather.fromOpenMeteo(Map<String, dynamic> json,
      {bool isFallbackLocation = false}) {
    final current = json['current'] as Map<String, dynamic>;
    final daily = json['daily'] as Map<String, dynamic>;
    double firstOf(String key) => (daily[key] as List).first.toDouble();
    final rainChance = (daily['precipitation_probability_max'] as List).first;

    return Weather(
      temperature: (current['temperature_2m'] as num).toDouble(),
      apparentTemperature: (current['apparent_temperature'] as num).toDouble(),
      minTemperature: firstOf('temperature_2m_min'),
      maxTemperature: firstOf('temperature_2m_max'),
      weatherCode: (current['weather_code'] as num).toInt(),
      precipitationProbability: (rainChance as num?)?.toInt() ?? 0,
      isFallbackLocation: isFallbackLocation,
    );
  }

  final double temperature;
  final double apparentTemperature;
  final double minTemperature;
  final double maxTemperature;

  /// WMO 날씨 코드. https://open-meteo.com/en/docs 의 "WMO Weather interpretation codes" 참고.
  final int weatherCode;

  /// 오늘 최대 강수 확률(%).
  final int precipitationProbability;

  /// 위치를 못 얻어 기본 위치(서울)로 조회했는지.
  final bool isFallbackLocation;

  String get condition {
    final code = weatherCode;
    if (code == 0) return '맑음';
    if (code <= 2) return '구름 조금';
    if (code == 3) return '흐림';
    if (code == 45 || code == 48) return '안개';
    if (code >= 51 && code <= 57) return '이슬비';
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return '비';
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) return '눈';
    if (code >= 95) return '뇌우';
    return '알 수 없음';
  }

  bool get needsUmbrella =>
      precipitationProbability >= 50 || condition == '비' || condition == '뇌우';

  /// 기온별 옷차림 힌트. 코디 추천의 기본 재료로 쓴다.
  String get clothingAdvice {
    final t = apparentTemperature;
    if (t >= 28) return '반팔과 반바지처럼 가볍고 얇은 옷이 좋아요.';
    if (t >= 23) return '반팔이나 얇은 셔츠에 면바지가 좋아요.';
    if (t >= 20) return '얇은 긴팔이나 가디건이 좋아요.';
    if (t >= 17) return '얇은 니트나 맨투맨에 긴바지가 좋아요.';
    if (t >= 12) return '자켓이나 가디건을 걸치세요.';
    if (t >= 9) return '트렌치코트나 야상 같은 겉옷이 필요해요.';
    if (t >= 5) return '코트와 히트텍처럼 따뜻한 옷이 좋아요.';
    return '패딩과 목도리처럼 아주 따뜻한 옷이 필요해요.';
  }

  /// TTS로 읽기 좋게 만든 안내 문장.
  String toSpeech() {
    final buffer = StringBuffer();
    if (isFallbackLocation) buffer.write('현재 위치를 알 수 없어 서울 기준으로 알려드려요. ');
    buffer
      ..write('오늘 날씨는 $condition입니다. ')
      ..write('지금 기온은 ${spokenDegrees(temperature)}, ')
      ..write('체감 온도는 ${spokenDegrees(apparentTemperature)}입니다. ')
      ..write('최저 ${spokenDegrees(minTemperature)}, ')
      ..write('최고 ${spokenDegrees(maxTemperature)}입니다. ')
      ..write('강수 확률은 $precipitationProbability퍼센트입니다. ');
    if (needsUmbrella) buffer.write('우산을 챙기세요. ');
    buffer.write(clothingAdvice);
    return buffer.toString();
  }

  /// 화면에 보여 줄 짧은 요약.
  String toDisplayText() => '$condition ${temperature.round()}°\n'
      '최저 ${minTemperature.round()}° / 최고 ${maxTemperature.round()}°\n'
      '강수 확률 $precipitationProbability%';
}

/// "-3" 같은 숫자를 TTS가 자연스럽게 읽도록 "영하 3도"로 바꾼다.
String spokenDegrees(double value) {
  final rounded = value.round();
  return rounded < 0 ? '영하 ${-rounded}도' : '$rounded도';
}
