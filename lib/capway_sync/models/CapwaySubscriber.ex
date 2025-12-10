defmodule CapwaySync.Models.CapwaySubscriber do
  @doc """
  This struct is based on the XML headers provided below:
  <Headers>
    <ReportResultHeader>
      <Format/>
      <Name i:nil="true"/>
      <Title>customerref</Title>
    </ReportResultHeader>
    <ReportResultHeader>
      <Format/>
      <Name i:nil="true"/>
      <Title>idnumber</Title>
    </ReportResultHeader>
    <ReportResultHeader>
      <Format/>
      <Name i:nil="true"/>
      <Title>name</Title>
    </ReportResultHeader>
    <ReportResultHeader>
      <Format/>
      <Name i:nil="true"/>
      <Title>contractrefno</Title>
    </ReportResultHeader>
    <ReportResultHeader>
      <Format/>
      <Name i:nil="true"/>
      <Title>regdate</Title>
    </ReportResultHeader>
    <ReportResultHeader>
      <Format/>
      <Name i:nil="true"/>
      <Title>startdate</Title>
    </ReportResultHeader>
    <ReportResultHeader>
      <Format/>
      <Name i:nil="true"/>
      <Title>enddate</Title>
    </ReportResultHeader>
    <ReportResultHeader>
      <Format/>
      <Name i:nil="true"/>
      <Title>active</Title>
    </ReportResultHeader>
  </Headers>
  """
  @derive Jason.Encoder
  defstruct customer_ref: nil,
            id_number: nil,
            name: nil,
            contract_ref_no: nil,
            reg_date: nil,
            start_date: nil,
            end_date: nil,
            active: nil,
            paid_invoices: nil,
            unpaid_invoices: nil,
            collection: nil,
            last_invoice_status: nil,
            # external data and debug
            origin: nil,
            trinity_id: nil,
            capway_id: nil,
            raw_data: nil
end
