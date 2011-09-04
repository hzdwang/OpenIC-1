require 'rubygems'
require 'yaml'
require 'fileutils'
require 'edi4r'
require 'edi4r/edifact'

module OIC

class Launcher

  def initialize
    dir = './handlers/*'
    Dir.glob(dir) {|file| require file}
#   redirect stdout/stderr
    $stdout.reopen( 'log/oic.log', 'a' )
    $stderr.reopen( 'log/oic.err', 'a' )
    ts = '[' + Time.now.utc.strftime("%Y.%m.%d %H:%M:%S") + ']'
    $stderr.puts ts    
    @log = Logger.new(STDOUT)
    @log.info( 'Started' ) 
    @partner_config = YAML::load_file( "./config/partners.yml" ) || {}  
  end
  
  def execute_inbound(message_type, filename, test=false)
    @log.info( 'Inbound ' + message_type )
    @log.info( 'Original filename: ' + filename ) 
    case message_type
      when 'EDI'
        execute_inbound_edi(filename)
        @log.info( 'Ended' )
      else
        @log.fatal( 'Unknown message type ' + message_type)
        exit 
    end
  end
  
  def execute_outbound(message_type, partner, id, message_sub_type = '', test=false)
    @log.info( 'Outbound ' + message_type )
    @log.info( 'Identifier : ' + id )
    case message_type
      when 'EDI'
        execute_outbound_edi(id, partner, message_sub_type, test)
        @log.info( 'Ended' )
      else
        @log.fatal( 'Unknown message type ' + message_type)
    end
  end
  
  private
  
  def execute_inbound_edi(filename)
    ts = Time.now.utc.strftime("%Y%m%d%H%M%S")
    @log.info( 'Timestamp: ' + ts )
#   check interchange header
    ic = EDI::E::Interchange.peek(File.open(filename))
    sender = ic.header.cS002.d0004
    @log.info( 'Sender: ' + sender )
    message_type = ic.header.d0026 || 'ORDERS'
    @log.info( 'EDI message type: ' + message_type )
#   get partner configuration
    config = @partner_config['EDI'][sender]['INBOUND'][message_type]
    message_directory = config['message_directory']
    handlers = config['handlers']
#   copy inbound file to message directory    
    new_filename = message_directory + message_type + '.' + ts
    edi_message_log = Logger.new(new_filename + '.log')
    @log.info( 'New filename: ' + new_filename )
    FileUtils.cp(filename, new_filename) 
#   handle inbound file    
    handlers.each do |handler|
      @log.info( 'Handler of message: ' + handler )
      io = Object::const_get(handler).new()
      io.process_file(new_filename, edi_message_log)
    end
  end 

  def execute_outbound_edi(id, partner, message_type, test=false)
    ts = Time.now.utc.strftime("%Y%m%d%H%M%S")
    @log.info( 'Timestamp: ' + ts )
    @log.info( 'Receiver: ' + partner )
    @log.info( 'EDI message type: ' + message_type )
#   get partner configuration
    config = @partner_config['EDI'][partner]['OUTBOUND'][message_type]
    message_directory = config['message_directory']
    handlers = config['handlers']
#   create files in message directory
    filename = message_directory + message_type + '.' + ts
    edi_message_log = Logger.new(filename + '.log')
    @log.info( 'Filename: ' + filename )
#   handle outbound file    
    handlers.each do |handler|
      @log.info( 'Handler of message: ' + handler )
      io = Object::const_get(handler).new()
      io.process_business_object(id, filename, edi_message_log, test)
    end    
  end

end

end
