<script setup lang="ts">
import type { Goal, GoalAnalysis, MemoryItem, ViewId } from '~/composables/useExplore'

type DetailTab = 'overview' | 'phase' | 'action' | 'memory' | 'analysis'
const props = defineProps<{ goal: Goal; memories: readonly MemoryItem[]; profile: Record<string, any> | null; analyzing: boolean; toggleAction: (stageId: string, actionId: string) => void }>()
const emit = defineEmits<{ back: []; navigate: [view: ViewId]; generate: [goalId: string]; 'update-status': [goalId: string, status: string] }>()
const activeTab = shallowRef<DetailTab>('overview')
const tabs: { id: DetailTab; label: string }[] = [
  { id: 'overview', label: '概览' },
  { id: 'phase', label: '阶段' },
  { id: 'action', label: '行动' },
  { id: 'memory', label: '记录' },
  { id: 'analysis', label: '分析' }
]

const analysis = computed<GoalAnalysis | null>(() => {
  if (!props.goal.aiSummary) return null
  try {
    const parsed = JSON.parse(props.goal.aiSummary)
    return {
      summary: typeof parsed.summary === 'string' ? parsed.summary : '',
      observation: typeof parsed.observation === 'string' ? parsed.observation : '',
      suggestion: typeof parsed.suggestion === 'string' ? parsed.suggestion : '',
      actions: Array.isArray(parsed.actions) ? parsed.actions.map(String) : [],
    }
  }
  catch {
    return null
  }
})

const growthComposition = computed(() => {
  const raw = props.profile?.growth_composition
  return Array.isArray(raw)
    ? raw.map((x: any) => ({ name: x?.name ?? '', ratio: Number(x?.ratio ?? 0) }))
    : []
})

const growthDimensions = computed(() => {
  const raw = props.profile?.growth_dimensions
  return Array.isArray(raw)
    ? raw.map((x: any) => ({ name: x?.name ?? '', score: Number(x?.score ?? 0) }))
    : []
})

const statusActions = computed(() => {
  const s = props.goal.rawStatus
  const actions: { status: string; label: string }[] = []
  if (s === 'exploring') {
    actions.push(
      { status: 'active', label: '开始' },
      { status: 'archived', label: '归档' },
    )
  } else if (s === 'active') {
    actions.push(
      { status: 'paused', label: '暂停' },
      { status: 'completed', label: '标记完成' },
      { status: 'archived', label: '归档' },
    )
  } else if (s === 'paused' || s === 'blocked') {
    actions.push(
      { status: 'active', label: '恢复进行' },
      { status: 'completed', label: '标记完成' },
      { status: 'archived', label: '归档' },
    )
  } else if (s === 'completed') {
    actions.push(
      { status: 'active', label: '重新开始' },
      { status: 'archived', label: '归档' },
    )
  } else if (s === 'archived') {
    actions.push({ status: 'active', label: '恢复' })
  }
  return actions
})
</script>

