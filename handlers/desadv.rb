require 'rubygems'
require 'edi4r'
require 'edi4r/edifact'
#require "edi4r-tdid"
require 'ooor'
require 'yaml'
require 'ruby-debug'

class OIC_edi_desadv_handler


def setup_openerp_connection
  # loading external configuration file
  app_config = YAML::load_file( "config/settings.yml" ) || {}

  # setup connection with openerp
  Ooor.new(:url => app_config["openerp"]["url"],
           :username => app_config["openerp"]["username"],
           :password => app_config["openerp"]["password"],
           :database => app_config["openerp"]["database"],
           :models => ['sale.order','sale.order.line','product.product','res.partner'])
end

def create_interchange
  @ic = EDI::E::Interchange.new
end

def create_desadv_message(so, test=false)
  msg = @ic.new_message( :msg_type=>'DESADV', :version=>'D', :release=>'96A', :resp_agency=>'UN' )
  @ic.header.d0035 = 1 if test
  # BGM
  bgm = msg.new_segment('BGM')
  bgm.d1004 = 'DES000001'
  bgm.cC002.d1001 = 351
  msg.add(bgm)
  # DTM
  # Planned Delivery Time
  dtm = msg.new_segment('DTM')
  dtm.cC507.d2005 = 171
  dtm.cC507.d2380 = Time.now.strftime("%Y%m%d%H%M")
  dtm.cC507.d2379 = 203
  msg.add(dtm)
  # Msg time
  dtm = msg.new_segment('DTM')
  dtm.cC507.d2005 = 137
  dtm.cC507.d2380 = Time.now.strftime("%Y%m%d%H%M")
  dtm.cC507.d2379 = 203
  msg.add(dtm)
  # RFF
  rff = msg.new_segment('RFF')
  rff.cC506.d1153 = "ON"
  rff.cC506.d1154 = so.client_order_ref || ""
  msg.add(rff)
  # NAD
  # Buyer
  nad = msg.new_segment('NAD')
  nad.d3035 = "BY"
  #nad.cC082.d3039 = so.partner_invoice_id.partner_id.ref || "GTIN_UNKNOWN"
  nad.cC082.d3039 = "5454200604004"
  msg.add(nad)
  # Supplier
  nad = msg.new_segment('NAD')
  nad.d3035 = "SU"
  nad.cC082.d3039 = "5454200604004"
  msg.add(nad)
  # Delivery Address
  nad = msg.new_segment('NAD')
  nad.d3035 = "DP"
  #nad.cC082.d3039 = so.partner_shipping_id.partner_id.ref || "GTIN_UNKNOWN"
  nad.cC082.d3039 = "5454200604004"
  msg.add(nad)
  # CPS
  cps = msg.new_segment('CPS')
  cps.d7164 = 1
  msg.add(cps)
  # LIN QTY
  i = 1
  so.order_line.each do |sol|
    lin = msg.new_segment('LIN')
    lin.d1082 = i
    lin.cC212.d7140 = sol.product_id.ean13
    lin.cC212.d7143 = "EN"
    msg.add(lin)
    qty = msg.new_segment('QTY')
    qty.cC186.d6063 = 12
    qty.cC186.d6060 = sol.product_uom_qty
    qty.cC186.d6411 = "PCE"
    msg.add(qty)
    i += 1
  end
  @ic.add( msg )
end

def process_business_object( object_id, filename, log )
  setup_openerp_connection
  create_interchange
  so = SaleOrder.first(:params => {:name => object_id})
  create_desadv_message(so)
  @ic.validate
  @ic.output_mode=:indented
  File.open(filename, 'w') {|f| f.write(@ic.to_s) } 
end

end
