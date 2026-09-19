import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const supabasePublishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;

/**
 * The shared Supabase client, or null when the build has no Supabase settings.
 * A missing backend is treated like an unreachable one: sign-in falls back to the
 * offline demo and live panels (ML risk) show "sign in required".
 */
export const supabase: SupabaseClient | null =
  supabaseUrl && supabasePublishableKey
    ? createClient(supabaseUrl, supabasePublishableKey, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true,
        },
      })
    : null;

if (!supabase) {
  console.warn("VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY are not set; running as offline demo.");
}
