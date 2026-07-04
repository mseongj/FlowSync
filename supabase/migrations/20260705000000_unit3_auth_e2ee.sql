-- Migration: Unit 3 Auth & E2EE Initialization
-- Creates the family_key_store table to store encrypted Group Master Keys and ECC payloads

CREATE TABLE public.family_key_store (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id UUID NOT NULL, -- Will reference families(id) in Unit 4
    member_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    encrypted_payload TEXT NOT NULL, -- The encrypted key payload
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.family_key_store ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only INSERT their own key payload
CREATE POLICY "Users can insert their own key payload" 
ON public.family_key_store 
FOR INSERT 
WITH CHECK (auth.uid() = member_id);

-- Policy: Users can UPDATE their own key payload
CREATE POLICY "Users can update their own key payload" 
ON public.family_key_store 
FOR UPDATE 
USING (auth.uid() = member_id);

-- CRITICAL SECURITY POLICY:
-- Direct SELECT is strictly DENIED to prevent brute-force downloads.
-- Fetching must occur through the rate-limited `fetch-encrypted-ecc-key` Edge Function.
CREATE POLICY "Direct SELECT is DENIED for key store" 
ON public.family_key_store 
FOR SELECT 
USING (false);

-- Optional: Rate Limit Tracking Table (for Edge Function)
CREATE TABLE public.key_fetch_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    attempt_timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    success BOOLEAN NOT NULL
);

ALTER TABLE public.key_fetch_attempts ENABLE ROW LEVEL SECURITY;
-- No policies for public access. Service Role only.
