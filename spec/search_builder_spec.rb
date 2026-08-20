require "spec_helper"

RSpec.describe BharatFilterEngine::SearchBuilder do

  let!(:client) do
    Client.create!(
      name: "John Doe",
      email: "john@example.com"
    )
  end

  let!(:lead) do
    Lead.create!(
      source: "google",
      client: client
    )
  end

  let!(:sale) do
    Sale.create!(
      stage: "qualified",
      lead: lead
    )
  end

  it "supports simple search" do

    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [
          :stage,
          :"lead__source"
        ]
      ).apply("google")

    expect(result).to contain_exactly(sale)
  end

  it "supports case insensitive search" do
    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [:stage]
      ).apply("QUAL")

    expect(result).to contain_exactly(sale)
  end

  it "supports nested field search" do

    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [
          :"lead__client__name"
        ]
      ).apply(
        "lead__client__name=John"
      )

    expect(result).to contain_exactly(sale)
  end

  it "supports multi-level association search" do
    organization = Organization.create!(
      name: "Acme"
    )

    client_two = Client.create!(
      name: "Jane",
      organization: organization
    )

    lead_two = Lead.create!(
      source: "referral",
      client: client_two
    )

    sale_two = Sale.create!(
      lead: lead_two
    )

    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [
          :"lead__client__organization__name"
        ]
      ).apply(
        "lead__client__organization__name=Acme"
      )

    expect(result).to contain_exactly(sale_two)
  end

  it "supports OR search" do

    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [
          :stage,
          :"lead__source"
        ]
      ).apply(
        "stage=qualified|lead__source=google"
      )

    expect(result).to contain_exactly(sale)
  end

  it "supports combined AND and OR conditions" do
    sale_one = Sale.create!(
      stage: "qualified",
      approval_status: "approved"
    )

    sale_two = Sale.create!(
      stage: "qualified",
      approval_status: "pending"
    )

    Sale.create!(
      stage: "new",
      approval_status: "approved"
    )

    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [
          :stage,
          :approval_status
        ]
      ).apply(
        "stage=qualified&approval_status=approved|approval_status=pending"
      )

    expect(result).to contain_exactly(
      sale_one,
      sale_two
    )
  end

  it "returns no records when the searched field is not configured" do
    result =
      described_class.new(
        scope: Sale.all,
        allowed_columns: [:stage]
      ).apply(
        "unknown=value"
      )

    expect(result).to be_empty
  end
end
