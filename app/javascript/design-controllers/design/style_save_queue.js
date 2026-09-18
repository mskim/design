// Save queue for the paragraph style panel (pure: no DOM; node-tested).
//
// • One request in flight at a time, sent in the order the user acted.
// • A job whose key matches one still waiting replaces it and moves to the
//   back (the newest value wins) — unless a revert-all (":style") or push
//   (":push") waits after that one: then it is appended, because sending the
//   newer value before the barrier would reorder what the user did.
// • A request asks for a preview only when nothing waits behind it, so a
//   burst of saves renders the preview once. Enqueues in one tick form a burst.
// • A failed request is reported (status "error") but never stops the queue.
// • send(job, { renderPreview }) resolves to { ok, apply }; apply() (render
//   the response) runs after the job has left the in-flight slot.

const FIELD_NAME = /^paragraph_style\[([a-z_]+)\]$/

// "paragraph_style[font_size]" → "font_size"; anything else → null.
export function fieldFromName(name) {
  const match = FIELD_NAME.exec(name ?? "")
  return match ? match[1] : null
}

// Keep a control's local value through a morph while its save is unanswered,
// or while it is dirty (its value differs from its committed attributes:
// typing, or a scrub-drag, which never focuses the input).
export function keepsLocalValue({ pending, dirty }) {
  return pending || dirty
}

// Jobs that whole-style edits order around: never coalesced across.
const BARRIERS = new Set([ ":style", ":push" ])

export class StyleSaveQueue {
  constructor({ send, onStatus = () => {} }) {
    this.send = send
    this.onStatus = onStatus
    this.waiting = []
    this.inFlight = null
    this.failed = false
    this.scheduled = false
    this.idleWaiters = []
  }

  get busy() { return this.inFlight !== null || this.waiting.length > 0 }

  isPending(key) { return this.inFlight?.key === key || this.waiting.some((job) => job.key === key) }

  enqueue(job) {
    if (!this.busy) this.failed = false // a new burst
    const i = this.waiting.findIndex((waiting) => waiting.key === job.key)
    const barrierAfter = i >= 0 && this.waiting.slice(i + 1).some((waiting) => BARRIERS.has(waiting.key))
    if (i >= 0 && !barrierAfter) this.waiting.splice(i, 1)
    this.waiting.push(job)
    this.onStatus("saving")
    this.schedule()
  }

  whenIdle() {
    if (!this.busy && !this.scheduled) return Promise.resolve()
    return new Promise((resolve) => this.idleWaiters.push(resolve))
  }

  schedule() {
    if (this.scheduled || this.inFlight) return
    this.scheduled = true
    queueMicrotask(() => { this.scheduled = false; this.next() })
  }

  async next() {
    if (this.inFlight) return
    const job = this.waiting.shift()
    if (!job) return this.settle()
    this.inFlight = job
    let result
    try {
      result = await this.send(job, { renderPreview: this.waiting.length === 0 })
    } catch {
      result = { ok: false }
    }
    this.inFlight = null
    if (!result?.ok) this.failed = true
    try { result?.apply?.() } catch { this.failed = true }
    this.next()
  }

  settle() {
    this.onStatus(this.failed ? "error" : "saved")
    this.idleWaiters.splice(0).forEach((resolve) => resolve())
  }
}
