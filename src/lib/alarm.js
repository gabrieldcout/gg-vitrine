// Alarme de "chegou cliente/pedido novo": três toques fortes, repetidos duas
// vezes. Gera um arquivo WAV aqui mesmo pra tocar num <audio>, que no iPhone
// toca mesmo com o botão do silencioso ligado (o Web Audio fica mudo nesse caso).
export function alarmUrl() {
  const rate = 22050
  const notes = []
  for (let r = 0; r < 2; r++) [988, 1319, 1568].forEach((f, i) => notes.push([r * 0.9 + i * 0.17, f]))
  const n = Math.round(rate * 1.9)
  const buf = new DataView(new ArrayBuffer(44 + n * 2))
  const str = (o, t) => [...t].forEach((c, k) => buf.setUint8(o + k, c.charCodeAt(0)))
  str(0, 'RIFF'); buf.setUint32(4, 36 + n * 2, true); str(8, 'WAVEfmt ')
  buf.setUint32(16, 16, true); buf.setUint16(20, 1, true); buf.setUint16(22, 1, true)
  buf.setUint32(24, rate, true); buf.setUint32(28, rate * 2, true); buf.setUint16(32, 2, true); buf.setUint16(34, 16, true)
  str(36, 'data'); buf.setUint32(40, n * 2, true)
  for (let k = 0; k < n; k++) {
    const t = k / rate
    let v = 0
    for (const [at, f] of notes) {
      const dt = t - at
      if (dt < 0 || dt > 0.16) continue
      const env = Math.min(1, dt / 0.01) * Math.min(1, (0.16 - dt) / 0.03)
      v += (Math.sin(2 * Math.PI * f * dt) > 0 ? 1 : -1) * 0.55 * env   // onda quadrada: corta o barulho do balcão
    }
    buf.setInt16(44 + k * 2, Math.max(-1, Math.min(1, v)) * 32767, true)
  }
  return URL.createObjectURL(new Blob([buf], { type: 'audio/wav' }))
}
