# Export adapter independent source review — a2

**Changes required.** A2 addresses the original missing final child/plan check, but a second race remains: the review and plan are parsed before their verified holds. A transient replacement can populate a different cached inventory and be replaced with the approved bytes before the hash-verified hold. The child then sees the approved file while a required dependency may remain unheld.

The disposable Windows test reproduced that ordering gap using the actual public hold helper. It passed as a reproduction test; it does not make the adapter pass review. No private adapter ran. The source owner confirmed the finding and is preparing an additive successor that holds the review and plan before parsing them.

Independent verification also reran the eight controlled adapter tests successfully and parsed the exact a2 candidate with zero errors; both historical ACL/UTC functions are unchanged. The earlier 19 Windows sharing checks ran on October 16 and remain separate dated evidence. The adjacent management builder was changing during review and receives no frozen verdict here.

Candidate SHA: `4dd4911e892fa75dfdaaa0e0ea9036ddaa2e93d5a040c736515b55cec9053c15`.

All private, live, SDK, native, acceptance and Git operations remained untouched. Budgets 141/166/174 are conditional source limits; this review grants no human approval or execution authority.

