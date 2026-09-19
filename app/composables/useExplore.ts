import { computed, readonly, ref } from 'vue'
import type { SupabaseClient, User } from '@supabase/supabase-js'

export type ViewId = 'home' | 'growth' | 'memory' | 'chat' | 'report' | 'goal-create' | 'goal-created' | 'goal-detail'

export interface Goal {
  id: string
  title: string
  description: string
  phase: string
  progress: number
  status: string
  rawStatus: string
  icon: string
  accent: string
  milestone: string
  aiSummary: string
  stages: Stage[]
}

export interface StageAction {
  id: string
  content: string
  done: boolean
}

export interface Stage {
  id: string
  name: string
  description: string
  status: 'not_started' | 'active' | 'completed'
  actions: StageAction[]
}

export interface GoalAnalysis {
  summary: string
  observation: string
  suggestion: string
  actions: string[]
}

export interface Observation {
  id: string
  label: string
  title: string
  content: string
  action: string
  tone: 'violet' | 'mint' | 'amber'
}

export interface MemoryItem {
  id: string
  date: string
  month: string
  type: string
  title: string
  detail: string
  icon: string
  tone: string
}

export interface Message {
  id: string
  role: 'assistant' | 'user'
  content: string
  time: string
}

export interface WeeklyReport {
  score: string
  completed: string[]
  insight: string
  nextSteps: string[]
}

const ACCENTS = ['violet', 'mint', 'coral', 'amber'] as const
const ICONS = ['target', 'globe', 'spark', 'sun'] as const

function visualFromId(id: string): { accent: string; icon: string } {
  let hash = 0
  for (const ch of id) hash = (hash * 31 + ch.charCodeAt(0)) % 997
  return { accent: ACCENTS[hash % ACCENTS.length], icon: ICONS[hash % ICONS.length] }
}

function goalStatusText(status: string): string {
  const map: Record<string, string> = {
    active: '进行中',
    exploring: '探索中',
    paused: '暂停中',
    completed: '已完成',
    archived: '已归档',
    blocked: '受阻',
  }
  return map[status] ?? '探索中'
}

function goalPhase(status: string): string {
  const map: Record<string, string> = {
    active: '进行期',
    paused: '暂停期',
    completed: '完成期',
    blocked: '受阻期',
    archived: '归档',
    exploring: '探索期',
  }
  return map[status] ?? '探索期'
}

function memoryTypeText(type: string): string {
  const map: Record<string, string> = {
    event: '成长事件',
    decision: '关键决定',
    reflection: '反思',
    achievement: '成就',
    failure: '失败',
    emotion: '情绪',
    thought: '想法',
  }
  return map[type] ?? '想法'
}

function memoryIcon(type: string): string {
  const map: Record<string, string> = {
    event: 'check',
    decision: 'decision',
    reflection: 'reflect',
    achievement: 'spark',
    failure: 'reflect',
    emotion: 'spark',
    thought: 'memory',
  }
  return map[type] ?? 'memory'
}

function memoryTone(type: string): string {
  const map: Record<string, string> = {
    event: 'violet',
    decision: 'coral',
    reflection: 'mint',
    achievement: 'amber',
    failure: 'coral',
    emotion: 'mint',
    thought: 'violet',
  }
  return map[type] ?? 'violet'
}

function toDateLabel(value: string): string {
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return ''
  if (d.toDateString() === new Date().toDateString()) {
    return `今天 ${d.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}`
  }
  return d.toLocaleDateString('zh-CN', { month: 'long', day: 'numeric' })
}

function toMonthLabel(value: string): string {
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return ''
  return `${d.getMonth() + 1} 月`
}

function toTimeLabel(value: string): string {
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return ''
  return d.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
}

function intValue(value: unknown): number {
  if (typeof value === 'number') return Math.max(0, Math.min(100, Math.round(value)))
  const n = Number.parseInt(String(value ?? ''), 10)
  return Number.isFinite(n) ? Math.max(0, Math.min(100, n)) : 0
}

// 新会话的 AI 开场白：空会话先展示，发出第一条消息时随会话落库（见 sendMessage）
export const CHAT_GREETING = '你好，我是探境。最近过得怎么样？开心的、烦心的，或者还没想明白的事，都可以随时说给我听。'

