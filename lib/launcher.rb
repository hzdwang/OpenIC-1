require 'rubygems'
require 'yaml'
require 'fileutils'
require 'edi4r'
require 'edi4r/edifact'
require 'ruby_debug'

module OIC

class Launcher

  def initialize    
    dir = 'handlers/*'
    Dir.glob(dir) {|file| require file}
#   redirect stdout/stderr
    $stdout.reopen( 'oic.log', 'a' )
    $stderr.reopen( 'oic.err', 'a' )
    ts = '[' + Time.now.utc.strftime("%Y.%m.%d %H:%M:%S") + ']'
    $stderr.puts ts    
    @log = Logger.new(STDOUT)
    @log.info( 'Started' ) 
    @partner_config = YAML::load_file( "config/partners.yml" ) || {}  
  end
  
  def execute_inbound(message_type, filename)
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
  
  def execute_outbound(message_type, recipient, object_type, object_id)
    @log.info( 'Outbound ' + message_type )
    @log.info( 'Business object ID: ' + object_id ) 
    case message_type
      when 'EDI'
        execute_outbound_edi(recipient, object_type, object_id)
        @log.info( 'Ended' )
      else
        @log.fatal( 'Unknown message type ' + message_type)
        exit 
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
    message_type = ic.header.d0026
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

  def execute_outbound_edi(recipient, message_type, object_id)
    ts = Time.now.utc.strftime("%Y%m%d%H%M%S")
    @log.info( 'Timestamp: ' + ts )
    @log.info( 'Recipient: ' + recipient )
    @log.info( 'EDI message type: ' + message_type )
#   get partner configuration
    config = @partner_config['EDI'][recipient]['OUTBOUND'][message_type]
    message_directory = config['message_directory']
    handlers = config['handlers']
#   copy inbound file to message directory    
    filename = message_directory + message_type + '.' + ts
    edi_message_log = Logger.new(filename + '.log')
    @log.info( 'Filename: ' + filename ) 
#   handle outbound object    
    handlers.each do |handler|
      @log.info( 'Handler of message: ' + handler )
      handler = Object::const_get(handler).new()
      handler.process_business_object(object_id, filename, edi_message_log)
    end    
  end
  
end

end
