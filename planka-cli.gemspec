require_relative "lib/planka/version"

Gem::Specification.new do |spec|
  spec.name = "planka-cli"
  spec.version = Planka::VERSION
  spec.authors = ["Marshall Yount"]
  spec.summary = "Command-line workflows for Planka boards"
  spec.description = "Pick, claim and link Planka cards, inspect branch handoffs, and close completed specs."
  spec.homepage = "https://github.com/marshally/planka-cli"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
  }
  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.bindir = "exe"
  spec.executables = Dir["exe/*"].map { |file| File.basename(file) }
  spec.require_paths = ["lib"]
  spec.add_dependency "net-http", ">= 0.3", "< 1.0"
end
