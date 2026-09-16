<script setup lang="ts">
import { renderMarkdown } from '~/utils/markdown'

const props = defineProps<{ text: string }>()
const html = computed(() => renderMarkdown(props.text))
</script>

<template>
  <div class="markdown-body" v-html="html" />
</template>
