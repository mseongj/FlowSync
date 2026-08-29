import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1"
import { crypto } from "https://deno.land/std@0.168.0/crypto/mod.ts"
import { encode as hexEncode } from "https://deno.land/std@0.168.0/encoding/hex.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input)
  const hashBuffer = await crypto.subtle.digest('SHA-256', data)
  return new TextDecoder().decode(hexEncode(new Uint8Array(hashBuffer)))
}

console.log("verify-parent-otp Edge Function starting...")

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Verify user
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser()
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { phone, otp } = await req.json()

    if (!phone || !otp) {
      return new Response(JSON.stringify({ error: 'Missing phone or otp' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Find the latest unexpired, unverified OTP for this user + phone
    const { data: otpRecord, error: fetchError } = await supabaseAdmin
      .from('parent_consent_otps')
      .select('*')
      .eq('user_id', user.id)
      .eq('phone', phone)
      .is('verified_at', null)
      .gt('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
      .limit(1)
      .single()

    if (fetchError || !otpRecord) {
      return new Response(JSON.stringify({ verified: false, error: 'No valid OTP found. Please request a new one.' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Check attempt limit (max 5 attempts per OTP)
    if (otpRecord.attempts >= 5) {
      // Invalidate this OTP
      await supabaseAdmin
        .from('parent_consent_otps')
        .update({ verified_at: new Date().toISOString() }) // mark as consumed
        .eq('id', otpRecord.id)

      return new Response(JSON.stringify({ verified: false, error: 'Too many failed attempts. Please request a new OTP.' }), {
        status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Increment attempt counter
    await supabaseAdmin
      .from('parent_consent_otps')
      .update({ attempts: otpRecord.attempts + 1 })
      .eq('id', otpRecord.id)

    // Compare hash
    const inputHash = await sha256(otp)
    if (inputHash !== otpRecord.otp_hash) {
      return new Response(JSON.stringify({ verified: false, error: 'Incorrect OTP' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // OTP matches — mark as verified
    await supabaseAdmin
      .from('parent_consent_otps')
      .update({ verified_at: new Date().toISOString() })
      .eq('id', otpRecord.id)

    // Update user metadata to record parental consent
    await supabaseAdmin.auth.admin.updateUserById(user.id, {
      user_metadata: {
        parent_consent_verified_at: new Date().toISOString(),
      },
    })

    return new Response(
      JSON.stringify({ verified: true }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (error) {
    console.error(error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
