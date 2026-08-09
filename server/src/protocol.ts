import { z } from 'zod'

const positiveLineNumber = z.coerce.number().int().min(1)

const previewDocumentSchema = z.object({
  content: z.string(),
  path: z.string(),
  line: positiveLineNumber.default(1),
})

const cursorUpdateSchema = z.object({
  line: positiveLineNumber,
})

const browserMessageSchema = z.discriminatedUnion('type', [
  z.object({
    type: z.literal('jump'),
    line: positiveLineNumber,
  }),
  z.object({
    type: z.literal('open_file'),
    href: z.string().min(1),
  }),
])

function normalizeEmptyLuaTable(value: unknown): unknown {
  return Array.isArray(value) && value.length === 0 ? {} : value
}

const previewFontSchema = z.preprocess(
  normalizeEmptyLuaTable,
  z.object({
    ui: z.string().optional(),
    mono: z.string().optional(),
    size: z.union([z.number().positive(), z.string().min(1)]).optional(),
  }),
)

const previewColorsSchema = z.preprocess(normalizeEmptyLuaTable, z.record(z.string(), z.string()))

const previewConfigSchema = z
  .object({
    theme: z.string().optional(),
    toc: z.boolean().optional(),
    toc_open: z.boolean().optional(),
    math: z.boolean().optional(),
    mermaid: z.boolean().optional(),
    emoji: z.boolean().optional(),
    raw_toggle: z.boolean().optional(),
    code_copy: z.boolean().optional(),
    scroll_sync: z.boolean().optional(),
    preserve_scroll: z.boolean().optional(),
    breaks: z.boolean().optional(),
    linkify: z.boolean().optional(),
    typographer: z.boolean().optional(),
    allow_html: z.boolean().optional(),
    sanitize: z.boolean().optional(),
    max_width: z.number().positive().optional(),
    font: previewFontSchema.optional(),
    colors: previewColorsSchema.optional(),
    custom_css: z.string().optional(),
  })
  .catchall(z.unknown())

export type PreviewDocument = z.infer<typeof previewDocumentSchema>
export type BrowserMessage = z.infer<typeof browserMessageSchema>

export function parsePreviewDocument(value: unknown): PreviewDocument {
  return previewDocumentSchema.parse(value)
}

export function parseCursorLine(value: unknown): number {
  return cursorUpdateSchema.parse(value).line
}

export function parseBrowserMessage(value: unknown): BrowserMessage {
  return browserMessageSchema.parse(value)
}

export function parsePreviewConfig(serializedConfig: string | undefined): Record<string, unknown> {
  return previewConfigSchema.parse(JSON.parse(serializedConfig || '{}'))
}
