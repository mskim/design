import { test } from "node:test"
import assert from "node:assert/strict"
import { StyleSaveQueue } from "../../app/javascript/design-controllers/design/style_save_queue.js"

// send() answered by hand: each call waits in `calls` until resolved or rejected.
function setup() {
  const calls = []
  const statuses = []
  const queue = new StyleSaveQueue({
    send: (job, opts) => new Promise((resolve, reject) => calls.push({ job, opts, resolve, reject })),
    onStatus: (status) => statuses.push(status)
  })
  return { queue, calls, statuses }
}
const tick = () => new Promise((resolve) => setImmediate(resolve))
const answer = async (call, result = { ok: true }) => { call.resolve(result); await tick() }

test("one request in flight at a time, in the order enqueued", async () => {
  const { queue, calls } = setup()
  queue.enqueue({ key: "font_size", value: "11" })
  queue.enqueue({ key: "text_align", value: "left" })
  await tick()
  assert.equal(calls.length, 1)
  assert.equal(calls[0].job.key, "font_size")
  await answer(calls[0])
  assert.equal(calls.length, 2)
  assert.equal(calls[1].job.key, "text_align")
})

test("a newer value for a waiting field replaces it and moves to the back", async () => {
  const { queue, calls } = setup()
  queue.enqueue({ key: "tracking", value: "1" })
  await tick() // tracking in flight
  queue.enqueue({ key: "font_size", value: "11" })
  queue.enqueue({ key: "text_align", value: "left" })
  queue.enqueue({ key: "font_size", value: "12" })
  await answer(calls[0]); await answer(calls[1]); await answer(calls[2])
  assert.equal(calls.length, 3, "font_size=11 is never sent")
  assert.deepEqual(calls.map((c) => [ c.job.key, c.job.value ]),
                   [ [ "tracking", "1" ], [ "text_align", "left" ], [ "font_size", "12" ] ])
})

test("coalescing never jumps over a waiting revert-all: both values are sent, around it", async () => {
  const { queue, calls } = setup()
  queue.enqueue({ key: "font_size", value: "11" })
  await tick() // 11 in flight
  queue.enqueue({ key: "font_size", value: "12" })
  queue.enqueue({ key: ":style" })
  queue.enqueue({ key: "font_size", value: "13" })
  for (let i = 0; i < 4; i++) await answer(calls[i])
  assert.deepEqual(calls.map((c) => c.job.value ?? c.job.key), [ "11", "12", ":style", "13" ])
})

test("coalescing never jumps over a waiting push either", async () => {
  const { queue, calls } = setup()
  queue.enqueue({ key: "tracking", value: "1" })
  await tick()
  queue.enqueue({ key: "font_size", value: "12" })
  queue.enqueue({ key: ":push" })
  queue.enqueue({ key: "font_size", value: "13" })
  for (let i = 0; i < 4; i++) await answer(calls[i])
  assert.deepEqual(calls.map((c) => c.job.value ?? c.job.key), [ "1", "12", ":push", "13" ])
})

test("after a barrier, later values of the same field still coalesce with each other", async () => {
  const { queue, calls } = setup()
  queue.enqueue({ key: "tracking", value: "1" })
  await tick()
  queue.enqueue({ key: ":style" })
  queue.enqueue({ key: "font_size", value: "12" })
  queue.enqueue({ key: "font_size", value: "13" })
  for (let i = 0; i < 3; i++) await answer(calls[i])
  assert.deepEqual(calls.map((c) => c.job.value ?? c.job.key), [ "1", ":style", "13" ])
})

test("only the last request of a burst asks for a preview", async () => {
  const { queue, calls } = setup()
  queue.enqueue({ key: "a" }); queue.enqueue({ key: "b" }); queue.enqueue({ key: "c" })
  await tick()
  await answer(calls[0]); await answer(calls[1]); await answer(calls[2])
  assert.deepEqual(calls.map((c) => c.opts.renderPreview), [ false, false, true ])
})

test("a request sent with nothing behind it asks for a preview", async () => {
  const { queue, calls } = setup()
  queue.enqueue({ key: "a" })
  await tick()
  queue.enqueue({ key: "b" })
  await answer(calls[0]); await answer(calls[1])
  assert.deepEqual(calls.map((c) => c.opts.renderPreview), [ true, true ])
})

test("errors don't stop the queue; the burst ends as an error; the next burst starts clean", async () => {
  const { queue, calls, statuses } = setup()
  queue.enqueue({ key: "a" }); queue.enqueue({ key: "b" })
  await tick()
  calls[0].reject(new Error("network")); await tick()
  assert.equal(calls.length, 2, "b is still sent")
  await answer(calls[1], { ok: false })
  assert.equal(statuses.at(-1), "error")
  queue.enqueue({ key: "c" }); await tick(); await answer(calls[2])
  assert.equal(statuses.at(-1), "saved")
})

test("status: saving while busy, saved when all answered", async () => {
  const { queue, calls, statuses } = setup()
  queue.enqueue({ key: "a" })
  assert.equal(statuses.at(-1), "saving")
  await tick(); await answer(calls[0])
  assert.equal(statuses.at(-1), "saved")
  await queue.whenIdle()
})

