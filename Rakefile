# frozen_string_literal: true

require "rake/testtask"
require "rdoc/task"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.pattern = "test/**/*_test.rb"
  t.warning = false
end

# Generate API docs into doc/ (gitignored; published to kuickr, not committed).
RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = "doc"
  rdoc.title    = "Permissify — activity-based authorization"
  rdoc.main     = "README.md"
  rdoc.rdoc_files.include("README.md", "EXAMPLES.md", "CHANGELOG.md", "lib/**/*.rb")
end

task default: :test
