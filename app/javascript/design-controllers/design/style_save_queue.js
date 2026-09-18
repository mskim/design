// Save queue for the paragraph style panel (pure: no DOM; node-tested).
//
// • One request in flight at a time, sent in the order the user acted.
// • A job whose key matches the last one still waiting replaces it and moves
//   to the back (the newest value wins) — unless a revert-all (":style") or
//   push (":push") waits after that one: then it is appended, because sending
//   the newer value before the barrier would reorder what the user did. So a
//   barrier only blocks coalescing with jobs before it.
// • A request asks for a preview only when nothing waits behind it, so a
//   burst of saves renders the preview once. Enqueues in one tick form a burst.
// • A failed request is reported but never stops the queue. The burst ends as
//   "error" while some key's last result failed (a later success for the same
//   key clears its failure), else "saved".
// • send(job, { renderPreview }) resolves to { ok, apply }; apply() (render
//   the response) runs after the job has left the in-flight slot; a throwing
//   apply() counts as a failure.
// • stop() (the panel is gone): waiting jobs are dropped unsent and later
//   enqueues ignored; the request in flight still completes.

// Jobs that whole-style edits order around: never coalesced across.
const BARRIERS = new Set([ ":style", ":push" ])

export class StyleSaveQueue {
  constructor({ send, onStatus = () => {} }) {
    this.send = send
    this.onStatus = onStatus
    this.waiting = []
    this.inFlight = null
    this.failedKeys = new Set()
    this.stopped = false
    this.scheduled = false
    this.idleWaiters = []
  }

  get busy() { return this.inFlight !== null || this.waiting.length > 0 }

  isPending(key) { return this.inFlight?.key === key || this.waiting.some((job) => job.key === key) }

  enqueue(job) {
    if (this.stopped) return
    if (!this.busy) this.failedKeys.clear() // a new burst
    const i = this.waiting.findLastIndex((waiting) => waiting.key === job.key)
    const barrierAfter = i >= 0 && this.waiting.slice(i + 1).some((waiting) => BARRIERS.has(waiting.key))
    if (i >= 0 && !barrierAfter) this.waiting.splice(i, 1)
    this.waiting.push(job)
    this.onStatus("saving")
    this.schedule()
  }

  stop() {
    this.stopped = true
    this.waiting = []
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
    const job = this.stopped ? undefined : this.waiting.shift()
    if (!job) return this.settle()
    this.inFlight = job
    let result
    try {
      result = await this.send(job, { renderPreview: this.waiting.length === 0 })
    } catch {
      result = { ok: false }
    }
    this.inFlight = null
    let ok = result?.ok === true
    try { result?.apply?.() } catch { ok = false }
    if (ok) this.failedKeys.delete(job.key)
    else this.failedKeys.add(job.key)
    this.next()
  }

  settle() {
    this.onStatus(this.failedKeys.size > 0 ? "error" : "saved")
    this.idleWaiters.splice(0).forEach((resolve) => resolve())
  }
}
