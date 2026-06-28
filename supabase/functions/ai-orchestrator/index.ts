import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";

const MAX_RETRIES = 3;
const BASE_DELAY_MS = 200;

interface Payload {
  masked_text: string;
  current_timestamp: string;
}

// Exponential Backoff Helper
async function fetchWithRetry(url: string, options: RequestInit, retries = MAX_RETRIES, delay = BASE_DELAY_MS): Promise<Response> {
  try {
    const response = await fetch(url, options);
    // If rate limited or transient error
    if ((response.status === 429 || response.status >= 500) && retries > 0) {
      console.warn(`Retry needed. Status: ${response.status}. Retries left: ${retries}`);
      await new Promise(res => setTimeout(res, delay));
      return fetchWithRetry(url, options, retries - 1, delay * 2);
    }
    return response;
  } catch (error) {
    if (retries > 0) {
      console.warn(`Network error. Retries left: ${retries}. Error: ${error}`);
      await new Promise(res => setTimeout(res, delay));
      return fetchWithRetry(url, options, retries - 1, delay * 2);
    }
    throw error;
  }
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization')!;
    if (!authHeader) {
        return new Response(JSON.stringify({ error: "Missing Auth Header" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const { masked_text, current_timestamp } = await req.json() as Payload;

    if (!masked_text) {
      return new Response(JSON.stringify({ error: "Missing masked_text" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const apiKey = Deno.env.get("LLM_API_KEY");
    if (!apiKey) {
      throw new Error("Missing LLM_API_KEY configuration");
    }

    // Example OpenAI Payload (can be abstracted later)
    const llmPayload = {
      model: "gpt-4o-mini", // Using fast model for <500ms
      messages: [
        { 
          role: "system", 
          content: `You are an AI calendar assistant. Current UTC time is ${current_timestamp}. Extract scheduling intents into structured JSON: { "intent": "create_event", "title": "...", "start_time": "..." }` 
        },
        { role: "user", content: masked_text }
      ],
      response_format: { type: "json_object" }
    };

    const response = await fetchWithRetry("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(llmPayload)
    });

    if (!response.ok) {
      // Failed after all retries
      return new Response(JSON.stringify({ error: "LLM Service Unavailable" }), { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const data = await response.json();
    const result = JSON.parse(data.choices[0].message.content);

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });

  } catch (error: any) {
    console.error("Function Error:", error.message);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
