import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { GoogleGenAI, Type } from 'npm:@google/genai'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

/**
 * Fetches the user's existing calendar events within a ±7 day window.
 * Used as RAG context for conflict detection.
 */
async function fetchCalendarContext(
  supabaseClient: ReturnType<typeof createClient>,
  userId: string
): Promise<string> {
  const now = new Date()
  const windowStart = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
  const windowEnd = new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000)

  try {
    // Query events visible to this user (via RLS)
    const { data: events, error } = await supabaseClient
      .from('calendar_events')
      .select('title, start_time, end_time, location, visibility')
      .gte('start_time', windowStart.toISOString())
      .lte('start_time', windowEnd.toISOString())
      .order('start_time', { ascending: true })
      .limit(50)

    if (error || !events || events.length === 0) {
      return ''
    }

    // Format as a compact text block for the LLM
    const lines = events.map((e: any) => {
      const start = new Date(e.start_time)
      const end = new Date(e.end_time)
      const dateStr = `${start.getMonth() + 1}/${start.getDate()}`
      const startStr = `${start.getHours()}:${String(start.getMinutes()).padStart(2, '0')}`
      const endStr = `${end.getHours()}:${String(end.getMinutes()).padStart(2, '0')}`
      const loc = e.location ? ` @ ${e.location}` : ''
      return `- ${dateStr} ${startStr}~${endStr} "${e.title}"${loc}`
    })

    return `\n\n[EXISTING CALENDAR - ${events.length} events in the next 2 weeks]\n${lines.join('\n')}`
  } catch {
    return ''
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

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

    const { text, chatHistory } = await req.json()
    if (!text) {
      return new Response(JSON.stringify({ error: 'Missing text parameter' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    console.time("gemini-request")

    // Heuristic Router Logic
    const isComplex = /(reschedule|conflict|find time|overlap|\[PERSON_\d+\](.*)\[PERSON_\d+\])/i.test(text)
    const hasHistory = Array.isArray(chatHistory) && chatHistory.length > 0
    const modelId = (isComplex || hasHistory) ? 'gemini-2.5-flash' : 'gemini-2.5-flash-lite'
    
    console.log(`Routing to ${modelId} | hasHistory=${hasHistory} (${chatHistory?.length ?? 0} turns)`)

    // RAG: Fetch existing calendar events for conflict detection
    const calendarContext = await fetchCalendarContext(supabaseClient, user.id)
    if (calendarContext) {
      console.log(`RAG context loaded: ${calendarContext.split('\n').length - 2} events`)
    }

    const ai = new GoogleGenAI({ apiKey: Deno.env.get('GEMINI_API_KEY') })

    // Build system instruction with RAG context
    const systemInstruction = `You are an AI calendar assistant for FlowSync. Parse user text into scheduling intents. Rules:
- Preserve exact tokens like [PERSON_1], [LOC_1] in your response.
- For intent: use "CREATE_EVENT" for new events, "RESCHEDULE" for modifications, "QUERY" when asking clarifying questions or reporting conflicts.
- When intent is "QUERY", set aiReplyMessage to your question/warning. Other fields can be null.
- When rescheduling, remember the context from previous messages and update accordingly.
- Always respond in the same language the user used.
- Do not output anything except valid JSON.

CONFLICT DETECTION:
- Check the user's existing calendar (provided below) for time overlaps with the requested event.
- If a conflict is found, set intent to "QUERY", describe the conflict in aiReplyMessage, and populate the "conflicts" array with details of each conflicting event.
- If no conflict, leave "conflicts" as an empty array.
- A conflict means the new event's time range overlaps with an existing event's time range.
${calendarContext || '\n[No existing events found]'}`

    // Build contents: either multi-turn array or single prompt
    let contents: any

    if (hasHistory) {
      // Multi-turn: convert chatHistory to Gemini contents format
      contents = chatHistory.map((msg: { role: string; text: string }) => ({
        role: msg.role === 'model' ? 'model' : 'user',
        parts: [{ text: msg.text }],
      }))
      // Append the latest user message
      contents.push({
        role: 'user',
        parts: [{ text: text }],
      })
    } else {
      // Single-turn: just the text
      contents = text
    }

    const response = await ai.models.generateContent({
        model: modelId,
        contents: contents,
        config: {
            systemInstruction: systemInstruction,
            responseMimeType: "application/json",
            responseSchema: {
                type: Type.OBJECT,
                properties: {
                    intent: { type: Type.STRING, description: "CREATE_EVENT, RESCHEDULE, or QUERY" },
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
        }
    })

    console.timeEnd("gemini-request")
    
    const responseJson = JSON.parse(response.text ?? "{}")

    return new Response(JSON.stringify(responseJson), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    console.error(error)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
