# log everything to a file
# FileUtils.mkdir_p 'log' unless File.exists?('log')
# log = File.new("log/sinatra.log", "a")
# $stdout.reopen(log)
# $stderr.reopen(log)

require File.join(File.dirname(__FILE__), 'edi4roe')

run Sinatra::Application