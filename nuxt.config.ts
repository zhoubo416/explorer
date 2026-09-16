export default defineNuxtConfig({
  srcDir: 'app/',
  ssr: false,
  devtools: { enabled: false },
  css: ['../assets/css/main.css', '../assets/css/auth.css'],
  runtimeConfig: {
    public: {
      supabaseUrl: '',
      supabaseAnonKey: '',
    },
  },
  app: {
    head: {
      title: '探境 · Explore',
      meta: [
        { name: 'description', content: '你的 AI 个人成长伙伴' },
        { name: 'theme-color', content: '#f7f8ff' }
      ],
      link: [
        { rel: 'icon', type: 'image/png', href: '/favicon.png' },
        { rel: 'apple-touch-icon', href: '/apple-touch-icon.png' }
      ]
    }
  },
  compatibilityDate: '2024-11-01'
})
