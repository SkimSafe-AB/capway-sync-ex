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
