# ML Kit 모델 묶음

google_mlkit 1.0.x는 Swift Package Manager로 ML Kit(d-date/google-mlkit-swiftpm 9.0.2)을 씁니다.
SwiftPM은 바이너리 안의 모델 묶음을 앱에 넣지 못해서, 여기 있는 `.bundle`을 Runner 타깃의 Copy Bundle Resources로 직접 넣습니다.
빠지면 카메라에서 물체·얼굴·자세 찾기를 시작하는 순간 앱이 꺼집니다(`+[MLKCommonObjectDetectorOptions initialize]` 예외).

| 묶음 | 쓰는 곳 |
| --- | --- |
| GoogleMVFaceDetectorResources | 얼굴 찾기 |
| MLKitObjectDetectionResources, MLKitObjectDetectionCommonResources | 물체(옷) 찾기 |
| MLKitPoseDetectionFastResources, MLKitPoseDetectionCommonResources, MLKitXenoResources | 자세(몸) 찾기 |

Other Linker Flags에 `-ObjC`, `-all_load`도 필요합니다. ML Kit 버전을 올리면 같은 버전 릴리스에서 묶음을 다시 받으세요.
