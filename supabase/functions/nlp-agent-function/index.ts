import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { GoogleGenAI, Type } from 'npm:@google/genai'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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

    const ai = new GoogleGenAI({ apiKey: Deno.env.get('GEMINI_API_KEY') })

    // Build multi-turn contents array
    const systemInstruction = `You are an AI calendar assistant for FlowSync. Parse user text into scheduling intents. Rules:
- Preserve exact tokens like [PERSON_1], [LOC_1] in your response.
- For intent: use "CREATE_EVENT" for new events, "RESCHEDULE" for modifications, "QUERY" when asking clarifying questions or reporting conflicts.
- When intent is "QUERY", set aiReplyMessage to your question/warning. Other fields can be null.
- When rescheduling, remember the context from previous messages and update accordingly.
- Always respond in the same language the user used.
- Do not output anything except valid JSON.`

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
                    aiReplyMessage: { type: Type.STRING }
                },
                required: ["intent", "participantsTokenized", "aiReplyMessage"]
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
