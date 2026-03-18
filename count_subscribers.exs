Code.require_file("lib/capway_sync/models/CapwaySubscriber.ex")
Code.require_file("lib/capway_sync/soap/response_handler.ex")

defmodule Counter do
  def count_file(path) do
    content = File.read!(path)
    # The file contains multiple XML documents appended together because of [:append]
    docs = String.split(content, "<s:Envelope")
           |> Enum.reject(&(&1 == ""))
           |> Enum.map(&("<s:Envelope" <> &1))
    
    # IO.puts("File #{path} contains #{length(docs)} XML responses")
    
    total_parsed = Enum.reduce(docs, [], fn doc, acc ->
      case Saxy.parse_string(doc, CapwaySync.Soap.ResponseHandler, []) do
        {:ok, subscribers} -> 
          acc ++ subscribers
        {:error, _} -> 
          acc
      end
    end)
    
    total_parsed
  end
  
  def run() do
    s1 = count_file("priv/soap_response_ext-1.xml")
    s2 = count_file("priv/soap_response_ext-2.xml")
    s3 = count_file("priv/soap_response_ext-3.xml")
    
    all = s1 ++ s2 ++ s3
    
    IO.puts("Total parsed subscribers: #{length(all)}")
    
    # Check for nil capway_ids
    nils = Enum.count(all, fn s -> s.capway_id == nil or s.capway_id == "" end)
    IO.puts("Subscribers with nil/empty capway_id: #{nils}")
    
    # Check for unique capway_ids
    unique_ids = all 
                 |> Enum.map(&(&1.capway_id)) 
                 |> Enum.reject(&(&1 == nil or &1 == "")) 
                 |> Enum.uniq()
                 |> length()
                 
    IO.puts("Unique capway_ids: #{unique_ids}")
  end
end

Counter.run()
