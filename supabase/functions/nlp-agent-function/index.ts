import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { GoogleGenAI, Type } from 'npm:@google/genai'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Expose-Headers': 'X-FlowSync-Router-Decision, X-FlowSync-Model-Used, X-FlowSync-Latency-Ms',
}

// ── Model Constants & Thresholds ──────────────────────────────────────────
export const MODEL_FLASH_LITE = 'gemini-2.5-flash-lite'
export const MODEL_FLASH = 'gemini-2.5-flash'
export const HARD_TIMEOUT_MS = 1200          // Max latency budget for primary 1st tier model
export const COMPLEXITY_THRESHOLD = 40       // Complexity score threshold for pre-routing bypass
export const QUALITY_SCORE_THRESHOLD = 0.75  // Response quality threshold for Flash-Lite acceptance

// ── Scheduling Response Schema ────────────────────────────────────────────
export const responseSchema = {
  type: Type.OBJECT,
  properties: {
    intent: { type: Type.STRING, description: "CREATE_EVENT, RESCHEDULE, CANCEL, or QUERY" },
    targetEventId: { 
      type: Type.STRING, 
      description: "The ID from [EXISTING CALENDAR] to reschedule or cancel if applicable, otherwise null" 
    },
    eventTitleTokenized: { type: Type.STRING },
    locationTokenized: { type: Type.STRING },
    startTime: { type: Type.STRING, description: "ISO 8601 timestamp" },
    endTime: { type: Type.STRING, description: "ISO 8601 timestamp" },
    participantsTokenized: { 
      type: Type.ARRAY, 
      items: { type: Type.STRING } 
    },
    aiReplyMessage: { type: Type.STRING },
    conflicts: {
      type: Type.ARRAY,
      description: "List of conflicting events detected from existing calendar",
      items: {
        type: Type.OBJECT,
        properties: {
          existingEventTitle: { type: Type.STRING },
          existingStartTime: { type: Type.STRING },
          existingEndTime: { type: Type.STRING },
          overlapMinutes: { type: Type.NUMBER }
        }
      }
    }
  },
  required: ["intent", "participantsTokenized", "aiReplyMessage", "conflicts"]
}

export interface CalendarContextResult {
  contextText: string
  eventCount: number
}

/**
 * Fetches the user's existing calendar events within a ±7 day window.
 * Used as RAG context for conflict detection and complexity calculation.
 */
export async function fetchCalendarContext(
  supabaseClient: ReturnType<typeof createClient>,
  userId: string
): Promise<CalendarContextResult> {
  const now = new Date()
  const windowStart = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
  const windowEnd = new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000)

  try {
    const { data: events, error } = await supabaseClient
      .from('calendar_events')
      .select('id, title, start_time, end_time, location, visibility')
      .neq('visibility', 'secret')
      .gte('start_time', windowStart.toISOString())
      .lte('start_time', windowEnd.toISOString())
      .order('start_time', { ascending: true })
      .limit(50)

    if (error || !events || events.length === 0) {
      return { contextText: '', eventCount: 0 }
    }

    const df = new Intl.DateTimeFormat('ko-KR', {
      timeZone: 'Asia/Seoul',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
      hour12: false,
    })

    const lines = events.map((e: any) => {
      const startStr = df.format(new Date(e.start_time))
      const endStr = df.format(new Date(e.end_time))
      const loc = e.location ? ` @ ${e.location}` : ''
      return `- [ID:${e.id}] ${startStr}~${endStr} "${e.title}"${loc}`
    })

    const contextText = `\n\n[EXISTING CALENDAR - ${events.length} events in the next 2 weeks]\n${lines.join('\n')}`
    return { contextText, eventCount: events.length }
  } catch {
    return { contextText: '', eventCount: 0 }
  }
}

export interface ComplexityResult {
  isComplex: boolean
  score: number
  reasons: string[]
}

/**
 * Evaluates the query complexity C(x) to decide on Pre-routing Bypass.
 * High complexity skips 1st-tier model and routes directly to Flash/Pro.
 */
