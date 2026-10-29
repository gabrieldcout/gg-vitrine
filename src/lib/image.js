// Reduz uma foto no próprio navegador antes de subir pro Storage. Foto de
// celular chega com 3–10 MB e deixa a vitrine lenta no 4G; depois de reduzida
// fica em ~100–300 KB. PNG continua PNG (logo com fundo transparente); o resto
// vira JPEG. Se não der pra ler a imagem (ex.: HEIC), devolve o arquivo original.
export async function shrinkImage(file, { max = 1200, quality = 0.82 } = {}) {
  const keepPng = file.type === 'image/png'
  const fallback = { file, ext: file.name.split('.').pop().toLowerCase() }
  let img
  try {
    img = await loadImage(file)
  } catch {
    return fallback
  }
  const scale = Math.min(1, max / Math.max(img.width, img.height))
  // Já pequena e leve: não mexe.
  if (scale === 1 && file.size < 400 * 1024) return fallback
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(img.width * scale)
  canvas.height = Math.round(img.height * scale)
  const ctx = canvas.getContext('2d')
  if (!keepPng) {
    ctx.fillStyle = '#ffffff'   // JPEG não tem transparência
    ctx.fillRect(0, 0, canvas.width, canvas.height)
  }
  ctx.drawImage(img, 0, 0, canvas.width, canvas.height)
  const type = keepPng ? 'image/png' : 'image/jpeg'
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, type, quality))
  if (!blob || blob.size >= file.size) return fallback
  return { file: blob, ext: keepPng ? 'png' : 'jpg' }
}

function loadImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => { URL.revokeObjectURL(url); resolve(img) }
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('imagem ilegível')) }
    img.src = url
  })
}

// A galeria guarda fotos e vídeos na mesma tabela; o tipo sai da extensão.
export function isVideo(url) {
  return /\.(mp4|webm|mov|m4v)(\?|$)/i.test(url ?? '')
}
