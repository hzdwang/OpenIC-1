require 'rubygems'
require 'lib/launcher.rb'

launcher = OIC::Launcher.new
launcher.execute_inbound('EDI', 'ORDERS.edi')
