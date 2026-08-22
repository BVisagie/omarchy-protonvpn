const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const Scheduler = require("../Scheduler.js")

function command(type, extra) {
  return Object.assign({ type: type, command: ["protonvpn", type] }, extra)
}

describe("action acceptance", () => {
  it("accepts an action while visual connecting state is ignored", () => {
    const queue = Scheduler.emptyQueue()
    const result = Scheduler.enqueueJob(queue, command("action", { action: "connect" }))
    assert.equal(result.accepted, true)
    assert.equal(Scheduler.hasAction(result.queue), true)
  })

  it("rejects a second action instead of queueing another write", () => {
    let queue = Scheduler.emptyQueue()
    queue = Scheduler.enqueueJob(queue, command("action", { action: "connect" })).queue
    const second = Scheduler.enqueueJob(queue, command("action", { action: "disconnect" }))
    assert.equal(second.accepted, false)
    assert.equal(second.reason, "action-busy")
    assert.equal(second.queue.jobs.length, 1)
  })

  it("rejects a second action while one is already running", () => {
    let queue = Scheduler.emptyQueue()
    queue = Scheduler.enqueueJob(queue, command("action", { action: "connect" })).queue
    const started = Scheduler.beginJob(queue)
    const second = Scheduler.enqueueJob(started.queue, command("action", { action: "connect" }))
    assert.equal(second.accepted, false)
    assert.equal(Scheduler.hasAction(started.queue), true)
  })
})

describe("coalescing", () => {
  it("keeps a single pending status refresh", () => {
    let queue = Scheduler.emptyQueue()
    queue = Scheduler.enqueueJob(queue, command("status")).queue
    queue = Scheduler.enqueueJob(queue, command("status")).queue
    queue = Scheduler.enqueueJob(queue, command("status")).queue
    assert.equal(queue.jobs.filter((job) => job.type === "status").length, 1)
  })

  it("does not queue another status while one is running", () => {
    let queue = Scheduler.emptyQueue()
    queue = Scheduler.enqueueJob(queue, command("status")).queue
    const started = Scheduler.beginJob(queue)
    const extra = Scheduler.enqueueJob(started.queue, command("status"))
    assert.equal(extra.accepted, false)
    assert.equal(extra.reason, "status-running")
  })

  it("coalesces country discovery and config list jobs", () => {
    let queue = Scheduler.emptyQueue()
    queue = Scheduler.enqueueJob(queue, command("discovery", { kind: "countries" })).queue
    queue = Scheduler.enqueueJob(queue, command("discovery", { kind: "countries" })).queue
    queue = Scheduler.enqueueJob(queue, command("config", { kind: "list" })).queue
    queue = Scheduler.enqueueJob(queue, command("config", { kind: "list" })).queue
    assert.equal(queue.jobs.filter((job) => job.kind === "countries").length, 1)
    assert.equal(queue.jobs.filter((job) => job.kind === "list").length, 1)
  })
})

describe("latest city selection", () => {
  it("replaces a queued city job with the latest country", () => {
    let queue = Scheduler.emptyQueue()
    queue = Scheduler.enqueueJob(queue, command("discovery", { kind: "cities", country: "US" })).queue
    queue = Scheduler.enqueueJob(queue, command("discovery", { kind: "cities", country: "IT" })).queue
    assert.equal(queue.jobs.length, 1)
    assert.equal(queue.jobs[0].country, "IT")
  })

  it("lets a newer city request supersede a running one", () => {
    let queue = Scheduler.emptyQueue()
    queue = Scheduler.enqueueJob(queue, command("discovery", { kind: "cities", country: "US" })).queue
    const started = Scheduler.beginJob(queue)
    const next = Scheduler.enqueueJob(started.queue, command("discovery", { kind: "cities", country: "DE" }))
    assert.equal(next.accepted, true)
    assert.equal(next.superseded, true)
    assert.equal(next.queue.jobs[0].country, "DE")
    assert.equal(started.job.country, "US")
  })
})

describe("timeout identity", () => {
  it("assigns a run id when a job starts", () => {
    let queue = Scheduler.emptyQueue()
    queue = Scheduler.enqueueJob(queue, command("action")).queue
    const started = Scheduler.beginJob(queue)
    assert.equal(started.started, true)
    assert.equal(started.job.runId, 1)
    assert.equal(started.queue.current.runId, 1)
  })

  it("ignores a late exit from a cancelled watchdog job", () => {
    let queue = Scheduler.emptyQueue()
    queue = Scheduler.enqueueJob(queue, command("action")).queue
    const first = Scheduler.beginJob(queue)
    const finished = Scheduler.finishJob(first.queue, first.job.runId)
    queue = Scheduler.enqueueJob(finished.queue, command("status")).queue
    const second = Scheduler.beginJob(queue)
    assert.equal(Scheduler.shouldApplyResult(second.queue, first.job.runId), false)
    const late = Scheduler.finishJob(second.queue, first.job.runId)
    assert.equal(late.finished, false)
    assert.equal(late.queue.current.runId, second.job.runId)
  })

  it("applies only the matching run id", () => {
    let queue = Scheduler.emptyQueue()
    queue = Scheduler.enqueueJob(queue, command("status")).queue
    const started = Scheduler.beginJob(queue)
    assert.equal(Scheduler.shouldApplyResult(started.queue, started.job.runId), true)
    const done = Scheduler.finishJob(started.queue, started.job.runId)
    assert.equal(done.finished, true)
    assert.equal(done.queue.current, null)
  })
})

describe("timeouts", () => {
  it("uses job-specific timeouts", () => {
    assert.equal(Scheduler.timeoutFor({ type: "action" }), 60000)
    assert.equal(Scheduler.timeoutFor({ type: "status" }), 25000)
    assert.equal(Scheduler.timeoutFor({ type: "discovery" }), 30000)
    assert.equal(Scheduler.timeoutFor({ type: "which" }), 5000)
    assert.equal(Scheduler.timeoutFor({ type: "action", timeout: 12000 }), 12000)
  })
})
