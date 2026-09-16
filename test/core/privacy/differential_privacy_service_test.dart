import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_sync/core/privacy/differential_privacy_service.dart';

void main() {
  group('DifferentialPrivacyService', () {
    // ──────────────────────────────────────────────────────────────────────
    // Laplace 분포 통계 검증
    // ──────────────────────────────────────────────────────────────────────
    group('injectTimeNoise — 라플라스 분포 통계', () {
      test('ε=1.0: 충분한 샘플 기준 평균 ≈ 0 (±10분 허용)', () {
        const n = 500;
        const epsilon = 1.0;
        final base = DateTime(2026, 9, 16, 14);

        var sumDiff = 0.0;
        for (var i = 0; i < n; i++) {
          final noised = DifferentialPrivacyService.injectTimeNoise(
            base,
            epsilon: epsilon,
          );
          sumDiff += noised.difference(base).inSeconds;
        }
        final meanMinutes = sumDiff / n / 60;
        // 평균은 0에 가까워야 함 (라플라스는 대칭 분포)
        expect(meanMinutes.abs(), lessThan(10.0),
            reason: 'ε=1.0 평균 편차가 10분 이내여야 함');
      });

      test('ε=0.1 (강한 보호): 표준편차가 ε=5.0 대비 더 큼', () {
        const n = 200;
        final base = DateTime(2026, 9, 16, 14);

        double stdDev(double epsilon) {
          final diffs = <double>[];
          for (var i = 0; i < n; i++) {
            final noised = DifferentialPrivacyService.injectTimeNoise(
              base,
              epsilon: epsilon,
            );
            diffs.add(noised.difference(base).inSeconds.toDouble());
          }
          final mean = diffs.reduce((a, b) => a + b) / n;
          final variance =
              diffs.map((d) => math.pow(d - mean, 2)).reduce((a, b) => a + b) /
                  n;
          return math.sqrt(variance);
        }

        final stdLowEps = stdDev(0.1);
        final stdHighEps = stdDev(5.0);
        // 낮은 epsilon = 높은 노이즈 = 더 큰 표준편차
        expect(stdLowEps, greaterThan(stdHighEps),
            reason: 'ε=0.1 표준편차 > ε=5.0 표준편차');
      });
    });

    // ──────────────────────────────────────────────────────────────────────
    // 시간 역전 방지
    // ──────────────────────────────────────────────────────────────────────
    group('injectEventTimeNoise — 시간 순서 보장', () {
      test('endTime은 항상 startTime + 15분 이후', () {
        final start = DateTime(2026, 9, 16, 14);
        final end = DateTime(2026, 9, 16, 14, 30);

        for (var i = 0; i < 100; i++) {
          final (noisedStart, noisedEnd) =
              DifferentialPrivacyService.injectEventTimeNoise(start, end);
          expect(
            noisedEnd.isAfter(noisedStart.add(const Duration(minutes: 14))),
            isTrue,
            reason: 'endTime이 startTime+15분 이상이어야 함',
          );
        }
      });
    });

    // ──────────────────────────────────────────────────────────────────────
    // 과거 시간 방지 가드
    // ──────────────────────────────────────────────────────────────────────
    group('guardAgainstPast', () {
      test('노이즈로 과거가 된 경우 원본 반환', () {
        final original = DateTime.now().add(const Duration(hours: 2));
        // 극단적 과거로 밀어버린 가상의 noisedTime
        final pastTime = DateTime.now().subtract(const Duration(hours: 1));

        final result =
            DifferentialPrivacyService.guardAgainstPast(pastTime, original);
        expect(result, equals(original));
      });

      test('노이즈 후 미래이면 그대로 반환', () {
        final original = DateTime.now().add(const Duration(hours: 2));
        final futureTime = DateTime.now().add(const Duration(hours: 3));

        final result =
            DifferentialPrivacyService.guardAgainstPast(futureTime, original);
        expect(result, equals(futureTime));
      });
    });

    // ──────────────────────────────────────────────────────────────────────
    // 위치 정밀도 강등
    // ──────────────────────────────────────────────────────────────────────
    group('degradeLocationPrecision', () {
      test('LOC 토큰 2개 이하: 그대로 반환', () {
        final tokenMap = {
          '[PERSON_1]': '민지',
          '[LOC_1]': '강남역',
          '[LOC_2]': '스타벅스',
        };
        final result =
            DifferentialPrivacyService.degradeLocationPrecision(tokenMap);
        expect(result['[LOC_1]'], equals('강남역'));
        expect(result['[LOC_2]'], equals('스타벅스'));
      });

      test('LOC 토큰 3개 이상: 마스킹 처리', () {
        final tokenMap = {
          '[LOC_1]': '강남역',
          '[LOC_2]': '스타벅스',
          '[LOC_3]': '선릉역',
        };
        final result =
            DifferentialPrivacyService.degradeLocationPrecision(tokenMap);
        expect(result['[LOC_1]'], equals('[위치 정보 보호됨]'));
        expect(result['[LOC_2]'], equals('[위치 정보 보호됨]'));
        expect(result['[LOC_3]'], equals('[위치 정보 보호됨]'));
      });
    });
  });
}
