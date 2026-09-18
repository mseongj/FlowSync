cmake_minimum_required(VERSION 3.22.1)

project("llama_flutter" LANGUAGES C CXX)

# ── llama.cpp 소스 경로 ──────────────────────────────────────────────────────
# llama.cpp는 git submodule로 관리됨: android/app/src/main/jni/llama.cpp/
set(LLAMA_DIR "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp")

# ── llama.cpp 빌드 옵션 ──────────────────────────────────────────────────────
option(LLAMA_BUILD_TESTS    "llama: Build tests"    OFF)
option(LLAMA_BUILD_EXAMPLES "llama: Build examples" OFF)
option(LLAMA_BUILD_SERVER   "llama: Build server"   OFF)
option(GGML_OPENMP          "ggml: Use OpenMP"      OFF)

# ARM NEON 가속 (Android ARMv8)
if(ANDROID_ABI STREQUAL "arm64-v8a")
    option(GGML_NEON "ggml: Use NEON" ON)
endif()

# ── llama.cpp 서브프로젝트 포함 ───────────────────────────────────────────────
add_subdirectory("${LLAMA_DIR}" llama_build EXCLUDE_FROM_ALL)

# ── Flutter FFI 브릿지 공유 라이브러리 ───────────────────────────────────────
add_library(
    llama_flutter          # libllama_flutter.so
    SHARED
    "llama_bridge.cpp"     # FlowSync FFI 브릿지 구현체
)

# llama.cpp 헤더 경로
target_include_directories(llama_flutter PRIVATE
    "${LLAMA_DIR}/include"
    "${LLAMA_DIR}/ggml/include"
)

# llama 정적 라이브러리 링크
target_link_libraries(llama_flutter
    llama
    ggml
    android
    log
)

# C++17 표준 사용
target_compile_features(llama_flutter PRIVATE cxx_std_17)
