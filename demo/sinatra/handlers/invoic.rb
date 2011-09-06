require 'rubygems'
require 'edi4r'
require 'edi4r/edifact'
require "edi4r-tdid"
require 'ooor'
require 'yaml'

class OICEdiInvoicHandler


def setup_openerp_connection
  # loading external configuration file
  app_config = YAML::load_file( "config/settings.yml" ) || {}

  # setup connection with openerp
  Ooor.new(:url => app_config["openerp"]["url"],
           :username => app_config["openerp"]["username"],
           :password => app_config["openerp"]["password"],
           :database => app_config["openerp"]["database"],
           :models => ['account.invoice','account.invoice.line','account.invoice.line.tax','product.product','res.partner','sale.order'])
end

def create_interchange
  @ic = EDI::E::Interchange.new
end

# The account_invoice object contains the following partners:
#   * partner_id : BY (buyer)
#   * address_invoice_id : IV (invoice)
# A reference to the sale_order is contained in
#   * origin: refers to the 'name' of the sale_order
# The sale_order supplies alle necessary partners
#   * BY: partner_id
#   * SU: shop_id (i.e. your own company)
#   * DP: partner_shipping_id
#   * IV: partner_invoice_id
#   * UC: partner_ult_cons_id
# and also the delivery date
#   * date_delivery
def create_invoic_message(inv, test=false)
  msg = @ic.new_message( :msg_type=>'INVOIC', :version=>'D', :release=>'96A', :resp_agency=>'UN' )
  
  # a lot of information is retrieved from the sale_order
  if inv.origin
    ord = SaleOrder.first(:params => {:name => inv.origin})
    unless ord
      @log.error( @log_pfx + 'No sales order found with number: ' + inv.origin)
      @log.info( @log_pfx + 'Invoic skipped' )
      return false
    end
    @log.info( @log_pfx + 'Sales order found with name: ' + inv.origin )
  else
    @log.error( @log_pfx + 'No sales order origin found for invoice')
    @log.info( @log_pfx + 'Invoic skipped' )
    return false      
  end
  
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
  @log.info( @log_pfx + 'Delivery date: ' + (ord.date_delivery ? ord.date_delivery.strftime("%Y%m%d") : ""))
  dtm = msg.new_segment('DTM')
  dtm.cC507.d2005 = 35
  dtm.cC507.d2380 = ord.date_delivery ? ord.date_delivery.strftime("%Y%m%d") : ""
  dtm.cC507.d2379 = 102 # YYYYMMDD
  msg.add(dtm)
  # RFF
  # PO number (customer order reference)
  @log.info( @log_pfx + 'Customer PO reference: ' + ord.client_order_ref  )
  rff = msg.new_segment('RFF')
  rff.cC506.d1153 = "ON"
  rff.cC506.d1154 = ord.client_order_ref
  msg.add(rff)
  # DTM
  # Delivery note date (date of the delivery document? --> is not recorded)
  # dtm = msg.new_segment('DTM')
  # dtm.cC507.d2005 = 171
  # dtm.cC507.d2380 = ord.date_delivery.strftime("%Y%m%d")
  # dtm.cC507.d2379 = 102 # YYYYMMDD
  # msg.add(dtm)
  # RFF
  # Delivery note
  @log.info( @log_pfx + 'Delivery note reference: ' + 'DES' + ord.id.to_s  )
  rff = msg.new_segment('RFF')
  rff.cC506.d1153 = "AAK"
  rff.cC506.d1154 = 'DES' + ord.id.to_s
  msg.add(rff)
  # DTM
  # Reference delivery date
  dtm = msg.new_segment('DTM')
  dtm.cC507.d2005 = 171
  dtm.cC507.d2380 = ord.date_delivery ? ord.date_delivery.strftime("%Y%m%d") : ""
  dtm.cC507.d2379 = 102 # YYYYMMDD
  msg.add(dtm)
  # NAD
  # Buyer
  @log.info( @log_pfx + 'Buyer (BY): ' + inv.partner_id.name  + " with EAN13 " + (inv.partner_id.ean13 ? inv.partner_id.ean13 : "GTIN_UNKNOWN"))
  nad = msg.new_segment('NAD')
  nad.d3035 = 'BY'
  nad.cC082.d3039 = inv.partner_id.ean13 || "GTIN_UNKNOWN"
  nad.cC082.d3055 = '9'
  msg.add(nad)
  # NAD
  # Supplier
  nad = msg.new_segment('NAD')
  nad.d3035 = 'SU'
  nad.cC082.d3039 = "5420060400001"
  nad.cC082.d3055 = '9'
  msg.add(nad)
  # RFF
  # VAT number supplier  
  rff = msg.new_segment('RFF')
  rff.cC506.d1153 = 'VA'
  rff.cC506.d1154 = 'BE0828768097'
  msg.add(rff)
  # NAD
  # Delivery Party
  @log.info( @log_pfx + 'Delivery (DP): ' + (ord.partner_shipping_id.ean13 ? ord.partner_shipping_id.ean13 : "GTIN_UNKNOWN"))
  nad = msg.new_segment('NAD')
  nad.d3035 = "DP"
  nad.cC082.d3039 = ord.partner_shipping_id.ean13 || "GTIN_UNKNOWN"
  nad.cC082.d3055 = '9'
  msg.add(nad)
  # NAD
  # Invoice party
  @log.info( @log_pfx + 'Invoice (IV): ' + (ord.partner_invoice_id.ean13 ? ord.partner_invoice_id.ean13 : "GTIN_UNKNOWN"))
  nad = msg.new_segment('NAD')
  nad.d3035 = 'IV'
  nad.cC082.d3039 = ord.partner_invoice_id.partner_id.ean13 || "GTIN_UNKNOWN"
  nad.cC082.d3055 = '9'
  msg.add(nad)
  # RFF
  # VAT number invoice buyer
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
  # for calculating totals at the end
  btw_6, btw_21, recupel = 0.0, 0.0, 0.0
  cnt = 0
  inv.invoice_line.each do |line|
    
    cnt = cnt + 1
    
    @log.info( @log_pfx + 'New invoice item' )
  	@log.info( @log_pfx + 'item ean_code:' + line.product_id.ean13 )
    
    # LIN
    lin = msg.new_segment('LIN')
    lin.d1082 = cnt
    lin.cC212.d7140 = line.product_id.ean13
    lin.cC212.d7143 = 'EN'
    msg.add(lin)  
        
    # PIA
    # Additional product id
    pia = msg.new_segment('PIA')
    pia.d4347 = '1' # additional identification
    pia.aC212[0].d7140 = line.product_id.default_code
    pia.aC212[0].d7143 = 'SA'
    msg.add(pia)  
    
    # IMD
    # item description
    imd = msg.new_segment('IMD')
    imd.d7077 = 'F' # free form
    imd.cC273.d7009 = 'IN'
    imd.cC273.a7008[0].value = line.name
    msg.add(imd)
    
    # QTY
    # invoiced qty
    qty = msg.new_segment('QTY')
    qty.cC186.d6063 = '47'
    qty.cC186.d6060 = sprintf("%.2f",line.quantity) # qty
    msg.add(qty)

    # QTY
    # delivered qty
    qty = msg.new_segment('QTY')
    qty.cC186.d6063 = '46'
    qty.cC186.d6060 = sprintf("%.2f",line.quantity) # qty
    msg.add(qty)

    # MOA
    # line item amount
    moa = msg.new_segment('MOA')
    moa.cC516.d5025 = '203' 
    moa.cC516.d5004 = sprintf("%.2f",line.price_subtotal)
    msg.add(moa)    
    
    # PRI
    # price details
    # pri = msg.new_segment('PRI')
    #     pri.cC509.d5125 = 'AAA' # net price (includes taxes)
    #     pri.cC509.d5118 = line.price_unit
    #     msg.add(pri)
    
    # CAUTION. Tax lines are sorted on id. This presumes that VAT always comes before recupel. Probably something we need to fix later.
    line.invoice_line_tax_id.sort_by!{|tax| tax.id}.each do |tax|
      case tax.id
      when 1 # btw 21
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
        moa.cC516.d5004 = sprintf("%.2f",line.price_subtotal)
        msg.add(moa)
        
        btw_21 = btw_21 + (line.price_subtotal * 0.21)
      when 5 # recupel 0.05
        # RECUPEL
        # ALC
        alc = msg.new_segment('ALC')
        alc.d5463 = 'C'
        alc.cC214.d7161 = '013'
        alc.cC214.a7160[0].value = 'RECUPEL'
        msg.add(alc)

        # TAX
        tax = msg.new_segment('TAX')
        tax.d5283 = '7'
        tax.cC241.d5153 = 'VAT'
        tax.cC243.d5278 = 'E'
        msg.add(tax)

        # MOA
        # recupel amount
        moa = msg.new_segment('MOA')
        moa.cC516.d5025 = '23' 
        moa.cC516.d5004 = sprintf("%.2f", line.quantity * 0.05)
        msg.add(moa)
        
        recupel = recupel + (line.quantity * 0.05)
      end
    end       
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
  moa.cC516.d5004 = sprintf("%.2f",inv.amount_total)
  msg.add(moa)
  
  # MOA
  # total taxable amount
  moa = msg.new_segment('MOA')
  moa.cC516.d5025 = '79'
  moa.cC516.d5004 = sprintf("%.2f",inv.amount_untaxed)
  msg.add(moa)
  
  # MOA
  # total vat tax amount
  moa = msg.new_segment('MOA')
  moa.cC516.d5025 = '124'
  moa.cC516.d5004 = sprintf("%.2f",btw_21 + btw_6)
  msg.add(moa)
  
  # check if there is recupel
  unless recupel == 0
    tax = msg.new_segment('TAX')
    tax.d5283 = '7'
    tax.cC241.d5153 = 'VAT'
    tax.cC243.d5278 = 'E'
    msg.add(tax)
    
    # RECUPEL TOTAL
    # ALC
    alc = msg.new_segment('ALC')
    alc.d5463 = 'C'
    alc.cC214.d7161 = '013'
    alc.cC214.a7160[0].value = 'RECUPEL'
    msg.add(alc)
    
    # MOA
    # recupel amount
    moa = msg.new_segment('MOA')
    moa.cC516.d5025 = '23' 
    moa.cC516.d5004 = recupel
    msg.add(moa)
  end
  
  @ic.add( msg )
  
end

def process_business_object( object_id, filename, log, test=false)
  setup_openerp_connection
  create_interchange
  @log = log
  @log_pfx = 'OIC: '
  inv = AccountInvoice.first(:params => {:number => object_id})
  unless inv
    @log.error( @log_pfx + 'No invoice found with number: ' + object_id)
    @log.info( @log_pfx + 'Invoic skipped' )
    return false      
  end
  @log.info( @log_pfx + 'invoice found with number: ' + inv.number )
  create_invoic_message(inv, test)
  @ic.validate
  @ic.output_mode=:indented
  File.open(filename, 'w') {|f| f.write(@ic.to_s) } 
end

end