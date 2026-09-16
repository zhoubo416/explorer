<script setup lang="ts">
import type { ViewId } from '~/composables/useExplore'

const props = defineProps<{ activeView: ViewId; userEmail: string }>()
const emit = defineEmits<{ navigate: [view: ViewId]; signOut: [] }>()

const navItems: { id: ViewId; label: string; icon: string }[] = [
  { id: 'home', label: '首页', icon: 'home' },
  { id: 'growth', label: '成长', icon: 'growth' },
  { id: 'memory', label: '记忆', icon: 'memory' },
  { id: 'chat', label: '对话', icon: 'chat' },
  { id: 'report', label: '我的', icon: 'user' }
]
</script>

<template>
  <div class="app-shell">
    <aside class="sidebar">
      <div class="brand-mark">
        <img class="brand-logo" src="/logo.png" alt="探境" width="34" height="34" />
        <div>
          <strong>探境</strong>
          <span>EXPLORE</span>
        </div>
      </div>

      <div class="sidebar-intro">
        <span class="eyebrow">YOUR GROWTH COMPANION</span>
        <p>让每一次思考，<br>都成为靠近自己的路。</p>
      </div>

      <nav class="primary-nav" aria-label="主导航">
        <button
          v-for="item in navItems"
          :key="item.id"
          class="nav-item"
          :class="{ active: props.activeView === item.id }"
          type="button"
          @click="emit('navigate', item.id)"
        >
          <Icon :name="item.icon" :size="18" />
          <span>{{ item.label }}</span>
          <span v-if="item.id === 'chat'" class="nav-dot" />
        </button>
      </nav>

      <div class="sidebar-footer">
        <div class="privacy-note"><Icon name="lock" :size="14" /><span>你的成长记录，仅属于你</span></div>
        <div class="profile-mini"><div class="avatar avatar-small">{{ (props.userEmail || 'U').charAt(0).toUpperCase() }}</div><div><strong>{{ props.userEmail || '未登录' }}</strong><span>正在探索中</span></div><button class="signout-link" type="button" @click="emit('signOut')">退出</button></div>
      </div>
    </aside>

    <main class="main-stage">
      <header class="topbar">
        <div class="topbar-context"><span class="status-dot" /> AI 成长伙伴在线</div>
        <div class="topbar-actions"><div class="avatar">{{ (props.userEmail || 'U').charAt(0).toUpperCase() }}</div></div>
      </header>
      <div class="page-content"><slot /></div>
    </main>
  </div>
</template>
