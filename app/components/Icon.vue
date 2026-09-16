<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(defineProps<{ name: string; size?: number }>(), { size: 20 })

const icons: Record<string, string[]> = {
  bell: ['M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9', 'M10 21h4'],
  home: ['M3 10.5 12 3l9 7.5', 'M5.5 9.5V21h13V9.5', 'M9 21v-6h6v6'],
  growth: ['M4 19V5', 'M4 19h16', 'm7 15 3-4 3 2 4-6'],
  memory: ['M5 4h14v16H5z', 'M8 8h8', 'M8 12h8', 'M8 16h5'],
  chat: ['M20 11.5a7.5 7.5 0 0 1-7.5 7.5H7l-4 3v-6.2A7.5 7.5 0 1 1 20 11.5Z', 'M8 11h.01', 'M12 11h.01', 'M16 11h.01'],
  user: ['M20 21a8 8 0 0 0-16 0', 'M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z'],
  target: ['M12 3v3', 'M12 18v3', 'M3 12h3', 'M18 12h3', 'M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z', 'M12 13.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z'],
  arrow: ['M5 12h14', 'm13 6 6 6-6 6'],
  plus: ['M12 5v14', 'M5 12h14'],
  spark: ['m12 3 1.6 5.4L19 10l-5.4 1.6L12 17l-1.6-5.4L5 10l5.4-1.6L12 3Z', 'm19 16 .6 2.4L22 19l-2.4.6L19 22l-.6-2.4L16 19l2.4-.6L19 16Z'],
  check: ['m5 12 4 4L19 6'],
  decision: ['M6 4h12v16H6z', 'M9 8h6', 'M9 12h6', 'M9 16h3'],
  reflect: ['M4 5h16v12H8l-4 3V5Z', 'M8 9h8', 'M8 13h5'],
  globe: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z', 'M3 12h18', 'M12 3a14 14 0 0 1 0 18', 'M12 3a14 14 0 0 0 0 18'],
  sun: ['M12 4V2', 'M12 22v-2', 'm4.93 4.93-1.42-1.42', 'm20.49 20.49-1.42-1.42', 'M4 12H2', 'M22 12h-2', 'm4.93 19.07-1.42 1.42', 'm20.49 3.51-1.42 1.42', 'M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10Z'],
  menu: ['M4 6h16', 'M4 12h16', 'M4 18h16'],
  clock: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z', 'M12 7v5l3 2'],
  back: ['m15 18-6-6 6-6'],
  close: ['M18 6 6 18', 'm6 6 12 12'],
  send: ['m22 2-7 20-4-9-9-4Z', 'M22 2 11 13'],
  microphone: ['M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z', 'M19 10v2a7 7 0 0 1-14 0v-2', 'M12 19v3', 'M8 22h8'],
  more: ['M5 12h.01', 'M12 12h.01', 'M19 12h.01'],
  lock: ['M6 10h12v10H6z', 'M8 10V7a4 4 0 0 1 8 0v3'],
  chevron: ['m9 18 6-6-6-6']
}

const paths = computed(() => icons[props.name] ?? icons.spark)
</script>

<template>
  <svg class="icon" :width="props.size" :height="props.size" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <path v-for="path in paths" :key="path" :d="path" />
  </svg>
</template>