// 目标共创的开场白：原「为什么从对话开始」侧栏文案并入这里
export const GOAL_CREATION_GREETING = '你好，我是探境。目标不是一开始就完美的答案，而是你愿意先靠近的一条路——不用先想清楚，我们边走边发现。最近有没有一件事，你一直想做，但还没真正开始？'

function chatGreetingMessage(): Message {
  return { id: 'chat-greeting', role: 'assistant', content: CHAT_GREETING, time: '' }
}

const emptyGoal = (): Goal => ({
  id: '',
  title: '还没有目标',
  description: '创建你的第一个成长方向',
  phase: '开始',
  progress: 0,
  status: '未开始',
  rawStatus: 'exploring',
  icon: 'target',
  accent: 'violet',
  milestone: '创建第一个目标',
  aiSummary: '',
  stages: [],
})

export function useExplore() {
  const { $supabase } = useNuxtApp()
  const supabase = $supabase as SupabaseClient
  const runtime = useRuntimeConfig().public

  const invokeWithRetry = async (fn: string, body?: Record<string, unknown>, retries = 3, signal?: AbortSignal): Promise<{ data: any; error: any }> => {
    let lastError: any = null
    for (let attempt = 0; attempt < retries; attempt++) {
      if (signal?.aborted) return { data: null, error: new DOMException('Aborted', 'AbortError') }
      try {
        const result = await supabase.functions.invoke(fn, { body, signal })
        if (!result.error) return result
        lastError = result.error
      }
      catch (e) {
        lastError = e
      }
      if (attempt < retries - 1 && !signal?.aborted) {
        await new Promise((resolve) => setTimeout(resolve, 1200 * (attempt + 1)))
      }
    }
    return { data: null, error: lastError }
  }

  const user = ref<User | null>(null)
  const authReady = ref(false)
  const loading = ref(false)
  const error = ref<string | null>(null)
  const goalChatSessionId = ref<string | null>(null)

  function resetGoalChat() {
    goalChatSessionId.value = null
  }

  const goals = ref<Goal[]>([])
  const observations = ref<Observation[]>([])
  const memories = ref<MemoryItem[]>([])
  const messages = ref<Message[]>([])
  const conversations = ref<{ id: string; title: string; preview: string }[]>([])
  const activeSessionId = ref<string | null>(null)
  const mainGoalId = ref<string | null>(null)
  const selectedGoalId = ref<string | null>(null)

  const currentGoal = computed<Goal>(() =>
    goals.value.find((g) => g.id === mainGoalId.value) ?? goals.value[0] ?? emptyGoal(),
  )
  const selectedGoal = computed<Goal>(() =>
    goals.value.find((g) => g.id === selectedGoalId.value) ?? currentGoal.value,
  )

  const report = ref<WeeklyReport>({ score: '-', completed: [], insight: '', nextSteps: [] })
  const reportLoading = ref(false)
  const reports = ref<Record<string, any>[]>([])
  const timelineSummary = ref<string | null>(null)
  const profile = ref<Record<string, any> | null>(null)
  const analyzingGoal = ref(false)
  const goalMemories = ref<MemoryItem[]>([])
  const actions = ref<Record<string, any>[]>([])
  const dailySuggestion = ref('')
  // 快速连续切换主目标时，建议请求可能乱序返回；只认最后一次发起的
  let suggestionRequestSeq = 0

  const rowToGoal = (row: Record<string, any>): Goal => {
    const status = row.status ?? 'exploring'
    const visual = visualFromId(row.id ?? '')
    return {
      id: row.id,
      title: row.title ?? '未命名目标',
      description: row.description ?? '',
    phase: goalPhase(status),
    progress: intValue(row.progress),
    status: goalStatusText(status),
    rawStatus: status,
    icon: visual.icon,
    accent: visual.accent,
    milestone: row.success_definition ?? '',
      aiSummary: row.ai_summary ?? '',
      stages: Array.isArray(row.stages) ? row.stages : [],
    }
  }

  const rowToMemory = (row: Record<string, any>): MemoryItem => {
    const type = row.type ?? 'thought'
    return {
      id: row.id,
      date: toDateLabel(row.created_at),
      month: toMonthLabel(row.created_at),
      type: memoryTypeText(type),
      title: row.summary ?? row.content ?? '',
      detail: row.content ?? '',
      icon: memoryIcon(type),
      tone: memoryTone(type),
    }
  }

  const rowToMessage = (row: Record<string, any>): Message => ({
    id: row.id,
    role: row.role === 'user' ? 'user' : 'assistant',
    content: row.content ?? '',
    time: toTimeLabel(row.created_at),
  })

  const resetAll = () => {
    goals.value = []
    observations.value = []
    memories.value = []
    messages.value = []
    activeSessionId.value = null
    mainGoalId.value = null
    selectedGoalId.value = null
  }

  async function loadGoals() {
    if (!user.value) return
    const { data, error: e } = await supabase
      .from('explore_growth_goals')
      .select('*')
      .neq('status', 'archived')
      .order('is_main_goal', { ascending: false })
      .order('created_at', { ascending: false })
    if (e) throw e
    goals.value = (data ?? []).map((row) => rowToGoal(row as Record<string, any>))
    mainGoalId.value = goals.value[0]?.id ?? null
    if (!selectedGoalId.value) selectedGoalId.value = mainGoalId.value
  }

  async function loadMemories() {
    if (!user.value) return
    const { data, error: e } = await supabase
      .from('explore_memory_items')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(50)
    if (e) throw e
    memories.value = (data ?? []).map((row) => rowToMemory(row as Record<string, any>))
  }

  async function loadObservations() {
    if (!user.value) return
    const { data, error: e } = await supabase
      .from('explore_ai_observations')
      .select('*')
      .eq('status', 'new')
      .order('created_at', { ascending: false })
      .limit(20)
    if (e) throw e
    const tones = ['violet', 'mint', 'amber'] as const
    observations.value = (data ?? []).map((row, index) => ({
      id: row.id,
      label: '探境观察',
      title: (row.content ?? '').slice(0, 24) || '新的观察',
      content: row.content ?? '',
      action: row.status === 'new' ? '标记已读' : '已读',
      tone: tones[index % tones.length],
    }))
  }

  async function generateObservations() {
    if (!user.value) return
    const { error: e } = await invokeWithRetry('explore-observations')
    if (e) throw e
    await loadObservations()
  }

  async function generateReport() {
    if (!user.value) return
    reportLoading.value = true
    try {
      const { data, error: e } = await invokeWithRetry('explore-weekly-report')
      if (e) throw e
      const r = data?.report
      if (r && typeof r === 'object') {
        report.value = {
          score: String(r.score ?? '-'),
          completed: Array.isArray(r.completed) ? r.completed.map(String) : [],
          insight: typeof r.insight === 'string' ? r.insight : '',
          nextSteps: Array.isArray(r.nextSteps) ? r.nextSteps.map(String) : [],
        }
      }
    }
    catch (err: any) {
      error.value = err?.message ?? '生成周报失败'
    }
    finally {
      reportLoading.value = false
    }
  }

  async function generateTimelineSummary() {
    if (!user.value) return
    const { data, error: e } = await invokeWithRetry('explore-timeline-summary')
    if (e) throw e
    timelineSummary.value = data?.summary ?? null
  }

  async function loadLatestReport() {
    if (!user.value) return
    const { data, error: e } = await supabase
      .from('explore_weekly_reports')
      .select('*')
      .eq('user_id', user.value.id)
      .order('week_start', { ascending: false })
      .limit(1)
    if (e) throw e
    const row = data?.[0]
    if (row) {
      report.value = {
        score: String(row.score ?? '-'),
        completed: Array.isArray(row.completed) ? row.completed.map(String) : [],
        insight: typeof row.insight === 'string' ? row.insight : '',
        nextSteps: Array.isArray(row.next_steps) ? row.next_steps.map(String) : [],
      }
    }
  }

  async function loadProfile() {
    if (!user.value) return
    const { data, error: e } = await supabase
      .from('explore_user_profiles')
      .select('*')
      .eq('user_id', user.value.id)
      .single()
    if (!e) profile.value = data
  }

  async function generateProfile() {
    if (!user.value) return
    const { data, error: e } = await invokeWithRetry('explore-profile')
    if (e) throw e
    profile.value = data?.profile ?? null
  }

  async function loadDailySuggestion() {
    if (!user.value) return
    const request = ++suggestionRequestSeq
    const { data, error: e } = await invokeWithRetry('explore-daily-suggestion')
    if (e) throw e
    if (request !== suggestionRequestSeq) return
    dailySuggestion.value = typeof data?.suggestion === 'string' ? data.suggestion : ''
  }

  async function loadReports() {
    if (!user.value) return
    const { data, error: e } = await supabase
      .from('explore_weekly_reports')
      .select('*')
      .eq('user_id', user.value.id)
      .order('week_start', { ascending: false })
    if (e) throw e
    reports.value = data ?? []
  }

  function selectReport(row: Record<string, any>) {
    report.value = {
      score: String(row.score ?? '-'),
      completed: Array.isArray(row.completed) ? row.completed.map(String) : [],
      insight: typeof row.insight === 'string' ? row.insight : '',
      nextSteps: Array.isArray(row.next_steps) ? row.next_steps.map(String) : [],
    }
  }

  async function loadActions() {
    if (!user.value) return
    const { data, error: e } = await supabase
      .from('explore_ai_actions')
      .select('*')
      .eq('user_id', user.value.id)
      .in('status', ['pending', 'sent'])
      .order('created_at', { ascending: false })
      .limit(5)
    if (e) throw e
    actions.value = data ?? []
  }

  async function runProactiveCheck() {
    if (!user.value) return
    const { error: e } = await invokeWithRetry('explore-proactive')
    if (e) throw e
    await loadActions()
  }

  async function dismissAction(id: string) {
    if (!user.value) return
    await supabase.from('explore_ai_actions').update({ status: 'read' }).eq('id', id)
    actions.value = actions.value.filter((a) => a.id !== id)
  }

  // 观察只有未读态会进入列表，标记已读后本地立即移除
  async function markObservationRead(id: string) {
    if (!user.value) return
    await supabase.from('explore_ai_observations').update({ status: 'read' }).eq('id', id)
    observations.value = observations.value.filter((o) => o.id !== id)
  }

  async function generateGoalAnalysis(goalId: string): Promise<GoalAnalysis | null> {
    if (!user.value) return null
    analyzingGoal.value = true
    try {
      const { data, error: e } = await invokeWithRetry('explore-goal-analysis', { goal_id: goalId })
      if (e) throw e
      const a = data?.analysis
      if (a && typeof a === 'object') {
        const analysis: GoalAnalysis = {
          summary: typeof a.summary === 'string' ? a.summary : '',
          observation: typeof a.observation === 'string' ? a.observation : '',
          suggestion: typeof a.suggestion === 'string' ? a.suggestion : '',
          actions: Array.isArray(a.actions) ? a.actions.map(String) : [],
        }
        const index = goals.value.findIndex((g) => g.id === goalId)
        if (index >= 0) {
          goals.value[index] = { ...goals.value[index], aiSummary: JSON.stringify(analysis) }
        }
        return analysis
      }
      return null
    }
    catch (err: any) {
      error.value = err?.message ?? '生成分析失败'
      return null
    }
    finally {
      analyzingGoal.value = false
    }
  }

  async function loadGoalMemories(goalId: string) {
    if (!user.value) return
    goalMemories.value = []
    const { data: events } = await supabase
      .from('explore_growth_events')
      .select('memory_id')
      .eq('goal_id', goalId)
      .eq('user_id', user.value.id)
    const ids = (events ?? []).map((e) => e.memory_id).filter(Boolean)
    if (!ids.length) return
    const { data: rows } = await supabase
      .from('explore_memory_items')
      .select('*')
      .in('id', ids)
      .order('created_at', { ascending: false })
    goalMemories.value = (rows ?? []).map((row) => rowToMemory(row as Record<string, any>))
  }

  async function loadConversations() {
    if (!user.value) return
    const { data: sessions, error: se } = await supabase
      .from('explore_conversation_sessions')
      .select('id,title,preview,updated_at')
      .order('updated_at', { ascending: false })
    if (se) throw se
    conversations.value = (sessions ?? []).map((s) => ({
      id: s.id,
      title: s.title ?? '新的对话',
      preview: s.preview ?? '',
    }))
    if (!conversations.value.length) {
      messages.value = []
      activeSessionId.value = null
      return
    }
    await selectConversation(conversations.value[0].id)
  }

  async function selectConversation(id: string) {
    if (!user.value) return
    activeSessionId.value = id
    const { data: rows, error: me } = await supabase
      .from('explore_conversations')
      .select('id,role,content,created_at')
      .eq('session_id', id)
      .order('created_at', { ascending: true })
    if (me) throw me
    messages.value = (rows ?? []).map((row) => rowToMessage(row as Record<string, any>))
  }

  // 切换/新建主目标后开启新对话：清空当前会话，
  // 下一条消息会创建新会话（见 sendMessage）
  function resetActiveConversation() {
    activeSessionId.value = null
    messages.value = []
  }

  async function loadAll() {
    loading.value = true
    error.value = null
    try {
      await Promise.all([loadGoals(), loadMemories(), loadObservations(), loadConversations(), loadLatestReport(), loadReports(), loadActions(), loadProfile(), loadDailySuggestion()])
      const hasData = goals.value.length > 0 || memories.value.length > 0
      if (hasData && observations.value.length === 0) {
        await generateObservations()
      }
      if (hasData) runProactiveCheck().catch(() => {})
    }
    catch (e: any) {
      error.value = e?.message ?? '加载失败'
    }
    finally {
      loading.value = false
    }
  }

  async function signIn(email: string, password: string): Promise<boolean> {
    error.value = null
    const { error: e } = await supabase.auth.signInWithPassword({ email, password })
    if (e) {
      error.value = e.message
      return false
    }
    return true
  }

  async function signUp(email: string, password: string, nickname?: string): Promise<boolean> {
    error.value = null
    const { error: e } = await supabase.auth.signUp({
      email,
      password,
      options: { data: nickname ? { nickname } : undefined },
    })
    if (e) {
      error.value = e.message
      return false
    }
    return true
  }

  async function signOut() {
    await supabase.auth.signOut()
  }

  function clearError() {
    error.value = null
  }

  async function createGoal(title: string, description: string, successDefinition?: string, stages: Stage[] = []): Promise<string> {
    if (!user.value) return ''
    const isFirst = goals.value.length === 0
    // 新建目标即当前专注：先清掉旧主目标标志再插入，
    // 直接插入 is_main_goal: true 会撞一人一主目标的唯一索引
    if (!isFirst) {
      const { error: me } = await supabase
        .from('explore_growth_goals')
        .update({ is_main_goal: false })
        .eq('user_id', user.value.id)
        .eq('is_main_goal', true)
      if (me) {
        error.value = me.message
        throw me
      }
    }
    const { data, error: e } = await supabase
      .from('explore_growth_goals')
      .insert({
        user_id: user.value.id,
        title,
        description,
        success_definition: successDefinition ?? null,
        stages,
        is_main_goal: true,
      })
      .select('*')
      .single()
    if (e) {
      error.value = e.message
      throw e
    }
    const goal = rowToGoal(data as Record<string, any>)
    goals.value = [goal, ...goals.value]
    mainGoalId.value = goal.id
    selectedGoalId.value = goal.id
    // 新建目标即当前专注：同样开启新对话（见 setMainGoal）
    resetActiveConversation()
    // 建议按「目标+天」缓存：新目标成为主目标后重新取，当天该目标首次会生成一次
    loadDailySuggestion().catch(() => {})
    if (isFirst) generateProfile().catch(() => {})
    return goal.id
  }

  async function planGoal(title: string, description: string, successDefinition: string, signal?: AbortSignal): Promise<Stage[]> {
    const { data, error: e } = await invokeWithRetry('explore-goal-plan', { title, description, success_definition: successDefinition }, 3, signal)
    if (e) throw e
    const raw = Array.isArray(data?.stages) ? data.stages : []
    return raw.map((s: any, i: number) => ({
      id: `s-${Date.now()}-${i}`,
      name: s?.name ?? `阶段 ${i + 1}`,
      description: s?.description ?? '',
      status: (i === 0 ? 'active' : 'not_started') as Stage['status'],
      actions: (Array.isArray(s?.actions) ? s.actions : []).map((a: any, j: number) => ({
        id: `a-${Date.now()}-${i}-${j}`,
        content: a?.content ?? '',
        done: false,
      })),
    }))
  }

  async function toggleAction(stageId: string, actionId: string) {
    const goal = goals.value.find((g) => g.id === selectedGoalId.value) ?? goals.value[0]
    if (!goal) return
    const stage = goal.stages.find((s) => s.id === stageId)
    const action = stage?.actions.find((a) => a.id === actionId)
    if (!action) return
    action.done = !action.done
    await supabase.from('explore_growth_goals').update({ stages: goal.stages }).eq('id', goal.id)
  }

  async function updateGoalStatus(goalId: string, status: string) {
    if (!user.value) return
    // loadGoals 会把 mainGoalId 重指到剩余目标上，先记下归档的是不是主目标
    const wasMainGoal = goalId === mainGoalId.value
    const goal = goals.value.find((g) => g.id === goalId)
    const patch: Record<string, any> = { status }
    if (status === 'completed') {
      patch.progress = 100
      if (goal?.stages.length) {
        patch.stages = goal.stages.map((s) => ({ ...s, status: 'completed' as const }))
      }
    }
    const { error: e } = await supabase
      .from('explore_growth_goals')
      .update(patch)
      .eq('id', goalId)
      .eq('user_id', user.value.id)
    if (e) {
      error.value = e.message
      throw e
    }
    await loadGoals()
    // 归档的是主目标时，主目标落到其它目标上，建议跟着重新取
    if (wasMainGoal && status === 'archived') loadDailySuggestion().catch(() => {})
  }

  async function goalChat(
    messages: { role: 'user' | 'assistant'; content: string }[],
    signal?: AbortSignal,
    onDelta?: (reply: string) => void,
  ): Promise<{
    reply: string
    goal: { title: string; description: string; success_definition: string } | null
  }> {
    if (!user.value) throw new Error('Authentication required.')
    try {
      if (!goalChatSessionId.value) {
        const { data: session, error: se } = await supabase
          .from('explore_conversation_sessions')
          .insert({ user_id: user.value.id, title: '与探境共创目标', mode: 'goal_creation' })
          .select('id')
          .single()
        if (se) throw se
        goalChatSessionId.value = session.id
        conversations.value = [
          { id: session.id, title: '与探境共创目标', preview: '' },
          ...conversations.value.filter((c) => c.id !== session.id),
        ]
        const first = messages[0]
        if (first?.role === 'assistant' && first.content.trim()) {
          await supabase.from('explore_conversations').insert({
            session_id: session.id,
            user_id: user.value.id,
            role: 'assistant',
            content: first.content,
          })
        }
      }
      const last = messages[messages.length - 1]
      if (last?.role === 'user' && last.content.trim()) {
        await supabase.from('explore_conversations').insert({
          session_id: goalChatSessionId.value,
          user_id: user.value.id,
          role: 'user',
          content: last.content,
        })
      }
    } catch (pe: any) {
      error.value = pe?.message ?? '目标共创对话保存失败'
    }

    const { data: sessionData } = await supabase.auth.getSession()
    const accessToken = sessionData.session?.access_token
    if (!accessToken) throw new Error('Authentication required.')

    const url = `${runtime.supabaseUrl}/functions/v1/explore-goal-chat`
    let reply = ''
    let goal: { title: string; description: string; success_definition: string } | null = null
    let lastErr: any = null
    let started = false

    for (let attempt = 0; attempt < 3; attempt++) {
      if (signal?.aborted) throw new DOMException('Aborted', 'AbortError')
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            apikey: runtime.supabaseAnonKey,
            'Content-Type': 'application/json',
            Accept: 'text/event-stream',
          },
          body: JSON.stringify({ messages }),
          signal,
        })
        if (!res.ok || !res.body) {
          const errBody = await res.json().catch(() => null)
          throw new Error(errBody?.error ?? `HTTP ${res.status}`)
        }
        const reader = res.body.getReader()
        const decoder = new TextDecoder()
        let buffer = ''
        const processPayload = (payload: string) => {
          if (!payload) return
          const data = JSON.parse(payload)
          if (data.error) throw new Error(data.error)
          if (typeof data.reply === 'string') {
            started = true
            reply += data.reply
            onDelta?.(reply)
          }
          if (data.goal !== undefined) goal = data.goal
        }
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          buffer += decoder.decode(value, { stream: true })
          const events = buffer.split('\n\n')
          buffer = events.pop() ?? ''
          for (const ev of events) {
            for (const line of ev.split('\n')) {
              const t = line.trim()
              if (!t.startsWith('data:')) continue
              processPayload(t.slice(5).trim())
            }
          }
        }
        if (buffer.trim()) {
          for (const line of buffer.split('\n')) {
            const t = line.trim()
            if (!t.startsWith('data:')) continue
            processPayload(t.slice(5).trim())
          }
        }
        if (reply && goalChatSessionId.value) {
          try {
            await supabase.from('explore_conversations').insert({
              session_id: goalChatSessionId.value,
              user_id: user.value.id,
              role: 'assistant',
              content: reply,
            })
            await supabase
              .from('explore_conversation_sessions')
              .update({ preview: reply })
              .eq('id', goalChatSessionId.value)
            conversations.value = conversations.value.map((c) =>
              c.id === goalChatSessionId.value ? { ...c, preview: reply } : c,
            )
          } catch (pe: any) {
            error.value = pe?.message ?? '目标共创对话保存失败'
          }
        }
        return { reply, goal }
      } catch (e: any) {
        lastErr = e
        if (signal?.aborted || started) throw e
        await new Promise((resolve) => setTimeout(resolve, 1200 * (attempt + 1)))
      }
    }
    throw lastErr
  }

  async function setMainGoal(id: string) {
    if (!user.value) return
    // 已是主目标就跳过，避免点开当前主目标把对话误清成新对话
    if (id === mainGoalId.value) return
    const { error: e1 } = await supabase
      .from('explore_growth_goals')
      .update({ is_main_goal: false })
      .eq('user_id', user.value.id)
      .eq('is_main_goal', true)
    if (e1) {
      error.value = e1.message
      return
    }
    const { error: e2 } = await supabase
      .from('explore_growth_goals')
      .update({ is_main_goal: true })
      .eq('id', id)
    if (e2) {
      error.value = e2.message
      return
    }
    const target = goals.value.find((g) => g.id === id)
    if (target) goals.value = [target, ...goals.value.filter((g) => g.id !== id)]
    mainGoalId.value = id
    // 新目标配新对话：进对话页保持空态，第一条消息创建新会话
    resetActiveConversation()
    // 建议按「目标+天」缓存：切换后重新取，新目标当天首次会生成一次
    loadDailySuggestion().catch(() => {})
  }

  function focusGoal(id: string) {
    if (goals.value.some((g) => g.id === id)) selectedGoalId.value = id
  }

  // 逐块读取 SSE，把每个 data 负载交给 onDelta；返回结束帧里携带的最终回复
  async function consumeConversationStream(
    url: string,
    accessToken: string,
    body: Record<string, unknown>,
    onDelta: (text: string) => void,
  ): Promise<string> {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        apikey: runtime.supabaseAnonKey,
        'Content-Type': 'application/json',
        Accept: 'text/event-stream',
      },
      body: JSON.stringify(body),
    })
    if (!res.ok || !res.body) {
      const errBody = await res.json().catch(() => null)
      throw new Error(errBody?.error ?? `HTTP ${res.status}`)
    }
    const reader = res.body.getReader()
    const decoder = new TextDecoder()
    let buffer = ''
    let finalReply = ''
    const handle = (payload: string) => {
      if (!payload) return
      const data = JSON.parse(payload)
      if (data?.error) throw new Error(data.error)
      if (data?.done === true) {
        if (typeof data.reply === 'string') finalReply = data.reply
        return
      }
      if (typeof data?.reply === 'string' && data.reply) onDelta(data.reply)
    }
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      buffer += decoder.decode(value, { stream: true })
      const events = buffer.split('\n\n')
      buffer = events.pop() ?? ''
      for (const event of events) {
        for (const line of event.split('\n')) {
          const trimmed = line.trim()
          if (!trimmed.startsWith('data:')) continue
          handle(trimmed.slice(5).trim())
        }
      }
    }
    return finalReply
  }

  async function sendMessage(content: string, mode: 'normal' | 'low_mood' = 'normal') {
    const text = content.trim()
    if (!text || !user.value) return

    messages.value = [
      ...messages.value,
      { id: `m-${Date.now()}`, role: 'user', content: text, time: toTimeLabel(new Date().toISOString()) },
    ]
    let replyId: string | null = null

    try {
      if (!activeSessionId.value) {
        const { data: session, error: se } = await supabase
          .from('explore_conversation_sessions')
          .insert({ user_id: user.value.id, title: '新的对话', mode })
          .select('id')
          .single()
        if (se) throw se
        activeSessionId.value = session.id
        conversations.value = [{ id: session.id, title: '新的对话', preview: text }, ...conversations.value]
        // 新会话先落一条 AI 欢迎语（与目标共创的开场一致），失败不阻塞发送；
        // 本地同步补上，避免发送后欢迎语凭空消失
        const { error: ge } = await supabase.from('explore_conversations').insert({
          session_id: activeSessionId.value,
          user_id: user.value.id,
          role: 'assistant',
          content: CHAT_GREETING,
        })
        if (!ge) messages.value = [chatGreetingMessage(), ...messages.value]
      }

      await supabase.from('explore_conversations').insert({
        session_id: activeSessionId.value,
        user_id: user.value.id,
        role: 'user',
        content: text,
      })

      const sessionData = await supabase.auth.getSession()
      const accessToken = sessionData.data.session?.access_token
      if (!accessToken) throw new Error('Authentication required.')

      // 占位消息随增量更新，避免等待期间界面没有反馈
      replyId = `m-${Date.now()}-a`
      messages.value = [
        ...messages.value,
        { id: replyId, role: 'assistant', content: '', time: toTimeLabel(new Date().toISOString()) },
      ]
      const updateReply = (value: string) => {
        messages.value = messages.value.map((m) => (m.id === replyId ? { ...m, content: value } : m))
      }

      let reply = ''
      let started = false
      let finished = false
      let lastErr: any = null
      for (let attempt = 0; attempt < 3 && !finished; attempt++) {
        try {
          const finalReply = await consumeConversationStream(
            `${runtime.supabaseUrl}/functions/v1/explore-conversation`,
            accessToken,
            { session_id: activeSessionId.value, mode },
            (delta) => {
              started = true
              reply += delta
              updateReply(reply)
            },
          )
          // 服务端交回的最终文本是权威版本：模型返回短纯文本时不会有增量
          if (finalReply && finalReply !== reply) {
            reply = finalReply
            updateReply(reply)
          }
          finished = true
        }
        catch (e: any) {
          lastErr = e
          // 已经吐过内容就不能重试，否则用户会看到重复文本
          if (started) throw e
          await new Promise((resolve) => setTimeout(resolve, 1200 * (attempt + 1)))
        }
      }
      if (!finished) throw lastErr

      const conv = conversations.value.find((c) => c.id === activeSessionId.value)
      if (conv) conv.preview = reply

      // 助手回复、记忆落库、成长事件、向量化、目标阶段更新均由后端 explore-conversation 完成，这里只刷新本地状态
      await loadMemories()
      await loadGoals()
    }
    catch (e: any) {
      // 一个增量都没收到时，移除空气泡
      if (replyId) messages.value = messages.value.filter((m) => m.id !== replyId || m.content !== '')
      error.value = e?.message ?? '发送失败'
    }
  }

  onMounted(async () => {
    const { data } = await supabase.auth.getSession()
    user.value = data.session?.user ?? null
    authReady.value = true
    if (user.value) await loadAll()

    supabase.auth.onAuthStateChange((_event, session) => {
      user.value = session?.user ?? null
      if (session?.user) loadAll()
      else resetAll()
    })
  })

  return {
    user,
    authReady,
    loading,
    error,
    goals,
    currentGoal,
    selectedGoal,
    observations: readonly(observations),
    memories: readonly(memories),
    messages: readonly(messages),
    conversations: readonly(conversations),
    report,
    reportLoading: readonly(reportLoading),
    reports: readonly(reports),
    timelineSummary: readonly(timelineSummary),
    profile: readonly(profile),
    dailySuggestion: readonly(dailySuggestion),
    analyzingGoal: readonly(analyzingGoal),
    goalMemories: readonly(goalMemories),
    actions: readonly(actions),
    signIn,
    signUp,
    signOut,
    clearError,
    generateReport,
    selectReport,
    generateTimelineSummary,
    generateProfile,
    loadDailySuggestion,
    generateGoalAnalysis,
    loadGoalMemories,
    dismissAction,
    markObservationRead,
    sendMessage,
    selectConversation,
    setMainGoal,
    focusGoal,
    resetGoalChat,
    createGoal,
    planGoal,
    toggleAction,
    updateGoalStatus,
    goalChat,
    refresh: loadAll,
  }
}
