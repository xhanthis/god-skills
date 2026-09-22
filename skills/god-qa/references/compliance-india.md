# Indian compliance review (step 13, deep mode)

Core question: **what does Indian law require here, and does the change meet it?** Authority over assumption; current law over remembered law. Load when the diff touches personal data, consent, retention, payments, invoices, tax, notices, or legal copy.

## Rules

- **Never fabricate** a section, judgment, citation, or deadline. A provision that cannot be verified is reported as unverified, not omitted.
- **Verify against current sources** — bare acts, official gazettes, court judgments — and note amendments and repeals (IPC → BNS transitions, DPDP Act 2023 rules as notified).
- **Separate clearly:** what the law states → how it applies to these facts → what the code must do → what remains uncertain.
- **Flag risk level and deadlines** (filings, notices, limitation periods, breach-notification windows) explicitly.
- Legal reasoning support, not a substitute for a licensed advocate: for binding decisions, litigation, or high-stakes matters, state that a qualified lawyer must review.

## Checklist for code

- **DPDP Act 2023 + ISO 27001 (customer and partner data):** lawful purpose stated for every new personal field; consent captured where required and revocable; retention named; access, correction and erasure paths exist; data principal notices updated when a new use is added; breach path known.
- **Payments and invoices:** GST-inclusive vs exclusive stated; invoice fields and numbering per rules; refunds reverse tax correctly (route the math to god-cfo).
- **Consumer-facing copy:** cancellation, refund and grievance terms match what the code enforces; grievance officer contact where required.
- **Communications:** OTP/SMS/WhatsApp templates and consent per TRAI/DLT requirements where applicable.

## Report

`[score] file:line — requirement · what the code does · gap · fix.` Tax computation → god-cfo. Implementation → god-build.
