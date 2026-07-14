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

    const { text } = await req.json()
    if (!text) {
      return new Response(JSON.stringify({ error: 'Missing text parameter' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    console.time("gemini-request")

    // Heuristic Router Logic
    const isComplex = /(reschedule|conflict|find time|overlap|\[PERSON_\d+\](.*)\[PERSON_\d+\])/i.test(text)
    const modelId = isComplex ? 'gemini-2.5-flash' : 'gemini-2.5-flash-lite'
    
    console.log(`Routing to \${modelId} based on heuristics.`)

    const ai = new GoogleGenAI({ apiKey: Deno.env.get('GEMINI_API_KEY') })

    // If isComplex, we would query Supabase for RAG context here
    // const { data: events } = await supabaseClient.from('events').select('*')

    const response = await ai.models.generateContent({
        model: modelId,
        contents: `You are an AI calendar assistant. Parse the following text into a scheduling intent. Do not output anything except valid JSON. Preserve exact tokens like [PERSON_1] in your response. Text: "\${text}"`,
        config: {
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
