<script setup>
import { ref, computed, onMounted } from 'vue'
import { supabase, unwrap } from '@/lib/supabase'
import { shrinkImage } from '@/lib/image'
import { useBusiness } from '@/lib/business'
import { money, plural } from '@/lib/format'
import Icon from '@/components/Icon.vue'
import SetupOffer from '@/components/SetupOffer.vue'
import { catalogWord } from '@/config/brand'
import { ask } from '@/lib/confirm'
import { toast } from '@/lib/toast'

const biz = useBusiness()
const categories = ref([])
const items = ref([])
const error = ref('')
const newCategory = ref('')
const editing = ref(null)   // produto aberto no formulário
const uploading = ref(false)
const T = computed(() => ({
  eyebrow: catalogWord(biz.business.category), title: 'Produtos', item: 'produto', itemCap: 'Produto', price: 'Preço (R$)',
  namePh: 'Ex.: X-burguer', descPh: 'Ex.: Pão, hambúrguer 150g, queijo, alface e tomate.', catPh: 'Ex.: Lanches, Porções, Bebidas',
  off: 'Esgotar', on: 'Disponibilizar', offBadge: 'Esgotado', available: 'Disponível para venda',
}))

const itemsByCategory = computed(() => {
  const map = Object.fromEntries(categories.value.map((c) => [c.id, []]))
  for (const i of items.value) map[i.category_id]?.push(i)
  return map
})

// Adicionais (migration 0032): grupos com opções e preço, dentro do produto.
const hasAddons = ref(false)
const newId = () => (crypto.randomUUID?.() ?? `${Date.now().toString(36)}${Math.random().toString(36).slice(2)}`)
const copyFrom = ref('')
const otherItemsWithAddons = computed(() => items.value.filter((i) => i.id !== editing.value?.id && i.addon_groups?.length))

function addGroup() {
  editing.value.addon_groups.push({ id: newId(), name: '', required: false, max: 3, options: [{ id: newId(), name: '', price: '' }] })
}
function addOption(g) { g.options.push({ id: newId(), name: '', price: '' }) }
function copyAddons() {
  const src = items.value.find((i) => i.id === copyFrom.value)
  if (!src) return
  // Ids novos: cada produto tem os seus.
  editing.value.addon_groups.push(...src.addon_groups.map((g) => ({
    id: newId(), name: g.name, required: Number(g.min) > 0, max: g.max ?? '',
    options: g.options.map((o) => ({ id: newId(), name: o.name, price: o.price })),
  })))
  copyFrom.value = ''
}
// Formulário -> jsonb guardado (ver 0032).
function cleanGroups(groups) {
  const out = []
  for (const g of groups) {
    const options = g.options
      .filter((o) => o.name.trim())
      .map((o) => ({ id: o.id, name: o.name.trim().slice(0, 60), price: Math.max(0, Number(o.price) || 0) }))
    if (!g.name.trim() && !options.length) continue
    if (!g.name.trim()) throw new Error('Dê um nome pra cada grupo de adicionais (ex.: Ingredientes adicionais).')
    if (!options.length) throw new Error(`O grupo "${g.name.trim()}" precisa de pelo menos uma opção.`)
    const max = g.max === '' || g.max == null ? null : Math.max(1, Math.min(Number(g.max), options.length))
    out.push({ id: g.id, name: g.name.trim().slice(0, 60), min: g.required ? 1 : 0, max, options })
  }
  return out
}
function groupHint(g) {
  const n = g.options.filter((o) => o.name.trim()).length
  const max = g.max === '' || g.max == null ? null : Number(g.max)
  if (g.required) return max === 1 ? 'O cliente escolhe 1 (obrigatório)' : `O cliente escolhe de 1 até ${max ?? n} (obrigatório)`
  return max ? `O cliente pode escolher até ${max}` : 'O cliente escolhe quantos quiser'
}

async function load() {
  const bid = biz.business.id
  hasAddons.value = !(await supabase.from('menu_items').select('addon_groups').limit(1)).error
  categories.value = unwrap(await supabase.from('menu_categories').select('*')
    .eq('business_id', bid).order('sort_order').order('name'))
  items.value = unwrap(await supabase.from('menu_items').select('*')
    .eq('business_id', bid).order('sort_order').order('name'))
}
onMounted(load)

