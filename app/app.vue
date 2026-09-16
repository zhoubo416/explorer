<script setup lang="ts">
import type { ViewId } from '~/composables/useExplore'

const activeView = shallowRef<ViewId>('home')
const {
  user,
  authReady,
  error,
  loading,
  goals,
  currentGoal,
  selectedGoal,
  observations,
  memories,
  messages,
  conversations,
  report,
  reportLoading,
  reports,
  timelineSummary,
  profile,
  dailySuggestion,
  analyzingGoal,
  goalMemories,
  actions,
  sendMessage,
  selectConversation,
  generateReport,
  selectReport,
  generateTimelineSummary,
  generateProfile,
  generateGoalAnalysis,
  loadGoalMemories,
  dismissAction,
  markObservationRead,
  setMainGoal,
  resetGoalChat,
  focusGoal,
  createGoal,
  planGoal,
  toggleAction,
  updateGoalStatus,
  goalChat,
  signIn,
  signUp,
  signOut,
  clearError,
} = useExplore()

function navigate(view: ViewId) {
  activeView.value = view
  if (view === 'goal-create') resetGoalChat()
  if (view === 'report' && report.value?.score === '-') generateReport()
}

function openGoal(goalId: string) {
  focusGoal(goalId)
  loadGoalMemories(goalId)
  activeView.value = 'goal-detail'
}

async function handleGoalCreated(title: string, description: string, successDefinition: string, stages: any[]) {
  const id = await createGoal(title, description, successDefinition, stages)
  if (id) activeView.value = 'goal-created'
}
</script>

<template>
  <div v-if="!authReady" class="app-loading"><div class="loading-orb" /><span>正在加载…</span></div>
  <AuthScreen v-else-if="!user" :error="error" :sign-in="signIn" :sign-up="signUp" />
  <AppShell v-else :active-view="activeView" :user-email="user?.email ?? ''" @navigate="navigate" @sign-out="signOut">
    <div v-if="actions.length" class="proactive-banner"><Icon name="spark" :size="16" /><span>{{ actions[0].content }}</span><button type="button" @click="dismissAction(actions[0].id)">知道了</button></div>
    <div v-if="error" class="error-banner"><span>{{ error }}</span><button type="button" @click="clearError">关闭</button></div>
    <div v-if="loading" class="page-loading"><div class="loading-orb" /><span>正在加载你的数据…</span></div>
    <template v-else>
      <DashboardView
        v-if="activeView === 'home'"
        :current-goal="currentGoal"
        :observations="observations"
        :memories="memories"
        :daily-suggestion="dailySuggestion"
        @navigate="navigate"
        @mark-observation-read="markObservationRead"
      />
      <GoalListView
        v-else-if="activeView === 'growth'"
        :goals="goals"
        :current-goal-id="currentGoal.id"
        @set-main-goal="setMainGoal"
        @open-goal="openGoal"
        @create-goal="navigate('goal-create')"
        @navigate="navigate"
      />
      <GoalCreateView v-else-if="activeView === 'goal-create'" :goal-chat="goalChat" :plan-goal="planGoal" @back="navigate('growth')" @created="handleGoalCreated" />
      <GoalCreatedView v-else-if="activeView === 'goal-created'" :goal="selectedGoal" @navigate="navigate" />
      <GoalDetailView v-else-if="activeView === 'goal-detail'" :goal="selectedGoal" :memories="goalMemories" :profile="profile" :analyzing="analyzingGoal" :toggle-action="toggleAction" @back="navigate('growth')" @navigate="navigate" @generate="generateGoalAnalysis" @update-status="updateGoalStatus" />
      <MemoryView
        v-else-if="activeView === 'memory'"
        :memories="memories"
        :timeline-summary="timelineSummary"
        @navigate="navigate"
        @generate-summary="generateTimelineSummary"
      />
      <ChatView
        v-else-if="activeView === 'chat'"
        :messages="messages"
        :conversations="conversations"
        @send="sendMessage"
        @select-conversation="selectConversation"
      />
      <ReportView v-else :report="report" :loading="reportLoading" :reports="reports" :profile="profile" @navigate="navigate" @regenerate="generateReport" @select="selectReport" @generate-profile="generateProfile" />
    </template>
  </AppShell>
</template>
