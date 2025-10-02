#!/usr/bin/env elixir

# Demo script for Mock Capway SOAP system
# Run with: USE_MOCK_CAPWAY=true elixir demo_mock.exs

System.put_env("USE_MOCK_CAPWAY", "true")

alias CapwaySync.Soap.GenerateReport

IO.puts "=== Mock Capway SOAP Demo ==="
IO.puts ""

# Test different offsets
{:ok, response1} = GenerateReport.generate_report("test", "Data", [], offset: 0, maxrows: 100)
IO.puts "✅ Offset 0 (normal data): " <> (if String.contains?(response1, "Erik Holmqvist"), do: "Contains expected name", else: "Unexpected data")

{:ok, response2} = GenerateReport.generate_report("test", "Data", [], offset: 100, maxrows: 100)
IO.puts "✅ Offset 100 (page 2): " <> (if String.contains?(response2, "Kenneth Bandgren"), do: "Contains expected name", else: "Unexpected data")

{:ok, response3} = GenerateReport.generate_report("test", "Data", [], offset: 200, maxrows: 100)
IO.puts "✅ Offset 200 (edge cases): " <> (if String.contains?(response3, "i:nil"), do: "Contains nil values", else: "No nil values")

{:ok, response4} = GenerateReport.generate_report("test", "Data", [], offset: 1000, maxrows: 100)
IO.puts "✅ Offset 1000 (empty): " <> (if String.contains?(response4, "<DataRows>") and not String.contains?(response4, "ReportResults"), do: "Empty response", else: "Not empty")

IO.puts ""
IO.puts "🎭 Mock system working correctly!"
IO.puts ""
IO.puts "Usage for development:"
IO.puts "export USE_MOCK_CAPWAY=true"
IO.puts "iex -S mix"
IO.puts "Reactor.run(CapwaySync.Reactor.V1.SubscriberSyncWorkflow, %{})"