async function run(promise) {
  error.value = ''
  const { error: err } = await promise
  if (err) error.value = err.message
  else toast('Cardápio atualizado.')
  await load()
  return !err
}

// ---- Categorias ----
async function addCategory() {
  const name = newCategory.value.trim()
  if (!name) return
  const sort = categories.value.length ? Math.max(...categories.value.map((c) => c.sort_order)) + 1 : 0
  if (await run(supabase.from('menu_categories').insert({ business_id: biz.business.id, name, sort_order: sort }))) {
    newCategory.value = ''
  }
}

function renameCategory(c) {
  const name = prompt('Novo nome da categoria:', c.name)
  if (name?.trim()) run(supabase.from('menu_categories').update({ name: name.trim() }).eq('id', c.id))
}

async function removeCategory(c) {
  const count = itemsByCategory.value[c.id].length
  if (!await ask(count ? `Excluir "${c.name}" e o que está dentro dela (${count})?` : `Excluir "${c.name}"?`)) return
  run(supabase.from('menu_categories').delete().eq('id', c.id))
}

async function moveCategory(index, delta) {
  const list = [...categories.value]
  const target = index + delta
  if (target < 0 || target >= list.length) return
  ;[list[index], list[target]] = [list[target], list[index]]
  await Promise.all(list.map((c, i) => supabase.from('menu_categories').update({ sort_order: i }).eq('id', c.id)))
  load()
}

// ---- Produtos ----
function newItem(category) {
  editing.value = { id: null, category_id: category.id, name: '', description: '', price: '', photo_url: null, available: true, addon_groups: [] }
  window.scrollTo({ top: 0, behavior: 'smooth' })
}

function editItem(i) {
  const { id, category_id, name, description, price, photo_url, available } = i
  const addon_groups = (i.addon_groups ?? []).map((g) => ({
    id: g.id, name: g.name, required: Number(g.min) > 0, max: g.max ?? '',
    options: g.options.map((o) => ({ ...o })),
  }))
  editing.value = { id, category_id, name, description, price, photo_url, available, addon_groups }
  window.scrollTo({ top: 0, behavior: 'smooth' })
}

async function saveItem() {
  const { id, addon_groups, ...fields } = editing.value
  const payload = { ...fields, price: Number(fields.price), business_id: biz.business.id }
  if (hasAddons.value) {
    try { payload.addon_groups = cleanGroups(addon_groups) } catch (e) { error.value = e.message; return }
  }
  const ok = await run(id
    ? supabase.from('menu_items').update(payload).eq('id', id)
    : supabase.from('menu_items').insert(payload))
  if (ok) editing.value = null
}

async function removeItem(i) {
  if (await ask(`Excluir "${i.name}"?`)) run(supabase.from('menu_items').delete().eq('id', i.id))
}

function toggleAvailable(i) {
  run(supabase.from('menu_items').update({ available: !i.available }).eq('id', i.id))
}

async function uploadPhoto(event) {
  const file = event.target.files[0]
  if (!file) return
  uploading.value = true
  error.value = ''
  const small = await shrinkImage(file, { max: 1000 })
  if (small.file.size > 5 * 1024 * 1024) { uploading.value = false; error.value = 'A foto precisa ter no máximo 5 MB.'; return }
  const path = `${biz.business.id}/menu/${Date.now()}.${small.ext}`
  const { error: err } = await supabase.storage.from('logos').upload(path, small.file)
  uploading.value = false
  if (err) { error.value = err.message; return }
  editing.value.photo_url = supabase.storage.from('logos').getPublicUrl(path).data.publicUrl
}
</script>

