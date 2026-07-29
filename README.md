# 🗓️ FlowSync (플로우싱크)

> **Secure & Intelligent Family Calendar Hub**  
> 완벽한 프라이버시가 보장되는 종단간 암호화(E2EE) 기반의 지능형 가족 캘린더 및 자동화 생태계입니다.

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)
![Gemini](https://img.shields.io/badge/Gemini_2.5_Flash-8E75B2?style=for-the-badge&logo=googlebard&logoColor=white)
![E2EE](https://img.shields.io/badge/Security-E2EE_&_Zero_Knowledge-black?style=for-the-badge)

## ✨ 핵심 기능 및 아키텍처 (Core Features & Architecture)

FlowSync는 단순한 스케줄링 앱을 넘어, 최상위 수준의 보안과 오프라인 복원력, 그리고 MLOps 수준의 AI 라우팅 기술이 집약된 엔터프라이즈급 프로덕트입니다.

### 🛡️ 1. 하이브리드 종단간 암호화 (E2EE & Memory Security)
* **Envelope Encryption:** 대용량 데이터는 모바일 기기의 하드웨어 가속(AES-GCM-256)으로 암호화하고, 가족 간 키 교환은 속도가 빠른 타원곡선 암호(ECC/ECDH)를 사용합니다.
* **Zero-Knowledge Sync:** 6자리 PIN을 Argon2 KDF로 파생시켜, 클라우드 관리자조차 사용자의 비밀 일정을 들여다볼 수 없습니다.
* **Deterministic RAM Overwrite:** 앱이 백그라운드로 전환될 때 메모리 덤프 공격을 막기 위해, RAM에 상주하는 마스터 키 배열과 PII 데이터를 명시적으로 덮어써서 파기(Zeroing-out)합니다.

### 🤖 2. 영지식(Zero-Knowledge) AI 스케줄링 어시스턴트
* **로컬 PII 마스킹:** 스마트폰 내부에서 이름과 장소 같은 민감한 개인정보를 토큰(`[PER_1]`, `[LOC_1]`)으로 치환한 뒤 클라우드로 전송하여 프라이버시 유출을 원천 차단합니다.
* **Hybrid LLM Routing:** Supabase Edge Function 내부에 커스텀 라우터를 구현하여, 단순 일정은 `Gemini 2.5 Flash-Lite`로(비용 및 속도 최적화), 복잡한 가족 일정 조율은 `Gemini 2.5 Flash`로 동적 할당합니다.
* **Client-Side Circuit Breaker:** LLM API 장애 시 즉시 서킷을 오픈하여 0초 만에 수동 입력 UI로 우아하게 성능을 저하시킵니다(Graceful Degradation).

### 📶 3. 완벽한 오프라인 복원력 (Offline-First)
* **Optimistic UI:** 네트워크가 단절된 환경에서도 일정을 생성 및 수정할 수 있습니다. 
* **SQLite Sync Queue:** 로컬 데이터베이스에 암호화된 명령 큐(Queue)를 쌓아두고, 네트워크가 복구되면 백그라운드에서 자동으로 Supabase 서버와 동기화합니다.

---

## 🛠️ 기술 스택 (Tech Stack)

### Frontend (App)
* **Framework:** Flutter (Cross-platform)
* **State Management:** BLoC (`flutter_bloc`)
* **Routing:** Hybrid Routing (`go_router` for deep linking + `Navigator` for bottom sheets/dialogs)
* **Security:** `cryptography_flutter`, `flutter_secure_storage`, `local_auth`

### Backend & AI
* **Database & Auth:** Supabase (PostgreSQL, GoTrue)
* **Edge Functions:** Deno / TypeScript
* **AI Orchestration:** Google `@google/genai` SDK
* **LLM:** Gemini 2.5 Flash & Flash-Lite

---

## 🚀 시작하기 (Getting Started)

### 1. 환경 변수 설정
프로젝트 루트 디렉토리에 `.env` 파일을 생성하고 다음 값을 채워 넣습니다.
```env
SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_supabase_anon_key


- todo

-- 로그인을 하면 지금 현재 일정을 불러와서 ai 요청 시 ai에게 요청과 함께 보낼 수 있도록 해야됨.
-- 구글 혹은 애플 캘린더와의 연동을 계획
-- Cloudplug 를 조사하고, 현재 내 프로젝트에 적합한지 검토