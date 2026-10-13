# frozen_string_literal: true

namespace :querylane do
  desc "Check the indexes behind a definition, e.g. rake querylane:doctor[PEOPLE] or querylane:doctor[MemberSearch::Definition.current]"
  task :doctor, [:definition] => :environment do |_task, args|
    receiver, method = args.fetch(:definition).split(".", 2)
    definition = method ? receiver.constantize.public_send(method) : receiver.constantize
    client = Querylane.configuration.searcher.send(:client)
    problems = Querylane::Doctor.check(definition, client: client)
    problems.each { |problem| puts problem }
    puts problems.empty? ? "querylane: #{definition.name} indexes are ready" : "querylane: #{problems.size} problem(s)"
    exit(1) if problems.any?
  end
end
