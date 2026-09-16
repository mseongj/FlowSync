import 'dart:math' as math;

/// 온디바이스 차분 프라이버시(Differential Privacy) 서비스.
///
/// 가이드 Module 1 Q1 수식 구현:
///   Noise ~ Laplace(0, Δf / ε)
///
/// - [epsilon]: 프라이버시 강도 파라미터 (작을수록 강한 보호, 클수록 정확도 우선)
///             FlowSync 기본값: 1.0 (균형점)
/// - [sensitivity]: 글로벌 민감도 Δf (기본: 60분 = 3600초)
class DifferentialPrivacyService {
  DifferentialPrivacyService._();

  /// 앱 고정 epsilon 값 (ε = 1.0: 균형 보호)
  static const double defaultEpsilon = 1.0;

  /// 글로벌 민감도: 이동 시간 최대 60분(3600초)
  static const double defaultSensitivitySeconds = 3600.0;

  /// 위치 정밀도 강등 레벨
  static const int _locationMaskThreshold = 3; // LOC 토큰 ≥ 3개면 마스킹

  static final _rng = math.Random.secure();

  // ──────────────────────────────────────────────────────────────────────────
  // Laplace Noise Sampler
  // ──────────────────────────────────────────────────────────────────────────

  /// 라플라스 분포에서 노이즈 샘플 생성.
  ///
  /// Laplace(0, b) 역CDF 샘플링:
  ///   X = -b * sgn(U) * ln(1 - 2|U - 0.5|)  (U ~ Uniform[0,1))
  static double _sampleLaplace({required double scale}) {
    // U ∈ (0, 1) — 0과 1 제외해 log 안정성 확보
    final u = _rng.nextDouble() - 0.5;
    if (u == 0) return 0;
    return -scale * u.sign * math.log(1 - 2 * u.abs());
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// 일정 시작/종료 시간에 Laplace 노이즈를 가산하여 반환.
  ///
  /// 예: epsilon=1.0, sensitivity=3600s → 표준편차 ≈ 3600s (최대 ±1시간 흔들림)
  /// 하지만 실제 분포는 중앙에 집중되어 평균적으로 ±수 분 수준.
  static DateTime injectTimeNoise(
    DateTime original, {
    double epsilon = defaultEpsilon,
    double sensitivitySeconds = defaultSensitivitySeconds,
  }) {
    final scale = sensitivitySeconds / epsilon;
    final noiseSeconds = _sampleLaplace(scale: scale);
    // 노이즈를 분 단위로 반올림하여 자연스럽게 표현
    final noisedMinutes = (noiseSeconds / 60).round();
    return original.add(Duration(minutes: noisedMinutes));
  }

  /// 시작/종료 시간 쌍에 노이즈를 주입하되, 순서 역전(endTime < startTime)을 방지.
  ///
  /// 반환값: `(noisedStart, noisedEnd)` 튜플
  static (DateTime start, DateTime end) injectEventTimeNoise(
    DateTime startTime,
    DateTime endTime, {
    double epsilon = defaultEpsilon,
  }) {
    final noisedStart = injectTimeNoise(startTime, epsilon: epsilon);
    var noisedEnd = injectTimeNoise(endTime, epsilon: epsilon);

    // 시간 역전 방지: endTime은 항상 startTime보다 최소 15분 이후
    final minDuration = const Duration(minutes: 15);
    if (!noisedEnd.isAfter(noisedStart.add(minDuration))) {
      noisedEnd = noisedStart.add(minDuration);
    }
    return (noisedStart, noisedEnd);
  }

  /// 위치 토큰 맵의 정밀도를 강등.
  ///
  /// 로직:
  /// - LOC 토큰 1~2개: 유지 (도시 수준 허용)
  /// - LOC 토큰 3개 이상: 전체 마스킹 → '[LOC_MASKED]'로 대체
  ///
  /// 이는 가이드 Q1의 "정밀 주소 마스킹"에 해당.
  static Map<String, String> degradeLocationPrecision(
    Map<String, String> tokenMap,
  ) {
    final locTokens = tokenMap.keys
        .where((k) => k.startsWith('[LOC_'))
        .toList();

    if (locTokens.length < _locationMaskThreshold) {
      return tokenMap; // 정밀도 강등 불필요
    }

    // 3개 이상이면 모든 LOC 토큰을 마스킹 처리
    final result = Map<String, String>.from(tokenMap);
    for (final token in locTokens) {
      result[token] = '[위치 정보 보호됨]';
    }
    return result;
  }

  /// DP 노이즈를 적용한 후 캘린더 이벤트 시간이 과거인지 검증.
  ///
  /// 노이즈가 과도하게 음수로 흘러 과거 시간이 되면 원본 시간 반환.
  static DateTime guardAgainstPast(DateTime noisedTime, DateTime original) {
    final now = DateTime.now();
    if (noisedTime.isBefore(now) && original.isAfter(now)) {
      // 노이즈가 원본을 과거로 밀어낸 경우 → 원본 복원
      return original;
    }
    return noisedTime;
  }
}
