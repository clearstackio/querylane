# frozen_string_literal: true

# A small member-search definition shared by the specs.
module TestSearch
  module Rules
    module_function

    def combo(index:) = (index == :ebmr) ? Querylane::Filter.eq(:combo, true) : Querylane::Filter.eq(:combo, "C")
  end

  module Interpreter
    module_function

    def call(token)
      case token
      when /\A\d{9}\z/ then [:ssn, token]
      when /\A\d{6}\z/ then [:policy, token]
      when /\A\d{4}\z/ then [:last4, token]
      end
    end
  end

  DEFINITION = Querylane::Definition.build(:test_members) do |d|
    d.index :employees, name: "ql_test_employees"
    d.index :ebmr, name: "ql_test_ebmr"
    d.text :name, attributes: %i[full_name], default: true, label: "Name contains %{value}"
    d.text :id, attributes: %i[memberid], sensitive: true, label: "Member ID starting %{value}"
    d.filter :ssn, attribute: :memberid, sensitive: true, normalize: :digits, format: /\A\d{9}\z/, label: "SSN %{value}", mask: :last4
    d.filter :last4, attribute: :memberid_last4, sensitive: true, normalize: :upcase, format: /\A[0-9A-Z]{4}\z/, label: "Last four %{value}", mask: :none
    d.filter :policy, attribute: :policy_number, label: "Policy %{value}"
    d.flags :is, alias: :status, attribute: :status_label, label: "Status",
      values: {active: "Active", pending: "Pending", terminated: "Terminated"}
    d.flags :has, rules: "TestSearch::Rules", label: "Has", values: {combo: "Combo"}
    d.facet :status, flag: :is
    d.facet :policy, filter: :policy, top: 2
    d.sort :best, label: "Best match", default: true
    d.sort :name, label: "Name A–Z", by: {full_name: :asc}
    d.per 25, 50, 100
    d.interpreter TestSearch::Interpreter
  end
end