export function evaluateComplexity(
  text: string,
  chatHistory?: Array<{ role: string; text: string }>,
  eventCount: number = 0
): ComplexityResult {
  let score = 0
  const reasons: string[] = []

  // 1. Negotiation & conflict resolution keywords (+40)
  const koKeywords = /(조율|겹치|비는|언제|변경|옮겨|바꿔|취소|삭제|미뤄|당겨|시간표|스케줄|가능한|확인해)/i
  const enKeywords = /(reschedule|conflict|find time|overlap|cancel|change|postpone|free time|available)/i
  if (koKeywords.test(text) || enKeywords.test(text)) {
    score += 40
    reasons.push('scheduling_negotiation_keyword')
  }

  // 2. Multi-person interaction token check (+30)
  // e.g. [PERSON_1] and [PERSON_2] both present
  const personMatches = text.match(/\[PERSON_\d+\]/g)
  if (personMatches && personMatches.length >= 2) {
    score += 30
    reasons.push(`multi_person_tokens(${personMatches.length})`)
  }

  // 3. Dense RAG schedule context check (+15 ~ +30)
  if (eventCount >= 5) {
    score += 30
    reasons.push(`dense_calendar_context(${eventCount}_events)`)
  } else if (eventCount >= 2) {
    score += 15
    reasons.push(`moderate_calendar_context(${eventCount}_events)`)
  }

  // 4. Multi-turn conversation depth (+25)
  if (Array.isArray(chatHistory) && chatHistory.length >= 2) {
    score += 25
    reasons.push(`multi_turn_history(${chatHistory.length}_turns)`)
  }

  // 5. Query length / verbosity (+15)
  if (text.length > 60) {
    score += 15
    reasons.push('long_prompt')
  }

  return {
    isComplex: score >= COMPLEXITY_THRESHOLD,
    score,
    reasons,
  }
}

export interface QualityScoreResult {
  score: number
  passed: boolean
  reason: string
}

/**
 * FrugalGPT Scoring Function:
 * Evaluates response quality and schema completeness from the primary lightweight model.
 */
export function scoreResponseQuality(response: any): QualityScoreResult {
  if (!response || typeof response !== 'object') {
    return { score: 0, passed: false, reason: 'invalid_json_object' }
  }

  let score = 0
  const reasons: string[] = []

  // 1. Required core fields present (+0.35)
  const hasCoreFields =
    typeof response.intent === 'string' &&
    typeof response.aiReplyMessage === 'string' &&
    Array.isArray(response.conflicts)

  if (hasCoreFields) {
    score += 0.35
  } else {
    reasons.push('missing_core_fields')
  }

  // 2. Valid intent enum (+0.25)
  const validIntents = ['CREATE_EVENT', 'RESCHEDULE', 'CANCEL', 'QUERY']
  if (validIntents.includes(response.intent)) {
    score += 0.25
  } else {
    reasons.push(`invalid_intent(${response.intent})`)
  }

  // 3. Scheduling integrity (+0.40)
  if (response.intent === 'CREATE_EVENT' || response.intent === 'RESCHEDULE') {
    let scheduleValid = true
    
    // Title must not be empty
    if (!response.eventTitleTokenized || response.eventTitleTokenized.trim() === '') {
      scheduleValid = false
      reasons.push('missing_title')
    }

    // Start/End must be valid parseable timestamps with End > Start
    const start = response.startTime ? new Date(response.startTime).getTime() : NaN
    const end = response.endTime ? new Date(response.endTime).getTime() : NaN

    if (isNaN(start) || isNaN(end) || end <= start) {
      scheduleValid = false
      reasons.push('invalid_time_range')
    }

    if (scheduleValid) {
      score += 0.40
    }
  } else if (response.intent === 'CANCEL') {
    // For CANCEL intent, reply message should be meaningful
    if (response.aiReplyMessage && response.aiReplyMessage.trim().length >= 2) {
      score += 0.40
    } else {
      reasons.push('empty_cancel_reply')
    }
  } else if (response.intent === 'QUERY') {
    // For QUERY intent, reply message must be meaningful
    if (response.aiReplyMessage && response.aiReplyMessage.trim().length >= 2) {
      score += 0.40
    } else {
      reasons.push('empty_query_reply')
    }
  }

  return {
    score,
    passed: score >= QUALITY_SCORE_THRESHOLD,
    reason: reasons.length > 0 ? reasons.join(', ') : 'all_checks_passed',
  }
}

