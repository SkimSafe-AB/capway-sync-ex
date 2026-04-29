# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
-   `sub_action` field on `ActionItem` for downstream branching of `:capway_update_customer`. Values: `:update_email`, `:update_nin`, `:update_email_and_nin`, or `nil` for any other action type. `CompareDataV2.get_customers_to_update/3` derives it from the same `{nat_diff, email_diff}` tuple that drives the comment text. The field is persisted to DynamoDB by `ActionItemRepositoryV2` and surfaced as a `sub_action_breakdown` (counts per sub_action) in the `update_customers` section of the `GeneralSyncReport`.
-   `FetchCapwayEmails` now also backfills `national_id` from the payment processor REST response (`idNumber`), in addition to `email`. This avoids false `:capway_update_customer` items caused by lag in the Capway SOAP report when a customer's personal number was just edited Trinity-side — the comparison now runs against fresh REST values.
-   Email-drift detection between Trinity subscribers and Capway customers:
    -   Trinity is the source of truth (`Trinity.Subscriber.email`, encrypted, surfaced into the local Ecto schema and the `Canonical` model).
    -   New `CapwaySync.Clients.PaymentProcessor.Client.get_capway_customer_by_id/1` (Req-based) fetches each customer one-by-one from `GET <PAYMENT_PROCESSOR_HOST>v3/capway/customers/by_customer_id/:customer_id` and returns the JSON body.
    -   New `CapwaySync.Reactor.V1.Steps.FetchCapwayEmails` step (inserted between `:group_subscribers` and `:compare_data`) backfills the Capway-side email on every active matched subscriber, concurrently via `Task.async_stream` (configurable via `CAPWAY_EMAIL_FETCH_CONCURRENCY`, default 10). Errors and `:not_found` are tolerated — the entry stays at `email: nil` and is treated as "unknown".
    -   `CompareDataV2.get_customers_to_update/3` now triggers `:capway_update_customer` action items on national-id mismatch **or** email mismatch (or both). The `comment` field reflects exactly which fields differ — actual email values are never logged or stored. Email comparison is case-insensitive and trim-insensitive; missing/blank emails on either side are treated as unknown.
    -   New required env var `PAYMENT_PROCESSOR_HOST` (must end with `/`).
-   `CapwayContractRepository` — stores every Capway contract as its own DynamoDB item keyed by `contract_ref_no`:
    -   Provides fast contract-level lookups without hitting the slow Capway SOAP API
    -   Query by `contract_ref_no` (primary key), `customer_ref` (GSI), or `id_number` (GSI)
    -   Automatically populated during the sync workflow after Capway data is fetched
    -   Table name configured via `CAPWAY_CONTRACTS_TABLE` env var (default: "capway-contracts")

### Changed
-   **Breaking**: Capway subscriber data is now keyed by `capway_contract_ref` instead of `trinity_subscriber_id`:
    -   Each contract is treated as a unique entity — multiple active contracts for the same customer are preserved separately
    -   Two active contracts for the same customer now produce two separate action items
    -   `above_collector_threshold` now only includes active contracts (previously included inactive contracts with stale collection data)
    -   Fixes false-positive suspend actions caused by old/inactive contracts with historical collection values overwriting current clean contracts
-   Added `capway_contract_ref` field to `ActionItem` model and DynamoDB storage for contract-level traceability
-   Action item result maps in `CompareDataV2` are keyed by `capway_contract_ref` for Capway-originated actions
-   `get_contracts_to_cancel` logic simplified — no longer has contradictory `has_key? == false` + `Map.get != nil` guard

### Added
-   DynamoDB cache layer for Capway subscriber data (`CapwayCacheRepository`):
    - Caches SOAP API results in DynamoDB keyed by date, since data only updates once per day
    - Subscribers chunked into groups of 200 to stay within DynamoDB's 400KB item limit
    - Manifest item per date tracks total count, chunk count, and timestamp
    - TTL of 2 days for automatic cleanup
    - `CAPWAY_CACHE_BYPASS=true` env var to force fresh SOAP fetch
    - New `CAPWAY_CACHE_TABLE` env var for table name configuration
