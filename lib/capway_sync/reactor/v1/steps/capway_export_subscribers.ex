defmodule CapwaySync.Reactor.V1.Steps.CapwayExportSubscribers do
  @moduledoc """
  Exports Capway subscribers with unpaid invoices and collections data to CSV format.

  This step filters subscribers based on unpaid invoices and collection amounts,
  then exports the relevant data to a CSV file for further analysis or processing.

  ## Input Arguments
  - `capway_data`: Raw Capway subscriber data containing unpaid invoices and collection info

  ## Output
  Returns a map with:
  - `csv_file_path`: Path to the generated CSV file
  - `customers_with_unpaid_invoices`: Count of subscribers with unpaid invoices > 0
  - `customers_with_collections`: Count of subscribers with collections > 0
  - `total_exported`: Total number of subscribers exported to CSV
  """

  use Reactor.Step
  require Logger

  @impl Reactor.Step
  def run(arguments, _context, options \\ []) do
    Logger.info("Starting CSV export for subscribers with unpaid invoices and collections")

    with {:ok, capway_data} <- validate_argument(arguments, :capway_data) do
      # Filter subscribers with unpaid invoices or collections
      subscribers_to_export = filter_subscribers_for_export(capway_data)

      # Generate CSV content
      csv_content = generate_csv_content(subscribers_to_export)

      # Write CSV file
      output_dir = Keyword.get(options, :output_dir, "priv/exports")
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
      filename = "capway_subscribers_unpaid_collections_#{timestamp}.csv"
      file_path = Path.join(output_dir, filename)

      case write_csv_file(file_path, csv_content, output_dir) do
        :ok ->
          # Calculate statistics
          customers_with_unpaid = count_subscribers_with_unpaid_invoices(subscribers_to_export)
          customers_with_collections = count_subscribers_with_collections(subscribers_to_export)

          result = %{
            csv_file_path: file_path,
            customers_with_unpaid_invoices: customers_with_unpaid,
            customers_with_collections: customers_with_collections,
            total_exported: length(subscribers_to_export)
          }

          Logger.info("CSV export completed: #{result.total_exported} subscribers exported to #{file_path}")
          Logger.info("  - Subscribers with unpaid invoices: #{result.customers_with_unpaid_invoices}")
          Logger.info("  - Subscribers with collections: #{result.customers_with_collections}")

          {:ok, result}

        {:error, reason} ->
          Logger.error("Failed to write CSV file: #{inspect(reason)}")
          {:error, "Failed to write CSV file: #{inspect(reason)}"}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Filters subscribers who have either unpaid invoices > 0 or collections > 0.
  Returns list of subscribers that should be exported to CSV.
  """
  def filter_subscribers_for_export(capway_data) when is_list(capway_data) do
    capway_data
    |> Enum.filter(fn subscriber ->
      unpaid_invoices = Map.get(subscriber, :unpaid_invoices, 0) || 0
      collection = Map.get(subscriber, :collection, 0) || 0

      unpaid_invoices > 0 || collection > 0
    end)
  end

  @doc """
  Generates CSV content from subscriber data.
  """
  def generate_csv_content(subscribers) when is_list(subscribers) do
    header = "id_number,name,customer_ref,email,unpaid_invoices,collection\n"

    rows =
      subscribers
      |> Enum.map(&subscriber_to_csv_row/1)
      |> Enum.join("")

    header <> rows
  end

  @doc """
  Converts a single subscriber record to a CSV row.
  """
  def subscriber_to_csv_row(subscriber) do
    id_number = Map.get(subscriber, :id_number, "")
    name = Map.get(subscriber, :name, "") |> escape_csv_field()
    customer_ref = Map.get(subscriber, :customer_ref, "")
    email = "" # Email not available in current data structure
    unpaid_invoices = Map.get(subscriber, :unpaid_invoices, 0) || 0
    collection = Map.get(subscriber, :collection, 0) || 0

    "#{id_number},#{name},#{customer_ref},#{email},#{unpaid_invoices},#{collection}\n"
  end

  @doc """
  Escapes CSV field content by wrapping in quotes if it contains commas, quotes, or newlines.
  """
  def escape_csv_field(nil), do: ""
  def escape_csv_field(""), do: ""
  def escape_csv_field(field) when is_binary(field) do
    if String.contains?(field, [",", "\"", "\n", "\r"]) do
      # Escape quotes by doubling them and wrap in quotes
      escaped = String.replace(field, "\"", "\"\"")
      "\"#{escaped}\""
    else
      field
    end
  end
  def escape_csv_field(field), do: to_string(field)

  @doc """
  Counts subscribers with unpaid invoices > 0.
  """
  def count_subscribers_with_unpaid_invoices(subscribers) when is_list(subscribers) do
    subscribers
    |> Enum.count(fn subscriber ->
      unpaid_invoices = Map.get(subscriber, :unpaid_invoices, 0) || 0
      unpaid_invoices > 0
    end)
  end

  @doc """
  Counts subscribers with collections > 0.
  """
  def count_subscribers_with_collections(subscribers) when is_list(subscribers) do
    subscribers
    |> Enum.count(fn subscriber ->
      collection = Map.get(subscriber, :collection, 0) || 0
      collection > 0
    end)
  end

  # Private helper functions

  defp validate_argument(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, "Missing required argument: #{key}"}
      [] -> {:ok, []} # Empty list is valid
      value when is_list(value) -> {:ok, value}
      _ -> {:error, "Argument #{key} must be a list"}
    end
  end

  defp write_csv_file(file_path, content, output_dir) do
    try do
      # Ensure output directory exists
      case File.mkdir_p(output_dir) do
        :ok ->
          File.write(file_path, content)
        {:error, reason} ->
          {:error, "Failed to create output directory: #{inspect(reason)}"}
      end
    rescue
      error ->
        {:error, "Exception writing file: #{inspect(error)}"}
    end
  end
end