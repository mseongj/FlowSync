import 'dart:math' as math;

import 'package:flow_sync/core/privacy/differential_privacy_service.dart';
import 'package:flow_sync/features/nlp/domain/entities/ai_scheduling_response.dart';
import 'package:flow_sync/features/nlp/domain/entities/nlp_command.dart';

/// DP-ICL(Differentially Private In-Context Learning) 합의 엔진.
///
/// 가이드 Module 1 Q2 "Noisy Consensus" 알고리즘 구현:
///
/// 1. 입력 텍스트를 k개 서브셋으로 분할
/// 2. 각 서브셋으로 로컬 파서를 병렬 실행 → 후보 카운트 집계
/// 3. Count(c) + Laplace(1/ε) 노이즈 추가 → argmax 선택
/// 4. 노이즈 카운트 < τ_dp 이면 환각으로 판단 → null 반환(Cloud 경유)
class DpIclConsensus {
  DpIclConsensus._();

  /// 서브셋 분할 수 (k)
  static const int _subsetCount = 3;

  /// 합의 임계값 τ_dp: 과반수 서브셋(≥2/3)이 동의해야 채택
  static const double _consensusThreshold = 2.0;

  /// 앱 고정 epsilon (Q2 노이즈용 — 라플라스 스케일 = 1/ε)
  static const double _epsilon = DifferentialPrivacyService.defaultEpsilon;

  static final _rng = math.Random.secure();

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// [candidates]로부터 Noisy Voting을 수행해 최종 응답을 선택.
  ///
  /// - [candidates]: 각 서브셋에서 나온 로컬 파싱 결과 (null = 파싱 실패)
  /// - 반환값: 신뢰할 수 있는 응답, 또는 null (→ Cloud 경유 필요)
  static AiSchedulingResponse? vote(
    List<AiSchedulingResponse?> candidates,
  ) {
    if (candidates.isEmpty) return null;

    // 1. 후보 카운트 집계 (intent 기준)
    final counts = <String, int>{};
    final responsesByIntent = <String, AiSchedulingResponse>{};

    for (final candidate in candidates) {
      if (candidate == null) continue;
      final intent = candidate.intent;
      counts[intent] = (counts[intent] ?? 0) + 1;
      responsesByIntent[intent] = candidate;
    }

    if (counts.isEmpty) return null;

    // 2. 라플라스 노이즈 가산 (Count(c) + Laplace(1/ε))
    final noisyCounts = counts.map((intent, count) {
      final noise = _sampleLaplace(scale: 1.0 / _epsilon);
      return MapEntry(intent, count + noise);
    });

    // 3. argmax 선택
    final bestIntent = noisyCounts.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    final bestNoisyCount = noisyCounts[bestIntent]!;

    // 4. τ_dp 임계값 검사 — 환각 방지
    if (bestNoisyCount < _consensusThreshold) {
      // 합의 불충분 → null 반환으로 Cloud 경유 유도
      return null;
    }

    return responsesByIntent[bestIntent];
  }

  /// 단일 NlpCommand에서 k개 서브셋으로 나눠 로컬 파서를 실행한 후
  /// Noisy Consensus로 최종 응답 선택.
  ///
  /// [localParser]: 각 서브셋에 적용할 로컬 파싱 함수
  static AiSchedulingResponse? runConsensus(
    NlpCommand command,
    AiSchedulingResponse? Function(NlpCommand subset) localParser,
  ) {
    final subsets = _splitIntoSubsets(command, _subsetCount);
    final candidates = subsets.map(localParser).toList();
    return vote(candidates);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal Helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// 텍스트를 단어 단위로 k개 서브셋으로 분할.
  ///
  /// 각 서브셋은 원본 텍스트의 일부 단어만 포함하되,
  /// 시간 정보(숫자+시)는 모든 서브셋에 포함하여 파싱 안정성 유지.
  static List<NlpCommand> _splitIntoSubsets(
    NlpCommand command,
    int k,
  ) {
    final words = command.tokenizedText.split(RegExp(r'\s+'));
    final timeWords = words
        .where((w) => RegExp(r'\d+시|\d+:\d+|오늘|내일|morning|evening').hasMatch(w))
        .toList();

    final nonTimeWords = words
        .where(
          (w) => !RegExp(r'\d+시|\d+:\d+|오늘|내일|morning|evening').hasMatch(w),
        )
        .toList();

    final subsets = <NlpCommand>[];
    final chunkSize = (nonTimeWords.length / k).ceil();

    for (var i = 0; i < k; i++) {
      final start = i * chunkSize;
      if (start >= nonTimeWords.length) {
        // 서브셋이 부족하면 원본 복사로 채움
        subsets.add(command);
        continue;
      }
      final end = math.min(start + chunkSize, nonTimeWords.length);
      final subsetWords = [...timeWords, ...nonTimeWords.sublist(start, end)];
      final subsetText = subsetWords.join(' ');

      subsets.add(
        NlpCommand(
          rawText: command.rawText,
          tokenizedText: subsetText,
          tokenMap: command.tokenMap,
          timestamp: command.timestamp,
        ),
      );
    }

    return subsets;
  }

  static double _sampleLaplace({required double scale}) {
    final u = _rng.nextDouble() - 0.5;
    if (u == 0) return 0;
    return -scale * u.sign * math.log(1 - 2 * u.abs());
  }
}