<template>
  <div class="page-header spread">
    <div>
      <p class="eyebrow">{{ T.eyebrow }}</p>
      <h1>{{ T.title }}</h1>
    </div>
    <a class="btn secondary" :href="`/${biz.business.slug}`" target="_blank">Ver minha vitrine</a>
  </div>
  <div v-if="error" class="error">{{ error }}</div>

  <!-- Formulário de produto -->
  <div v-if="editing" class="card glow">
    <div class="spread">
      <h3>{{ editing.id ? `Editar ${T.item}` : `Novo ${T.item}` }}</h3>
      <button class="btn small secondary" @click="editing = null">Fechar</button>
    </div>
    <form @submit.prevent="saveItem">
      <div class="row">
        <div class="field" style="flex-basis: 280px"><label>Nome</label><input v-model="editing.name" required :placeholder="T.namePh" /></div>
        <div class="field"><label>{{ T.price }}</label><input v-model="editing.price" type="number" min="0" step="0.01" required /></div>
        <div class="field">
          <label>Categoria</label>
          <select v-model="editing.category_id">
            <option v-for="c in categories" :key="c.id" :value="c.id">{{ c.name }}</option>
          </select>
        </div>
      </div>
      <div class="field">
        <label>Descrição <small>(opcional)</small></label>
        <textarea v-model="editing.description" rows="2" :placeholder="T.descPh" />
      </div>
      <div class="row" style="align-items: center">
        <img v-if="editing.photo_url" :src="editing.photo_url" alt="" class="shrink thumb large" />
        <div class="field">
          <label>Foto <small>(opcional, deixa sua vitrine muito mais bonita)</small></label>
          <input type="file" accept="image/png,image/jpeg,image/webp" @change="uploadPhoto" />
          <small v-if="uploading">Enviando foto...</small>
        </div>
      </div>
      <!-- Adicionais -->
      <div v-if="hasAddons" class="addons">
        <div class="addons-head">
          <strong>Adicionais <small class="muted">(opcional)</small></strong>
          <small class="muted">Ex.: "Ingredientes adicionais": cheddar + R$ 3,00, bacon + R$ 4,00. Ou "Ponto da carne", obrigatório, escolhe 1.</small>
        </div>
        <div v-for="(g, gi) in editing.addon_groups" :key="g.id" class="addon-group">
          <div class="row">
            <div class="field" style="flex: 2 1 220px"><label>Nome do grupo</label><input v-model="g.name" maxlength="60" placeholder="Ex.: Ingredientes adicionais" /></div>
            <div class="field" style="flex: 1 1 140px"><label>Máximo de escolhas</label><input v-model="g.max" type="number" min="1" placeholder="Sem limite" /></div>
          </div>
          <label class="addon-req"><input v-model="g.required" type="checkbox" /> Obrigatório escolher pelo menos 1</label>
          <small class="muted addon-hint">{{ groupHint(g) }}</small>
          <div v-for="(o, oi) in g.options" :key="o.id" class="addon-option">
            <input v-model="o.name" maxlength="60" placeholder="Ex.: Cheddar" aria-label="Nome do adicional" />
            <div class="addon-price"><span>+ R$</span><input v-model="o.price" type="number" min="0" step="0.01" placeholder="0,00" aria-label="Preço do adicional" /></div>
            <button type="button" class="btn small secondary" title="Tirar opção" @click="g.options.splice(oi, 1)">✕</button>
          </div>
          <div class="chips" style="margin-top: 8px">
            <button type="button" class="btn small secondary" @click="addOption(g)"><Icon name="plus" style="width: 14px; height: 14px" />Opção</button>
            <button type="button" class="btn small danger" @click="editing.addon_groups.splice(gi, 1)">Tirar grupo</button>
          </div>
        </div>
        <div class="chips">
          <button type="button" class="btn small secondary" @click="addGroup"><Icon name="plus" style="width: 14px; height: 14px" />Grupo de adicionais</button>
          <select v-if="otherItemsWithAddons.length" v-model="copyFrom" class="addon-copy" @change="copyAddons">
            <option value="">Copiar adicionais de outro {{ T.item }}...</option>
            <option v-for="i in otherItemsWithAddons" :key="i.id" :value="i.id">{{ i.name }}</option>
          </select>
        </div>
      </div>

      <div class="spread">
        <label><input v-model="editing.available" type="checkbox" /> {{ T.available }}</label>
        <button class="btn" :disabled="uploading">{{ editing.id ? 'Salvar' : `Adicionar ${T.item}` }}</button>
      </div>
    </form>
  </div>

  <!-- Nova categoria -->
  <form class="card" @submit.prevent="addCategory">
    <div class="row">
      <div class="field" style="margin: 0">
        <label>Nova categoria</label>
        <input v-model="newCategory" :placeholder="T.catPh" />
      </div>
      <div class="shrink"><button class="btn">Adicionar</button></div>
    </div>
  </form>

  <p v-if="!categories.length" class="notice">
    Comece criando as categorias ({{ T.catPh.replace('Ex.: ', 'ex.: ') }}). Depois adicione os {{ T.item }}s em cada uma.
  </p>
  <SetupOffer v-if="!categories.length" />

  <!-- Categorias e produtos -->
  <div v-for="(c, index) in categories" :key="c.id" class="card">
    <div class="spread" style="margin-bottom: 8px">
      <h3 style="margin: 0">{{ c.name }} <small>· {{ plural(itemsByCategory[c.id].length, T.item, T.item + 's') }}</small></h3>
      <div class="chips">
        <button class="btn small secondary" :disabled="index === 0" title="Subir" @click="moveCategory(index, -1)">↑</button>
        <button class="btn small secondary" :disabled="index === categories.length - 1" title="Descer" @click="moveCategory(index, 1)">↓</button>
        <button class="btn small secondary" @click="renameCategory(c)">Renomear</button>
        <button class="btn small danger" @click="removeCategory(c)">Excluir</button>
        <button class="btn small" @click="newItem(c)"><Icon name="plus" style="width: 15px; height: 15px" />{{ T.itemCap }}</button>
      </div>
    </div>

    <p v-if="!itemsByCategory[c.id].length" class="muted" style="margin: 8px 0 0">Nenhum {{ T.item }} nesta categoria.</p>
    <div v-for="i in itemsByCategory[c.id]" :key="i.id" class="item-row" :class="{ off: !i.available }">
      <img v-if="i.photo_url" :src="i.photo_url" alt="" class="thumb" />
      <div v-else class="thumb empty"><Icon name="utensils" /></div>
      <div style="flex: 1; min-width: 0">
        <strong>{{ i.name }}</strong>
        <span v-if="!i.available" class="badge red" style="margin-left: 6px">{{ T.offBadge }}</span>
        <span v-if="i.addon_groups?.length" class="badge" style="margin-left: 6px">com adicionais</span>
        <div class="muted desc">{{ i.description }}</div>
      </div>
      <strong class="price">{{ money(i.price) }}</strong>
      <div class="chips actions">
        <button class="btn small secondary" @click="toggleAvailable(i)">{{ i.available ? T.off : T.on }}</button>
        <button class="btn small secondary" @click="editItem(i)">Editar</button>
        <button class="btn small secondary" title="Excluir" @click="removeItem(i)">✕</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.item-row { display: flex; gap: 14px; align-items: center; padding: 12px 0; border-top: 1px solid var(--border); flex-wrap: wrap; }
