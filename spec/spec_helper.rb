require 'active_support/core_ext/numeric/time'
require 'active_support'
require 'sidekiq'
require 'rspec/enqueue_sidekiq_job'

# We allow that for earlier versions and if users opt out of strict arg types
Sidekiq.strict_args!(false) if Sidekiq::VERSION >= '7'