/**
 * Calls Gemini with a hard timeout using Promise.race.
 */
async function callGeminiWithTimeout(
  ai: GoogleGenAI,
  modelId: string,
  contents: any,
  systemInstruction: string,
  timeoutMs: number
): Promise<{ result: any; latencyMs: number }> {
  const start = Date.now()
  let timer: number | undefined

  const timeoutPromise = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      const err = new Error(`Model ${modelId} timed out after ${timeoutMs}ms`)
      err.name = 'TimeoutError'
      reject(err)
    }, timeoutMs)
  })

  try {
    const callPromise = ai.models.generateContent({
      model: modelId,
      contents: contents,
      config: {
        systemInstruction: systemInstruction,
        responseMimeType: 'application/json',
        responseSchema: responseSchema,
      },
    })

    const response = await Promise.race([callPromise, timeoutPromise])
    clearTimeout(timer)
    const latencyMs = Date.now() - start
    const result = JSON.parse(response.text ?? '{}')
    return { result, latencyMs }
  } catch (err) {
    clearTimeout(timer)
    throw err
  }
}

/**
 * Streams Gemini response as SSE (Server-Sent Events).
 * data: {"type":"token","chunk":"..."}  — 실시간 토큰 청크
 * data: {"type":"final","payload":{...}} — 최종 JSON 페이로드
 */