<template>
  <div class="goal-detail-view page-enter">
    <header class="detail-header">
      <button class="back-button" type="button" @click="emit('back')"><Icon name="back" :size="18" /> 返回成长方向</button>
    </header>
    <div class="detail-title">
      <div><span class="goal-status"><i />{{ props.goal.status }}</span><h1>{{ props.goal.title }}</h1><p>{{ props.goal.description }}</p></div>
      <div class="detail-progress"><strong>{{ props.goal.progress }}<small>%</small></strong><span>整体进度</span></div>
    </div>
    <div class="detail-tabs">
      <button v-for="tab in tabs" :key="tab.id" type="button" :class="{ active: activeTab === tab.id }" @click="activeTab = tab.id">{{ tab.label }}</button>
    </div>

    <section v-if="activeTab === 'overview'" class="detail-tab-content">
      <div class="detail-main-card">
        <div class="section-label-row"><div><span class="eyebrow">整体进度</span><h2>{{ props.goal.phase }}</h2></div><span class="phase-tag">{{ props.goal.phase }}</span></div>
        <div class="big-progress"><span :style="{ width: `${props.goal.progress}%` }" /></div>
        <div class="progress-caption"><span>起点</span><strong>目标达成</strong></div>
        <div class="detail-summary"><div><span>当前阶段</span><strong>{{ props.goal.phase }}</strong></div><div><span>成功标准</span><strong>{{ props.goal.milestone || '尚未设定' }}</strong></div></div>
        <div v-if="statusActions.length" class="goal-status-actions">
          <button v-for="a in statusActions" :key="a.status" type="button" class="quiet-link" @click="emit('update-status', props.goal.id, a.status)">{{ a.label }}</button>
        </div>
        <div v-if="growthComposition.length" class="growth-dims">
          <span class="eyebrow">成长构成</span>
          <div v-for="dim in growthComposition" :key="dim.name" class="growth-dim">
            <span>{{ dim.name }}</span>
            <div class="growth-dim-bar"><span :style="{ width: `${dim.ratio}%` }" /></div>
            <strong>{{ dim.ratio }}%</strong>
          </div>
        </div>
        <div v-if="growthDimensions.length" class="growth-dims">
          <span class="eyebrow">能力维度</span>
          <div v-for="cap in growthDimensions" :key="cap.name" class="growth-dim">
            <span>{{ cap.name }}</span>
            <div class="growth-dim-bar"><span :style="{ width: `${cap.score}%` }" /></div>
            <strong>{{ cap.score }}%</strong>
          </div>
        </div>
        <div v-if="!growthComposition.length && !growthDimensions.length" class="detail-empty"><Icon name="spark" :size="20" /><p>生成画像后，这里会展示 AI 推断的能力维度与成长构成。</p></div>
      </div>
    </section>

    <section v-else-if="activeTab === 'phase'" class="detail-tab-content">
      <div class="phase-banner"><span class="eyebrow">当前阶段</span><h2>{{ props.goal.phase }}</h2><p>{{ props.goal.description }}</p></div>
      <div v-if="props.goal.stages.length" class="stages-list">
        <div v-for="(stage, si) in props.goal.stages" :key="stage.id" class="stage-card" :class="`stage-${stage.status}`">
          <div class="stage-card-head"><span class="stage-num">{{ si + 1 }}</span><div><strong>{{ stage.name }}</strong><span class="stage-status">{{ stage.status === 'completed' ? '已完成' : stage.status === 'active' ? '进行中' : '未开始' }}</span></div></div>
          <p>{{ stage.description }}</p>
          <div v-if="stage.actions.length" class="stage-action-list">
            <label v-for="action in stage.actions" :key="action.id" class="stage-action">
              <input type="checkbox" :checked="action.done" :disabled="stage.status !== 'active'" @change="props.toggleAction(stage.id, action.id)">
              <span>{{ action.content }}</span>
            </label>
          </div>
        </div>
      </div>
      <div v-else class="detail-empty"><Icon name="spark" :size="22" /><p>这个目标还没有拆解阶段。</p></div>
    </section>

    <section v-else-if="activeTab === 'action'" class="detail-tab-content">
      <div class="action-card"><span class="eyebrow">本阶段行动</span><h2>让下一步变得足够小</h2><div v-if="analysis?.actions.length" class="action-list"><label v-for="(action, index) in analysis.actions" :key="action"><input type="checkbox"><span class="fake-check">{{ index + 1 }}</span><strong>{{ action }}</strong></label></div><div v-else class="detail-empty"><Icon name="spark" :size="22" /><p>{{ props.analyzing ? '正在生成行动建议…' : '还没有行动建议。' }}</p></div><button class="primary-button" type="button" :disabled="props.analyzing" @click="emit('generate', props.goal.id)">{{ props.analyzing ? '生成中…' : analysis?.actions.length ? '重新生成' : '生成行动建议' }}</button></div>
    </section>

    <section v-else-if="activeTab === 'memory'" class="detail-tab-content">
      <div class="section-label-row"><div><span class="eyebrow">与目标有关的记忆</span><h2>这些时刻，正在推动你</h2></div></div>
      <div v-if="props.memories.length" class="detail-memory-list"><MemoryRow v-for="memory in props.memories.slice(0, 10)" :key="memory.id" :memory="memory" /></div>
      <div v-else class="detail-empty"><Icon name="memory" :size="22" /><p>还没有相关记忆。</p></div>
    </section>

    <section v-else class="detail-tab-content analysis-content">
      <template v-if="analysis">
        <div class="analysis-card"><div class="analysis-card-head"><div class="analysis-number">01</div><div><span class="eyebrow">阶段总结</span><h2>{{ analysis.summary }}</h2></div></div><p>{{ analysis.observation }}</p></div>
        <div class="analysis-card recommendation-card"><div class="analysis-card-head"><div class="analysis-number">02</div><div><span class="eyebrow">我的建议</span><h2>{{ analysis.suggestion }}</h2></div></div></div>
      </template>
      <div v-else class="detail-empty"><Icon name="spark" :size="22" /><p>{{ props.analyzing ? '正在生成分析…' : '还没有分析。' }}</p></div>
      <div class="analysis-chat-card"><span class="eyebrow">目标分析</span><h2>基于目标、记忆和对话，让探境帮你梳理方向。</h2><button class="quiet-link" type="button" :disabled="props.analyzing" @click="emit('generate', props.goal.id)">{{ props.analyzing ? '生成中…' : analysis ? '重新生成分析' : '生成分析' }} <Icon name="arrow" :size="15" /></button></div>
    </section>
  </div>
</template>

<style scoped>
.goal-status-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 14px;
  margin-top: 16px;
}
</style>
