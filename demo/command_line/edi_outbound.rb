require 'rubygems'
require 'lib/launcher.rb'

launcher = OIC::Launcher.new
launcher.execute_outbound('EDI', '5400000000000', 'DESADV', 'SO114')
