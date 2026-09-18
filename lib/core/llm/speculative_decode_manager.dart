import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flow_sync/core/llm/llama_ffi_service.dart';

/// Speculative Decoding 수락/거절 판정 및 최종 응답 합성 관리자.
///
/// 가이드 Module 2 Q3 구현:
///
/// Accept 조건:
///   P_cloud(T_i) / P_local(T_i) >= U(0,1)
///
/// - Accept: 로컬 Draft 토큰을 그대로 사용 (Cloud 대역폭 절감)
/// - Reject: 최초 거절 지점 이후는 Cloud가 새로 생성한 토큰으로 교체
class SpeculativeDecodeManager {
  SpeculativeDecodeManager._();

  static final _rng = math.Random.secure();

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Draft 토큰 목록과 Cloud 검증 확률을 비교하여 Accept/Reject 판정.
  ///
  /// [draftResult]   : 로컬 Llama-1B가 생성한 Draft 토큰 + logit
  /// [cloudLogprobs] : Cloud LLM이 각 Draft 토큰에 대해 반환한 log 확률
  ///
  /// 반환: [SpeculativeDecodeResult]
  ///   - [acceptedCount]: 수락된 토큰 수 (0이면 전부 거절 → Cloud가 전부 재생성)
  ///   - [acceptanceRate]: 수락률 (0.0 ~ 1.0)
  static SpeculativeDecodeResult evaluate({
    required LlamaDraftResult draftResult,
    required List<double> cloudLogprobs,
  }) {
    final k = math.min(draftResult.tokens.length, cloudLogprobs.length);
    if (k == 0) {
      return const SpeculativeDecodeResult(acceptedCount: 0, acceptanceRate: 0);
    }

    int acceptedCount = 0;

    for (var i = 0; i < k; i++) {
      final pCloud = _softmaxSingle(cloudLogprobs[i]);
      final pLocal = _softmaxSingle(draftResult.logprobs[i]);

      // P_cloud(T_i) / P_local(T_i) >= U(0,1) 조건
      final ratio = pLocal > 0 ? (pCloud / pLocal) : 0.0;
      final threshold = _rng.nextDouble(); // U(0,1)

      if (ratio >= threshold) {
        acceptedCount++;
        debugPrint(
          '🔵 [Speculative] T[$i] ACCEPT '
          '(ratio=${ratio.toStringAsFixed(3)}, threshold=${threshold.toStringAsFixed(3)})',
        );
      } else {
        // 최초 거절 지점 → 이후 토큰 모두 Cloud가 재생성
        debugPrint(
          '🔴 [Speculative] T[$i] REJECT '
          '(ratio=${ratio.toStringAsFixed(3)}, threshold=${threshold.toStringAsFixed(3)}) '
          '→ Cloud 재생성 시작',
        );
        break;
      }
    }

    final acceptanceRate = acceptedCount / k;
    debugPrint(
      '📊 [Speculative] 수락률: ${(acceptanceRate * 100).toStringAsFixed(1)}% '
      '($acceptedCount/$k 토큰 수락)',
    );

    return SpeculativeDecodeResult(
      acceptedCount: acceptedCount,
      acceptanceRate: acceptanceRate,
    );
  }

  /// Draft 결과를 Edge Function 요청 body에 직렬화.
  ///
  /// Edge Function은 이 데이터를 받아 Cloud LLM에 Draft 검증을 요청.
  static Map<String, dynamic> serializeDraft(LlamaDraftResult draft) {
    return {
      'draftTokens': draft.tokens,
      'draftLogprobs': draft.logprobs,
      'draftK': draft.tokens.length,
    };
  }

  /// Cloud 응답에서 Draft 검증 데이터를 추출.
  ///
  /// Edge Function이 `X-FlowSync-Acceptance-Rate` 헤더와
  /// `cloudLogprobs` 필드를 반환하면 이를 파싱.
  static List<double> extractCloudLogprobs(Map<String, dynamic> response) {
    final raw = response['cloudLogprobs'];
    if (raw == null) return [];
    return (raw as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Internal Helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// 단일 logit을 소프트맥스로 변환 (다른 logit 없이 근사).
  /// 실제 확률 추정 목적이 아닌 비교를 위한 정규화.
  static double _softmaxSingle(double logit) {
    // exp(logit) / (1 + exp(logit)) — sigmoid 근사
    return 1.0 / (1.0 + math.exp(-logit));
  }
}

/// Speculative Decoding 판정 결과.
class SpeculativeDecodeResult {
  /// 수락된 Draft 토큰 수.
  /// 이 숫자만큼 Cloud 생성 비용이 절감됨.
  final int acceptedCount;

  /// 수락률 (0.0 ~ 1.0).
  final double acceptanceRate;

  const SpeculativeDecodeResult({
    required this.acceptedCount,
    required this.acceptanceRate,
  });

  /// 모든 Draft 토큰이 수락된 경우 (완전 로컬 처리)
  bool get isFullyAccepted => acceptedCount > 0;

  @override
  String toString() =>
      'SpeculativeDecodeResult(accepted=$acceptedCount, rate=${(acceptanceRate * 100).toStringAsFixed(1)}%)';
}
