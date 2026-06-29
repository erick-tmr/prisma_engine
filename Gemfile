source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Authentication: Devise + pt-BR upstream translations
gem "devise", "~> 5.0", ">= 5.0.4"
gem "devise-i18n", "~> 1.16"

# Password hashing (pulled by Devise, pinned for explicit lockfile visibility)
gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Zero-downtime Docker deploys to the production VPS [https://kamal-deploy.org]
gem "kamal", "~> 2.12", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.0"

# S3-compatible client for the Cloudflare R2 Active Storage service [https://github.com/aws/aws-sdk-ruby]
gem "aws-sdk-s3", "~> 1.226", require: false

# HTTP client for the Correios tracking (rastro) API [https://github.com/lostisland/faraday]
gem "faraday", "~> 2.14"

# Pretty, history-tracked slugs for catalog URLs [https://github.com/norman/friendly_id]
gem "friendly_id", "~> 5.5"

# Condense controller request logs into single-line structured JSON for off-box
# analysis, enabled in production only [https://github.com/roidrage/lograge]
gem "lograge", "~> 0.14"

group :development, :test do
  # Load environment variables from .env files [https://github.com/bkeepers/dotenv]
  gem "dotenv", "~> 3.1", require: "dotenv/load"

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Code smell detection for changed files [https://github.com/troessner/reek]
  gem "reek", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Preview Devise (confirmation / password-reset) emails in the browser via
  # a mounted /cartas inbox — the plain letter_opener gem hands the email
  # file to Launchy, which on many setups hijacks the focused tab.
  gem "letter_opener_web", "~> 3.0"

  # Memory profiling, run on demand — see CLAUDE.md "Investigating memory"
  gem "derailed_benchmarks", require: false
  gem "memory_profiler", require: false
end

group :test do
  gem "capybara"
  gem "cuprite", "~> 0.17"

  # Object#stub / Minitest::Mock, extracted from minitest core in v6 [https://github.com/minitest/minitest-mock]
  gem "minitest-mock", "~> 5.27"

  # Stub external HTTP (Correios rastro) in tests [https://github.com/bblimke/webmock]
  gem "webmock", "~> 3.26"

  # Test coverage reporting [https://github.com/simplecov-ruby/simplecov]
  gem "simplecov", require: false
  # Changed-line coverage on PRs; ships the SimpleCov JSON formatter it reads
  # [https://github.com/grodowski/undercover]
  gem "undercover", require: false
end
