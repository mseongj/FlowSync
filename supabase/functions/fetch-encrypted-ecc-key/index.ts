import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1"

console.log("fetch-encrypted-ecc-key Edge Function starting...")

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' } })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return new Response('Unauthorized', { status: 401 })

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
    if (userError || !user) return new Response('Unauthorized', { status: 401 })

    // Rate Limiting Logic
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()
    const { data: attempts } = await supabaseAdmin
      .from('key_fetch_attempts')
      .select('id')
      .eq('user_id', user.id)
      .eq('success', false)
      .gte('attempt_timestamp', oneHourAgo)

    if (attempts && attempts.length >= 5) {
      return new Response(JSON.stringify({ error: 'Too many failed attempts. Try again in an hour.' }), { status: 429 })
    }

    // The client sends the Argon2 hash they derived from their PIN
    // In a full implementation, we might use this hash to verify against a stored hash 
    // before returning the payload, but here we just return the payload for local decryption
    // and log the attempt.
    
    // Fetch payload bypassing RLS via Service Role
    const { data: keyStore, error: keyError } = await supabaseAdmin
      .from('family_key_store')
      .select('encrypted_payload')
      .eq('member_id', user.id)
      .single()

    if (keyError || !keyStore) {
      await supabaseAdmin.from('key_fetch_attempts').insert({ user_id: user.id, success: false })
      return new Response(JSON.stringify({ error: 'Key not found' }), { status: 404 })
    }

    // Log success
    await supabaseAdmin.from('key_fetch_attempts').insert({ user_id: user.id, success: true })

    return new Response(
      JSON.stringify({ encrypted_payload: keyStore.encrypted_payload }),
      { headers: { "Content-Type": "application/json" } },
    )
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})
