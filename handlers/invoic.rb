require 'rubygems'
require 'edi4r'
require 'edi4r/edifact'
#require "edi4r-tdid"
require 'ooor'
require 'yaml'
require 'ruby-debug'

class OIC_edi_invoic_handler


def setup_openerp_connection
  # loading external configuration file
  app_config = YAML::load_file( "config/settings.yml" ) || {}

  # setup connection with openerp
  Ooor.new(:url => app_config["openerp"]["url"],
           :username => app_config["openerp"]["username"],
           :password => app_config["openerp"]["password"],
           :database => app_config["openerp"]["database"],
           :models => ['account.invoice','account.invoice.line','sales.order','product.product','res.partner'])
end

def create_interchange
  @ic = EDI::E::Interchange.new
end

def create_invoic_message(inv, test=false)
  msg = @ic.new_message( :msg_type=>'INVOIC', :version=>'D', :release=>'96A', :resp_agency=>'UN' )
  
  @ic.header.d0035 = 1 if test
  # BGM
  bgm = msg.new_segment('BGM')
  bgm.cC002.d1001 = 380 # Commercial invoice
  bgm.d1004 = inv.number # Invoice Number assigned by document sender (us)
  bgm.d1225 = '9' # Original
  msg.add(bgm)
  # DTM
  # Msg date/time e.g.: 201108151716 YYYYMMDDhhmm
  dtm = msg.new_segment('DTM')
  dtm.cC507.d2005 = 137
  dtm.cC507.d2380 = Time.now.strftime("%Y%m%d%H%M")
  dtm.cC507.d2379 = 203 # YYYYMMDDhhmm
  msg.add(dtm)
  # DTM
  # Invoice date
  dtm = msg.new_segment('DTM')
  dtm.cC507.d2005 = 454
  dtm.cC507.d2380 = inv.date_invoice.strftime("%Y%m%d")
  dtm.cC507.d2379 = 102 # YYYYMMDD
  msg.add(dtm)
  # DTM
  # Delivery date
  dtm = msg.new_segment('DTM')
  dtm.cC507.d2005 = 35
  dtm.cC507.d2380 = inv.date_invoice.strftime("%Y%m%d")
  dtm.cC507.d2379 = 102 # YYYYMMDD
  msg.add(dtm)
  # RFF
  # PO number (customer order reference)  
  rff = msg.new_segment('RFF')
  rff.cC506.d1153 = "ON"
  rff.cC506.d1154 = '12345'#inv.reference
  msg.add(rff)
  # DTM
  # Delivery note date
  dtm = msg.new_segment('DTM')
  dtm.cC507.d2005 = 171
  dtm.cC507.d2380 = inv.date_invoice.strftime("%Y%m%d")
  dtm.cC507.d2379 = 102 # YYYYMMDD
  msg.add(dtm)
  # RFF
  # Delivery note  
  rff = msg.new_segment('RFF')
  rff.cC506.d1153 = "AAK"
  rff.cC506.d1154 = '12345'#inv.reference
  msg.add(rff)
  # DTM
  # Reference delivery date
  dtm = msg.new_segment('DTM')
  dtm.cC507.d2005 = 171
  dtm.cC507.d2380 = inv.date_invoice.strftime("%Y%m%d")
  dtm.cC507.d2379 = 102 # YYYYMMDD
  msg.add(dtm)
  # NAD
  # Buyer
  nad = msg.new_segment('NAD')
  nad.d3035 = 'BY'
  nad.cC082.d3039 = '5454200604004'
  nad.cC082.d3055 = '9'
  msg.add(nad)
  # NAD
  # Supplier
  nad = msg.new_segment('NAD')
  nad.d3035 = 'SU'
  nad.cC082.d3039 = '5454200604004'
  nad.cC082.d3055 = '9'
  msg.add(nad)
  # RFF
  # VAT number supplier  
  rff = msg.new_segment('RFF')
  rff.cC506.d1153 = 'VA'
  rff.cC506.d1154 = 'BE0123456789'
  msg.add(rff)
  # NAD
  # Delivery Party
  nad = msg.new_segment('NAD')
  nad.d3035 = 'DP'
  nad.cC082.d3039 = '5454200604004'
  nad.cC082.d3055 = '9'
  msg.add(nad)
  # NAD
  # Invoice party
  nad = msg.new_segment('NAD')
  nad.d3035 = 'IV'
  nad.cC082.d3039 = '5400107000012'
  nad.cC082.d3055 = '9'
  msg.add(nad)
  # RFF
  # VAT number buyer
  rff = msg.new_segment('RFF')
  rff.cC506.d1153 = 'VA'
  rff.cC506.d1154 = 'BE9876543210'#inv.reference
  msg.add(rff)
  # CUX
  cux = msg.new_segment('CUX')
  cux.aC504[0].d6347 = 2
  cux.aC504[0].d6345 = 'EUR'
  cux.aC504[0].d6343 = 4
  msg.add(cux)  
  
  # LINES -------------------------------------------------------------
  cnt = 0
  inv.invoice_line.each do |line|
    
    cnt = cnt + 1
    
    # LIN
    lin = msg.new_segment('LIN')
    lin.d1082 = cnt
    lin.cC212.d7140 = 'AZERTY'#line.product_id
    lin.cC212.d7143 = 'EN'
    msg.add(lin)  
        
    # PIA
    # Additional product id
    pia = msg.new_segment('PIA')
    pia.d4347 = '1' # additional identification
    pia.aC212[0].d7140 = 'OUR MATNR'
    pia.aC212[0].d7143 = 'SA'
    msg.add(pia)  
    
    # IMD
    # item description
    imd = msg.new_segment('IMD')
    imd.d7077 = 'F' # free form
    imd.cC273.d7009 = 'IN'
    imd.cC273.a7008[0].value = 'OUR MATERIAL Description'
    msg.add(imd)
    
    # QTY
    # invoiced qty
    qty = msg.new_segment('QTY')
    qty.cC186.d6063 = '47'
    qty.cC186.d6060 = '160' # qty
    msg.add(qty)

    # QTY
    # delivered qty
    qty = msg.new_segment('QTY')
    qty.cC186.d6063 = '46'
    qty.cC186.d6060 = '160' # qty
    msg.add(qty)

    # MOA
    # line item amount
    moa = msg.new_segment('MOA')
    moa.cC516.d5025 = '203' 
    moa.cC516.d5004 = '123.45' 
    msg.add(moa)    
    
    # PRI
    # price details
    pri = msg.new_segment('PRI')
    pri.cC509.d5125 = 'AAA' # net price
    pri.cC509.d5118 = '115.47'
    msg.add(pri)
    
    # TAX
    tax = msg.new_segment('TAX')
    tax.d5283 = '7'
    tax.cC241.d5153 = 'VAT'
    tax.cC243.d5278 = '21.00'
    msg.add(tax)
 
    # MOA
    # taxable amount
    moa = msg.new_segment('MOA')
    moa.cC516.d5025 = '125' 
    moa.cC516.d5004 = '666.45' 
    msg.add(moa)
       
  end
  # -------------------------------------------------------------------
  
  # UNS
  # To separate header, detail, and summary sections of a message
  uns = msg.new_segment('UNS')
  uns.d0081 = 'S'
  msg.add(uns)
  
  # MOA
  # total amount including VAT
  moa = msg.new_segment('MOA')
  moa.cC516.d5025 = '77'
  moa.cC516.d5004 = '21824.31'
  msg.add(moa) 
  
  @ic.add( msg )
  
end

def process_business_object( object_id, filename, log )
  setup_openerp_connection
  create_interchange
  inv = AccountInvoice.first(:params => {:number => object_id})
#  p inv
  create_invoic_message(inv)
# @ic.validate
  @ic.output_mode=:indented
  File.open(filename, 'w') {|f| f.write(@ic.to_s) } 
  p @ic.to_s
end

end
