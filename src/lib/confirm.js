import { reactive } from 'vue'

// Pergunta de confirmação no lugar do confirm() do navegador.
// Uso: if (!(await ask('Excluir o serviço?', { danger: true }))) return
export const dialog = reactive({ open: false, text: '', confirmLabel: 'Confirmar', danger: false, resolve: null })

export function ask(text, { confirmLabel, danger } = {}) {
  // Palavras de ação que não dá pra desfazer deixam o botão vermelho sozinhas.
  const destructive = danger ?? /^(excluir|remover|cancelar|tirar|encerrar|sair)/i.test(text.trim())
  return new Promise((resolve) => {
    dialog.resolve?.(false)
    Object.assign(dialog, {
      open: true, text, danger: destructive, resolve,
      confirmLabel: confirmLabel ?? (destructive ? 'Sim, confirmar' : 'Confirmar'),
    })
  })
}

export function answer(ok) {
  dialog.resolve?.(ok)
  Object.assign(dialog, { open: false, resolve: null })
}
