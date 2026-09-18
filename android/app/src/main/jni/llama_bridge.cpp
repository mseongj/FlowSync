/**
 * llama_bridge.cpp
 *
 * FlowSync <-> llama.cpp Flutter FFI 브릿지.
 * Flutter의 dart:ffi에서 호출하는 C 함수들을 정의합니다.
 *
 * 기능:
 *   - 모델 로드 / 해제
 *   - Draft 토큰 k개 생성 (Speculative Decoding용)
 *   - 메모리 안전 클린업
 */

#include <cstring>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include <android/log.h>

// llama.cpp 공개 헤더
#include "llama.h"

#define LOG_TAG "FlowSync_LlamaBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ── 전역 모델 상태 ─────────────────────────────────────────────────────────
static llama_model*   g_model   = nullptr;
static llama_context* g_ctx     = nullptr;

extern "C" {

// ── 1. 모델 로드 ───────────────────────────────────────────────────────────
/**
 * GGUF 파일을 로드하여 전역 모델/컨텍스트를 초기화.
 *
 * @param model_path  GGUF 파일의 절대 경로 (앱 문서 디렉토리 내)
 * @param n_ctx       컨텍스트 윈도우 크기 (기본: 2048)
 * @return  0 = 성공, -1 = 실패
 */
int32_t llama_flutter_load(const char* model_path, int32_t n_ctx) {
    if (g_model != nullptr) {
        LOGI("Model already loaded. Unloading previous model first.");
        if (g_ctx != nullptr) {
            llama_free(g_ctx);
            g_ctx = nullptr;
        }
        llama_model_free(g_model);
        g_model = nullptr;
    }

    LOGI("Loading model from: %s", model_path);

    llama_model_params model_params = llama_model_default_params();
    // GPU 레이어 오프로드 비활성화 (모바일에서 CPU 전용)
    model_params.n_gpu_layers = 0;

    g_model = llama_model_load_from_file(model_path, model_params);
    if (g_model == nullptr) {
        LOGE("Failed to load model from: %s", model_path);
        return -1;
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx     = static_cast<uint32_t>(n_ctx);
    ctx_params.n_batch   = 512;
    ctx_params.n_threads = 4;  // ARM 코어 4개 활용

    g_ctx = llama_init_from_model(g_model, ctx_params);
    if (g_ctx == nullptr) {
        LOGE("Failed to create context.");
        llama_model_free(g_model);
        g_model = nullptr;
        return -1;
    }

    LOGI("Model loaded successfully. n_ctx=%d", n_ctx);
    return 0;
}

// ── 2. 모델 해제 ───────────────────────────────────────────────────────────
/**
 * 전역 모델과 컨텍스트를 메모리에서 해제.
 * 앱 종료 시 또는 메모리 부족 시 호출.
 */
void llama_flutter_free() {
    if (g_ctx   != nullptr) { llama_free(g_ctx);        g_ctx   = nullptr; }
    if (g_model != nullptr) { llama_model_free(g_model); g_model = nullptr; }
    LOGI("Model freed.");
}

// ── 3. Draft 토큰 생성 (Speculative Decoding용) ─────────────────────────────
/**
 * 프롬프트로부터 k개의 Draft 토큰을 생성.
 *
 * @param prompt       입력 프롬프트 (UTF-8 C 문자열)
 * @param k            생성할 Draft 토큰 수 (가이드: k=5)
 * @param out_tokens   출력 버퍼 (호출자가 k * sizeof(int32_t) 만큼 할당)
 * @param out_logprobs 출력 로그 확률 버퍼 (호출자가 k * sizeof(float) 만큼 할당)
 * @return  실제 생성된 토큰 수, 실패 시 -1
 */
int32_t llama_flutter_draft(
    const char* prompt,
    int32_t     k,
    int32_t*    out_tokens,
    float*      out_logprobs
) {
    if (g_model == nullptr || g_ctx == nullptr) {
        LOGE("Model not loaded. Call llama_flutter_load() first.");
        return -1;
    }

    const struct llama_vocab* vocab = llama_model_get_vocab(g_model);
    if (vocab == nullptr) {
        LOGE("Failed to get vocab from model.");
        return -1;
    }

    // 프롬프트 토크나이즈
    const int max_tokens = 1024;
    std::vector<llama_token> input_tokens(max_tokens);
    int n_input = llama_tokenize(
        vocab,
        prompt,
        static_cast<int32_t>(strlen(prompt)),
        input_tokens.data(),
        max_tokens,
        /*add_special=*/true,
        /*parse_special=*/false
    );

    if (n_input < 0) {
        LOGE("Tokenization failed for prompt.");
        return -1;
    }
    input_tokens.resize(n_input);

    // 컨텍스트/메모리 초기화
    llama_memory_clear(llama_get_memory(g_ctx), true);

    // 입력 배치 처리
    llama_batch batch = llama_batch_get_one(input_tokens.data(), n_input);
    if (llama_decode(g_ctx, batch) != 0) {
        LOGE("llama_decode failed for input batch.");
        return -1;
    }

    // k개 Draft 토큰 그리디 샘플링
    int generated = 0;
    const int n_vocab = llama_vocab_n_tokens(vocab);

    for (int i = 0; i < k; ++i) {
        // 로짓에서 greedy 샘플링 (argmax)
        float* logits = llama_get_logits_ith(g_ctx, -1);
        if (logits == nullptr) {
            LOGE("Failed to get logits.");
            break;
        }

        // Argmax 탐색
        llama_token best_token = 0;
        float best_logit = logits[0];
        for (int t = 1; t < n_vocab; ++t) {
            if (logits[t] > best_logit) {
                best_logit = logits[t];
                best_token = static_cast<llama_token>(t);
            }
        }

        out_tokens[i]   = best_token;
        out_logprobs[i] = best_logit;  // 실제 log-prob 아닌 raw logit (근사)

        // EOS 토큰이면 조기 종료
        if (llama_vocab_is_eog(vocab, best_token)) {
            generated = i + 1;
            break;
        }

        // 다음 토큰을 입력으로 디코딩
        llama_batch next_batch = llama_batch_get_one(&best_token, 1);
        if (llama_decode(g_ctx, next_batch) != 0) {
            break;
        }
        generated = i + 1;
    }

    LOGI("Draft generation complete: %d tokens generated.", generated);
    return generated;
}

// ── 4. 모델 로드 여부 확인 ────────────────────────────────────────────────
int32_t llama_flutter_is_loaded() {
    return (g_model != nullptr && g_ctx != nullptr) ? 1 : 0;
}

} // extern "C"
