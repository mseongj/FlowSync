import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

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
/// **스레딩**: 모델 로드 / Draft 생성 / 해제는 수백 ms~수 초가 걸리는
/// 동기 네이티브 호출이므로 [Isolate.run]으로 백그라운드 isolate에서 실행한다.
/// 네이티브 모델 상태(g_model, g_ctx)는 프로세스 전역이라 isolate가 달라도 공유되며,
/// 동시 접근은 Dart 측 직렬화 큐 + 네이티브 mutex로 이중 보호한다.
///
/// **주의**: 대용량 GGUF 모델(~700MB)을 메모리에 유지하므로
/// 앱이 백그라운드로 전환될 때 [free]를 호출하여 메모리를 해제하세요.
@lazySingleton
class LlamaFfiService {
  LlamaFfiService();

  // ── FFI 함수 포인터 (메인 isolate: 가벼운 상태 조회 전용) ─────────────────
  late final int Function() _isLoadedFn;

  bool _initialized = false;

  /// 네이티브 호출 직렬화 큐 (load/draft/free가 겹치지 않도록)
  Future<void> _queue = Future<void>.value();

  /// 모델 파일명 (assets/models/ 에 넣은 GGUF 파일 이름)
  static const _modelFileName = 'Llama-3.2-1B-Instruct-Q4_K_M.gguf';

  /// 컨텍스트 크기 (토큰 수)
  static const _nCtx = 2048;

  /// Draft 토큰 수 k (가이드: k=5)
  static const int defaultK = 5;

  // ── 초기화 ────────────────────────────────────────────────────────────────

  /// FFI 라이브러리를 열어 심볼 존재를 확인. 앱 시작 시 한 번만 호출.
  void initialize() {
    if (_initialized) return;

    final lib = _openLibrary();

    // 무거운 함수는 워커 isolate에서 각자 lookup하지만,
    // 여기서 미리 lookup해 심볼 누락을 앱 시작 시점에 감지한다.
    lib
      ..lookup<NativeFunction<Int32 Function(Pointer<Utf8>, Int32)>>(
        'llama_flutter_load',
      )
      ..lookup<NativeFunction<Void Function()>>('llama_flutter_free')
      ..lookup<
          NativeFunction<
              Int32 Function(
                Pointer<Utf8>,
                Int32,
                Pointer<Int32>,
                Pointer<Float>,
              )>>('llama_flutter_draft');

    _isLoadedFn = lib.lookupFunction<Int32 Function(), int Function()>(
      'llama_flutter_is_loaded',
    );

    _initialized = true;
    debugPrint('🦙 [LlamaFFI] 라이브러리 초기화 완료');
  }

  // ── 모델 로드 ─────────────────────────────────────────────────────────────

  /// GGUF 모델을 앱 문서 디렉토리로 복사하고 백그라운드 isolate에서 로드.
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
      debugPrint('🦙 [LlamaFFI] 모델 로드 중 (background isolate): $modelPath');

      final result = await _serialized(
        () => Isolate.run(() => _nativeLoad(modelPath, _nCtx)),
      );
      if (result == 0) {
        debugPrint('🦙 [LlamaFFI] 모델 로드 성공');
        return true;
      }
      debugPrint('🦙 [LlamaFFI] 모델 로드 실패 (code=$result)');
      return false;
    } catch (e) {
      debugPrint('🦙 [LlamaFFI] 모델 로드 예외: $e');
      return false;
    }
  }

  // ── Draft 토큰 생성 ───────────────────────────────────────────────────────

  /// 프롬프트로부터 [k]개의 Draft 토큰과 로그 확률을 백그라운드 isolate에서 생성.
  ///
  /// Speculative Decoding 가이드 Q3:
  ///   "Llama-1B 모델이 K개의 초안 토큰을 고속 생성"
  ///
  /// 반환: [LlamaDraftResult] (토큰 ID 목록 + 로그 확률 목록)
  /// 실패 시 null 반환 → Cloud가 직접 생성
  Future<LlamaDraftResult?> generateDraft(
    String prompt, {
    int k = defaultK,
  }) async {
    _ensureInitialized();

    if (_isLoadedFn() != 1) {
      debugPrint('🦙 [LlamaFFI] generateDraft 호출 실패: 모델 미로드');
      return null;
    }

    final result = await _serialized(
      () => Isolate.run(() => _nativeDraft(prompt, k)),
    );
    if (result == null) {
      debugPrint('🦙 [LlamaFFI] Draft 생성 실패');
      return null;
    }
    debugPrint('🦙 [LlamaFFI] Draft 생성 완료: ${result.tokens.length} 토큰 → ${result.tokens}');
    return result;
  }

  // ── 모델 해제 ─────────────────────────────────────────────────────────────

  /// 메모리에서 모델을 해제. 백그라운드 전환 시 호출 권장.
  /// 진행 중인 Draft 생성이 끝난 뒤 실행된다.
  Future<void> free() async {
    if (!_initialized) return;
    await _serialized(() => Isolate.run(_nativeFree));
    debugPrint('🦙 [LlamaFFI] 모델 해제 완료');
  }

  bool get isLoaded => _initialized && _isLoadedFn() == 1;

  // ── 내부 헬퍼 ─────────────────────────────────────────────────────────────

  /// 네이티브 작업을 순차 실행 (이전 작업 실패와 무관하게 다음 작업 진행).
  Future<T> _serialized<T>(Future<T> Function() task) {
    final next = _queue.then((_) => task());
    _queue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  static DynamicLibrary _openLibrary() {
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

  // ── 워커 isolate 진입점 (static: this를 캡처하지 않도록) ──────────────────

  static int _nativeLoad(String modelPath, int nCtx) {
    final load = _openLibrary().lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int)>('llama_flutter_load');
    final pathPtr = modelPath.toNativeUtf8();
    try {
      return load(pathPtr, nCtx);
    } finally {
      malloc.free(pathPtr);
    }
  }

  static void _nativeFree() {
    _openLibrary()
        .lookupFunction<Void Function(), void Function()>('llama_flutter_free')();
  }

  static LlamaDraftResult? _nativeDraft(String prompt, int k) {
    final draft = _openLibrary().lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, Pointer<Int32>, Pointer<Float>),
        int Function(Pointer<Utf8>, int, Pointer<Int32>, Pointer<Float>)>(
      'llama_flutter_draft',
    );

    final tokensBuf = calloc<Int32>(k);
    final logprobsBuf = calloc<Float>(k);
    final promptPtr = prompt.toNativeUtf8(allocator: calloc);

    try {
      final generated = draft(promptPtr, k, tokensBuf, logprobsBuf);
      if (generated <= 0) return null;

      return LlamaDraftResult(
        tokens: List<int>.generate(generated, (i) => tokensBuf[i]),
        logprobs: List<double>.generate(
          generated,
          (i) => logprobsBuf[i].toDouble(),
        ),
      );
    } finally {
      calloc
        ..free(tokensBuf)
        ..free(logprobsBuf)
        ..free(promptPtr);
    }
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
    // 임시 파일에 쓴 뒤 rename → 복사 도중 앱이 종료돼도 손상 파일이 캐시되지 않음
    final tmpFile = File('$targetPath.part');
    await tmpFile.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    await tmpFile.rename(targetPath);
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
