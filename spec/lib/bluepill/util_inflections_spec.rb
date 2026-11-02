# frozen_string_literal: true

describe Bluepill::Util do
  describe ".camelize" do
    {
      :mem_usage => "MemUsage",
      "cpu_usage" => "CpuUsage",
      :http => "Http",
      :not_found => "NotFound",
      "my_check2" => "MyCheck2",
      "already_Camel" => "AlreadyCamel",
      "a__b" => "AB",
      "HTTP" => "HTTP",
      "x" => "X",
      "Ab_c" => "AbC",
      "mem_usage_check" => "MemUsageCheck",
      "a_bCD" => "ABcd"
    }.each do |name, camelized|
      it "turns #{name.inspect} into #{camelized}" do
        expect(described_class.camelize(name)).to eq(camelized)
      end
    end
  end

  describe ".underscore" do
    {
      "Flapping" => "flapping",
      "MemUsage" => "mem_usage",
      "HTTPCheck" => "http_check",
      "MyTrigger2" => "my_trigger2",
      "Trigger2Fast" => "trigger2_fast",
      "ABC" => "abc",
      "MyTriggerName" => "my_trigger_name",
      "HTTPServerXMLParser" => "http_server_xml_parser",
      "ABcDEf" => "a_bc_d_ef",
      "X-Ray" => "x-ray"
    }.each do |name, underscored|
      it "turns #{name} into #{underscored}" do
        expect(described_class.underscore(name)).to eq(underscored)
      end
    end
  end
end
