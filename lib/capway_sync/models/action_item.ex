defmodule CapwaySync.Models.ActionItem do
  @moduledoc """
  Represents an individual action item that needs to be processed as a result of sync analysis.

  This struct contains specific actions identified during the subscriber sync workflow,
  such as accounts that need to be suspended, unsuspended, or synchronized to Capway.
  Each action item represents a single, trackable task that can be processed independently.

  ## Action Types

  - **suspend** - Account needs to be suspended in Capway (collection >= threshold)
  - **unsuspend** - Account needs to be unsuspended in Capway (collection = 0 AND unpaid_invoices = 0)
  - **sync_to_capway** - Account needs to be added to Capway (missing in Capway system)
  - **cancel_capway_contract** - Capway contract needs cancellation (payment method changed from "capway" in Trinity)

  ## Storage Schema

  The DynamoDB table uses the following key structure:
  - **Partition Key**: `id` (String) - UUID of the action item
  - **Sort Key**: `created_at` (String) - Human-readable date format (YYYY-MM-DD-HH-mm) for chronological ordering

  ## Usage

      # Create action items from sync report
      action_items = ActionItem.create_action_items_from_report(sync_report)

      # Store individual action item
      {:ok, item_id} = ActionItemRepository.store_action_item(action_item)
  """

  @valid_actions ~w(suspend unsuspend sync_to_capway cancel_capway_contract)

  @type action_type :: :suspend | :unsuspend | :sync_to_capway | :cancel_capway_contract

  @type t :: %__MODULE__{
          id: String.t() | nil,
          trinity_id: String.t(),
          personal_number: String.t() | nil,
          created_at: String.t(),
          timestamp: non_neg_integer(),
          action: String.t(),
          status: :pending | :completed | :failed
        }

  @derive Jason.Encoder
  @derive ExAws.Dynamo.Encodable
  defstruct id: nil,
            trinity_id: nil,
            personal_number: nil,
            created_at: nil,
            timestamp: 0,
            action: nil,
            status: :pending

  @doc """
  Creates action items from a GeneralSyncReport.

  Extracts actionable data from the sync report and creates individual ActionItem
  structs for each required action. All action items from the same report share
  the same created_at timestamp for correlation.

  ## Parameters
  - `report`: %GeneralSyncReport{} struct containing sync results

  ## Returns
  - List of %ActionItem{} structs ready for storage

  ## Examples

      iex> report = %GeneralSyncReport{
      ...>   missing_in_capway: [%{id: "123456789012", personal_number: "199001012345"}],
      ...>   suspend_accounts: [%{id: "234567890123", personal_number: "199002023456"}],
      ...>   unsuspend_accounts: [%{id: "345678901234", personal_number: "199003034567"}],
      ...>   created_at: ~U[2024-01-15 10:30:00Z]
      ...> }
      iex> items = ActionItem.create_action_items_from_report(report)
      iex> length(items)
      3
      iex> Enum.map(items, & &1.action) |> Enum.sort()
      ["suspend", "sync_to_capway", "unsuspend"]
  """
  def create_action_items_from_report(%CapwaySync.Models.GeneralSyncReport{} = report) do
    # Use report's created_at or current time
    base_datetime = report.created_at || DateTime.utc_now()
    timestamp_unix = DateTime.to_unix(base_datetime)
    created_at_formatted = format_date_time(base_datetime)

    # Create action items for each category
    sync_items =
      create_action_items(
        report.missing_in_capway,
        "sync_to_capway",
        created_at_formatted,
        timestamp_unix
      )

    suspend_items =
      create_action_items(
        report.suspend_accounts,
        "suspend",
        created_at_formatted,
        timestamp_unix
      )

    unsuspend_items =
      create_action_items(
        report.unsuspend_accounts,
        "unsuspend",
        created_at_formatted,
        timestamp_unix
      )

    cancel_items =
      create_action_items(
        Map.get(report, :cancel_capway_contracts, []),
        "cancel_capway_contract",
        created_at_formatted,
        timestamp_unix
      )

    sync_items ++ suspend_items ++ unsuspend_items ++ cancel_items
  end

  @doc """
  Validates an action type.

  ## Parameters
  - `action`: String representing the action type

  ## Returns
  - `:ok` if action is valid
  - `{:error, reason}` if action is invalid

  ## Examples

      iex> ActionItem.validate_action("suspend")
      :ok

      iex> ActionItem.validate_action("invalid_action")
      {:error, "Invalid action type. Must be one of: suspend, unsuspend, sync_to_capway, cancel_capway_contract"}
  """
  def validate_action(action) when action in @valid_actions, do: :ok

  def validate_action(_action) do
    {:error, "Invalid action type. Must be one of: #{Enum.join(@valid_actions, ", ")}"}
  end

  @doc """
  Returns list of valid action types.
  """
  def valid_actions, do: @valid_actions

  # Private helper functions

  defp create_action_items(
         subscriber_data,
         action,
         created_at_formatted,
         timestamp_unix,
         status \\ :pending
       )
       when is_list(subscriber_data) do
    Enum.map(subscriber_data, fn subscriber ->
      # Handle both old format (simple IDs) and new format (maps with id and personal_number)
      {trinity_id, personal_number} = case subscriber do
        %{id: id, personal_number: pn} -> {id, pn}
        id when is_binary(id) or is_integer(id) -> {id, nil}
        _ -> {nil, nil}
      end

      %__MODULE__{
        id: UUID.uuid4(),
        trinity_id: to_string(trinity_id),
        personal_number: personal_number,
        created_at: created_at_formatted,
        timestamp: timestamp_unix,
        action: action,
        status: status
      }
    end)
    |> Enum.reject(fn item -> is_nil(item.trinity_id) or item.trinity_id == "nil" end)
  end

  defp format_date_time(%DateTime{} = datetime) do
    Timex.format!(datetime, "{YYYY}-{0M}-{0D}")
  end
end
