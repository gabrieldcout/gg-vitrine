import { money, formatTime, formatDate, APPOINTMENT_STATUS } from './format'

// Impressão de comprovante / agenda do dia. Monta um HTML simples num iframe
// escondido e chama o print do navegador. O layout é estreito (cabe em
// impressora térmica de 80mm) e também sai bem numa folha A4.

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])

const STYLE = `
  * { box-sizing: border-box; }
  body { margin: 0; padding: 12px; font: 13px/1.4 Arial, Helvetica, sans-serif; color: #000; }
  .ticket { max-width: 300px; margin: 0 auto; }
  h1 { font-size: 16px; margin: 0; text-align: center; }
  .sub { text-align: center; font-size: 12px; margin: 2px 0 0; }
  hr { border: 0; border-top: 1px dashed #000; margin: 10px 0; }
  .row { display: flex; justify-content: space-between; gap: 8px; margin: 3px 0; }
  .row span:first-child { color: #333; }
  .row strong { text-align: right; }
  .total { font-size: 15px; }
  .notes { margin: 6px 0 0; white-space: pre-wrap; }
  .foot { text-align: center; font-size: 11px; margin-top: 10px; }
  table { width: 100%; border-collapse: collapse; }
  th, td { text-align: left; padding: 6px 4px; border-bottom: 1px solid #ccc; vertical-align: top; }
  th { font-size: 11px; text-transform: uppercase; }
  td small { display: block; color: #444; }
  .canceled { text-decoration: line-through; color: #777; }
  @page { margin: 8mm; }
`

function printHtml(title, body) {
  const iframe = document.createElement('iframe')
  iframe.setAttribute('aria-hidden', 'true')
  iframe.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0;'
  document.body.appendChild(iframe)
  const doc = iframe.contentDocument
  doc.open()
  doc.write(`<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>${esc(title)}</title><style>${STYLE}</style></head><body>${body}</body></html>`)
  doc.close()
  const win = iframe.contentWindow
  // Remove o iframe depois que a janela de impressão fecha.
  win.addEventListener('afterprint', () => setTimeout(() => iframe.remove(), 0))
  setTimeout(() => { win.focus(); win.print() }, 50)
}

// Comprovante de um agendamento.
export function printAppointment(a, business) {
  const tz = business.timezone
  const notes = a.notes ? `<hr><div><span>Observações</span><p class="notes">${esc(a.notes)}</p></div>` : ''
  printHtml(`Agendamento - ${a.customer?.name ?? ''}`, `
    <div class="ticket">
      <h1>${esc(business.name)}</h1>
      ${business.phone ? `<p class="sub">${esc(business.phone)}</p>` : ''}
      <hr>
      <div class="row"><span>Data</span><strong>${esc(formatDate(a.starts_at, tz))}</strong></div>
      <div class="row"><span>Horário</span><strong>${esc(formatTime(a.starts_at, tz))} às ${esc(formatTime(a.ends_at, tz))}</strong></div>
      <div class="row"><span>Cliente</span><strong>${esc(a.customer?.name)}</strong></div>
      ${a.customer?.phone ? `<div class="row"><span>Telefone</span><strong>${esc(a.customer.phone)}</strong></div>` : ''}
      <div class="row"><span>Serviço</span><strong>${esc(a.service?.name)}</strong></div>
      <div class="row"><span>${esc(business.staff_label)}</span><strong>${esc(a.professional?.name)}</strong></div>
      <div class="row"><span>Status</span><strong>${esc(APPOINTMENT_STATUS[a.status])}</strong></div>
      ${notes}
      <hr>
      <div class="row total"><span>Total</span><strong>${esc(money(a.price))}</strong></div>
      <p class="foot">Impresso em ${esc(new Date().toLocaleString('pt-BR', { timeZone: tz }))}</p>
    </div>`)
}

// Lista de agendamentos de um dia (a que está na tela, com o filtro aplicado).
export function printDay(list, business, dayLabel, total) {
  const tz = business.timezone
  const rows = list.map((a) => `
    <tr class="${a.status === 'canceled' ? 'canceled' : ''}">
      <td><strong>${esc(formatTime(a.starts_at, tz))}</strong><small>até ${esc(formatTime(a.ends_at, tz))}</small></td>
      <td>${esc(a.customer?.name)}${a.customer?.phone ? `<small>${esc(a.customer.phone)}</small>` : ''}</td>
      <td>${esc(a.service?.name)}<small>${esc(a.professional?.name)}</small>${a.notes ? `<small>Obs: ${esc(a.notes)}</small>` : ''}</td>
      <td>${esc(money(a.price))}<small>${esc(APPOINTMENT_STATUS[a.status])}</small></td>
    </tr>`).join('')
  printHtml(`Agenda - ${dayLabel}`, `
    <h1>${esc(business.name)}</h1>
    <p class="sub">${esc(dayLabel)}</p>
    <hr>
    <table>
      <thead><tr><th>Horário</th><th>Cliente</th><th>Serviço</th><th>Valor</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
    <hr>
    <div class="row total"><span>${list.length} agendamento(s) · previsto</span><strong>${esc(money(total))}</strong></div>`)
}

// Comanda de um pedido do cardápio.
export function printOrder(o, business) {
  const tz = business.timezone
  const items = (o.order_items ?? []).map((i) =>
    `<div class="row"><span>${esc(i.qty)}x ${esc(i.name)}</span><strong>${esc(money(i.total))}</strong></div>`).join('')
  const change = o.change_for ? ` · troco p/ ${esc(money(o.change_for))}` : ''
  printHtml(`Pedido #${o.number}`, `
    <div class="ticket">
      <h1>${esc(business.name)}</h1>
      ${business.phone ? `<p class="sub">${esc(business.phone)}</p>` : ''}
      <hr>
      <h1>PEDIDO #${esc(o.number)}</h1>
      <p class="sub">${esc(formatDate(o.created_at, tz))} às ${esc(formatTime(o.created_at, tz))}</p>
      <hr>
      <div class="row"><span>Cliente</span><strong>${esc(o.customer_name)}</strong></div>
      <div class="row"><span>Telefone</span><strong>${esc(o.phone)}</strong></div>
      <div class="row"><span>${o.mode === 'entrega' ? 'Entrega' : 'Retirada no local'}</span></div>
      ${o.mode === 'entrega' && o.address ? `<p class="notes">${esc(o.address)}</p>` : ''}
      <hr>
      ${items}
      <hr>
      <div class="row"><span>Subtotal</span><strong>${esc(money(o.subtotal))}</strong></div>
      ${o.fee_pending ? '<div class="row"><span>Entrega</span><strong>A COMBINAR</strong></div>'
        : Number(o.delivery_fee) ? `<div class="row"><span>Entrega</span><strong>${esc(money(o.delivery_fee))}</strong></div>` : ''}
      ${Number(o.discount) ? `<div class="row"><span>Desconto${o.coupon_code ? ` (${esc(o.coupon_code)})` : ''}</span><strong>-${esc(money(o.discount))}</strong></div>` : ''}
      <div class="row total"><span>Total</span><strong>${esc(money(o.total))}</strong></div>
      <div class="row"><span>Pagamento</span><strong>${esc(o.payment)}${change}</strong></div>
      ${o.notes ? `<hr><div><span>Observações</span><p class="notes">${esc(o.notes)}</p></div>` : ''}
      <p class="foot">Impresso em ${esc(new Date().toLocaleString('pt-BR', { timeZone: tz }))}</p>
    </div>`)
}
