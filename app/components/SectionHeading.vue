<script setup lang="ts">
withDefaults(defineProps<{ eyebrow: string; title: string; description?: string }>(), { description: '' })
</script>

<template>
  <div class="section-heading">
    <div><span class="eyebrow">{{ eyebrow }}</span><h1>{{ title }}</h1><p v-if="description">{{ description }}</p></div>
    <slot />
  </div>
</template>
