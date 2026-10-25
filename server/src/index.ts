import { createServer } from './server.js'

export type { PreviewDocument } from './protocol.js'
export { createServer, type PreviewServerOptions } from './server.js'

if (import.meta.main) {
  const server = createServer({
    editorInput: process.stdin,
    onEditorEvent(message) {
      process.stdout.write(`MD_PEEK_EVENT=${JSON.stringify(message)}\n`)
    },
  })
  // Neovim owns this process; when it goes away (even abruptly) stdin ends, so exit instead of
  // lingering as an orphaned listener.
  process.stdin.on('end', () => process.exit(0))
  server.listen(Number(process.env.MD_PEEK_PORT || 0), '127.0.0.1', () => {
    const address = server.address()
    if (address && typeof address !== 'string') {
      process.stdout.write(`MD_PEEK_URL=http://127.0.0.1:${address.port}/\n`)
    }
  })
}
