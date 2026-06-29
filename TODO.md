# TODO: Rekey Capway data by contract reference

## Problem
Capway subscriber data is keyed by `trinity_subscriber_id`, causing last-one-wins overwrites when a customer has multiple contracts. Inactive contracts with historical collection data leak into suspend logic.

## Tasks
- [x] 1. Add `capway_contract_ref` field to `ActionItem` model
- [x] 2. Store `capway_contract_ref` in `ActionItemRepositoryV2`
- [x] 3. Rekey `Helper.group(:capway)` by `capway_contract_ref` (active contracts only)
- [x] 4. Update `CompareDataV2` comparison functions to iterate by contract ref
- [x] 5. Update existing tests for new keying
- [x] 6. Add new tests (multi-contract, helper module)
- [x] 7. Run `mix test` and verify all pass (142 tests, 0 new failures — 1 pre-existing failure in CachedCapwaySubscribersTest)

---

# TODO: Language-code sync for `:capway_update_customer`

## Goal
The REST customer sync must also check the Capway customer's `languageCode` against the
correct value for the active market and emit an update when it drifts.

## Decisions (confirmed with user)
- `sub_action` becomes a **list of atoms** (`[:update_email, :update_nin, :update_language]`)
  instead of a single combination atom — removes the combinatorial explosion.
- Expected language per market: `:se → "sv"`, `:no → "nb"`.
- Missing/blank language on a **fetched** Capway customer counts as wrong → emit update.
  A customer we could *not* fetch stays `nil` ("unknown") → no action, so a transient REST
  failure never produces a false language update.
- New `CapwaySync.Market` module is the single source of per-market settings.

## Tasks
- [x] 1. Investigate flow (FetchCapwayEmails → Canonical → CompareDataV2 → ActionItem → report)
- [x] 2. `lib/capway_sync/market.ex` — per-market settings registry
- [x] 3. `Canonical` — add `language_code` field (default nil = "not fetched")
- [x] 4. `FetchCapwayEmails` — extract `languageCode`; "" sentinel when fetched-but-blank; merge
- [x] 5. `CompareDataV2` — language mismatch check; 3-field diffs; list sub_actions; reason builder
- [x] 6. `ActionItem` — `sub_action` type → list of atoms
- [x] 7. `GeneralSyncReportRepositoryV2` — per-field `sub_action_breakdown` incl. `update_language`
- [x] 8. Tests: market, compare (default + market), fetch_capway_emails, action_item, canonical
- [x] 9. Run full test suite (274 tests + 1 doctest, 0 failures)
- [x] 10. Changelog + CLAUDE.md notes

## Out of repo (must be coordinated)
The Trinity-side worker that *executes* `:capway_update_customer` action items must learn to
PATCH the customer `languageCode` and to read `sub_action` as a **list**. This repo only
decides that an update is needed; it does not perform the REST write.