.item-row.off { opacity: 0.6; }
.thumb { width: 56px; height: 56px; border-radius: 12px; object-fit: cover; flex-shrink: 0; border: 1px solid var(--border); }
.thumb.large { width: 84px; height: 84px; }
.thumb.empty { display: grid; place-items: center; background: var(--surface); color: var(--muted); }
.thumb.empty svg { width: 22px; height: 22px; }
.desc { font-size: 0.85rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.price { white-space: nowrap; }
.addons { margin: 14px 0; padding: 14px; border-radius: 14px; border: 1px dashed var(--border); display: grid; gap: 12px; }
.addons-head small { display: block; margin-top: 2px; }
.addon-group { padding: 12px; border-radius: 12px; background: var(--surface); border: 1px solid var(--border); }
.addon-req { display: flex; gap: 8px; align-items: center; font-size: 0.9rem; }
.addon-hint { display: block; margin: 4px 0 8px; }
.addon-option { display: flex; gap: 8px; align-items: center; margin-top: 6px; }
.addon-option > input { flex: 1; min-width: 0; }
.addon-price { display: flex; align-items: center; gap: 6px; width: 140px; flex-shrink: 0; }
.addon-price span { color: var(--muted); font-size: 0.85rem; white-space: nowrap; }
.addon-price input { min-width: 0; }
.addon-copy { max-width: 280px; }
@media (max-width: 640px) { .actions { width: 100%; } }
</style>