test("apply() runs after the job has left the in-flight slot", async () => {
  const { queue, calls } = setup()
  let pendingDuringApply
  queue.enqueue({ key: "font_size" }); await tick()
  await answer(calls[0], { ok: true, apply: () => { pendingDuringApply = queue.isPending("font_size") } })
  assert.equal(pendingDuringApply, false)
})

test("isPending covers waiting and in-flight jobs", async () => {
  const { queue, calls } = setup()
  queue.enqueue({ key: "a" }); await tick(); queue.enqueue({ key: "b" })
  assert.ok(queue.isPending("a")); assert.ok(queue.isPending("b")); assert.ok(!queue.isPending("c"))
  await answer(calls[0]); await answer(calls[1])
  assert.ok(!queue.isPending("a")); assert.ok(!queue.isPending("b"))
})

test("a barrier only blocks coalescing with jobs before it", async () => {
  const { queue, calls } = setup()
  queue.enqueue({ key: "tracking", value: "1" })
  await tick() // tracking in flight
  queue.enqueue({ key: "font_size", value: "12" })
  queue.enqueue({ key: ":style" })
  queue.enqueue({ key: "font_size", value: "13" })
  queue.enqueue({ key: "font_size", value: "14" })
  queue.enqueue({ key: "font_size", value: "15" })
  assert.deepEqual(queue.waiting.map((j) => j.value ?? j.key), [ "12", ":style", "15" ])
  for (let i = 0; i < 4; i++) await answer(calls[i])
  assert.deepEqual(calls.map((c) => c.job.value ?? c.job.key), [ "1", "12", ":style", "15" ])
})

test("a field that fails and then saves in the same burst ends the burst as saved", async () => {
  const { queue, calls, statuses } = setup()
  queue.enqueue({ key: "font_size", value: "x" })
  await tick()
  queue.enqueue({ key: "font_size", value: "12" })
  await answer(calls[0], { ok: false })
  await answer(calls[1])
  assert.equal(statuses.at(-1), "saved")
})

test("another field's success doesn't clear a failure", async () => {
  const { queue, calls, statuses } = setup()
  queue.enqueue({ key: "font_size", value: "x" })
  await tick()
  queue.enqueue({ key: "tracking", value: "1" })
  await answer(calls[0], { ok: false })
  await answer(calls[1])
  assert.equal(statuses.at(-1), "error")
})

test("an ok result whose apply() throws counts as a failure", async () => {
  const { queue, calls, statuses } = setup()
  queue.enqueue({ key: "a" }); await tick()
  await answer(calls[0], { ok: true, apply: () => { throw new Error("no Turbo") } })
  assert.equal(statuses.at(-1), "error")
})

test("stop(): waiting jobs are dropped, the one in flight completes, later enqueues are ignored", async () => {
  const { queue, calls } = setup()
  let applied = false
  queue.enqueue({ key: "a" }); await tick()
  queue.enqueue({ key: "b" })
  queue.stop()
  assert.ok(!queue.isPending("b"))
  await answer(calls[0], { ok: true, apply: () => { applied = true } })
  assert.ok(applied, "the in-flight response is still handed back")
  queue.enqueue({ key: "c" }); await tick()
  assert.deepEqual(calls.map((c) => c.job.key), [ "a" ])
  assert.ok(!queue.busy)
  await queue.whenIdle()
})

test("a failed linked pair is cleared by a later Left or Right success: the burst ends saved", async () => {
  const { queue, calls, statuses } = setup()
  queue.enqueue({ key: ":linked_margins", fields: [ "left_margin_mm", "right_margin_mm" ] })
  await tick() // the pair in flight
  queue.enqueue({ key: "left_margin_mm", value: "20" })
  await answer(calls[0], { ok: false })
  await answer(calls[1])
  assert.equal(statuses.at(-1), "saved")
})

test("…and a successful pair clears failed Left/Right saves", async () => {
  const { queue, calls, statuses } = setup()
  queue.enqueue({ key: "right_margin_mm", value: "20" })
  await tick()
  queue.enqueue({ key: ":linked_margins", fields: [ "left_margin_mm", "right_margin_mm" ] })
  await answer(calls[0], { ok: false })
  await answer(calls[1])
  assert.equal(statuses.at(-1), "saved")
})

test("an unrelated success leaves a failure standing", async () => {
  const { queue, calls, statuses } = setup()
  queue.enqueue({ key: ":linked_margins", fields: [ "left_margin_mm", "right_margin_mm" ] })
  await tick()
  queue.enqueue({ key: "top_margin_mm", value: "20" })
  await answer(calls[0], { ok: false })
  await answer(calls[1])
  assert.equal(statuses.at(-1), "error")
})

test("isPending sees a field inside a job's `fields` (the linked margin pair)", async () => {
  const { queue, calls } = setup()
  queue.enqueue({ key: ":linked_margins", fields: [ "left_margin_mm", "right_margin_mm" ] })
  assert.equal(queue.isPending("left_margin_mm"), true, "waiting")
  await tick()
  assert.equal(queue.isPending("right_margin_mm"), true, "in flight")
  assert.equal(queue.isPending("top_margin_mm"), false)
  await answer(calls[0])
  assert.equal(queue.isPending("left_margin_mm"), false)
})
