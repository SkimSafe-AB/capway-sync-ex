# CapwaySync

CapwaySync is an Elixir application that synchronizes subscriber data between Trinity (master system) and Capway systems. It performs data comparison, identifies accounts that need suspension/unsuspension, and generates comprehensive reports.

## Quick Start

### Connect to iex on docker
```bash
iex --cookie mycookie --name debug@127.0.0.1 --remsh capway_sync@127.0.0.1
```

### Run the sync workflow
```elixir
i
```

### Development with Mock Data
For faster local development, enable mock Capway SOAP responses:
```bash
export USE_MOCK_CAPWAY=true
iex -S mix
```

## Sync Report Structure

The workflow generates a `GeneralSyncReport` that contains all synchronization results. Understanding what each list means is crucial for interpreting the sync results.

### Data Flow Overview

1. **Trinity** (Master System) - The authoritative source of subscriber data
2. **Capway** (Target System) - The system to be synchronized with Trinity
3. **Comparison** - Identifies differences between the two systems
4. **Actions** - Determines what accounts need suspension/unsuspension

### Report Fields Explained

#### Data Comparison Results

These fields show the overall comparison between Trinity and Capway systems:

- **`missing_in_capway`** - Subscriber IDs that exist in Trinity but are missing in Capway
  - **Meaning**: These accounts need to be **added** to Capway
  - **Action Required**: Create these accounts in Capway system

- **`missing_in_trinity`** - Subscriber IDs that exist in Capway but are missing in Trinity
  - **Meaning**: These accounts should be **removed** from Capway (no longer exist in master system)
  - **Action Required**: Deactivate/remove these accounts from Capway

- **`existing_in_both`** - Count of subscribers that exist in both systems
  - **Meaning**: These accounts are properly synchronized
  - **Action Required**: None (for comparison purposes)

#### Suspension Analysis Results

These fields identify accounts that need their suspension status changed:

- **`suspend_accounts`** - Subscriber IDs that should be suspended
  - **Criteria**: Accounts with `collection >= suspend_threshold` (default: 2)
  - **Meaning**: These accounts have 2 or more collections and should be suspended
  - **Action Required**: Suspend these accounts in Capway

- **`unsuspend_accounts`** - Subscriber IDs that should be unsuspended
  - **Criteria**: Accounts with `collection = 0` AND `unpaid_invoices = 0` (BOTH conditions must be true)
  - **Meaning**: These accounts have completely cleared ALL debts and collections
  - **Action Required**: Unsuspend these accounts in Capway
  - **Note**: Very strict criteria - account must be completely clean

#### Analysis Metadata & Statistics

The report includes a nested `analysis_metadata` field that contains **all statistical insights** and analytics about your subscriber base. This data is for analysis, reporting, and understanding trends - not for direct actions:

```elixir
analysis_metadata: %{
  suspend_total_analyzed: integer(),
  unsuspend_total_analyzed: integer(),
  suspend_collection_summary: map(),
  unsuspend_collection_summary: map(),
  unsuspend_unpaid_invoices_summary: map()
}
```

**Fields within `analysis_metadata`:**

- **`suspend_total_analyzed`** - Total number of accounts analyzed for suspension
  - **Meaning**: Count of accounts that exist in both systems and were checked for suspension criteria
  - **Context**: This is the denominator when calculating suspension rates

- **`suspend_collection_summary`** - **Statistical breakdown** of collection values across analyzed accounts
  - **Structure**: `%{"0" => count, "1" => count, "2" => count, "3+" => count, "invalid" => count, "nil" => count}`
  - **Purpose**: Analytics and reporting - understand your subscriber payment patterns
  - **Example**: `%{"0" => 50, "1" => 30, "2" => 15, "3+" => 5}` means 50 accounts have no collections, 30 have 1 collection, etc.
  - **Use Case**: Track trends, generate reports, monitor overall financial health

- **`unsuspend_total_analyzed`** - Total number of accounts analyzed for unsuspension
  - **Meaning**: Same as suspend_total_analyzed but for unsuspension logic
  - **Context**: All accounts existing in both systems are analyzed for both suspend and unsuspend

