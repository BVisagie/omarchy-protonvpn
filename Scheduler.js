function emptyQueue() {
  return {
    jobs: [],
    current: null,
    nextRunId: 0
  }
}

function cloneJob(job) {
  var copy = {}
  if (!job) return copy
  for (var key in job) copy[key] = job[key]
  return copy
}

function hasType(jobs, current, type, kind) {
  if (current && current.type === type && (kind === undefined || current.kind === kind)) return true
  for (var i = 0; i < jobs.length; i++) {
    if (jobs[i].type === type && (kind === undefined || jobs[i].kind === kind)) return true
  }
  return false
}

function hasAction(queue) {
  return hasType(queue.jobs, queue.current, "action")
}

function filterJobs(jobs, keep) {
  var next = []
  for (var i = 0; i < jobs.length; i++) {
    if (keep(jobs[i])) next.push(jobs[i])
  }
  return next
}

function enqueueJob(queue, job) {
  var source = queue || emptyQueue()
  var jobs = source.jobs.slice()
  var current = source.current

  if (!job || !job.command || job.command.length === 0) {
    return { accepted: false, reason: "invalid", queue: source }
  }

  if (job.type === "action") {
    if (hasType(jobs, current, "action")) {
      return { accepted: false, reason: "action-busy", queue: source }
    }
    jobs.push(cloneJob(job))
    return { accepted: true, reason: "", queue: { jobs: jobs, current: current, nextRunId: source.nextRunId } }
  }

  if (job.type === "status") {
    if (current && current.type === "status") {
      return { accepted: false, reason: "status-running", queue: source }
    }
    jobs = filterJobs(jobs, function(item) { return item.type !== "status" })
    jobs.push(cloneJob(job))
    return { accepted: true, reason: "", queue: { jobs: jobs, current: current, nextRunId: source.nextRunId } }
  }

  if (job.type === "config" && job.kind === "list") {
    if (current && current.type === "config" && current.kind === "list") {
      return { accepted: false, reason: "config-running", queue: source }
    }
    jobs = filterJobs(jobs, function(item) { return !(item.type === "config" && item.kind === "list") })
    jobs.push(cloneJob(job))
    return { accepted: true, reason: "", queue: { jobs: jobs, current: current, nextRunId: source.nextRunId } }
  }

  if (job.type === "config" && job.kind === "set") {
    jobs = filterJobs(jobs, function(item) {
      return !(item.type === "config" && item.kind === "set" && item.setting === job.setting)
    })
    jobs.push(cloneJob(job))
    return { accepted: true, reason: "", queue: { jobs: jobs, current: current, nextRunId: source.nextRunId } }
  }

  if (job.type === "discovery" && job.kind === "countries") {
    if (current && current.type === "discovery" && current.kind === "countries") {
      return { accepted: false, reason: "countries-running", queue: source }
    }
    jobs = filterJobs(jobs, function(item) { return !(item.type === "discovery" && item.kind === "countries") })
    jobs.push(cloneJob(job))
    return { accepted: true, reason: "", queue: { jobs: jobs, current: current, nextRunId: source.nextRunId } }
  }

  if (job.type === "discovery" && job.kind === "cities") {
    jobs = filterJobs(jobs, function(item) { return !(item.type === "discovery" && item.kind === "cities") })
    jobs.push(cloneJob(job))
    return {
      accepted: true,
      reason: "",
      superseded: current && current.type === "discovery" && current.kind === "cities" && String(current.country || "") !== String(job.country || ""),
      queue: { jobs: jobs, current: current, nextRunId: source.nextRunId }
    }
  }

  jobs.push(cloneJob(job))
  return { accepted: true, reason: "", queue: { jobs: jobs, current: current, nextRunId: source.nextRunId } }
}

function beginJob(queue) {
  var source = queue || emptyQueue()
  if (source.current || source.jobs.length === 0) {
    return { started: false, job: null, queue: source }
  }
  var job = cloneJob(source.jobs[0])
  var runId = source.nextRunId + 1
  job.runId = runId
  return {
    started: true,
    job: job,
    queue: {
      jobs: source.jobs.slice(1),
      current: job,
      nextRunId: runId
    }
  }
}

function finishJob(queue, runId) {
  var source = queue || emptyQueue()
  if (!source.current) return { finished: false, job: null, queue: source }
  if (runId !== undefined && source.current.runId !== runId) {
    return { finished: false, job: null, queue: source }
  }
  return {
    finished: true,
    job: source.current,
    queue: {
      jobs: source.jobs.slice(),
      current: null,
      nextRunId: source.nextRunId
    }
  }
}

function shouldApplyResult(queue, runId) {
  return !!(queue && queue.current && queue.current.runId === runId)
}

function timeoutFor(job) {
  if (!job) return 20000
  if (typeof job.timeout === "number" && job.timeout > 0) return job.timeout
  if (job.type === "action") return 60000
  if (job.type === "status") return 25000
  if (job.type === "discovery") return 30000
  if (job.type === "which") return 5000
  return 20000
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyQueue: emptyQueue,
    hasAction: hasAction,
    enqueueJob: enqueueJob,
    beginJob: beginJob,
    finishJob: finishJob,
    shouldApplyResult: shouldApplyResult,
    timeoutFor: timeoutFor
  }
}
