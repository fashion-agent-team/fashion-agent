import 'dart:typed_data';

import '../models/clothes_scan.dart';
import 'vision_service.dart';

/// 프록시 없이 흐름을 끝까지 돌려 보기 위한 가짜 비전 AI.
///
/// 촬영 목적마다 정해 둔 응답을 차례로 돌려준다. 응답이 바닥나면 마지막 것을 반복한다.
class FakeVisionService implements VisionService {
  FakeVisionService({Map<ScanPurpose, List<ClothesScan>>? scripted})
      : _scripted = scripted ?? defaultScript;

  final Map<ScanPurpose, List<ClothesScan>> _scripted;
  final _calls = <ScanPurpose, int>{};

  @override
  Future<ClothesScan> describe(Uint8List jpeg, ScanPurpose purpose) async {
    final scans = _scripted[purpose] ?? const [];
    if (scans.isEmpty) return const ClothesScan(garments: []);
    final i = _calls[purpose] ?? 0;
    _calls[purpose] = i + 1;
    return scans[i < scans.length ? i : scans.length - 1];
  }

  /// 데모용 시나리오: 빨간 셔츠 + 초록 바지 → 경고 → 옷장에서 베이지 바지 찾기 → 확인.
  static final defaultScript = <ScanPurpose, List<ClothesScan>>{
    ScanPurpose.outfit: [
      ClothesScan.fromJson({
        'garments': [
          {
            'id': 'top-1',
            'category': 'top',
            'name': '셔츠',
            'colorName': '빨간색',
            'colorFamily': 'red',
            'tone': 'mid',
            'pattern': null,
            'material': '면 같음',
            'notes': '약간 구김 있음',
            'box': {'x': 0.1, 'y': 0.1, 'w': 0.8, 'h': 0.4},
            'confidence': 0.9,
          },
          {
            'id': 'bottom-1',
            'category': 'bottom',
            'name': '면바지',
            'colorName': '초록색',
            'colorFamily': 'green',
            'tone': 'dark',
            'box': {'x': 0.2, 'y': 0.55, 'w': 0.6, 'h': 0.4},
            'confidence': 0.88,
          },
        ],
        'framing': null,
        'lighting': 'ok',
      }),
    ],
    ScanPurpose.closet: [
      ClothesScan.fromJson({
        'garments': [
          {
            'id': 'closet-1',
            'category': 'bottom',
            'name': '청바지',
            'colorName': '파란색',
            'colorFamily': 'blue',
            'tone': 'mid',
            'material': '데님 같음',
            'box': {'x': 0.05, 'y': 0.5, 'w': 0.2, 'h': 0.45},
            'confidence': 0.85,
          },
          {
            'id': 'closet-2',
            'category': 'bottom',
            'name': '면바지',
            'colorName': '베이지',
            'colorFamily': 'beige',
            'tone': 'light',
            'box': {'x': 0.3, 'y': 0.5, 'w': 0.2, 'h': 0.45},
            'confidence': 0.9,
          },
          {
            'id': 'closet-3',
            'category': 'top',
            'name': '니트',
            'colorName': '회색',
            'colorFamily': 'gray',
            'tone': 'mid',
            'material': '니트 같음',
            'box': {'x': 0.6, 'y': 0.05, 'w': 0.3, 'h': 0.4},
            'confidence': 0.8,
          },
        ],
        'framing': null,
        'lighting': 'ok',
      }),
    ],
    ScanPurpose.check: [
      ClothesScan.fromJson({
        'garments': [
          {
            'id': 'check-1',
            'category': 'bottom',
            'name': '면바지',
            'colorName': '베이지',
            'colorFamily': 'beige',
            'tone': 'light',
            'confidence': 0.9,
          },
        ],
        'framing': null,
        'lighting': 'ok',
      }),
    ],
  };
}
