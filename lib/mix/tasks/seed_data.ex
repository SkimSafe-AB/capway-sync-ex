defmodule Mix.Tasks.SeedData do
  @moduledoc """
  Mix task to generate test data based on real SOAP response.

  This task parses the actual SOAP response XML and generates randomized
  test data with various suspension statuses for testing the suspend/unsuspend workflows.

  ## Usage

      # Generate default number of records (50)
      mix seed_data

      # Generate specific number of records
      mix seed_data --count 100

      # Output to file
      mix seed_data --output priv/test_data.exs

      # Insert into Trinity database
      mix seed_data --count 25 --insert

      # Insert with specific subscription statuses
      mix seed_data --count 25 --insert --suspend-some
  """

  use Mix.Task

  alias CapwaySync.Models.CapwaySubscriber
  alias CapwaySync.Models.Trinity.{Subscriber, Subscription}
  alias CapwaySync.TrinityRepo

  @default_count 50
  @soap_response_file "priv/soap_response.xml"

  @doc """
  Main entry point for the Mix task.
  """
  def run(args) do
    {opts, _args, _invalid} = OptionParser.parse(args,
      strict: [count: :integer, output: :string, insert: :boolean, suspend_some: :boolean],
      aliases: [c: :count, o: :output, i: :insert]
    )

    count = Keyword.get(opts, :count, @default_count)
    output_file = Keyword.get(opts, :output)
    insert_to_trinity = Keyword.get(opts, :insert, false)
    suspend_some = Keyword.get(opts, :suspend_some, false)

    Mix.shell().info("🔄 Parsing SOAP response data...")
    real_data = parse_soap_response()

    Mix.shell().info("📊 Found #{length(real_data)} real subscriber records")
    Mix.shell().info("🎲 Generating #{count} randomized test records...")

    test_data = generate_test_data(real_data, count)

    # Analyze the generated data
    suspend_count = Enum.count(test_data, fn sub ->
      case parse_int_safely(sub.collection) do
        {:ok, val} when val >= 2 -> true
        _ -> false
      end
    end)

    unsuspend_count = Enum.count(test_data, fn sub ->
      collection_ok = case parse_int_safely(sub.collection) do
        {:ok, 0} -> true
        _ -> false
      end

      unpaid_invoices_ok = case parse_int_safely(sub.unpaid_invoices) do
        {:ok, 0} -> true
        _ -> false
      end

      collection_ok && unpaid_invoices_ok
    end)

    Mix.shell().info("📈 Generated data analysis:")
    Mix.shell().info("   • Total records: #{length(test_data)}")
    Mix.shell().info("   • Should be suspended (collection >= 2): #{suspend_count}")
    Mix.shell().info("   • Should be unsuspended (collection=0 & unpaid_invoices=0): #{unsuspend_count}")

    # Insert to Trinity database if requested
    if insert_to_trinity do
      Mix.shell().info("📥 Inserting data into Trinity database...")
      case insert_to_trinity_db(test_data, suspend_some) do
        {:ok, inserted_count} ->
          Mix.shell().info("✅ Inserted #{inserted_count} subscribers into Trinity database")
        {:error, :database_unavailable} ->
          Mix.shell().error("❌ Trinity database not available. Please:")
          Mix.shell().error("   1. Start the database with: docker compose up postgres")
          Mix.shell().error("   2. Check your database configuration")
          Mix.shell().error("   3. Ensure TRINITY_DB_* environment variables are set")
        {:error, reason} ->
          Mix.shell().error("❌ Database insertion failed: #{reason}")
      end
    end

    # Output the data
    if output_file do
      write_to_file(test_data, output_file)
      Mix.shell().info("✅ Data written to #{output_file}")
    else
      print_data(test_data)
    end
  end

  @doc """
  Parse the SOAP response XML file to extract real subscriber data.
  """
  def parse_soap_response do
    file_path = Path.join(File.cwd!(), @soap_response_file)

    unless File.exists?(file_path) do
      Mix.raise("SOAP response file not found: #{file_path}")
    end

    # Read the XML content
    xml_content = File.read!(file_path)

    # Parse using simple regex pattern matching since the file is too large for full XML parsing
    # Extract ReportResults sections
    report_results = Regex.scan(~r/<ReportResults>.*?<\/ReportResults>/s, xml_content)

    # Parse each ReportResults section
    Enum.map(report_results, fn [report_result] ->
      # Extract all Value elements from this report
      values = Regex.scan(~r/<Value(?:\s+[^>]*)?>([^<]*)<\/Value>|<Value[^>]*nil="true"[^>]*\/?>/, report_result)
      |> Enum.map(fn
        [_, value] when value != "" -> String.trim(value)
        [_] -> nil  # nil values
        _ -> nil
      end)

      # Convert to CapwaySubscriber based on field mapping
      create_subscriber_from_values(values)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.customer_ref)  # Remove duplicates by customer_ref
  end

  @doc """
  Create a CapwaySubscriber from parsed XML values based on field mapping.
  Field order: [rownum, datasetid, customerref, idnumber, name, contractrefno, regdate, startdate, enddate, active, paidInvoices, w, collection, lastInvoiceStatus]
  """
  def create_subscriber_from_values(values) when length(values) >= 14 do
    %CapwaySubscriber{
      customer_ref: Enum.at(values, 2),
      id_number: Enum.at(values, 3),
      name: Enum.at(values, 4),
      contract_ref_no: Enum.at(values, 5),
      reg_date: Enum.at(values, 6),
      start_date: Enum.at(values, 7),
      end_date: Enum.at(values, 8),
      active: Enum.at(values, 9),
      paid_invoices: Enum.at(values, 10),
      unpaid_invoices: Enum.at(values, 11),
      collection: Enum.at(values, 12),
      last_invoice_status: Enum.at(values, 13),
      origin: "soap_seed_data",
      raw_data: values
    }
  end
  def create_subscriber_from_values(_), do: nil

  @doc """
  Generate randomized test data based on real data patterns.
  """
  def generate_test_data(real_data, count) do
    # Extract patterns from real data
    names = Enum.map(real_data, & &1.name) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    id_patterns = Enum.map(real_data, & &1.id_number) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    # Generate test data
    1..count
    |> Enum.map(fn i ->
      # Pick random base data
      base = Enum.random(real_data)

      # Generate random values for testing
      collection = random_collection_value()
      unpaid_invoices_value = random_unpaid_invoices_value()

      # Create variations of names
      name = generate_swedish_name(names)

      # Generate Swedish personal number
      id_number = generate_swedish_id(id_patterns)

      %CapwaySubscriber{
        customer_ref: "SEED_#{i}_#{:rand.uniform(99999)}",
        id_number: id_number,
        name: name,
        contract_ref_no: generate_contract_ref(),
        reg_date: generate_date_near(base.reg_date),
        start_date: generate_date_near(base.start_date),
        end_date: maybe_generate_end_date(),
        active: random_active_status(),
        paid_invoices: "#{:rand.uniform(5)}",
        unpaid_invoices: unpaid_invoices_value,
        collection: collection,
        last_invoice_status: random_invoice_status(),
        origin: "generated_seed_data"
      }
    end)
  end

  # Helper functions for generating random data

  defp random_collection_value do
    # Weight the distribution to create good test cases
    case :rand.uniform(100) do
      n when n <= 20 -> "0"      # 20% - candidates for unsuspend
      n when n <= 35 -> "1"      # 15% - normal
      n when n <= 55 -> "2"      # 20% - candidates for suspend
      n when n <= 75 -> "3"      # 20% - candidates for suspend
      n when n <= 85 -> "4"      # 10% - candidates for suspend
      n when n <= 95 -> "5"      # 10% - candidates for suspend
      _ -> nil                   # 5% - nil values for edge case testing
    end
  end

  defp random_unpaid_invoices_value do
    # Weight towards 0 for unsuspend candidates
    case :rand.uniform(100) do
      n when n <= 40 -> "0"      # 40% - candidates for unsuspend when collection=0
      n when n <= 60 -> "1"      # 20% - normal
      n when n <= 75 -> "2"      # 15% - normal
      n when n <= 90 -> "3"      # 15% - normal
      _ -> nil                   # 10% - nil values
    end
  end

  defp generate_swedish_name(existing_names) do
    first_names = ["Karl", "Carl", "Ulf", "Anders", "Kenneth", "Johan", "Lars", "Erik", "Anna", "Maria", "Kerstin", "Johanna", "Kristin", "Ulla"]
    last_names = ["Holmqvist", "Mannheimer", "Dahlin", "Blomberg", "Ekholm", "Johansson", "Bandgren", "Falk", "Andersson", "Lindqvist"]

    case :rand.uniform(3) do
      1 -> Enum.random(existing_names)  # Use real name
      2 -> "#{Enum.random(first_names)} #{Enum.random(last_names)}"  # Generate simple combination
      3 -> "#{Enum.random(first_names)} #{Enum.random(first_names)} #{Enum.random(last_names)}"  # Swedish pattern with middle name
    end
  end

  defp generate_swedish_id(existing_patterns) do
    case :rand.uniform(2) do
      1 -> Enum.random(existing_patterns)  # Use real pattern
      2 ->
        # Generate Swedish personal number format (YYYYMMDDXXXX)
        year = Enum.random(1940..2000)
        month = Enum.random(1..12) |> Integer.to_string() |> String.pad_leading(2, "0")
        day = Enum.random(1..28) |> Integer.to_string() |> String.pad_leading(2, "0")
        suffix = Enum.random(1000..9999)
        "#{year}#{month}#{day}#{suffix}"
    end
  end

  defp generate_contract_ref do
    case :rand.uniform(3) do
      1 -> "contract_-#{:rand.uniform(999999999999999999)}"
      2 -> generate_uuid()
      3 -> "#{:rand.uniform(99999)}-#{:rand.uniform(9999)}-#{:rand.uniform(9999)}"
    end
  end

  defp generate_uuid do
    # Generate a simple UUID-like string
    part1 = :rand.uniform(0xFFFFFFFF) |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(8, "0")
    part2 = :rand.uniform(0xFFFF) |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0")
    part3 = :rand.uniform(0xFFFF) |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0")
    part4 = :rand.uniform(0xFFFF) |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0")
    part5 = :rand.uniform(0xFFFFFFFFFFFF) |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(12, "0")

    "#{part1}-#{part2}-#{part3}-#{part4}-#{part5}"
  end

  defp generate_date_near(nil), do: generate_date_near("2025-06-22")
  defp generate_date_near(base_date) when is_binary(base_date) do
    # Parse base date and add random days
    case Date.from_iso8601(base_date) do
      {:ok, date} ->
        days_offset = :rand.uniform(60) - 30  # ±30 days
        date
        |> Date.add(days_offset)
        |> Date.to_iso8601()
      _ ->
        "2025-#{:rand.uniform(12) |> Integer.to_string() |> String.pad_leading(2, "0")}-#{:rand.uniform(28) |> Integer.to_string() |> String.pad_leading(2, "0")}"
    end
  end

  defp maybe_generate_end_date do
    case :rand.uniform(4) do
      1 -> nil  # No end date
      _ -> generate_date_near("2025-08-01")
    end
  end

  defp random_active_status do
    case :rand.uniform(10) do
      n when n <= 8 -> "1"  # 80% active
      _ -> "0"              # 20% inactive
    end
  end

  defp random_invoice_status do
    statuses = ["Invoice", "Reminder", "Collection Agency", ""]
    Enum.random(statuses)
  end

  defp parse_int_safely(value) do
    case value do
      nil -> {:error, :nil}
      val when is_binary(val) ->
        case Integer.parse(String.trim(val)) do
          {int_val, ""} -> {:ok, int_val}
          _ -> {:error, :invalid}
        end
      val when is_integer(val) -> {:ok, val}
      _ -> {:error, :invalid}
    end
  end

  defp print_data(data) do
    Mix.shell().info("\n🎯 Generated Test Data:")
    Mix.shell().info("```elixir")

    data
    |> Enum.take(10)  # Show first 10 records
    |> Enum.each(fn sub ->
      Mix.shell().info("%CapwaySubscriber{")
      Mix.shell().info("  customer_ref: #{inspect(sub.customer_ref)},")
      Mix.shell().info("  id_number: #{inspect(sub.id_number)},")
      Mix.shell().info("  name: #{inspect(sub.name)},")
      Mix.shell().info("  collection: #{inspect(sub.collection)},")
      Mix.shell().info("  unpaid_invoices: #{inspect(sub.unpaid_invoices)},")
      Mix.shell().info("  active: #{inspect(sub.active)}")
      Mix.shell().info("},")
    end)

    if length(data) > 10 do
      Mix.shell().info("# ... #{length(data) - 10} more records")
    end

    Mix.shell().info("```")
  end

  defp write_to_file(data, output_file) do
    content = """
    # Generated test data - #{DateTime.utc_now() |> DateTime.to_iso8601()}
    # Total records: #{length(data)}

    #{inspect(data, pretty: true, limit: :infinity)}
    """

    File.write!(output_file, content)
  end

  @doc """
  Insert generated test data into Trinity database.

  Creates Trinity subscribers with encrypted personal numbers and subscriptions
  with "capway" payment method.
  """
  def insert_to_trinity_db(test_data, suspend_some) do
    # Start required applications and check database connectivity
    case ensure_trinity_repo_started() do
      :ok ->
        inserted_count = 0
        result = Enum.reduce_while(test_data, inserted_count, fn capway_sub, acc ->
          try do
            TrinityRepo.transaction(fn ->
              # Create subscription first using changeset
              # Determine payment method to create realistic test scenarios
              payment_method = determine_payment_method(capway_sub, acc)

              subscription_attrs = %{
                status: determine_subscription_status(capway_sub, suspend_some),
                payment_method: payment_method,
                end_date: parse_date(capway_sub.end_date),
                requested_cancellation: false
              }

              subscription_changeset = Subscription.changeset(%Subscription{}, subscription_attrs)

              case TrinityRepo.insert(subscription_changeset) do
                {:ok, inserted_subscription} ->
                  # Create subscriber with encrypted personal number using changeset
                  # The personal_number field will be auto-encrypted by Cloak.Ecto.Binary
                  # The personal_number_hash will be set automatically by the changeset
                  subscriber_attrs = %{
                    personal_number: capway_sub.id_number,
                    activated: capway_sub.active == "1",
                    subscription_id: inserted_subscription.id
                  }

                  subscriber_changeset = Subscriber.changeset(%Subscriber{}, subscriber_attrs)

                  case TrinityRepo.insert(subscriber_changeset) do
                    {:ok, _subscriber} ->
                      :ok
                    {:error, changeset} ->
                      Mix.shell().error("Failed to insert subscriber: #{inspect(changeset.errors)}")
                      TrinityRepo.rollback(:subscriber_error)
                  end

                {:error, changeset} ->
                  Mix.shell().error("Failed to insert subscription: #{inspect(changeset.errors)}")
                  TrinityRepo.rollback(:subscription_error)
              end
            end)
            |> case do
              {:ok, _} -> {:cont, acc + 1}
              {:error, _reason} -> {:cont, acc}
            end
          rescue
            e ->
              Mix.shell().error("Error inserting data: #{inspect(e)}")
              {:cont, acc}
          end
        end)

        {:ok, result}

      :error ->
        {:error, :database_unavailable}
    end
  end

  defp ensure_trinity_repo_started do
    # Start required applications
    Application.ensure_all_started(:capway_sync)

    # The repo should start with the application
    case Process.whereis(TrinityRepo) do
      nil ->
        Mix.shell().error("Trinity repo not started - check your configuration")
        :error
      _pid ->
        :ok
    end
  end

  defp determine_subscription_status(capway_sub, suspend_some) do
    cond do
      suspend_some && should_be_suspended?(capway_sub) -> :suspended
      capway_sub.active == "1" -> :active
      true -> :inactive
    end
  end

  defp should_be_suspended?(capway_sub) do
    case parse_int_safely(capway_sub.collection) do
      {:ok, val} when val >= 2 -> true
      _ -> false
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> NaiveDateTime.new!(date, ~T[00:00:00])
      _ -> nil
    end
  end
  defp parse_date(_), do: nil

  # Determines payment method to create realistic test scenarios.
  #
  # Creates a distribution where:
  # - ~70% remain "capway" (these will exist in both systems)
  # - ~15% become "bank" (these will be missing from Capway - should be added)
  # - ~10% become "card" (these will be missing from Capway - should be added)
  # - ~5% become "other" (these will be missing from Capway - should be added)
  #
  # This creates realistic scenarios where some Trinity subscribers are missing from Capway
  # and need to be added, while the mock XML contains legacy contracts that don't exist
  # in Trinity and should be cancelled.
  defp determine_payment_method(capway_sub, _inserted_count) do
    # Use subscriber data to create deterministic but varied distribution
    seed = :erlang.phash2(capway_sub.id_number, 100)

    case seed do
      n when n < 70 -> "capway"  # 70% - will exist in both systems
      n when n < 85 -> "bank"    # 15% - missing from Capway, should be added
      n when n < 95 -> "card"    # 10% - missing from Capway, should be added
      _ -> "other"               # 5% - missing from Capway, should be added
    end
  end
end