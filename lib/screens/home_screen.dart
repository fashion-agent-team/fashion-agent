import 'package:flutter/material.dart';

import '../models/weather.dart';
import '../services/speech_service.dart';
import '../services/weather_service.dart';

/// 첫 화면. 시각장애인 사용자를 위해 화면 전체를 하나의 큰 버튼으로 둔다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.weatherService, this.speechService});

  final WeatherService? weatherService;
  final SpeechService? speechService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SpeechService _speech = widget.speechService ?? SpeechService();
  late final WeatherService _weather =
      widget.weatherService ?? WeatherService();

  Weather? _today;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _speech.speak('패션 에이전트입니다. 화면 아무 곳이나 누르면 오늘의 날씨와 옷차림을 알려드립니다.');
  }

  Future<void> _announceWeather() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _speech.speak('오늘 날씨를 확인하고 있어요.');

    try {
      final weather = await _weather.fetchTodayWeather();
      if (!mounted) return;
      setState(() => _today = weather);
      await _speech.speak(weather.toSpeech());
    } catch (_) {
      if (!mounted) return;
      const message = '날씨를 가져오지 못했어요. 인터넷 연결을 확인하고 다시 눌러 주세요.';
      setState(() => _error = message);
      await _speech.speak(message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _displayText {
    if (_loading) return '날씨 확인 중…';
    if (_error != null) return _error!;
    if (_today != null) return _today!.toDisplayText();
    return '화면을 눌러\n오늘 날씨 듣기';
  }

  String get _semanticsLabel {
    if (_today != null && !_loading) {
      return '${_today!.toSpeech()} 다시 들으려면 두 번 누르세요.';
    }
    return '오늘 날씨와 옷차림 듣기';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        button: true,
        label: _semanticsLabel,
        excludeSemantics: true,
        child: InkWell(
          onTap: _announceWeather,
          child: SizedBox.expand(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _displayText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
