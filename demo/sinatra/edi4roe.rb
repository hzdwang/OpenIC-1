require 'rubygems'
require 'sinatra'
require 'haml'
require './lib/launcher.rb'
require 'ruby-debug'

configure :production do
  libdir = Pathname(__FILE__).dirname.expand_path
  set :views,  "#{libdir}/views"
  set :public, "#{libdir}/public"
  set :haml, {:format => :html5 }
end

get '/' do
  redirect '/inbound/orders'
end

get '/inbound/orders' do
  haml :inbound_orders
end

post '/inbound/orders' do
  filename = 'tmp/' + 'ORDERS' + '_' + Time.now.utc.strftime("%Y%m%d%H%M%S" + ".tmp")
  File.open(filename, 'w') do |file|
    file.write(params['content'])
  end
  launcher = OIC::Launcher.new
  launcher.execute_inbound('EDI', filename)
  redirect '/inbound/orders/log'
end

get '/outbound/desadv' do
  haml :outbound_desadv
end

post '/outbound/desadv' do
  launcher = OIC::Launcher.new
  launcher.execute_outbound('EDI', "5400107009992", params['sale_order'], "DESADV")
  redirect '/outbound/desadv/log'
end

get '/outbound/invoic' do
  haml :outbound_invoic
end

post '/outbound/invoic' do
  launcher = OIC::Launcher.new
  launcher.execute_outbound('EDI', "5400107009992", params['invoice'], "INVOIC")
  redirect '/outbound/invoic/log'
end

get '/:direction/:message_type/log' do
  @message_type = params[:message_type]
  Dir.chdir("#{params[:direction]}/" + @message_type)
  @files = Dir.glob("#{@message_type.upcase}*[^.log]")
  Dir.chdir('../..')
  haml_view = "#{params[:direction]}" + "_log"
  haml haml_view.to_sym
  #haml :outbound_log
end

get '/:direction/:message_type/log/:filename' do
  filename = "#{params[:direction]}/#{params[:message_type]}/" + params[:filename]
  @lines = IO.readlines(filename)
  haml :print_file
end

# You can see all your app specific information this way.
# IMPORTANT! This is a very bad thing to do for a production
# application with sensitive information

get '/env' do
  ENV.inspect
end
