# NATS and JetStream Reference

This document summarizes core NATS/JetStream concepts, key policies, and recommended settings for event-driven services.

## 1. NATS vs JetStream

- NATS Core: fast pub/sub messaging, no persistence by default.
- JetStream: persistence, replay, consumer state, ack/retry, and stream management.

Use JetStream when you need durability, auditability, retries, backpressure, or deterministic replay behavior.

## 2. JetStream Building Blocks

- Stream: durable message storage bound to one or more subjects.
- Consumer: read cursor + delivery behavior over a stream.
- Subject: routing key (for example: `kb.pdf.parsed`).

## 3. Stream Policies (Retention)

### `LimitsPolicy`
Messages are retained until stream limits are reached (max age, max bytes, max messages, etc.).

Good for:
- Audit/debug history
- Replays
- Multi-consumer analytics/inspection

### `WorkQueuePolicy`
Messages are intended for work-queue semantics. A message is removed once one consumer successfully processes/acks it.

Good for:
- Strict one-time worker processing
- Queue-like workloads

Important constraint:
- WorkQueue streams require consumer `DeliverAll` semantics in common setups.

### `InterestPolicy`
Messages are kept only while consumers have interest (unconsumed state). Once no consumer needs them, they can be removed.

Good for:
- Consumer-interest-driven retention
- Less long-term storage than `LimitsPolicy`

## 4. Consumer Start Policies (Deliver)

### `DeliverAll`
Start from oldest available message in stream.

### `DeliverNew`
Start only from messages published after consumer creation.

### `DeliverLast`
Start from the latest message, then continue with new messages.

### `DeliverByStartSequence`
Start from a specific stream sequence number.

### `DeliverByStartTime`
Start from a specific timestamp.

### `DeliverLastPerSubject`
Start from latest message per subject (useful with wildcard subjects).

## 5. Ack Policies

### `AckExplicit`
Each message must be acked explicitly.

### `AckAll`
Acking one message implicitly acks all earlier pending messages for that consumer.

### `AckNone`
No ack required.

## 6. Replay Policies

### `ReplayInstant`
Deliver as fast as possible.

### `ReplayOriginal`
Deliver according to original publish timing (historical pacing).

## 7. Discard Policies (when stream limits are hit)

### `DiscardOld`
Drop oldest messages to admit new ones.

### `DiscardNew`
Reject new messages when limits are full.

## 8. Compatibility Notes

- `LimitsPolicy` + `DeliverNew`: valid and common.
- `WorkQueuePolicy` + `DeliverNew`: typically not allowed for queue-style consumers; use `DeliverAll`.
- If you need both history and `DeliverNew`, choose `LimitsPolicy`.

## 9. Recommended Settings for PDF Pipeline

For a parsed-event stream (example: `kb.pdf.parsed`) where you want audit/debug history and new-only consumption for fresh consumers:

- Retention: `LimitsPolicy`
- Deliver: `DeliverNew`
- Ack: `AckExplicit`
- Replay: `ReplayInstant`
- Discard: `DiscardOld`

This combination supports:
- Event retention for debugging and audits
- No historical replay for brand-new consumers
- Explicit control over success/failure ack handling

## 10. Operational Guidance

1. Define stream policy intentionally at creation time.
2. Treat stream retention policy as part of API contract.
3. Use durable names consistently per service role.
4. Decide retry semantics explicitly:
   - `Nak` for retryable failures
   - `Ack` for terminal/non-retryable failures
5. Log subject, durable, stream, and policy settings at startup.

## 11. Example (Go / nats.go)

```go
_, err := js.AddStream(&nats.StreamConfig{
    Name:      "pdf-parsed-events",
    Subjects:  []string{"kb.pdf.parsed"},
    Retention: nats.LimitsPolicy,
    Discard:   nats.DiscardOld,
    Storage:   nats.FileStorage,
})
if err != nil {
    return err
}

_, err = js.Subscribe("kb.pdf.parsed", handler,
    nats.Durable("pdf-result-converter"),
    nats.ManualAck(),
    nats.AckExplicit(),
    nats.DeliverNew(),
    nats.ReplayInstant(),
)
if err != nil {
    return err
}
```

## 12. Quick Troubleshooting

- Error: `consumer must be deliver all on workqueue stream`
  - Cause: stream is `WorkQueuePolicy`, consumer asks for `DeliverNew`.
  - Fix: use `DeliverAll`, or recreate stream as `LimitsPolicy` if you need `DeliverNew`.

- Messages repeatedly redeliver
  - Cause: message not acked; or repeatedly `Nak`ed.
  - Fix: distinguish retryable vs terminal errors and ack terminal ones.

- New consumer replays too much history
  - Cause: `DeliverAll` or reused durable state.
  - Fix: use `DeliverNew` on `LimitsPolicy`, and validate durable strategy.