-   `CachedCapwaySubscribers` Reactor step wrapping `CapwaySubscribers` with cache logic
-   `query/2` function to DynamoDB Client and Behaviour
-   Personal number details to the synchronization process.
-   Configurable page limit for Capway data fetching via `CAPWAY_MAX_PAGES` environment variable:
    - Each page contains 100 records
    - Defaults to unlimited if not set
    - Significantly speeds up tests when limited (e.g., `CAPWAY_MAX_PAGES=6` for 600 records)
    - Logs warning when limiting is applied to ensure visibility

### Fixed
-   Fixed `Enum.reduce` arity error in `CapwaySync.Models.Subscribers.Cannonical.Helper.group/2` function:
    - The `locked_subscribers` calculation was incorrectly trying to iterate over `active_subscribers` (a Map) instead of the original `subscribers` list
    - Now correctly filters from the original list and checks both active status and subscription_type in a single pass
    - Added comprehensive documentation for both Trinity and Capway grouping functions

### Fixed
-   Fixed `Protocol.UndefinedError` for `ExAws.Dynamo.Encodable` when storing data to DynamoDB.
    - Changed `created_at` field in GeneralSyncReport from `DateTime` to `String` type
    - Changed `end_date` field in Canonical model from `NaiveDateTime` to `String` type
    - Now using Timex to format timestamps as ISO8601 strings
    - Removed `@derive ExAws.Dynamo.Encodable` from models with DateTime/NaiveDateTime fields:
      - GeneralSyncReport
      - Canonical (Subscribers)
      - Trinity Subscription (has end_date and requested_cancellation_date as NaiveDateTime)
      - Trinity Subscriber (has timestamps from Ecto)
      - CapwaySubscriber (for consistency)
    - Updated repository to store only ID lists instead of full structs in DynamoDB:
      - `missing_in_capway`, `missing_in_trinity`, `existing_in_both` now use ID lists
      - This avoids nested struct encoding issues
    - Updated repository functions and tests to handle string-based timestamps properly

### Changed
-   Canonical subscriber model now includes `status` field to preserve original Trinity subscription status.
-   Canonical subscriber model now includes `subscription_type` field to preserve subscription type from Trinity.
-   `missing_in_capway` list now excludes subscribers with cancelled status from Trinity, preventing cancelled subscriptions from being incorrectly identified as missing in Capway.
-   `suspend_accounts` list now excludes subscribers with `pending_cancel` status from suspension, avoiding suspension of accounts already in the cancellation process.
-   `SuspendAccounts` step now separates accounts meeting suspend threshold into two lists:
    -   `suspend_accounts`: Accounts with `subscription_type == "locked"` (to be suspended)
    -   `cancel_contracts`: Accounts without `subscription_type == "locked"` (to be cancelled instead of suspended)
-   Trinity Subscription model now includes `subscription_type` field to support differentiation between locked and unlocked subscriptions.
-   `prepare_suspend_unsuspend_data` workflow step now enriches Capway data with Trinity `subscription_type` and `status` fields to enable proper filtering in suspend/unsuspend steps.
-   `cancel_capway_contracts` list now merges contracts from both sources:
    -   Contracts needing cancellation due to payment method changes (from `CancelCapwayContracts` step)
    -   Non-locked subscriptions with high collection that should be cancelled instead of suspended (from `SuspendAccounts` step)

## [0.1.0] - 2025-10-06

### Added
-   Initial version of the `CapwaySync` application.
-   Core synchronization logic between Trinity and Capway.
-   Functionality to suspend and unsuspend accounts.
-   Generation of synchronization reports.
-   Creation of action items in DynamoDB.
-   Testing suite with ExUnit.
-   CI/CD pipeline with GitHub Actions.
-   Support for production and mock development environments.
-   Functionality to cancel contracts.
-   Concurrent execution of synchronization steps.
-   SOAP integration for communication with Capway.
-   Ecto integration for communication with Trinity.
-   Basic application supervision.