- **`unsuspend_collection_summary`** - **Statistical distribution** of collection values for analytics
  - **Structure**: Same as suspend_collection_summary
  - **Purpose**: Same data as suspend summary, provided for consistency in reporting

- **`unsuspend_unpaid_invoices_summary`** - **Statistical breakdown** of unpaid invoice values
  - **Structure**: `%{"0" => count, "1" => count, "2" => count, "3+" => count, "invalid" => count, "nil" => count}`
  - **Purpose**: Analytics on invoice payment patterns - understand billing collection effectiveness
  - **Use Case**: Monitor how many customers have outstanding invoices, track payment trends

#### Summary Counts

- **`total_trinity`** - Total number of subscribers in Trinity system
- **`total_capway`** - Total number of subscribers in Capway system
- **`missing_capway_count`** - Count of accounts to add to Capway
- **`missing_trinity_count`** - Count of accounts to remove from Capway
- **`suspend_count`** - Count of accounts to suspend
- **`unsuspend_count`** - Count of accounts to unsuspend

### Example Report Interpretation

```elixir
%GeneralSyncReport{
  # Actionable data - what to DO
  total_trinity: 1000,
  total_capway: 995,
  missing_in_capway: ["123456789012", "234567890123"],  # 2 accounts to ADD
  missing_in_trinity: ["345678901234"],                  # 1 account to REMOVE
  suspend_accounts: ["456789012345", "567890123456"],    # 2 accounts to SUSPEND
  unsuspend_accounts: ["678901234567"],                  # 1 account to UNSUSPEND
  suspend_threshold: 2,

  # Statistical insights - for ANALYSIS
  analysis_metadata: %{
    suspend_total_analyzed: 990,                         # 990 accounts checked for suspension
    unsuspend_total_analyzed: 990,                       # Same 990 accounts checked for unsuspension
    suspend_collection_summary: %{
      "0" => 800,    # 800 accounts with no collections
      "1" => 100,    # 100 accounts with 1 collection
      "2" => 50,     # 50 accounts with 2 collections (candidates for suspension)
      "3+" => 40     # 40 accounts with 3+ collections (candidates for suspension)
    },
    unsuspend_collection_summary: %{                     # Same as suspend summary
      "0" => 800, "1" => 100, "2" => 50, "3+" => 40
    },
    unsuspend_unpaid_invoices_summary: %{
      "0" => 850,    # 850 accounts with no unpaid invoices
      "1" => 80,     # 80 accounts with 1 unpaid invoice
      "2" => 40,     # 40 accounts with 2 unpaid invoices
      "3+" => 20     # 20 accounts with 3+ unpaid invoices
    }
  },
  # ... other fields
}
```

**Interpretation:**
- Trinity has 1000 subscribers, Capway has 995
- 2 new subscribers need to be added to Capway
- 1 old subscriber should be removed from Capway
- Of the 990 accounts existing in both systems:
  - **90 accounts qualify for suspension** (50 with collection=2 + 40 with collection=3+) but only **2 were actually selected**
  - **Only 1 account qualified for unsuspension** (collection=0 AND unpaid_invoices=0)
  - 800 accounts have clean collection status (collection=0)
  - 850 accounts have no unpaid invoices
  - For unsuspension: an account must have BOTH collection=0 AND unpaid_invoices=0 (very strict criteria)

### Data Privacy and Storage

To protect sensitive data, the report stores only **reference IDs** instead of full subscriber objects:

- **`trinity_id`** - Preferred identifier from Trinity system
- **`capway_id`** - Fallback identifier from Capway system
- **`customer_ref`** - Additional fallback identifier
- **`id_number`** - Final fallback (personal number)

The actual sensitive data (names, personal numbers, etc.) is **not stored** in the report for privacy compliance.

### DynamoDB Storage Structure

The report is stored in DynamoDB with a clean nested structure for easy exploration in the AWS console:

