# Ops pass

Core question: **how does this work repeatedly in the real world, without heroics?**

## Rules

- Every process gets an **owner, an SLA, and an escalation path**, or it silently rots.
- **Design for the exception:** the vendor doesn't reply, the payment fails, the guest arrives early, the system is down. Exceptions define the process.
- Reduce human error **structurally** — checklists, defaults, automation — never by asking people to be careful.
- **Instrument it:** cycle time, failure rate, escalation volume, and where each is read.
- **Kill steps** that exist only because they always have; run god-build's remove-first question on the process.

## Output

```
Process: <name> — owner · SLA · escalation
Happy path: 1. … 2. … (≤ 7 steps)
Exceptions: <case → what happens → who is told>
Automate: <steps that tooling removes — hand to god-build>
Measure: <metric → where it is read → threshold that triggers review>
Removed: <steps cut and why nothing broke>
```

Tooling or automation → god-build. Metrics → god-cfo.
