<script setup lang="ts">
import type { Stage } from '~/composables/useExplore'
import { GOAL_CREATION_GREETING } from '~/composables/useExplore'

type Msg = { role: 'user' | 'assistant'; content: string }
type GoalDraft = { title: string; description: string; success_definition: string }

const props = defineProps<{
  goalChat: (messages: { role: 'user' | 'assistant'; content: string }[], signal?: AbortSignal, onDelta?: (reply: string) => void) => Promise<{ reply: string; goal: GoalDraft | null }>
  planGoal: (title: string, description: string, successDefinition: string, signal?: AbortSignal) => Promise<Stage[]>
}>()
const emit = defineEmits<{ back: []; created: [title: string, description: string, successDefinition: string, stages: Stage[]] }>()

const messages = shallowRef<Msg[]>([
  { role: 'assistant', content: GOAL_CREATION_GREETING },
])
const draft = shallowRef('')
const submitting = shallowRef(false)
const goal = shallowRef<GoalDraft | null>(null)
const stages = shallowRef<Stage[]>([])
const planning = shallowRef(false)
const chatBody = ref<HTMLElement | null>(null)
const goalInput = ref<HTMLInputElement | null>(null)
const controller = ref<AbortController | null>(null)
const busy = computed(() => submitting.value || planning.value)
const streamingReply = shallowRef('')

async function scrollToBottom() {
  await nextTick()
  chatBody.value?.scrollTo({ top: chatBody.value.scrollHeight, behavior: 'smooth' })
}

watch(
  () => [messages.value.length, goal.value, stages.value.length, planning.value],
  () => scrollToBottom(),
)

async function submit() {
  const content = draft.value.trim()
  if (!content || busy.value) return
  draft.value = ''
  messages.value = [...messages.value, { role: 'user', content }]
  submitting.value = true
  const ac = new AbortController()
  controller.value = ac
  try {
    const { reply, goal: g } = await props.goalChat(messages.value, ac.signal, (text) => {
      streamingReply.value = text
    })
    if (ac.signal.aborted) return
    messages.value = [...messages.value, { role: 'assistant', content: reply }]
    streamingReply.value = ''
    if (g) {
      goal.value = g
      planning.value = true
      try {
        stages.value = await props.planGoal(g.title, g.description, g.success_definition, ac.signal)
      }
      catch {
        if (!ac.signal.aborted) stages.value = []
      }
      planning.value = false
    }
  }
  catch {
    if (!ac.signal.aborted) {
      messages.value = [...messages.value, { role: 'assistant', content: '抱歉，我走神了，我们换个方式再说说？' }]
    }
  }
  finally {
    submitting.value = false
    planning.value = false
    controller.value = null
    streamingReply.value = ''
    goalInput.value?.focus()
  }
}

function cancel() {
  controller.value?.abort()
  submitting.value = false
  planning.value = false
}

function create() {
  if (!goal.value) return
  emit('created', goal.value.title, goal.value.description, goal.value.success_definition, stages.value)
}
</script>

<template>
  <div class="flow-view page-enter">
    <header class="flow-header">
      <button class="back-button" type="button" @click="emit('back')"><Icon name="back" :size="18" /> 返回目标</button>
      <div class="flow-title"><div class="agent-avatar"><span /></div><strong>与探境共创目标</strong></div>
      <span class="flow-step">创建目标 · 01</span>
    </header>
    <!-- 创作理念已并入 AI 开场欢迎语（见 GOAL_CREATION_GREETING），页面收成单列对话 -->
    <div class="create-chat">
      <div ref="chatBody" class="chat-body">
        <div v-for="message in messages" :key="message.content" class="message-row" :class="message.role">
          <div v-if="message.role === 'assistant'" class="message-avatar"><span /></div>
          <div class="message-bubble"><MarkdownText v-if="message.role === 'assistant'" :text="message.content" /><p v-else>{{ message.content }}</p></div>
        </div>
        <div v-if="submitting" class="message-row assistant">
          <div class="message-avatar"><span /></div>
          <div v-if="!streamingReply" class="message-bubble typing-bubble"><i class="typing-dot" /><i class="typing-dot" /><i class="typing-dot" /></div>
          <div v-else class="message-bubble"><MarkdownText :text="streamingReply" /></div>
        </div>
        <div v-if="goal" class="goal-preview">
          <span class="eyebrow">我帮你整理成了一个方向</span>
          <h2>{{ goal.title }}</h2>
          <p>{{ goal.description }}</p>
          <div v-if="goal.success_definition" class="preview-meta"><span><Icon name="target" :size="14" /> {{ goal.success_definition }}</span></div>
          <div v-if="planning" class="preview-hint"><Icon name="spark" :size="15" /> 正在拆解阶段与行动项…</div>
          <div v-else-if="stages.length" class="stage-preview">
            <span class="eyebrow">拆解后的成长路径</span>
            <div v-for="(stage, si) in stages" :key="stage.id" class="stage-preview-item">
              <strong>{{ si + 1 }}. {{ stage.name }}</strong>
              <p>{{ stage.description }}</p>
              <div v-if="stage.actions.length" class="stage-actions">
                <span v-for="action in stage.actions" :key="action.id">· {{ action.content }}</span>
              </div>
            </div>
          </div>
          <button class="primary-button" type="button" :disabled="planning" @click="create">确认并创建目标 <Icon name="arrow" :size="16" /></button>
        </div>
      </div>
      <form class="chat-composer flow-composer" @submit.prevent="submit">
        <input ref="goalInput" v-model="draft" aria-label="说说你的想法" :disabled="busy" :placeholder="busy ? '正在思考…' : '说说你一直想做的那件事…'">
        <button v-if="!busy" class="send-button" type="submit" aria-label="发送"><Icon name="send" :size="17" /></button>
        <button v-else class="cancel-button" type="button" aria-label="取消" @click="cancel"><Icon name="close" :size="14" /> 取消</button>
      </form>
    </div>
  </div>
</template>
