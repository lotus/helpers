# frozen_string_literal: true

source "https://rubygems.org"
gemspec

unless ENV["CI"]
  gem "byebug", require: false, platforms: :mri
  gem "yard", require: false
end

gem "hanami-utils",       "~> 1.3", git: "https://github.com/hanami/utils.git", branch: "1.3.x"
gem "hanami-validations", "~> 2.0.alpha", git: "https://github.com/hanami/validations.git", branch: "main"
gem "hanami-controller",  "~> 1.3", git: "https://github.com/hanami/controller.git",  branch: "1.3.x"
gem "hanami-view",        "~> 1.3", git: "https://github.com/hanami/view.git",        branch: "1.3.x"

gem "hanami-devtools", git: "https://github.com/hanami/devtools.git", branch: "1.3.x", require: false
