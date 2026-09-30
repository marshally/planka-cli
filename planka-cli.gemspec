require_relative "lib/planka/version"

Gem::Specification.new do |spec|
  spec.name = "planka-cli"
  spec.version = Planka::VERSION
  spec.authors = ["Marshall Yount"]
  spec.summary = "Command-line workflows for Planka boards"
  spec.description = "Pick, claim and link Planka cards, inspect branch handoffs, and close completed specs."
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = Dir["exe/*"].map { |file| File.basename(file) }
  spec.require_paths = ["lib"]
  spec.add_dependency "net-http", ">= 0.3", "< 1.0"
end