async function callGeminiStreaming(
  ai: GoogleGenAI,
  modelId: string,
  contents: any,
  systemInstruction: string,
): Promise<ReadableStream<Uint8Array>> {
  const encoder = new TextEncoder()

  return new ReadableStream({
    async start(controller) {
      try {
        const stream = await ai.models.generateContentStream({
          model: modelId,
          contents: contents,
          config: {
            systemInstruction: systemInstruction,
            responseMimeType: 'application/json',
            responseSchema: responseSchema,
          },
        })

        let fullText = ''
        for await (const chunk of stream) {
          const chunkText = chunk.text ?? ''
          if (chunkText) {
            fullText += chunkText
            const sseChunk = `data: ${JSON.stringify({ type: 'token', chunk: chunkText })}\n\n`
            controller.enqueue(encoder.encode(sseChunk))
          }
        }

        // 스트리밍 완료 후 최종 JSON 파싱하여 payload로 전송
        try {
          const finalPayload = JSON.parse(fullText)
          const sseFinal = `data: ${JSON.stringify({ type: 'final', payload: finalPayload })}\n\n`
          controller.enqueue(encoder.encode(sseFinal))
        } catch {
          const sseFinal = `data: ${JSON.stringify({ type: 'final', payload: { aiReplyMessage: fullText, intent: 'QUERY', participantsTokenized: [], conflicts: [] } })}\n\n`
          controller.enqueue(encoder.encode(sseFinal))
        }

        controller.close()
      } catch (err: any) {
        const sseErr = `data: ${JSON.stringify({ type: 'error', message: err.message })}\n\n`
        controller.enqueue(encoder.encode(sseErr))
        controller.close()
      }
    },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const reqStart = Date.now()

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: { headers: { Authorization: req.headers.get('Authorization')! } },
      }
    )

    // JWT Validation - User must be logged in
    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser()

    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      })
    }

    const { text, chatHistory, draftTokens, draftLogprobs } = await req.json()
    if (!text) {
      return new Response(JSON.stringify({ error: 'Missing text parameter' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // Draft 토큰 수신 여부 (Speculative Decoding 모드)
    const hasSpeculativeDraft = Array.isArray(draftTokens) && draftTokens.length > 0
    if (hasSpeculativeDraft) {
      console.log(`[Speculative] Draft 수신: ${draftTokens.length}개 토큰`)
    }

    // 스트리밍 모드 여부 확인 (?streaming=true)
    const url = new URL(req.url)
    const isStreaming = url.searchParams.get('streaming') === 'true'

    // 1. RAG Context (Existing calendar events ±7d)
    const { contextText, eventCount } = await fetchCalendarContext(supabaseClient, user.id)
    if (eventCount > 0) {
      console.log(`RAG context loaded: ${eventCount} events`)
    }

    // 2. Pre-routing Complexity Evaluation (FrugalGPT Step 1)
    const complexity = evaluateComplexity(text, chatHistory, eventCount)
    console.log(
      `Complexity: score=${complexity.score}, isComplex=${complexity.isComplex}, reasons=[${complexity.reasons.join(', ')}]`
    )

    // 3. System Instruction Assembly
    const systemInstruction = `You are an AI calendar assistant for FlowSync. Parse user text into scheduling intents. Rules:
- Preserve exact tokens like [PERSON_1], [LOC_1] in your response.
- For intent:
  - "CREATE_EVENT": Adding a new event.
  - "RESCHEDULE": Modifying time, date, or details of an existing event from [EXISTING CALENDAR]. Find the event ID from [ID:uuid] and populate targetEventId.
  - "CANCEL": Deleting or canceling an existing event from [EXISTING CALENDAR]. Find the event ID from [ID:uuid] and populate targetEventId, and describe the cancellation in aiReplyMessage.
  - "QUERY": Asking clarifying questions, reporting conflicts, or when the target event to modify/cancel cannot be found in [EXISTING CALENDAR].
- When intent is "QUERY", set aiReplyMessage to your question/warning. Other fields can be null.
- When rescheduling or canceling, match the event from [EXISTING CALENDAR]. If multiple matching events exist or ambiguous, set intent to "QUERY" and ask user for clarification.
- Always respond in the same language the user used.
- Do not output anything except valid JSON.

CONFLICT DETECTION:
- Check the user's existing calendar (provided below) for time overlaps with the requested event.
- If a conflict is found, set intent to "QUERY", describe the conflict in aiReplyMessage, and populate the "conflicts" array with details of each conflicting event.
- If no conflict, leave "conflicts" as an empty array.
- A conflict means the new event's time range overlaps with an existing event's time range.
${contextText || '\n[No existing events found]'}`

    // 4. Build contents payload
    let contents: any
    if (Array.isArray(chatHistory) && chatHistory.length > 0) {
      contents = chatHistory.map((msg: { role: string; text: string }) => ({
        role: msg.role === 'model' ? 'model' : 'user',
        parts: [{ text: msg.text }],
      }))
      contents.push({ role: 'user', parts: [{ text: text }] })
    } else {
      contents = text
    }

    const ai = new GoogleGenAI({ apiKey: Deno.env.get('GEMINI_API_KEY') })

    let finalResponse: any
    let modelUsed: string
    let routerDecision: 'BYPASS_DIRECT_FLASH' | 'LITE_ACCEPTED' | 'FALLBACK_TIMEOUT' | 'FALLBACK_LOW_QUALITY'

    // 5. Cascading Router Execution
    if (complexity.isComplex) {
      // ── Path A: Pre-routing Bypass to Flash ──
      console.log(`[Router] Pre-routing bypass triggered -> Direct call to ${MODEL_FLASH}`)
      modelUsed = MODEL_FLASH
      routerDecision = 'BYPASS_DIRECT_FLASH'

      const { result, latencyMs } = await callGeminiWithTimeout(
        ai,
        MODEL_FLASH,
        contents,
        systemInstruction,
        10000
      )
      finalResponse = result
      console.log(`[Router] ${MODEL_FLASH} direct response completed in ${latencyMs}ms`)
    } else {
      // ── Path B: Cascading Execution (Flash-Lite 1st -> Fallback to Flash) ──
      console.log(`[Router] Calling primary model ${MODEL_FLASH_LITE} (Hard Timeout: ${HARD_TIMEOUT_MS}ms)...`)
      
      try {
        const { result, latencyMs } = await callGeminiWithTimeout(
          ai,
          MODEL_FLASH_LITE,
          contents,
          systemInstruction,
          HARD_TIMEOUT_MS
        )

        // Quality Scoring (FrugalGPT Step 2)
        const quality = scoreResponseQuality(result)
        console.log(
          `[Router] ${MODEL_FLASH_LITE} finished in ${latencyMs}ms. Quality score=${quality.score.toFixed(2)} (passed=${quality.passed}, reason=${quality.reason})`
        )

        if (quality.passed) {
          finalResponse = result
          modelUsed = MODEL_FLASH_LITE
          routerDecision = 'LITE_ACCEPTED'
        } else {
          console.warn(`[Router] Quality failed. Cascading to ${MODEL_FLASH}...`)
          const fallbackRes = await callGeminiWithTimeout(
            ai,
            MODEL_FLASH,
            contents,
            systemInstruction,
            10000
          )
          finalResponse = fallbackRes.result
          modelUsed = MODEL_FLASH
          routerDecision = 'FALLBACK_LOW_QUALITY'
        }
      } catch (err: any) {
        const isTimeout = err.name === 'TimeoutError'
        console.warn(`[Router] ${MODEL_FLASH_LITE} failed (${isTimeout ? 'TIMEOUT' : err.message}). Cascading to ${MODEL_FLASH}...`)

        const fallbackRes = await callGeminiWithTimeout(
          ai,
          MODEL_FLASH,
          contents,
          systemInstruction,
          10000
        )
        finalResponse = fallbackRes.result
        modelUsed = MODEL_FLASH
        routerDecision = isTimeout ? 'FALLBACK_TIMEOUT' : 'FALLBACK_LOW_QUALITY'
      }
    }

    const totalDurationMs = Date.now() - reqStart
    console.log(`[Router] Total request completed in ${totalDurationMs}ms | Model=${modelUsed} | Decision=${routerDecision}`)

    // ── Speculative Decoding: Cloud logprob 첨부 ─────────────────────────────
    // Draft 토큰이 있으면, Cloud 응답에 각 Draft 토큰의 Cloud logprob를 첨부.
    // Flutter의 SpeculativeDecodeManager가 Accept/Reject 판정에 사용.
    let cloudLogprobs: number[] = []
    if (hasSpeculativeDraft && draftLogprobs) {
      // 실제 Cloud logprob을 가져오는 것은 Gemini API가 logprob를 노출할 때만 가능.
      // 현재 Gemini API는 logprob를 직접 제공하지 않으므로,
      // Draft 토큰에 대한 신뢰도를 0.0~1.0 범위의 품질 점수로 근사.
      const qualityScore = scoreResponseQuality(finalResponse)
      cloudLogprobs = Array(draftTokens.length).fill(
        Math.log(Math.max(qualityScore.score, 0.01))  // log(score)로 logprob 근사
      )
      console.log(`[Speculative] Cloud logprob 근사: score=${qualityScore.score.toFixed(3)}, logprob=${cloudLogprobs[0]?.toFixed(3)}`)
    }

    // cloudLogprobs와 acceptanceRate를 응답에 포함
    const enrichedResponse = {
      ...finalResponse,
      ...(hasSpeculativeDraft ? { cloudLogprobs, draftAcceptanceInfo: { k: draftTokens?.length ?? 0 } } : {}),
    }

    // ── 스트리밍 모드: SSE 응답 ──────────────────────────────────────────────
    if (isStreaming) {
      const sseStream = await callGeminiStreaming(ai, modelUsed, contents, systemInstruction)
      return new Response(sseStream, {
        headers: {
          ...corsHeaders,
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'X-FlowSync-Router-Decision': routerDecision,
          'X-FlowSync-Model-Used': modelUsed,
          'X-FlowSync-Latency-Ms': totalDurationMs.toString(),
          'X-FlowSync-Streaming': 'true',
        },
        status: 200,
      })
    }

    // ── 기존 JSON 모드 (하위 호환 유지) ────────────────────────────────────
    return new Response(JSON.stringify(enrichedResponse), {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
        'X-FlowSync-Router-Decision': routerDecision,
        'X-FlowSync-Model-Used': modelUsed,
        'X-FlowSync-Latency-Ms': totalDurationMs.toString(),
        ...(hasSpeculativeDraft ? { 'X-FlowSync-Acceptance-Rate': (cloudLogprobs[0] ? '1' : '0') } : {}),
      },
      status: 200,
    })
  } catch (error: any) {
    console.error('[Router Error]', error)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
