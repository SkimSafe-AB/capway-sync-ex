# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
-   Personal number details to the synchronization process.

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
