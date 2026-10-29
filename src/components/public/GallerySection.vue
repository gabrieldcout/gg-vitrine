<script setup>
import { ref } from 'vue'
import { isVideo } from '@/lib/image'
import Icon from '@/components/Icon.vue'

defineProps({ photos: { type: Array, required: true } })
const open = ref(null)
</script>

<template>
  <div v-if="photos.length" class="gal-grid">
    <button v-for="p in photos" :key="p.id" class="gal-thumb" @click="open = p"
            :aria-label="p.caption || (isVideo(p.url) ? 'Ver vídeo' : 'Ampliar foto')">
      <template v-if="isVideo(p.url)">
        <video :src="`${p.url}#t=0.5`" muted playsinline preload="metadata" />
        <span class="gal-play"><Icon name="play" /></span>
      </template>
      <img v-else :src="p.url" :alt="p.caption || ''" loading="lazy" />
    </button>
    <div v-if="open" class="sheet-backdrop" @click="open = null">
      <figure class="viewer">
        <video v-if="isVideo(open.url)" :src="open.url" controls autoplay playsinline @click.stop />
        <img v-else :src="open.url" :alt="open.caption || ''" />
        <figcaption v-if="open.caption">{{ open.caption }}</figcaption>
      </figure>
    </div>
  </div>
</template>

<style scoped>
.viewer { margin: auto; max-width: min(920px, 94vw); text-align: center; }
.viewer img, .viewer video { max-height: 82vh; max-width: 100%; border-radius: 16px; }
.viewer figcaption { color: var(--silver); margin-top: 10px; }
.gal-thumb video { width: 100%; height: 100%; object-fit: cover; display: block; }
.gal-play {
  position: absolute; inset: 0; margin: auto; z-index: 1;
  width: 48px; height: 48px; border-radius: 50%;
  display: grid; place-items: center;
  background: rgba(0, 0, 0, 0.55); color: #fff; backdrop-filter: blur(4px);
}
.gal-play :deep(svg) { width: 20px; height: 20px; margin-left: 3px; fill: currentColor; }
</style>
