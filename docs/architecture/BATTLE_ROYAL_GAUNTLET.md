# Battle Chess follow-up: the king's last chance

User direction recorded during Classic development on 2026-11-07. This is the
next Battle ruleset design, **not** a change to standard Classic Chess or to
shipped v1 payloads. It supersedes the blanket no-king-duel design for the future
Battle mode. Combat implementation belongs to Claude Code.

Confirmed requirements:

- The king is the strongest fighter.
- At checkmate in Battle Chess, the king receives a last-chance sequence of
  duels against the opponent's characters that are mating the king, one after
  another.
- The king's HP does **not** reset between these fights. The remaining HP after
  one fight is the starting HP for the next.
- Losing a king duel ends the match as checkmate. Classic Chess still ends
  immediately at ordinary chess checkmate; it never starts a duel.

Integration decisions still needed before implementation: exactly which pieces
constitute the mating group (direct checking pieces versus pieces covering
escape squares), their order, whether the king can initiate ordinary capture
duels too, how a successful entire sequence changes the board, and how stamina,
cooldowns and enemy HP persist. These details must not be guessed in a live
rules implementation. No arbitrary removal of a king or illegal post-duel
position is allowed.

Introduce an explicit Battle v2 ruleset and versioned request/snapshot/result
contracts for the sequence and persistent king HP. Preserve v1 as a named legacy
ruleset until consumers migrate. The current Classic PR deliberately changes
no combat-owned file, fighter balance table, legacy Battle rules, or v1 schema.

**Update 2026-11-11:** the open decisions above are made and implemented as the opt-in
`battle-royal-v1` ruleset; see [`BATTLE_ROYAL_V1.md`](BATTLE_ROYAL_V1.md) (ADR, contract,
edge cases). The v1 payloads and the legacy `battle-checkmate-v1` ruleset are unchanged.