```json
{
  "id": "report-uuid-123",
  "created_at": "2024-01-15T10:30:00Z",
  "sync": {
    "missing_in_capway": ["123456789012"],
    "missing_in_trinity": ["345678901234"],
    "existing_in_both": ["567890123456"],
    "missing_capway_count": 2,
    "missing_trinity_count": 1,
    "existing_in_both_count": 990
  },
  "suspend": {
    "suspend_accounts": ["456789012345"],
    "suspend_count": 1,
    "suspend_threshold": 2
  },
  "unsuspend": {
    "unsuspend_accounts": ["678901234567"],
    "unsuspend_count": 1
  },
  "stats": {
    "total_trinity": 1000,
    "total_capway": 995,
    "execution_duration_ms": 1500,
    "execution_duration_formatted": "1.5s",
    "suspend_total_analyzed": 990,
    "suspend_collection_summary": {"0": 800, "1": 100, "2": 50},
    "unsuspend_collection_summary": {"0": 800, "1": 100, "2": 50},
    "unsuspend_unpaid_invoices_summary": {"0": 850, "1": 80, "2": 40}
  }
}
```

**Benefits of this structure:**
- **`sync`** section - All synchronization data is expandable and browsable
- **`suspend`** section - Suspension actions are grouped together
- **`unsuspend`** section - Unsuspension actions are grouped together
- **`stats`** section - All analytics and statistical data in one place
- **Console-friendly** - Each nested object can be expanded in the DynamoDB console for easy debugging

### Action Items Storage

The workflow automatically creates individual ActionItem records in DynamoDB for each required action identified during sync. This enables tracking and processing of individual tasks:

#### Action Item Schema

Each action item contains:
- **`id`** - UUID for unique identification
- **`trinity_id`** - Trinity subscriber ID for linking back to source data
- **`created_at`** - Human-readable date format (YYYY-MM-DD-HH-mm) used as DynamoDB sort key
- **`timestamp`** - Unix timestamp for precise time calculations
- **`action`** - Action type: "suspend", "unsuspend", or "sync_to_capway"

#### Action Types Created

- **`sync_to_capway`** - For accounts in `missing_in_capway` list (need to be added to Capway)
- **`suspend`** - For accounts in `suspend_accounts` list (collection >= threshold)
- **`unsuspend`** - For accounts in `unsuspend_accounts` list (collection = 0 AND unpaid_invoices = 0)

#### DynamoDB Table Configuration

Action items are stored in a separate DynamoDB table:
- **Table Name**: Configured via `ACTION_ITEMS_TABLE` environment variable (default: "capway-sync-action-items")
- **Partition Key**: `id` (String) - UUID of the action item
- **Sort Key**: `created_at` (String) - Human-readable date format (YYYY-MM-DD-HH-mm)

#### Querying Action Items

The ActionItemRepository provides filtering capabilities:

```elixir
# Get all suspend actions
{:ok, suspend_items} = ActionItemRepository.list_action_items(action: "suspend")

# Get recent items for specific trinity_id
{:ok, user_items} = ActionItemRepository.list_action_items(
  trinity_id: "123456789012",
  limit: 10
)

# Get items within date range (using string format)
{:ok, daily_items} = ActionItemRepository.list_action_items(
  start_date: "2024-01-15-00-00-00",
  end_date: "2024-01-15-23-59-59"
)
```

#### Integration with External Systems

The action items storage enables:
- **Queue Processing** - External systems can poll for pending actions
- **Audit Trail** - Complete history of all sync-generated tasks
- **Batch Operations** - Group actions by type for efficient processing
- **Monitoring** - Track completion rates and processing times
- **Manual Review** - Human oversight of critical actions before execution

### Mock Development Data

For local development, mock data includes:
- Realistic Swedish names and personal numbers
- Various collection and invoice values (0-5)
- Edge cases with nil values and special characters
- Pagination simulation with different data sets

Enable with: `export USE_MOCK_CAPWAY=true`

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `capway_sync` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:capway_sync, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/capway_sync>.

