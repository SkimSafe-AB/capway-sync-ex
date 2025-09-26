defmodule CapwaySync.Soap.ResponseHandler do
  @behaviour Saxy.Handler
  alias CapwaySync.Models.CapwaySubscriber

  # Parsing state structure
  defmodule State do
    defstruct subscribers: [],
              current_subscriber: nil,
              current_field_index: 0,
              current_raw_data: [],
              in_data_rows: false,
              in_report_results: false,
              in_rows: false,
              in_value: false,
              current_value_is_nil: false
  end

  # Initialize the parsing state
  def handle_event(:start_document, _prolog, _user_state) do
    {:ok, %State{}}
  end

  def handle_event(:end_document, _data, state) do
    # Reverse subscribers list to maintain original order
    final_state = %{state | subscribers: Enum.reverse(state.subscribers)}
    {:ok, final_state.subscribers}
  end

  # Handle start of XML elements
  def handle_event(:start_element, {tag_name, attributes}, state) do
    case tag_name do
      "DataRows" ->
        {:ok, %{state | in_data_rows: true}}

      "ReportResults" when state.in_data_rows ->
        {:ok,
         %{
           state
           | in_report_results: true,
             current_subscriber: %CapwaySubscriber{},
             current_raw_data: []
         }}

      "Rows" when state.in_report_results ->
        {:ok, %{state | in_rows: true, current_field_index: 0}}

      "Value" when state.in_rows ->
        # Check if this value is nil
        is_nil =
          Enum.any?(attributes, fn {attr_name, attr_value} ->
            (attr_name == "nil" or String.ends_with?(attr_name, ":nil")) and attr_value == "true"
          end)

        # If value is nil, immediately add nil to raw data and update subscriber
        if is_nil do
          new_raw_data = state.current_raw_data ++ [nil]

          updated_subscriber =
            update_subscriber_field(state.current_subscriber, state.current_field_index, nil)

          {:ok,
           %{
             state
             | in_value: true,
               current_value_is_nil: true,
               current_subscriber: updated_subscriber,
               current_raw_data: new_raw_data
           }}
        else
          {:ok, %{state | in_value: true, current_value_is_nil: false}}
        end

      _ ->
        {:ok, state}
    end
  end

  # Handle end of XML elements
  def handle_event(:end_element, tag_name, state) do
    case tag_name do
      "DataRows" ->
        {:ok, %{state | in_data_rows: false}}

      "ReportResults" when state.in_report_results ->
        # Complete the current subscriber and add to list
        completed_subscriber =
          finalize_subscriber(state.current_subscriber, state.current_raw_data)

        new_subscribers = [completed_subscriber | state.subscribers]

        {:ok,
         %{
           state
           | in_report_results: false,
             current_subscriber: nil,
             current_raw_data: [],
             subscribers: new_subscribers
         }}

      "Rows" when state.in_rows ->
        {:ok, %{state | in_rows: false}}

      "Value" when state.in_value ->
        {:ok, %{state | in_value: false, current_value_is_nil: false}}

      "ReportResultData" when state.in_rows ->
        # Move to next field
        {:ok, %{state | current_field_index: state.current_field_index + 1}}

      _ ->
        {:ok, state}
    end
  end

  # Handle character data (text content)
  def handle_event(:characters, chars, state) do
    if state.in_value and state.in_rows and not state.current_value_is_nil do
      # Ensure proper UTF-8 encoding
      value =
        case chars do
          chars when is_binary(chars) ->
            # Ensure the binary is valid UTF-8 and trim
            case String.valid?(chars) do
              true ->
                trimmed = String.trim(chars)
                # Check for HTML entities and fix them
                fix_html_entities(trimmed)

              false ->
                # Try to convert from latin1 or other encoding to UTF-8
                case :unicode.characters_to_binary(chars, :latin1, :utf8) do
                  utf8_binary when is_binary(utf8_binary) ->
                    fix_html_entities(String.trim(utf8_binary))

                  _ ->
                    String.trim(to_string(chars))
                end
            end

          chars when is_list(chars) ->
            # Convert from list to UTF-8 binary and trim
            case :unicode.characters_to_binary(chars, :utf8, :utf8) do
              utf8_binary when is_binary(utf8_binary) ->
                fix_html_entities(String.trim(utf8_binary))

              _ ->
                String.trim(to_string(chars))
            end

          _ ->
            fix_html_entities(String.trim(to_string(chars)))
        end

      # Ensure value is a string before storing
      string_value = ensure_string(value)

      # Add to raw data
      new_raw_data = state.current_raw_data ++ [string_value]

      # Update subscriber field based on index
      updated_subscriber =
        update_subscriber_field(state.current_subscriber, state.current_field_index, string_value)

      {:ok, %{state | current_subscriber: updated_subscriber, current_raw_data: new_raw_data}}
    else
      {:ok, state}
    end
  end

  def handle_event(:cdata, _cdata, state) do
    {:ok, state}
  end

  # Map field index to CapwaySubscriber field
  # Header structure: rownum(0), datasetid(1), customerref(2), idnumber(3), name(4), contractrefno(5), regdate(6), startdate(7), enddate(8), active(9), paidInvoices(10), unpaidInvoices(11), collection(12), lastInvoicestatus(13)
  defp update_subscriber_field(subscriber, index, value) do
    case index do
      # rownum - ignore
      0 -> subscriber
      # datasetid - ignore
      1 -> subscriber
      2 -> %{subscriber | customer_ref: value}
      3 -> %{subscriber | id_number: value}
      4 -> %{subscriber | name: value}
      5 -> %{subscriber | contract_ref_no: value}
      6 -> %{subscriber | reg_date: value}
      7 -> %{subscriber | start_date: value}
      8 -> %{subscriber | end_date: value}
      9 -> %{subscriber | active: value}
      10 -> %{subscriber | paid_invoices: value}
      11 -> %{subscriber | unpaid_invoices: value}
      12 -> %{subscriber | collection: value}
      13 -> %{subscriber | last_invoice_status: value}
      # Ignore extra fields
      _ -> subscriber
    end
  end

  # Finalize subscriber with raw data
  defp finalize_subscriber(subscriber, raw_data) do
    %{subscriber | origin: :capway, raw_data: raw_data}
  end

  # Fix common HTML entity encoding issues for Swedish characters
  defp fix_html_entities(value) when is_binary(value) do
    value
    # ä
    |> String.replace("Ã¤", "ä")
    # å
    |> String.replace("Ã¥", "å")
    # ö
    |> String.replace("Ã¶", "ö")
    # Ä
    |> String.replace("Ã„", "Ä")
    # Å
    |> String.replace("Ã…", "Å")
    # Ö
    |> String.replace("Ã–", "Ö")
    # é
    |> String.replace("Ã©", "é")
    # é
    |> String.replace("Ã©", "é")
    # á
    |> String.replace("Ã¡", "á")
    # í
    |> String.replace("Ã­", "í")
    # ó
    |> String.replace("Ã³", "ó")
    # ú
    |> String.replace("Ãº", "ú")
    # ñ
    |> String.replace("Ã±", "ñ")
  end

  defp fix_html_entities(value), do: value

  # Ensure value is always a string, even if it comes as binary
  defp ensure_string(value) when is_binary(value) do
    case String.valid?(value) do
      true ->
        value

      false ->
        # Try to force conversion to UTF-8 string
        case :unicode.characters_to_binary(value, :latin1, :utf8) do
          result when is_binary(result) ->
            result

          _ ->
            # Last resort: inspect the binary to make it a readable string
            inspect(value)
        end
    end
  end

  defp ensure_string(value), do: to_string(value)
end
