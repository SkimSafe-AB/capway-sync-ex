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

---

# TODO: Detect missing autogiro debit mandates → `:capway_create_mandate` (2026-07-21, DONE)

## Goal
For every subscription whose `payment_method` is `"capway_autogiro"` OR `"capway autogiro"`
(both variants exist in data), check subscriber metadata for the debit mandate
(`capway_mandate_guid` key, written by Trinity's `PaymentService.store_mandate_guid/2`).
If missing/blank → emit a new action item `:capway_create_mandate`, comment
"Capway autogiro mandate missing". Trinity then executes it from /admin/capway (see
apps/trinity/TODO.md for the executor half).

## Decisions (confirmed with user 2026-07-21)
- Action type name: `:capway_create_mandate` (imperative, matches convention).
- Scope: ACTIVE subscriptions only, following `get_contracts_to_create` pattern
  (not `capway_sync_excluded`, `older_than_yesterday?`).
- Detection = metadata presence only (no REST validation of the mandate at Capway).
- Trinity execute flow: hybrid form — prefill clearing/account from WC meta
  (`_clearing_number`/`_account_number`), operator can edit/fill, POST creates mandate.

## Key facts (from exploration)
- NO autogiro/mandate concept exists in this app today — `"capway_autogiro"` appears nowhere.
- Pattern to copy: `get_contracts_to_create/3` at `lib/capway_sync/reactor/v1/steps/compare_data_v2.ex:195-218`
  (comprehension over trinity grouped data, emits `build_action_item(:capway_create_contract, sub, reason)`; builder at :489).
- Canonical struct (`lib/capway_sync/models/subscribers/canonical.ex`, `from_trinity/1` at :121)
  already reads metadata keys (:148-159: capway_last_updated, capway_created_at,
  capway_cancelled_at, capway_sync_excluded) and carries `payment_method` — must ADD
  `capway_mandate_guid` field populated from metadata.
- ActionItem model: `lib/capway_sync/models/dynamodb/action_item.ex` — add `:capway_create_mandate`
  to `@type action_type` (lines 2-9). `create_action_item/2` at :53.
- Workflow: `lib/capway_sync/reactor/v1/subscriber_sync_workflow.ex` — new bucket must be
  persisted in `:dynamodb_store_action_items` step (:147-188) and counted in
  `:dynamodb_store_report` (GeneralSyncReportRepositoryV2 builds counts+ids per bucket).
- VERIFY: whether grouping (`lib/capway_sync/models/subscribers/cannonical/helper.ex` `group/2`,
  note payment_method=="capway" check at helper.ex:53) lets capway_autogiro subs reach
  CompareDataV2's trinity map at all — the detector input may need widening.

## Tasks
- [x] 1. Verify data flow for capway_autogiro subs — confirmed: `list_subscribers(true)` fetches ALL
        payment methods and `Helper.group(:trinity)` does not filter by payment_method, so autogiro
        subs reach `CompareDataV2.active_subscribers` (only the `locked_subscribers` bucket is
        capway-only).
- [x] 2. `ActionItem` — added `:capway_create_mandate` to action_type union
- [x] 3. `Canonical` — added `trinity_capway_mandate_guid` (from `capway_mandate_guid` metadata)
- [x] 4. `CompareDataV2` — `get_mandates_to_create/2` + `create_mandates` bucket in `run/3`
- [x] 5. `SubscriberSyncWorkflow` — stores bucket; `GeneralSyncReportRepositoryV2` reports counts/ids
- [x] 6. Tests: 9 new compare_data_v2 cases + 2 canonical cases
- [x] 7. `mix test` full suite — 298 tests + 1 doctest, 0 failures (env vars from docker-compose-test.yml)
- [x] 8. CHANGELOG + CLAUDE.md updated
- [x] 9. Follow-up (2026-07-21): item comment now includes Trinity's recorded mandate
        failure — `Canonical` reads `capway_mandate_error`/`capway_mandate_error_at`
        metadata; comment becomes "… — last attempt failed: <reason> (<at>)".
        (301 tests, 0 failures.)

---

# TODO: Harden the Capway SOAP fetch against silent row loss (2026-09-02)

## Problem
Action item `2026-09-02:capway_create_contract:tsuid:65200` was emitted for a subscriber whose
contract (`v2:1780472140:875617`) was active in the 2026-09-01 snapshot. The 2026-09-02 fetch did
not contain the row at all (all Capway fields on the item were `nil`, and the `capway-contracts`
row was not rewritten by that run). Root causes in `CapwaySubscribers`:
1. Worker ranges are sized from the REST *customer* count, but the report returns one row per
   *contract* — rows past the customer count are never requested.
2. A page that parses to zero rows is only logged, never treated as a failure.
3. Nothing compares today's fetched count with yesterday's cached count.
4. Nothing cross-checks a create item against the `capway-contracts` table.

## Tasks
- [x] 1. `CapwaySubscribers`: track pages (offset/requested/fetched), sweep the tail past the REST
      count until a short page, validate the page sequence (no data after a short/empty page)
- [x] 2. `CachedCapwaySubscribers`: abort (no cache write) when today's count drops below the
      previous day's manifest count by more than `CAPWAY_SNAPSHOT_DROP_TOLERANCE` (default 5%)
- [x] 3. `CapwayCacheRepository.read_manifest/1` + `CapwaySubscriber.updated_at` +
      `CapwayContractRepository.deserialize/1` populates it
- [x] 4. New step `SuppressKnownContracts` between `compare_data` and the store steps: drop a
      `:capway_create_contract` item when `capway-contracts` holds a recently-updated active
      contract for the same national id
- [x] 5. Tests for all of the above
- [x] 6. Docs: CHANGELOG, CLAUDE.md, README env vars
- [x] 7. `mix compile` warning scan (no warnings for new symbols) + `mix test` (352 tests, 0 failures)
