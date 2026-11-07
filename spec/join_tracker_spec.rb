# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BharatFilterEngine::JoinTracker do
  subject(:tracker) { described_class.new(Lead) }

  let(:resolver) { BharatFilterEngine::AssociationResolver.new(Lead.all) }

  def resolve(path)
    resolver.resolve(path)
  end

  it 'lets the first path to a table use a plain join' do
    expect(tracker.claim(resolve(:client))).to eq(:join)
  end

  it 'reuses the join when exactly the same path is claimed again' do
    tracker.claim(resolve(:client))

    expect(tracker.claim(resolve(:client))).to eq(:join)
  end

  it 'moves a different path to an already-used table into a subquery' do
    tracker.claim(resolve(:client))

    expect(tracker.claim(resolve(:referrer))).to eq(:subquery)
  end

  it 'keeps answering :subquery for that second path' do
    tracker.claim(resolve(:client))
    tracker.claim(resolve(:referrer))

    expect(tracker.claim(resolve(:referrer))).to eq(:subquery)
  end

  it 'joins paths that end in different tables' do
    expect(tracker.claim(resolve(:client))).to eq(:join)
    expect(tracker.claim(resolve(:client__organization))).to eq(:join)
  end

  it 'shares a prefix that an earlier, longer path already joined' do
    tracker.claim(resolve(:client__organization))

    expect(tracker.claim(resolve(:client))).to eq(:join)
  end

  it 'detects collisions at the end of multi-level paths' do
    tracker.claim(resolve(:client__organization))

    expect(tracker.claim(resolve(:referrer__organization))).to eq(:subquery)
  end

  it 'sends a path that returns to the base table to a subquery' do
    expect(tracker.claim(resolve(:client__leads))).to eq(:subquery)
  end

  it 'always joins when there is no association path' do
    expect(tracker.claim(associations: [], table_name: 'leads')).to eq(:join)
  end

  it 'falls back to joins for composite primary keys' do
    klass = double('composite_pk_model', table_name: 'leads', primary_key: %w[a b])
    composite = described_class.new(klass)

    composite.claim(resolve(:client))

    expect(composite.claim(resolve(:referrer))).to eq(:join)
  end
end