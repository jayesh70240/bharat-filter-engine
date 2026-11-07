# frozen_string_literal: true

require 'spec_helper'

# Two different associations that point at the SAME table (Lead#client and
# Lead#referrer are both `clients`). ActiveRecord aliases the second join, so
# conditions written against the plain table name used to hit the wrong join.
RSpec.describe 'filters through two associations to the same table' do
  def nested(association, filter_type, column, **extra)
    { type: :nested, association: association, filter_type: filter_type, dbcolumn: column }.merge(extra)
  end

  def search(columns)
    { type: :single, filter_type: :search, dbcolumns: columns }
  end

  let!(:acme)   { Organization.create!(name: 'Acme') }
  let!(:globex) { Organization.create!(name: 'Globex') }

  let!(:alice) { Client.create!(name: 'Alice', email: 'alice@x.com', organization: acme) }
  let!(:bob)   { Client.create!(name: 'Bob', email: 'bob@x.com', organization: globex) }

  let!(:alice_bob)   { Lead.create!(source: 'google', client: alice, referrer: bob) }
  let!(:bob_alice)   { Lead.create!(source: 'google', client: bob, referrer: alice) }
  let!(:alice_alice) { Lead.create!(source: 'google', client: alice, referrer: alice) }
  let!(:alice_none)  { Lead.create!(source: 'google', client: alice, referrer: nil) }

  let(:both_names) do
    {
      client_name: nested(:client, :string, :name),
      referrer_name: nested(:referrer, :string, :name)
    }
  end

  def apply(config, scope: Lead.all, **params)
    BharatFilterEngine::Engine.apply(scope: scope, config: config, params: params)
  end

  describe 'nested filters' do
    it 'applies each condition to its own association' do
      expect(apply(both_names, client_name: 'Alice', referrer_name: 'Bob')).to contain_exactly(alice_bob)
      expect(apply(both_names, client_name: 'Bob', referrer_name: 'Alice')).to contain_exactly(bob_alice)
    end

    it 'allows both associations to match the same record' do
      expect(apply(both_names, client_name: 'Alice', referrer_name: 'Alice')).to contain_exactly(alice_alice)
    end

    it 'does not depend on the order of the config' do
      reversed = both_names.to_a.reverse.to_h

      expect(apply(reversed, client_name: 'Alice', referrer_name: 'Bob')).to contain_exactly(alice_bob)
    end

    it 'returns nothing when no record matches both conditions' do
      expect(apply(both_names, client_name: 'Bob', referrer_name: 'Bob')).to be_empty
    end

    it 'supports a negated filter on the second association' do
      config = {
        client_name: nested(:client, :string, :name),
        referrer_name: nested(:referrer, :string, :name, negate: true)
      }

      expect(apply(config, client_name: 'Alice', referrer_name: 'Bob')).to contain_exactly(alice_alice)
    end

    it 'works across multi-level paths that end in the same table' do
      config = {
        client_org: nested(:client__organization, :string, :name),
        referrer_org: nested(:referrer__organization, :string, :name)
      }

      expect(apply(config, client_org: 'Acme', referrer_org: 'Globex')).to contain_exactly(alice_bob)
      expect(apply(config, client_org: 'Globex', referrer_org: 'Acme')).to contain_exactly(bob_alice)
    end

    it 'works through a has_many-free parent (Sale -> lead -> client/referrer)' do
      Sale.create!(lead: alice_bob, stage: 'won')
      Sale.create!(lead: bob_alice, stage: 'won')

      sale_config = {
        client_name: nested(:lead__client, :string, :name),
        referrer_name: nested(:lead__referrer, :string, :name)
      }
      sales = apply(sale_config, scope: Sale.all, client_name: 'Alice', referrer_name: 'Bob')
      expect(sales.map(&:lead)).to contain_exactly(alice_bob)
    end

    it 'returns a normal relation that can be counted, ordered and limited' do
      relation = apply(both_names, client_name: 'Alice', referrer_name: 'Bob')

      expect(relation).to be_a(ActiveRecord::Relation)
      expect(relation.count).to eq(1)
      expect(relation.exists?).to be(true)
      expect(relation.order(:id).limit(1).pluck(:id)).to eq([alice_bob.id])
    end
  end

  describe 'search' do
    it 'searches both associations with OR semantics' do
      result = apply({ q: search(%i[client__name referrer__name]) }, q: 'Bob')

      expect(result).to contain_exactly(alice_bob, bob_alice)
    end

    it 'supports field=value search on both associations (AND)' do
      result = apply({ q: search(%i[client__name referrer__name]) }, q: 'client__name=Alice&referrer__name=Bob')

      expect(result).to contain_exactly(alice_bob)
    end

    it 'works when SearchBuilder is used on its own (no engine)' do
      builder = BharatFilterEngine::SearchBuilder.new(scope: Lead.all, allowed_columns: %w[client__name referrer__name])

      expect(builder.apply('Bob')).to contain_exactly(alice_bob, bob_alice)
    end
  end

  describe 'nested filter combined with search' do
    let(:nested_then_search) do
      { referrer_name: nested(:referrer, :string, :name), q: search(%i[client__name]) }
    end

    it 'is correct when the nested filter comes first' do
      expect(apply(nested_then_search, referrer_name: 'Bob', q: 'alice')).to contain_exactly(alice_bob)
    end

    it 'is correct when the search comes first' do
      search_then_nested = nested_then_search.to_a.reverse.to_h

      expect(apply(search_then_nested, referrer_name: 'Bob', q: 'alice')).to contain_exactly(alice_bob)
    end
  end

  describe 'has_many paths to the same table' do
    let!(:dave) { Client.create!(name: 'Dave') }
    let!(:carol) { Client.create!(name: 'Carol') }

    before do
      # alice: a google lead; referred leads won/referral and lost/web (DIFFERENT rows)
      # bob:   a google lead; referred lead won/web (ONE row satisfies both)
      # carol: no google lead; referred lead won/web
      Lead.where(client: [alice, bob, carol]).delete_all
      Lead.create!(source: 'google', client: alice)
      Lead.create!(source: 'google', client: bob)
      Lead.create!(source: 'referral', client: carol)
      Lead.create!(source: 'referral', status: 'won', client: dave, referrer: alice)
      Lead.create!(source: 'web', status: 'lost', client: dave, referrer: alice)
      Lead.create!(source: 'web', status: 'won', client: dave, referrer: bob)
      Lead.create!(source: 'web', status: 'won', client: dave, referrer: carol)
    end

    let(:config) do
      {
        own_source: nested(:leads, :string, :source),
        ref_status: nested(:referred_leads, :string, :status),
        ref_source: nested(:referred_leads, :string, :source)
      }
    end

    it 'works when two has_many associations point at the same table' do
      result = apply(config.slice(:own_source, :ref_status), scope: Client.all, own_source: 'google', ref_status: 'won')

      expect(result).to contain_exactly(alice, bob)
    end

    it 'keeps conditions on one path matching the SAME joined row' do
      result = apply(config, scope: Client.all, own_source: 'google', ref_status: 'won', ref_source: 'web')

      expect(result).to contain_exactly(bob)
    end
  end

  describe 'SQL for cases that never collided' do
    it 'keeps a single nested filter as a plain DISTINCT join' do
      sql = apply({ c: nested(:client, :string, :name) }, c: 'Alice').to_sql

      expect(sql.scan('INNER JOIN').size).to eq(1)
      expect(sql).to include('DISTINCT')
      expect(sql).not_to include('IN (SELECT')
    end

    it 'shares one join when two filters use the same path' do
      config = { n: nested(:client, :string, :name), e: nested(:client, :string, :email) }
      sql = apply(config, n: 'Alice', e: 'alice@x.com').to_sql

      expect(sql.scan('INNER JOIN').size).to eq(1)
      expect(sql).not_to include('IN (SELECT')
    end

    it 'does not use a subquery for joins to different tables' do
      config = { c: nested(:client, :string, :name), o: nested(:client__organization, :string, :name) }
      sql = apply(config, c: 'Alice', o: 'Acme').to_sql

      expect(sql).not_to include('IN (SELECT')
    end
  end
end
