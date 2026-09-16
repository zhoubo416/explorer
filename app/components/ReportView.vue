<script setup lang="ts">
import type { ViewId, WeeklyReport } from '~/composables/useExplore'

const props = defineProps<{ report: WeeklyReport; loading: boolean; reports: readonly Record<string, any>[]; profile: Record<string, any> | null }>()
const emit = defineEmits<{ navigate: [view: ViewId]; regenerate: []; select: [row: Record<string, any>]; generateProfile: [] }>()

const weekLabel = computed(() => {
  const end = new Date()
  const start = new Date(end.getTime() - 6 * 86400000)
  const fmt = (d: Date) => d.toLocaleDateString('zh-CN', { month: 'numeric', day: 'numeric' })
  return `${fmt(start)} — ${fmt(end)}`
})

const isEmpty = computed(() =>
  props.report.score === '-' && props.report.completed.length === 0 && !props.report.insight,
)

function profileItems(key: string): string[] {
  const v = props.profile?.[key]
  return Array.isArray(v) ? v.map(String) : []
}
</script>

<template>
  <div class="inner-view report-view page-enter">
    <SectionHeading eyebrow="GROWTH OS · WEEKLY REFLECTION" title="本周成长报告" :description="weekLabel">
      <div class="report-history-row">
        <select v-if="props.reports.length" class="report-history-select" @change="(e) => emit('select', props.reports[Number((e.target as HTMLSelectElement).value)])">
          <option v-for="(r, i) in props.reports" :key="r.id" :value="i">{{ r.week_start }} — {{ r.week_end }}</option>
        </select>
        <button class="quiet-link" type="button" :disabled="props.loading" @click="emit('regenerate')">重新生成 <Icon name="arrow" :size="15" /></button>
      </div>
    </SectionHeading>

    <section class="profile-card">
      <div class="profile-head"><span class="eyebrow">PROFILE · 你的画像</span><button class="quiet-link" type="button" @click="emit('generateProfile')">{{ props.profile ? '重新生成' : '生成画像' }}</button></div>
      <h2>{{ props.profile?.ai_summary || '让探境更了解你' }}</h2>
      <template v-if="props.profile">
        <div v-for="group in [['personality', '性格'], ['values', '价值观'], ['interests', '兴趣'], ['strengths', '优势'], ['weaknesses', '待改进']]" :key="group[0]" class="profile-group">
          <span>{{ group[1] }}</span>
          <div class="profile-tags"><em v-for="item in profileItems(group[0])" :key="item">{{ item }}</em><em v-if="!profileItems(group[0]).length" class="profile-tag-empty">暂无</em></div>
        </div>
      </template>
      <p v-else class="report-empty">还没有画像，点击「生成画像」让探境从你的记忆里认识你。</p>
    </section>

    <div v-if="props.loading" class="page-loading"><div class="loading-orb" /><span>正在生成周报…</span></div>

    <div v-else-if="isEmpty" class="detail-empty"><Icon name="spark" :size="22" /><p>还没有周报，点击右上角「重新生成」。</p></div>

    <template v-else>
      <div class="report-score"><div><span class="eyebrow">本周评分</span><div class="score-line"><strong>{{ props.report.score }}</strong><span>/ 10</span></div><p>{{ props.report.insight }}</p></div><div class="score-orb"><Icon name="spark" :size="28" /></div></div>

      <div class="report-grid">
        <section class="report-card"><div class="section-label-row"><div><span class="eyebrow">本周完成</span><h2>你做到了这些</h2></div><Icon name="check" :size="20" /></div><ul v-if="props.report.completed.length" class="report-list"><li v-for="item in props.report.completed" :key="item"><span><Icon name="check" :size="13" /></span>{{ item }}</li></ul><p v-else class="report-empty">本周还没有完成的记录。</p></section>
        <section class="report-card insight-card"><div class="section-label-row"><div><span class="eyebrow">本周发现</span><h2>一个重要变化</h2></div><Icon name="spark" :size="20" /></div><p>{{ props.report.insight || '继续积累，变化会逐渐显现。' }}</p></section>
      </div>

      <section class="next-week-card"><div><span class="eyebrow">下一步建议</span><h2>把方向，再往前推一步</h2></div><div v-if="props.report.nextSteps.length" class="next-week-list"><div v-for="(step, index) in props.report.nextSteps" :key="step"><span>0{{ index + 1 }}</span><strong>{{ step }}</strong><Icon name="arrow" :size="15" /></div></div><p v-else class="report-empty">本周暂无额外建议。</p></section>
    </template>
  </div>
</template>
