<script setup lang="ts">
import type { Message } from '~/composables/useExplore'
import { CHAT_GREETING } from '~/composables/useExplore'

const props = defineProps<{ messages: readonly Message[]; conversations: readonly { id: string; title: string; preview: string }[] }>()
const emit = defineEmits<{ send: [content: string, mode: 'normal' | 'low_mood']; selectConversation: [id: string] }>()
const mode = shallowRef<'normal' | 'low-mood'>('normal')
const draft = shallowRef('')
const showHistory = shallowRef(false)
const inputRef = useTemplateRef<HTMLInputElement>('chatInput')

// 空会话显示一条 AI 欢迎语（与目标共创的开场一致）；
// 发出第一条消息时由 sendMessage 落库，此后保留在会话历史里
const displayMessages = computed(() =>
  props.messages.length
    ? props.messages
    : [{ id: 'chat-greeting', role: 'assistant' as const, content: CHAT_GREETING, time: '' }],
)

function submitMessage() {
  const content = draft.value.trim()
  if (!content) return
  emit('send', content, mode.value === 'low-mood' ? 'low_mood' : 'normal')
  draft.value = ''
  inputRef.value?.focus()
}

function todayLabel() {
  return new Date().toLocaleDateString('zh-CN', { month: 'long', day: 'numeric', weekday: 'long' })
}
</script>

<template>
  <div class="chat-view page-enter">
    <header class="chat-header">
      <div class="chat-agent"><div class="agent-avatar"><span /></div><div><strong>{{ mode === 'low-mood' ? '成长陪伴' : '探境' }}</strong><span><i /> {{ mode === 'low-mood' ? '我会陪你慢慢聊' : 'AI 成长伙伴' }}</span></div></div>
      <button class="quiet-link chat-history-toggle" type="button" @click="showHistory = !showHistory">历史会话 <Icon name="chevron" :size="14" /></button>
    </header>
    <div v-if="showHistory" class="chat-history-panel">
      <button v-for="c in props.conversations" :key="c.id" class="chat-history-item" type="button" @click="emit('selectConversation', c.id); showHistory = false">
        <strong>{{ c.title }}</strong>
        <span>{{ c.preview || '暂无内容' }}</span>
      </button>
      <div v-if="!props.conversations.length" class="chat-history-empty">还没有历史会话。</div>
    </div>
    <div class="chat-body">
      <div class="chat-date">今天 · {{ todayLabel() }}</div>
      <div v-if="mode === 'low-mood'" class="companion-banner"><Icon name="spark" :size="15" /><span>你不用现在就解决所有问题，我们先一起理解它。</span></div>
      <div v-for="message in displayMessages" :key="message.id" class="message-row" :class="message.role">
        <div v-if="message.role === 'assistant'" class="message-avatar"><span /></div>
        <div class="message-bubble"><MarkdownText v-if="message.role === 'assistant' && message.content" :text="message.content" /><span v-else-if="message.role === 'assistant'" class="message-thinking">正在思考…</span><p v-else>{{ message.content }}</p><time>{{ message.time }}</time></div>
      </div>
      <div v-if="mode === 'normal'" class="chat-suggestion"><span class="eyebrow">可以这样开始</span><div><button type="button" @click="draft = '我最近有点不知道下一步该做什么。'">我不知道下一步做什么</button><button type="button" @click="draft = '帮我回顾一下最近的成长。'">帮我回顾最近的成长</button><button type="button" class="low-mood-trigger" @click="mode = 'low-mood'">我有点累，想放弃</button></div></div>
      <div v-else class="chat-suggestion"><span class="eyebrow">慢慢想，不急着回答</span><div><button type="button" @click="draft = '我想先把目标拆小一点。'">把目标拆小一点</button><button type="button" @click="draft = '我想重新看看为什么出发。'">重新看看为什么出发</button></div></div>
    </div>
    <form class="chat-composer" @submit.prevent="submitMessage">
      <input ref="chatInput" v-model="draft" aria-label="输入你的想法" :placeholder="mode === 'low-mood' ? '把此刻的感受告诉我……' : '写下你的想法……'">
      <button class="send-button" type="submit" aria-label="发送"><Icon name="send" :size="17" /></button>
    </form>
  </div>
</template>
