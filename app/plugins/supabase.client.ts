import { createClient, type SupabaseClient } from '@supabase/supabase-js'

export default defineNuxtPlugin(() => {
  const config = useRuntimeConfig().public
  const supabase: SupabaseClient = createClient(
    config.supabaseUrl,
    config.supabaseAnonKey,
  )

  return {
    provide: {
      supabase,
    },
  }
})
