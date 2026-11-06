import Foundation

private final class StreamGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: UInt64 = 0
    var value: UInt64 { lock.lock(); defer { lock.unlock() }; return storage }
    func set(_ value: UInt64) { lock.lock(); storage = value; lock.unlock() }
}

/// Bounded scheduler: one inference, up to two final windows, and one latest
/// provisional window. Slow hardware drops oldest queued audio with an explicit
/// metric instead of building an ever-growing latency/memory backlog.
public actor StreamingTranscriber {
    private struct ScheduledWindow {
        let audio: SpeechWindow
        let sequence: UInt64
        let language: String?
    }
    public nonisolated let events: AsyncStream<TranscriptionEvent>
    /// UI consumers should use this stream and reject envelopes whose generation
    /// differs from currentGeneration. Even already-buffered events then become
    /// invalid immediately after seek/stop, not just C results still in flight.
    public nonisolated let taggedEvents: AsyncStream<GenerationTaggedEvent>
    public nonisolated var currentGeneration: UInt64 { generation.value }
    private nonisolated let generation = StreamGeneration()
    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    private let taggedContinuation: AsyncStream<GenerationTaggedEvent>.Continuation
    private let engine: any SpeechRecognizing
    private var builder = SpeechWindowBuilder()
    private var reconciler = CaptionReconciler()
    private var language: String?
    private var running = false
    private var epoch: UInt64 = 0
    private var queue: [ScheduledWindow] = []
    private var pendingPartial: ScheduledWindow?
    private var latestWindowSequence: UInt64 = 0
    private var worker: Task<Void, Never>?
    private var metrics = TranscriptionMetrics()
    private var partialID = UUID()
    private var lastNoAudio = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(engine: any SpeechRecognizing) {
        self.engine = engine
        var captured: AsyncStream<TranscriptionEvent>.Continuation!
        // Bounded newest events. A normal UI should consume continuously.
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(128)) { captured = $0 }
        self.continuation = captured
        var tagged: AsyncStream<GenerationTaggedEvent>.Continuation!
        self.taggedEvents = AsyncStream(bufferingPolicy: .bufferingNewest(128)) { tagged = $0 }
        self.taggedContinuation = tagged
    }

    deinit { worker?.cancel(); continuation.finish(); taggedContinuation.finish() }

    public func start(language: String?) {
        self.language = language
        builder.reset()
        running = true; lastNoAudio = false
        emit(.status(.listening))
    }

    public func append(samples: [Float], at startTime: Double) {
        guard running, startTime.isFinite, !samples.isEmpty else { return }
        let valid = samples.map { $0.isFinite ? max(-1, min(1, $0)) : 0 }
        // While inference is busy, keep accumulating PCM but do not manufacture
        // newer provisional jobs that would invalidate its only useful result.
        // The next input after it becomes idle uses the latest accumulated audio.
        // Final windows remain unconditional and retain priority in the queue.
        for window in builder.append(valid, at: startTime, emitPartials: worker == nil) { enqueue(window) }
        if builder.silentSeconds >= 6 && !lastNoAudio {
            lastNoAudio = true; emit(.status(.noAudio))
        } else if builder.silentSeconds < 0.1 && lastNoAudio {
            lastNoAudio = false; emit(.status(.listening))
        }
    }

    public func pause() {
        running = false
        if let final = builder.flush() { enqueue(final) }
        emit(.status(.paused))
    }

    public func finish() async {
        let generationAtFinish = epoch
        pause()
        if worker != nil { await withCheckedContinuation { waiters.append($0) } }
        if generationAtFinish == epoch && !running { emit(.status(.stopped)) }
    }

    /// Seek/discontinuity invalidates ALL in-flight output. Call before feeding
    /// samples from the new playhead. Previously emitted history belongs to UI.
    public func reset(at time: Double) {
        invalidate()
        reconciler.reset()
        metrics = TranscriptionMetrics()
        emit(.metrics(metrics))
        emit(.status(running ? .listening : .paused))
    }

    public func stop(unloadModel: Bool = true) async {
        running = false
        invalidate()
        let generationAtStop = epoch
        if unloadModel { await engine.unload() }
        if generationAtStop == epoch && !running { emit(.status(.stopped)) }
    }

    private func invalidate() {
        epoch &+= 1
        generation.set(epoch)
        engine.cancel()
        worker?.cancel(); worker = nil
        queue.removeAll(keepingCapacity: true); pendingPartial = nil
        builder.reset(); partialID = UUID(); lastNoAudio = false
        emit(.partial(nil))
        let saved = waiters; waiters.removeAll()
        for waiter in saved { waiter.resume() }
    }

    private func enqueue(_ window: SpeechWindow) {
        latestWindowSequence &+= 1
        let scheduled = ScheduledWindow(audio: window, sequence: latestWindowSequence, language: language)
        if window.isFinal {
            pendingPartial = nil
            queue.append(scheduled)
            if queue.count > 2 {
                let dropped = queue.removeFirst()
                metrics.droppedAudioSeconds += Double(dropped.audio.samples.count) / 16_000
                emit(.metrics(metrics))
            }
        } else { pendingPartial = scheduled }
        startWorkerIfNeeded()
    }

    private func emit(_ event: TranscriptionEvent) {
        continuation.yield(event)
        taggedContinuation.yield(GenerationTaggedEvent(generation: epoch, event: event))
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        let currentEpoch = epoch
        worker = Task { await self.drain(epoch: currentEpoch) }
    }

    private func drain(epoch requestedEpoch: UInt64) async {
        while requestedEpoch == epoch && !Task.isCancelled {
            let scheduled: ScheduledWindow
            if !queue.isEmpty { scheduled = queue.removeFirst() }
            else if let partial = pendingPartial { scheduled = partial; pendingPartial = nil }
            else { break }
            let job = scheduled.audio
            emit(.status(.processing))
            let begin = ContinuousClock.now
            do {
                let segments = try await engine.transcribe(samples: job.samples, language: scheduled.language)
                guard requestedEpoch == epoch, !Task.isCancelled else { return }
                let elapsed = begin.duration(to: .now)
                metrics.inferenceSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                metrics.audioSeconds = Double(job.samples.count) / 16_000
                emit(.metrics(metrics))
                if job.isFinal {
                    let confirmed = reconciler.confirm(segments, windowStart: job.start, windowEnd: job.end)
                    emit(.partial(nil))
                    if !confirmed.isEmpty { emit(.confirmed(confirmed)) }
                    partialID = UUID()
                } else if scheduled.sequence == latestWindowSequence {
                    // A newer scheduled window supersedes this hypothesis,
                    // including a final later shed on overload. Merely receiving
                    // more audio while busy does not suppress the best available
                    // preview and cannot starve slower models of all partials.
                    emit(.partial(reconciler.provisional(segments, windowStart: job.start, windowEnd: job.end, id: partialID)))
                }
            } catch is CancellationError {
                if requestedEpoch != epoch || Task.isCancelled { return }
            } catch {
                guard requestedEpoch == epoch else { return }
                emit(.status(.failed(error.localizedDescription)))
                running = false; queue.removeAll(); pendingPartial = nil; builder.reset()
                break
            }
        }
        guard requestedEpoch == epoch else { return }
        worker = nil
        if running { emit(.status(lastNoAudio ? .noAudio : .listening)) }
        let saved = waiters; waiters.removeAll()
        for waiter in saved { waiter.resume() }
    }
}
