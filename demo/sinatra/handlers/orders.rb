require 'rubygems'
require 'edi4r'
require 'edi4r/edifact'
require 'ooor'
require 'yaml'
require 'ruby-debug'

module Models

  class Order_item
    attr_accessor :number, :ean_code, :quantity, :unit, 
                  :unit_price, :total_amount, :vat_percentage
  end

  class Order
    attr_accessor :reference, :delivery_date,
              		:partner_buyer, :partner_invoice, :partner_delivery, :partner_ult_cons,
              		:items
    def initialize
      @items = Array.new
    end
  end

end

# mapping #############################################################
class IOOrder

def initialize
  @log_pfx = 'OIC: '
end

def map_order_message( msg )

  order = Models::Order.new
  order_item = nil
  msg.each do |seg|
		
    seg_name = seg.name
    seg_name += ' ' + seg.sg_name if seg.sg_name
      
    case seg_name 
      when 'BGM'
        order.reference = seg.d1004
      when 'DTM'
        case seg.cC507.d2005
          when '2'
            order.delivery_date = seg.cC507.d2380
        end
      when 'NAD SG2'
        case seg.d3035
          when 'BY'
            order.partner_buyer = seg.cC082.d3039
          when 'DP'
            order.partner_delivery = seg.cC082.d3039
          when 'IV'
            order.partner_invoice = seg.cC082.d3039
          when 'UC'
            order.partner_ult_cons = seg.cC082.d3039            
        end
      when 'LIN SG25'
        order_item = Models::Order_item.new
        order_item.number = seg.d1082
        order_item.ean_code = seg.cC212.d7140
      when 'QTY SG25'
        case seg.cC186.d6063
          when '21'
            order_item.quantity = seg.cC186.d6060
            order_item.unit = seg.cC186.d6411
        end
      when 'MOA SG25'
        case seg.cC516.d5025
          when '203'
            order_item.total_amount = seg.cC516.d5004
        end
      when 'PRI SG28'
        case seg.cC509.d5125
          when 'AAA'
            order_item.unit_price = seg.cC509.d5118
        end
      when 'TAX SG34'
        case seg.d5283
          when '7'
            case seg.cC241.d5153
              when 'VAT'
                order_item.vat_percentage = seg.cC243.d5278
                order.items.push order_item
            end
        end
    end

  end
  
  order
  
end

def process_file(filename, log)
  
  @message_file = filename
  @log = log
  @log.info( @log_pfx + 'New session: ORDERS' ) 
  @app_config = YAML::load_file( "config/settings.yml" ) || {}  
  import_file
  create_orders
  @log.close
 
end

def import_file

  ic = nil
  File.open(@message_file) {|hnd| ic = EDI::E::Interchange.parse( hnd )}
  @iobs = Array.new 
  ic.each {|msg| @iobs.push map_order_message( msg )}

end

# Open ERP ############################################################
def create_orders

# setup connection
  Ooor.new(:url => @app_config["openerp"]["url"],
           :username => @app_config["openerp"]["username"],
           :password => @app_config["openerp"]["password"],
           :database => @app_config["openerp"]["database"],
           :models => ['sale.order','sale.order.line','product.product', 'product.uom', 'res.partner', 'res.partner.address'],
           :log_level => 0)

  @iobs.each do |order|
  
    @log.info( @log_pfx + 'New order' )
    @log.info( @log_pfx + 'order reference:' + order.reference )
    @log.info( @log_pfx + 'order delivery_date:' + order.delivery_date )
  
#   check if there's no previous order with the same reference
    if SaleOrder.find(:first, :params => { :client_order_ref => order.reference })
      @log.error( @log_pfx + 'An order with customer order reference ' + order.reference + ' already exists' )
      @log.info( @log_pfx + 'Order skipped' )
      next
    end
  
#   partner addresses
    oe_partner_buyer    = ResPartner.find(:first, :params => { :ean13 => order.partner_buyer })
    if !oe_partner_buyer
      @log.error( @log_pfx + 'No buyer found for GTIN:' + order.partner_buyer )
      @log.info( @log_pfx + 'Order skipped' )
      next
    end

    oe_addr_buyer  = ResPartnerAddress.find(:first, :params => { :ean13 => order.partner_buyer })
    if !oe_addr_buyer
      @log.error( @log_pfx + 'No buyer address found for GTIN:' + order.partner_buyer )
      @log.info( @log_pfx + 'Order skipped' )
      next
    end
    
    oe_addr_invoice  = ResPartnerAddress.find(:first, :params => { :ean13 => order.partner_invoice })
    if !oe_addr_invoice
      @log.error( @log_pfx + 'No invoice address found for GTIN:' + order.partner_invoice )
      @log.info( @log_pfx + 'Order skipped' )
      next
    end
    
    oe_addr_delivery = ResPartnerAddress.find(:first, :params => { :ean13 => order.partner_delivery })
    if !oe_addr_delivery
      @log.error( @log_pfx + 'No delivery address found for GTIN:' + order.partner_delivery )
      @log.info( @log_pfx + 'Order skipped' )
      next
    end
    
    if order.partner_ult_cons
      oe_addr_ult_cons = ResPartnerAddress.find(:first, :params => { :ean13 => order.partner_ult_cons })
      if !oe_addr_ult_cons
        @log.error( @log_pfx + 'No ultimate consignee address found for GTIN:' + order.partner_ult_cons )
        @log.info( @log_pfx + 'Order skipped' )
        next
      end
    end    
    
    oe_order = SaleOrder.create(:shop_id => 1,
                                :picking_policy => 'direct',
                                :order_policy => 'manual',
                                :pricelist_id => 1,
                                :client_order_ref => order.reference,
                                :date_delivery => order.delivery_date,
                                :partner_id => oe_partner_buyer.id,
                                :partner_order_id => oe_addr_buyer.id,
                                :partner_invoice_id => oe_addr_invoice.id,
                                :partner_shipping_id => oe_addr_delivery.id,
                                :partner_ult_cons_id => oe_addr_ult_cons.id,
                                :origin => File.basename(@message_file) )

    @log.info( @log_pfx + oe_order.name )

    order.items.each do |item|
	
	    @log.info( @log_pfx + 'New order item' )
    	@log.info( @log_pfx + 'item ean_code:' + item.ean_code )  
	
	    oe_product = ProductProduct.find(:first, :params => { :ean13 => item.ean_code })
	    oe_uom = ProductUom.find(:first, :params => { :name => item.unit })
	    oe_order_line = SaleOrderLine.create(:order_id => oe_order.id,
                                           :product_id => oe_product.id,
                                           :name => oe_product.name,  
                                           :product_uom_qty => item.quantity,
                                           :product_uom => oe_uom.id,
                                           :price_unit => item.unit_price)
	
    end  

  end

end

end
