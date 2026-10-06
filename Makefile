.PHONY: lint test build ci
lint:
	bundle exec rubocop
test:
	ruby -w -Ilib -Itest -e 'ARGV.each { |file| require File.expand_path(file) }' $$(find test -name '*_test.rb')
build:
	mkdir -p pkg
	gem build planka-cli.gemspec --output pkg/planka-cli-0.1.0.gem
ci: lint test build
