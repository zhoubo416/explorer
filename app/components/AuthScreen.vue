<script setup lang="ts">
const props = defineProps<{
  error: string | null
  signIn: (email: string, password: string) => Promise<boolean>
  signUp: (email: string, password: string, nickname?: string) => Promise<boolean>
}>()

const isSignUp = shallowRef(false)
const email = shallowRef('')
const password = shallowRef('')
const nickname = shallowRef('')
const submitting = shallowRef(false)
const validationError = shallowRef<string | null>(null)

const displayError = computed(() => validationError.value ?? props.error)

async function submit() {
  const cleanEmail = email.value.trim()
  if (!cleanEmail || password.value.length < 6) {
    validationError.value = '请输入邮箱和至少 6 位密码。'
    return
  }
  submitting.value = true
  validationError.value = null
  try {
    const ok = isSignUp.value
      ? await props.signUp(cleanEmail, password.value, nickname.value.trim())
      : await props.signIn(cleanEmail, password.value)
    if (!ok && !props.error) validationError.value = '操作失败，请稍后再试。'
  } catch (e: any) {
    validationError.value = e?.message ?? '操作失败，请稍后再试。'
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="auth-screen">
    <form class="auth-card" @submit.prevent="submit">
      <div class="auth-brand"><img class="brand-logo" src="/logo.png" alt="探境" width="34" height="34" /><strong>探境</strong></div>
      <span class="eyebrow">{{ isSignUp ? 'CREATE YOUR SPACE' : 'WELCOME BACK' }}</span>
      <h1>{{ isSignUp ? '创建你的探境' : '欢迎回来' }}</h1>
      <p>{{ isSignUp ? '保存你的成长轨迹，让 AI 越来越了解你。' : '登录后继续你的成长探索。' }}</p>

      <label v-if="isSignUp" class="auth-field">
        <span>昵称（可选）</span>
        <input v-model="nickname" type="text" autocomplete="nickname" placeholder="你想被怎么称呼">
      </label>
      <label class="auth-field">
        <span>邮箱</span>
        <input v-model="email" type="email" autocomplete="email" placeholder="you@example.com">
      </label>
      <label class="auth-field">
        <span>密码</span>
        <input v-model="password" type="password" autocomplete="current-password" placeholder="至少 6 位">
      </label>

      <p v-if="displayError" class="auth-error">{{ displayError }}</p>

      <button class="primary-button auth-submit" type="submit" :disabled="submitting">
        {{ submitting ? '处理中…' : isSignUp ? '注册' : '登录' }}
      </button>

      <button class="auth-switch" type="button" @click="isSignUp = !isSignUp; validationError = null">
        {{ isSignUp ? '已有账号？去登录' : '还没有账号？去注册' }}
      </button>
    </form>
  </div>
</template>
