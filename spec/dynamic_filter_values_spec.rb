require "spec_helper"

RSpec.describe BharatFilterEngine::DynamicFilterValues do

  let!(:client_one) do
    Client.create!(
      name: "John"
    )
  end

  let!(:client_two) do
    Client.create!(
      name: "Jane"
    )
  end

  let!(:lead_one) do
    Lead.create!(
      source: "google",
      client: client_one
    )
  end

  let!(:lead_two) do
    Lead.create!(
      source: "referral",
      client: client_two
    )
  end

  before do
    Sale.create!(
      stage: "qualified",
      lead: lead_one
    )

    Sale.create!(
      stage: "new",
      lead: lead_two
    )
  end

  it "returns direct values" do

    result =
      described_class.new(
        scope: Sale.all,
        field: "stage"
      ).call

    expect(result).to eq(
      %w[new qualified]
    )
  end

  it "returns nested values" do

    result =
      described_class.new(
        scope: Sale.all,
        field: "lead__source"
      ).call

    expect(result).to eq(
      %w[google referral]
    )
  end

  it "returns multi-level nested values" do

    result =
      described_class.new(
        scope: Sale.all,
        field: "lead__client__name"
      ).call

    expect(result).to eq(
      %w[Jane John]
    )
  end

  it "returns nil for invalid field" do

    result =
      described_class.new(
        scope: Sale.all,
        field: "invalid_field"
      ).call

    expect(result).to be_nil
  end

  it "returns nil for a valid association with an invalid column" do

    result =
      described_class.new(
        scope: Sale.all,
        field: "lead__something_wrong"
      ).call

    expect(result).to be_nil
  end

  it "returns nil for an invalid association" do

    result =
      described_class.new(
        scope: Sale.all,
        field: "something__name"
      ).call

    expect(result).to be_nil
  end

  it "does not return blank values" do
    Sale.create!(stage: "")
    Sale.create!(stage: nil)

    result =
      described_class.new(
        scope: Sale.all,
        field: "stage"
      ).call

    expect(result).to eq(
      %w[new qualified]
    )
  end

end