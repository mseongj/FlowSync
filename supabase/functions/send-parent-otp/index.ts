import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1"

console.log("send-parent-otp Edge Function starting...")

serve(async (req) => {
  // CORS Headers
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' } })
  }

  try {
    const { phone } = await req.json()

    if (!phone || !phone.match(/^\+[1-9]\d{1,14}$/)) {
      return new Response(JSON.stringify({ error: 'Invalid E.164 phone number' }), { status: 400 })
    }

    // Generate 6-digit OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString()

    // In a real scenario, we would integrate Twilio here:
    // await twilioClient.messages.create({ body: `FlowSync Parental Consent OTP: ${otp}`, to: phone, from: '...' })
    
    // For demo purposes, we'll log it (DO NOT DO THIS IN PROD)
    console.log(`[MOCK SMS] Sent OTP ${otp} to ${phone}`)

    // Store OTP in Supabase Auth (We can use a custom table or magic link approach)
    // Here we'll just return success to simulate the integration.
    
    return new Response(
      JSON.stringify({ success: true, message: 'OTP sent successfully' }),
      { headers: { "Content-Type": "application/json" } },
    )
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})
