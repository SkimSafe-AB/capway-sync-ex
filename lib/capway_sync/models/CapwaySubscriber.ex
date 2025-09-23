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
  defstruct customer_ref: nil,
            id_number: nil,
            name: nil,
            contract_ref_no: nil,
            reg_date: nil,
            start_date: nil,
            end_date: nil,
            active: nil,
            raw_data: nil
end
