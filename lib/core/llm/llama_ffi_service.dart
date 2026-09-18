import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';

// ── FFI 함수 시그니처 정의 ─────────────────────────────────────────────────
// NativeFunction<...>을 typedef 없이 직접 lookupFunction에 인라인으로 사용

/// Flutter FFI를 통해 llama.cpp 온디바이스 추론을 수행하는 서비스.
///
/// [loadModel] → [generateDraft] → [free] 순서로 사용.
///
/// **주의**: 대용량 GGUF 모델(~700MB)을 메모리에 유지하므로
/// 앱이 백그라운드로 전환될 때 [free]를 호출하여 메모리를 해제하세요.
@lazySingleton
class LlamaFfiService {
  LlamaFfiService();

  // ── FFI 함수 포인터 ──────────────────────────────────────────────────────
  late final int Function(Pointer<Utf8>, int) _load;
  late final void Function() _free;
  late final int Function(Pointer<Utf8>, int, Pointer<Int32>, Pointer<Float>)
      _draft;
  late final int Function() _isLoadedFn;

  bool _initialized = false;

  /// 모델 파일명 (assets/models/ 에 넣은 GGUF 파일 이름)
  static const _modelFileName = 'Llama-3.2-1B-Instruct.Q4_K_M.gguf';

  /// 컨텍스트 크기 (토큰 수)
  static const _nCtx = 2048;

  /// Draft 토큰 수 k (가이드: k=5)
  static const int defaultK = 5;

  // ── 초기화 ────────────────────────────────────────────────────────────────

  /// FFI 라이브러리를 로드하고 함수 포인터를 바인딩.
  /// 앱 시작 시 한 번만 호출.
  void initialize() {
    if (_initialized) return;

    final lib = _openLibrary();

    _load = lib
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32),
          int Function(Pointer<Utf8>, int)
        >('llama_flutter_load');

    _free = lib
        .lookupFunction<Void Function(), void Function()>(
      'llama_flutter_free',
    );

    _draft = lib
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32, Pointer<Int32>, Pointer<Float>),
          int Function(Pointer<Utf8>, int, Pointer<Int32>, Pointer<Float>)
        >('llama_flutter_draft');

    _isLoadedFn = lib
        .lookupFunction<Int32 Function(), int Function()>(
      'llama_flutter_is_loaded',
    );

    _initialized = true;
    debugPrint('🦙 [LlamaFFI] 라이브러리 초기화 완료');
  }

  // ── 모델 로드 ─────────────────────────────────────────────────────────────

  /// GGUF 모델을 앱 문서 디렉토리로 복사하고 로드.
  ///
  /// assets/models/ 에서 앱 데이터 디렉토리로 한 번만 복사 후 재사용.
  Future<bool> loadModel() async {
    _ensureInitialized();

    if (_isLoadedFn() == 1) {
      debugPrint('🦙 [LlamaFFI] 모델 이미 로드됨');
      return true;
    }

    try {
      final modelPath = await _copyModelToDocumentsIfNeeded();
      debugPrint('🦙 [LlamaFFI] 모델 로드 중: $modelPath');

      final pathPtr = modelPath.toNativeUtf8();
      try {
        final result = _load(pathPtr, _nCtx);
        if (result == 0) {
          debugPrint('🦙 [LlamaFFI] 모델 로드 성공');
          return true;
        } else {
          debugPrint('🦙 [LlamaFFI] 모델 로드 실패 (code=$result)');
          return false;
        }
      } finally {
        malloc.free(pathPtr);
      }
    } catch (e) {
      debugPrint('🦙 [LlamaFFI] 모델 로드 예외: $e');
      return false;
    }
  }

  // ── Draft 토큰 생성 ───────────────────────────────────────────────────────

  /// 프롬프트로부터 [k]개의 Draft 토큰과 로그 확률을 생성.
  ///
  /// Speculative Decoding 가이드 Q3:
  ///   "Llama-1B 모델이 K개의 초안 토큰을 고속 생성"
  ///
  /// 반환: [LlamaDraftResult] (토큰 ID 목록 + 로그 확률 목록)
  /// 실패 시 null 반환 → Cloud가 직접 생성
  LlamaDraftResult? generateDraft(String prompt, {int k = defaultK}) {
    _ensureInitialized();

    if (_isLoadedFn() != 1) {
      debugPrint('🦙 [LlamaFFI] generateDraft 호출 실패: 모델 미로드');
      return null;
    }

    final tokensBuf   = calloc<Int32>(k);
    final logprobsBuf = calloc<Float>(k);
    final promptPtr   = prompt.toNativeUtf8();

    try {
      final generated = _draft(promptPtr, k, tokensBuf, logprobsBuf);
      if (generated <= 0) {
        debugPrint('🦙 [LlamaFFI] Draft 생성 실패 (generated=$generated)');
        return null;
      }

      final tokens = List<int>.generate(generated, (i) => tokensBuf[i]);
      final logprobs =
          List<double>.generate(generated, (i) => logprobsBuf[i].toDouble());

      debugPrint('🦙 [LlamaFFI] Draft 생성 완료: $generated 토큰 → $tokens');
      return LlamaDraftResult(tokens: tokens, logprobs: logprobs);
    } finally {
      calloc
        ..free(tokensBuf)
        ..free(logprobsBuf)
        ..free(promptPtr);
    }
  }

  // ── 모델 해제 ─────────────────────────────────────────────────────────────

  /// 메모리에서 모델을 해제. 백그라운드 전환 시 호출 권장.
  void free() {
    if (!_initialized) return;
    _free();
    debugPrint('🦙 [LlamaFFI] 모델 해제 완료');
  }

  bool get isLoaded => _initialized && _isLoadedFn() == 1;

  // ── 내부 헬퍼 ─────────────────────────────────────────────────────────────

  DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libllama_flutter.so');
    } else if (Platform.isIOS) {
      // iOS는 정적 링크 (Runner 번들에 포함)
      return DynamicLibrary.process();
    }
    throw UnsupportedError(
      'LlamaFfiService는 Android/iOS만 지원합니다. '
      '현재 플랫폼: ${Platform.operatingSystem}',
    );
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'LlamaFfiService.initialize()를 먼저 호출해야 합니다.',
      );
    }
  }

  /// assets에서 앱 데이터 디렉토리로 모델 파일을 복사 (최초 1회).
  Future<String> _copyModelToDocumentsIfNeeded() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final targetPath = '${docsDir.path}/$_modelFileName';
    final targetFile = File(targetPath);

    if (targetFile.existsSync()) {
      debugPrint('🦙 [LlamaFFI] 캐시된 모델 사용: $targetPath');
      return targetPath;
    }

    debugPrint('🦙 [LlamaFFI] assets에서 모델 복사 중...');
    final bytes = await rootBundle.load('assets/models/$_modelFileName');
    await targetFile.writeAsBytes(
      bytes.buffer.asUint8List(),
      flush: true,
    );
    debugPrint('🦙 [LlamaFFI] 모델 복사 완료: $targetPath');
    return targetPath;
  }
}

/// Speculative Decoding용 Draft 결과.
class LlamaDraftResult {
  /// 생성된 Draft 토큰 ID 목록
  final List<int> tokens;

  /// 각 토큰의 Raw logit (로그 확률 근사값)
  final List<double> logprobs;

  const LlamaDraftResult({
    required this.tokens,
    required this.logprobs,
  });

  @override
  String toString() =>
      'LlamaDraftResult(tokens: $tokens, logprobs: $logprobs)';
}
