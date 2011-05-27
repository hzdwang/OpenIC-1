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
  'done'
end

get '/inbound/log' do
  Dir.chdir('inbound/orders')
  @files = Dir.glob('ORDERS*[^.log]')
  Dir.chdir('../..')
  haml :inbound_log
end

get '/inbound/log/:filename' do
  filename = 'inbound/orders/' + params[:filename]
  @lines = IO.readlines(filename)
  haml :print_file
end

get '/outbound/desadv' do
  haml :outbound_desadv
end

get '/outbound/invoic' do
  haml :outbound_invoic
end

# You can see all your app specific information this way.
# IMPORTANT! This is a very bad thing to do for a production
# application with sensitive information

get '/env' do
  ENV.inspect
end
