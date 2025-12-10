# CapwaySync Elixir Application

## Project Overview

`CapwaySync` is an Elixir-based application designed to synchronize subscriber data between a primary system called "Trinity" and a secondary system, "Capway". The application's core responsibilities include:

-   **Data Synchronization:** Comparing subscriber data between Trinity and Capway to identify discrepancies.
-   **Account Status Management:** Determining which accounts should be suspended or unsuspended based on predefined business logic.
-   **Reporting:** Generating detailed synchronization reports (`GeneralSyncReport`) in DynamoDB.
-   **Action Item Generation:** Creating `ActionItem` records in DynamoDB for necessary actions (e.g., "suspend", "unsuspend", "sync_to_capway", "update_capway_contract").

## Operational Guidelines

### Development Workflow
-   **Compilation:** Always run `mix compile` after completing a task or making code changes.
-   **Testing:** Always run `mix test` after making changes. Tests must cover 100% of the functionality.
-   **Changelog:** Always add a summary of your changes to `CHANGELOG.md` if available.
-   **Agent Context:** When initializing (or effectively re-initializing), always read `CLAUDE.md` or other agent files to gather full context.

### Key Commands
-   `mix deps.get`: Install dependencies.
-   `mix compile`: Compile the project.
-   `mix test`: Run all tests.
-   `iex -S mix`: Start interactive shell with application loaded.

## Local Development & Mocking

### Mock Capway SOAP
For faster local development, the application supports mocking SOAP responses. This avoids slow external calls to the Capway API.

**Configuration:**
```bash
# Enable mock mode
export USE_MOCK_CAPWAY=true

# Optional: Override specific response file
export MOCK_CAPWAY_RESPONSE="capway_edge_cases.xml"

# Optional: Add artificial delay (ms) for timeout testing
export MOCK_CAPWAY_DELAY=100
```

**Mock Response Behavior (by Offset):**
-   **Offset 0**: Normal data (Swedish names) - `capway_page_1.xml`
-   **Offset 100+**: Different data set - `capway_page_2.xml`
-   **Offset 200+**: Edge cases (nil values, encoding) - `capway_edge_cases.xml`
-   **Offset 1000+**: Empty response - `capway_empty.xml`

**Mock Files Location:** `priv/mock_responses/`

## Architecture & Technology Stack

-   **Language:** Elixir (~> 1.18)
-   **Workflow Engine:** `Reactor` (~> 0.16) - Manages the sync workflow steps.
-   **SOAP Client:** `soap` (~> 1.0) & `saxy` - For communicating with Capway's SOAP API (version 1.2).
-   **Database (Trinity):** `Ecto` (PostgreSQL) - For reading subscriber data.
-   **Cloud Storage (AWS):** `ExAws` (DynamoDB) - For storing reports and action items.
-   **Encryption:** `Cloak` - For handling sensitive data.
-   **HTTP Client:** `Req` - For general HTTP requests.
-   **Utilities:** `Jason` (JSON), `Timex` (Time), `UUID`.

### Sync Workflow Steps (`CapwaySync.Reactor.V1.SubscriberSyncWorkflow`)
1.  **fetch_trinity_data:** Fetches subscriber data from Trinity (Postgres).
2.  **convert_to_canonical_data:** Normalizes Trinity data for comparison.
3.  **fetch_capway_data:** Fetches subscriber data from Capway (SOAP).
4.  **compare_data:** Compares canonical datasets. Identifies missing/extra accounts and detects contracts needing update (missing ID in Capway but valid match) or creation (missing ID in Trinity).
5.  **prepare_suspend_unsuspend_data:** Enriches data to prepare for status logic.
6.  **suspend_accounts:** Identifies accounts to suspend (Collection >= 2).
7.  **unsuspend_accounts:** Identifies accounts to unsuspend (Collection=0, Unpaid=0).
8.  **cancel_capway_contracts:** Identifies contracts to cancel (Payment method changed).
9.  **capway_export_subscribers_csv:** Exports specific Capway data to CSV.
10. **process_results:** Aggregates all results and stores a `GeneralSyncReport` in DynamoDB.
11. **store_action_items:** Stores individual `ActionItem` records in DynamoDB for each required action.

### AWS/DynamoDB Integration
-   **Tables:**
    -   `SYNC_REPORTS_TABLE` (default: "capway-sync-reports")
    -   `ACTION_ITEMS_TABLE` (default: "capway-sync-action-items")
-   **Local Development:** Supports LocalStack (`USE_LOCALSTACK=true`).
-   **Credentials:** Requires standard AWS env vars (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`).

## Key Directories & Files
-   `lib/capway_sync/soap/generate_report.ex`: SOAP client implementation.
-   `lib/capway_sync/reactor/`: Workflow definitions.
-   `priv/`: WSDL files and mock responses.
-   `config/`: Configuration files (check `config.exs` and `runtime.exs`).

## Testing Strategy
-   **Framework:** ExUnit.
-   **Integration:** DynamoDB tests run against LocalStack.
-   **Coverage:** Strict requirement for high coverage (aiming for 100%).