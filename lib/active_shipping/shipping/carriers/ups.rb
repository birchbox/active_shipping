# -*- encoding: utf-8 -*-

module ActiveMerchant
  module Shipping
    class UPS < Carrier
      self.retry_safe = true

      cattr_accessor :default_options
      cattr_reader :name
      @@name = "UPS"

      TEST_URL = 'https://wwwcie.ups.com'
      LIVE_URL = 'https://onlinetools.ups.com'

      RESOURCES = {
            :rates => 'ups.app/xml/Rate',
            :track => 'ups.app/xml/Track',
            :ship_confirm => 'ups.app/xml/ShipConfirm',
            :ship_accept => 'ups.app/xml/ShipAccept',
            :ship_void => 'ups.app/xml/Void',
            :address_validation => 'ups.app/xml/XAV',
            :quantum_view => 'ups.app/xml/QVEvents'
      }

      PICKUP_CODES = HashWithIndifferentAccess.new({
                                                         :daily_pickup => "01",
                                                         :customer_counter => "03",
                                                         :one_time_pickup => "06",
                                                         :on_call_air => "07",
                                                         :suggested_retail_rates => "11",
                                                         :letter_center => "19",
                                                         :air_service_center => "20"
                                                   })

      CUSTOMER_CLASSIFICATIONS = HashWithIndifferentAccess.new({
                                                                     :wholesale => "01",
                                                                     :occasional => "03",
                                                                     :retail => "04"
                                                               })

      # these are the defaults described in the UPS API docs,
      # but they don't seem to apply them under all circumstances,
      # so we need to take matters into our own hands
      DEFAULT_CUSTOMER_CLASSIFICATIONS = Hash.new do |hash, key|
        hash[key] = case key.to_sym
          when :daily_pickup then
            :wholesale
          when :customer_counter then
            :retail
          else
            :occasional
        end
      end

      DEFAULT_SERVICES = {
            "01" => "UPS Next Day Air",
            "02" => "UPS Second Day Air",
            "03" => "UPS Ground",
            "07" => "UPS Worldwide Express",
            "08" => "UPS Worldwide Expedited",
            "11" => "UPS Standard",
            "12" => "UPS Three-Day Select",
            "13" => "UPS Next Day Air Saver",
            "14" => "UPS Next Day Air Early A.M.",
            "54" => "UPS Worldwide Express Plus",
            "59" => "UPS Second Day Air A.M.",
            "65" => "UPS Saver",
            "82" => "UPS Today Standard",
            "83" => "UPS Today Dedicated Courier",
            "84" => "UPS Today Intercity",
            "85" => "UPS Today Express",
            "86" => "UPS Today Express Saver"
      }

      CANADA_ORIGIN_SERVICES = {
            "01" => "UPS Express",
            "02" => "UPS Expedited",
            "14" => "UPS Express Early A.M."
      }

      MEXICO_ORIGIN_SERVICES = {
            "07" => "UPS Express",
            "08" => "UPS Expedited",
            "54" => "UPS Express Plus"
      }

      EU_ORIGIN_SERVICES = {
            "07" => "UPS Express",
            "08" => "UPS Expedited"
      }

      OTHER_NON_US_ORIGIN_SERVICES = {
            "07" => "UPS Express"
      }

      # From http://en.wikipedia.org/w/index.php?title=European_Union&oldid=174718707 (Current as of November 30, 2007)
      EU_COUNTRY_CODES = ["GB", "AT", "BE", "BG", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"]

      US_TERRITORIES_TREATED_AS_COUNTRIES = ["AS", "FM", "GU", "MH", "MP", "PW", "PR", "VI"]


      def requirements
        [:key, :login, :password]
      end

      def find_rates(origin, destination, packages, options={})
        origin, destination = upsified_location(origin), upsified_location(destination)
        options = @options.merge(options)
        packages = Array(packages)
        access_request = build_access_request
        rate_request = build_rate_request(origin, destination, packages, options)
        response = commit(:rates, save_request(access_request + rate_request), (options[:test] || false))
        parse_rate_response(origin, destination, packages, response, options)
      end

      def find_tracking_info(tracking_number, options={})
        options = @options.update(options)
        access_request = build_access_request
        tracking_request = build_tracking_request(tracking_number, options)
        response = commit(:track, save_request(access_request + tracking_request), (options[:test] || false))
        parse_tracking_response(response, options)
      end

      def get_confirmation_response(options)
        options = @options.update(options)
        access_request = build_access_request
        confirmation_request = build_confirmation_request(options)
        response = commit(:ship_confirm, save_request(access_request + confirmation_request), (options[:test] || false))
        parse_confirmation_response(response)
      end

      def get_acceptance_response(options)
        options = @options.update(options)
        access_request = build_access_request
        acceptance_request = build_acceptance_request(options)
        response = commit(:ship_accept, save_request(access_request + acceptance_request), (options[:test] || false))
        parse_acceptance_response(response)
      end

      def get_unparsed_void_response(options)
        options = @options.update(options)
        access_request = build_access_request
        void_request = build_void_request(options)
        request = "<?xml version='1.0'?>#{access_request}<?xml version='1.0'?>#{void_request}"

        commit(:ship_void, save_request(request), (options[:test] || false))
      end

      def get_void_response(options)
        options = @options.update(options)
        access_request = build_access_request
        void_request = build_void_request(options)
        request = "<?xml version='1.0'?>#{access_request}<?xml version='1.0'?>#{void_request}"
        response = commit(:ship_void, save_request(request), (options[:test] || false))

        parse_void_response response
      end

      def get_address_validation_response(options)
        options = @options.update(options)
        options[:strict] = true unless options.has_key?(:strict)
        access_request = build_access_request
        address_validation_request = build_address_validation_request(options)
        request = "<?xml version='1.0'?>#{access_request}<?xml version='1.0'?>#{address_validation_request}"
        response = commit(:address_validation, save_request(request), (options[:test] || false))
        parse_address_validation_response(response, options[:strict])
      end

      def get_quantum_view_response
        access_request = build_access_request

        acc_shipped_info = {}
        bookmark = nil

        while true
          options = (bookmark) ? {bookmark: bookmark} : {}
          request = "<?xml version='1.0'?>#{access_request}<?xml version='1.0'?>#{build_quantum_view_request(options)}"
          response = commit(:quantum_view, save_request(request), (@options[:test] || false))

          quantum_view_response = parse_quantum_view_response(response)
          acc_shipped_info.update(quantum_view_response.shipped_info)

          bookmark = quantum_view_response.bookmark
          break unless bookmark
        end

        quantum_view_response.shipped_info = acc_shipped_info
        quantum_view_response
      end

      protected

      def upsified_location(location)
        if location.country_code == 'US' && US_TERRITORIES_TREATED_AS_COUNTRIES.include?(location.state)
          atts = {:country => location.state}
          [:zip, :city, :address1, :address2, :address3, :phone, :fax, :address_type].each do |att|
            atts[att] = location.send(att)
          end
          Location.new(atts)
        else
          location
        end
      end

      def build_access_request
        xml_request = XmlNode.new('AccessRequest') do |access_request|
          access_request << XmlNode.new('AccessLicenseNumber', @options[:key])
          access_request << XmlNode.new('UserId', @options[:login])
          access_request << XmlNode.new('Password', @options[:password])
        end
        xml_request.to_s
      end

      def build_rate_request(origin, destination, packages, options={})
        packages = Array(packages)
        xml_request = XmlNode.new('RatingServiceSelectionRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Rate')
            request << XmlNode.new('RequestOption', 'Shop')
            # not implemented: 'Rate' RequestOption to specify a single service query
            # request << XmlNode.new('RequestOption', ((options[:service].nil? or options[:service] == :all) ? 'Shop' : 'Rate'))
          end

          pickup_type = options[:pickup_type] || :daily_pickup

          root_node << XmlNode.new('PickupType') do |pickup_type_node|
            pickup_type_node << XmlNode.new('Code', PICKUP_CODES[pickup_type])
            # not implemented: PickupType/PickupDetails element
          end
          cc = options[:customer_classification] || DEFAULT_CUSTOMER_CLASSIFICATIONS[pickup_type]
          root_node << XmlNode.new('CustomerClassification') do |cc_node|
            cc_node << XmlNode.new('Code', CUSTOMER_CLASSIFICATIONS[cc])
          end

          root_node << XmlNode.new('Shipment') do |shipment|
            # not implemented: Shipment/Description element
            shipment << build_location_node('Shipper', (options[:shipper] || origin), options)
            shipment << build_location_node('ShipTo', destination, options)
            if options[:shipper] and options[:shipper] != origin
              shipment << build_location_node('ShipFrom', origin, options)
            end

            # not implemented:  * Shipment/ShipmentWeight element
            #                   * Shipment/ReferenceNumber element                    
            #                   * Shipment/Service element                            
            #                   * Shipment/PickupDate element                         
            #                   * Shipment/ScheduledDeliveryDate element              
            #                   * Shipment/ScheduledDeliveryTime element              
            #                   * Shipment/AlternateDeliveryTime element              
            #                   * Shipment/DocumentsOnly element                      

            packages.each do |package|
              imperial = ['US', 'LR', 'MM'].include?(origin.country_code(:alpha2))

              shipment << XmlNode.new("Package") do |package_node|

                # not implemented:  * Shipment/Package/PackagingType element
                #                   * Shipment/Package/Description element

                package_node << XmlNode.new("PackagingType") do |packaging_type|
                  packaging_type << XmlNode.new("Code", '02')
                end

                package_node << XmlNode.new("Dimensions") do |dimensions|
                  dimensions << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'IN' : 'CM')
                  end
                  [:length, :width, :height].each do |axis|
                    value = ((imperial ? package.inches(axis) : package.cm(axis)).to_f*1000).round/1000.0 # 3 decimals
                    dimensions << XmlNode.new(axis.to_s.capitalize, [value, 0.1].max)
                  end
                end

                package_node << XmlNode.new("PackageWeight") do |package_weight|
                  package_weight << XmlNode.new("UnitOfMeasurement") do |units|
                    units << XmlNode.new("Code", imperial ? 'LBS' : 'KGS')
                  end

                  value = ((imperial ? package.lbs : package.kgs).to_f*1000).round/1000.0 # 3 decimals
                  package_weight << XmlNode.new("Weight", [value, 0.1].max)
                end

                # not implemented:  * Shipment/Package/LargePackageIndicator element
                #                   * Shipment/Package/ReferenceNumber element
                #                   * Shipment/Package/PackageServiceOptions element
                #                   * Shipment/Package/AdditionalHandling element  
              end

            end

            # not implemented:  * Shipment/ShipmentServiceOptions element
            #                   * Shipment/RateInformation element

          end

        end
        xml_request.to_s
      end

      def build_tracking_request(tracking_number, options={})
        xml_request = XmlNode.new('TrackRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Track')
            request << XmlNode.new('RequestOption', '1')
          end
          root_node << XmlNode.new('TrackingNumber', tracking_number.to_s)
        end
        xml_request.to_s
      end

      def build_location_node(name, location, options={})
        # not implemented:  * Shipment/Shipper/Name element
        #                   * Shipment/(ShipTo|ShipFrom)/CompanyName element
        #                   * Shipment/(Shipper|ShipTo|ShipFrom)/AttentionName element
        #                   * Shipment/(Shipper|ShipTo|ShipFrom)/TaxIdentificationNumber element
        location_node = XmlNode.new(name) do |location_node|
          location_node << XmlNode.new('PhoneNumber', location.phone.gsub(/[^\d]/, '')) unless location.phone.blank?
          location_node << XmlNode.new('FaxNumber', location.fax.gsub(/[^\d]/, '')) unless location.fax.blank?

          if name == 'Shipper' and (origin_account = @options[:origin_account] || options[:origin_account])
            location_node << XmlNode.new('ShipperNumber', origin_account)
          elsif name == 'ShipTo' and (destination_account = @options[:destination_account] || options[:destination_account])
            location_node << XmlNode.new('ShipperAssignedIdentificationNumber', destination_account)
          end

          location_node << XmlNode.new('Address') do |address|
            address << XmlNode.new("AddressLine1", location.address1) unless location.address1.blank?
            address << XmlNode.new("AddressLine2", location.address2) unless location.address2.blank?
            address << XmlNode.new("AddressLine3", location.address3) unless location.address3.blank?
            address << XmlNode.new("City", location.city) unless location.city.blank?
            address << XmlNode.new("StateProvinceCode", location.province) unless location.province.blank?
            # StateProvinceCode required for negotiated rates but not otherwise, for some reason
            address << XmlNode.new("PostalCode", location.postal_code) unless location.postal_code.blank?
            address << XmlNode.new("CountryCode", location.country_code(:alpha2)) unless location.country_code(:alpha2).blank?
            address << XmlNode.new("ResidentialAddressIndicator", true) unless location.commercial? # the default should be that UPS returns residential rates for destinations that it doesn't know about
                                                                                                    # not implemented: Shipment/(Shipper|ShipTo|ShipFrom)/Address/ResidentialAddressIndicator element
          end
        end
      end

      def build_confirmation_request(options)
        xml_request = XmlNode.new('ShipmentConfirmRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'ShipConfirm')
            request << XmlNode.new('RequestOption', 'validate')
          end

          root_node << XmlNode.new('Shipment') do |shipment|
            shipment << XmlNode.new('Shipper') do |shipper|
              options_shipper = options[:shipper]
              shipper << XmlNode.new('Name', options_shipper[:name])
              shipper << XmlNode.new('PhoneNumber', options_shipper[:phone_number])
              shipper << XmlNode.new('EMailAddress', options_shipper[:email_address])
              shipper << XmlNode.new('ShipperNumber', options_shipper[:account_number])
              shipper << XmlNode.new('Address') do |address|
                address << XmlNode.new('AddressLine1', options_shipper[:address].address1)
                address << XmlNode.new('AddressLine2', options_shipper[:address].address2) if options_shipper[:address].address2
                address << XmlNode.new('City', options_shipper[:address].city)
                address << XmlNode.new('StateProvinceCode', options_shipper[:address].state)
                address << XmlNode.new('PostalCode', options_shipper[:address].zip)
                address << XmlNode.new('CountryCode', options_shipper[:address].country_code)
              end
            end

            shipment << XmlNode.new('ShipFrom') do |shipper|
              options_ship_from = options[:origin]
              shipper << XmlNode.new('CompanyName', options_ship_from[:company_name])
              shipper << XmlNode.new('AttentionName', options_ship_from[:attention_name])
              shipper << XmlNode.new('PhoneNumber', options_ship_from[:phone_number])
              shipper << XmlNode.new('Address') do |address|
                address << XmlNode.new('AddressLine1', options_ship_from[:address].address1)
                address << XmlNode.new('AddressLine2', options_ship_from[:address].address2) if options_ship_from[:address].address2
                address << XmlNode.new('City', options_ship_from[:address].city)
                address << XmlNode.new('StateProvinceCode', options_ship_from[:address].state)
                address << XmlNode.new('PostalCode', options_ship_from[:address].zip)
                address << XmlNode.new('CountryCode', options_ship_from[:address].country_code)

              end
            end

            shipment << XmlNode.new('ShipTo') do |recipient|
              options_ship_to = options[:destination]
              recipient << XmlNode.new('CompanyName', options_ship_to[:company_name])
              recipient << XmlNode.new('AttentionName', options_ship_to[:attention_name])
              recipient << XmlNode.new('PhoneNumber', options_ship_to[:phone_number])
              recipient << XmlNode.new('Address') do |address|
                address << XmlNode.new('AddressLine1', options_ship_to[:address].address1)
                address << XmlNode.new('AddressLine2', options_ship_to[:address].address2) if options_ship_to[:address].address2
                address << XmlNode.new('City', options_ship_to[:address].city)
                address << XmlNode.new('StateProvinceCode', options_ship_to[:address].state)
                address << XmlNode.new('PostalCode', options_ship_to[:address].zip)
                address << XmlNode.new('CountryCode', options_ship_to[:address].country_code)

              end
            end

            shipment << XmlNode.new('PaymentInformation') do |payment_info|
              payment_info << XmlNode.new('Prepaid') do |prepaid|
                prepaid << XmlNode.new('BillShipper') do |bill_shipper|
                  bill_shipper << XmlNode.new('AccountNumber', options[:shipper][:account_number])
                end
              end
            end

            shipment << XmlNode.new('Service') do |service|
              service << XmlNode.new('Code', options[:service_code])
            end

            options[:packages].each do |package|
              shipment << XmlNode.new('Package') do |package_node|
                package_node << XmlNode.new('PackagingType') do |packaging_type|
                  #TODO consider whether it makes sense to not hard-code the package type
                  packaging_type << XmlNode.new('Code', '02')
                end

                package_node << XmlNode.new('PackageWeight') do |package_weight|
                  package_weight << XmlNode.new('UnitOfMeasurement') do |unit_of_measurement|
                    unit = (package.options[:units] == :imperial) ? 'LBS' : 'KGS'
                    unit_of_measurement << XmlNode.new('Code', unit)
                  end
                  package_weight << XmlNode.new('Weight', package.pounds)
                end

                package_node << XmlNode.new('Dimensions') do |dimensions|
                  dimensions << XmlNode.new('UnitOfMeasurement') do |unit_of_measurement|
                    unit = (package.options[:units] == :imperial) ? 'IN' : 'CM'
                    unit_of_measurement << XmlNode.new('Code', unit)
                  end
                  dimensions << XmlNode.new('Length', package.inches(:length))
                  dimensions << XmlNode.new('Height', package.inches(:height))
                  dimensions << XmlNode.new('Width', package.in(:width))
                end

                if (package.dry_ice_weight && (options[:service_code] != '03')) || package.value
                  package_node << XmlNode.new('PackageServiceOptions') do |package_service_options|
                    if package.value
                      package_service_options << XmlNode.new('InsuredValue') do |insured_value|
                        insured_value << XmlNode.new('CurrencyCode', 'USD')
                        value = (BigDecimal.new(package.value.to_s) / 100).round(2).to_s('F')
                        insured_value << XmlNode.new('MonetaryValue', value)
                      end
                    end

                    if package.dry_ice_weight
                      package_service_options << XmlNode.new('DryIce') do |dry_ice|
                        dry_ice << XmlNode.new('RegulationSet', 'CFR')
                        dry_ice << XmlNode.new('DryIceWeight') do |dry_ice_weight|
                          dry_ice_weight << XmlNode.new('UnitOfMeasurement') do |unit_of_measurement|
                            unit = (package.options[:units] == :imperial) ? 'LBS' : 'KGS'
                            unit_of_measurement << XmlNode.new('Code', unit)
                          end
                          dry_ice_weight << XmlNode.new('Weight', package.dry_ice_weight)
                        end
                      end
                    end
                  end
                end
              end
            end
          end
          root_node << XmlNode.new('LabelSpecification') do |label_specification|
            label_specification << XmlNode.new('LabelPrintMethod') do |label_print_method|
              #TODO: Maybe include other types of labels?
              label_print_method << XmlNode.new('Code', 'GIF')
            end
            label_specification << XmlNode.new('HTTPUserAgent', 'Mozilla/4.5')
            label_specification << XmlNode.new('LabelImageFormat') do |label_image_format|
              label_image_format << XmlNode.new('Code', 'GIF')
            end
          end
        end
        xml_request.to_s
      end

      def build_acceptance_request(options)
        xml_request = XmlNode.new('ShipmentAcceptRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'ShipAccept')
          end

          root_node << XmlNode.new('ShipmentDigest', options[:shipment_digest])
        end
        xml_request.to_s
      end

      def build_void_request(options)
        xml_request = XmlNode.new('VoidShipmentRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Void')
          end
          if options[:tracking_numbers]
            root_node << XmlNode.new('ExpandedVoidShipment') do |expanded_node|
              expanded_node << XmlNode.new('ShipmentIdentificationNumber', options[:shipment_identification_number])
              options[:tracking_numbers].each do |tracking_number|
                expanded_node << XmlNode.new('TrackingNumber', tracking_number)
              end
            end
          elsif root_node << XmlNode.new('ShipmentIdentificationNumber', options[:shipment_identification_number])
          end
        end
        xml_request.to_s
      end

      def parse_rate_response(origin, destination, packages, response, options={})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)

        if success
          rate_estimates = []

          xml.elements.each('/*/RatedShipment') do |rated_shipment|
            service_code = rated_shipment.get_text('Service/Code').to_s
            days_to_delivery = rated_shipment.get_text('GuaranteedDaysToDelivery').to_s.to_i
            delivery_date = days_to_delivery >= 1 ? days_to_delivery.days.from_now.strftime("%Y-%m-%d") : nil

            rate_estimates << RateEstimate.new(origin, destination, @@name,
                                               service_name_for(origin, service_code),
                                               :total_price => rated_shipment.get_text('TotalCharges/MonetaryValue').to_s.to_f,
                                               :currency => rated_shipment.get_text('TotalCharges/CurrencyCode').to_s,
                                               :service_code => service_code,
                                               :packages => packages,
                                               :delivery_range => [delivery_date])
          end
        end
        RateResponse.new(success, message, Hash.from_xml(response).values.first, :rates => rate_estimates, :xml => response, :request => last_request)
      end

      def parse_tracking_response(response, options={})
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)

        if success
          tracking_number, origin, destination = nil
          shipment_events = []

          first_shipment = xml.elements['/*/Shipment']
          first_package = first_shipment.elements['Package']
          tracking_number = first_shipment.get_text('ShipmentIdentificationNumber | Package/TrackingNumber').to_s

          origin, destination = %w{Shipper ShipTo}.map do |location|
            location_from_address_node(first_shipment.elements["#{location}/Address"])
          end

          activities = first_package.get_elements('Activity')
          unless activities.empty?
            shipment_events = activities.map do |activity|
              description = activity.get_text('Status/StatusType/Description').to_s
              zoneless_time = if (time = activity.get_text('Time')) &&
                    (date = activity.get_text('Date'))
                time, date = time.to_s, date.to_s
                hour, minute, second = time.scan(/\d{2}/)
                year, month, day = date[0..3], date[4..5], date[6..7]
                Time.utc(year, month, day, hour, minute, second)
              end
              location = location_from_address_node(activity.elements['ActivityLocation/Address'])
              ShipmentEvent.new(description, zoneless_time, location)
            end

            shipment_events = shipment_events.sort_by(&:time)

            if origin
              first_event = shipment_events[0]
              same_country = origin.country_code(:alpha2) == first_event.location.country_code(:alpha2)
              same_or_blank_city = first_event.location.city.blank? or first_event.location.city == origin.city
              origin_event = ShipmentEvent.new(first_event.name, first_event.time, origin)
              if same_country and same_or_blank_city
                shipment_events[0] = origin_event
              else
                shipment_events.unshift(origin_event)
              end
            end
            if shipment_events.last.name.downcase == 'delivered'
              shipment_events[-1] = ShipmentEvent.new(shipment_events.last.name, shipment_events.last.time, destination)
            end
          end

        end
        TrackingResponse.new(success, message, Hash.from_xml(response).values.first,
                             :xml => response,
                             :request => last_request,
                             :shipment_events => shipment_events,
                             :origin => origin,
                             :destination => destination,
                             :tracking_number => tracking_number)
      end

      def parse_confirmation_response(response)
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        options = {
              xml_response: response
        }

        if success
          options.update(
                {
                      total_cost: BigDecimal.new(xml.get_text('/*/ShipmentCharges/TotalCharges/MonetaryValue').to_s),
                      shipment_digest: xml.get_text('/*/ShipmentDigest').to_s,
                      shipment_identification_number: xml.get_text('/*/ShipmentIdentificationNumber').to_s
                }
          )
        end
        ConfirmationResponse.new(success, message, Hash.from_xml(response).values.first, options)
      end

      def parse_acceptance_response(response)
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        options = {
              xml_response: response
        }

        if success
          packages = []

          xml.elements.each('/*/ShipmentResults/PackageResults') do |package|
            packages << {
                  tracking_number: package.get_text('TrackingNumber').to_s,
                  image_data: Base64.decode64(package.get_text('LabelImage/GraphicImage').to_s),
                  label_html: Base64.decode64(package.get_text('LabelImage/HTMLImage').to_s)
            }
          end

          options.update(
                {
                      total_cost: BigDecimal.new(xml.get_text('/*/ShipmentResults/ShipmentCharges/TotalCharges/MonetaryValue').to_s),
                      shipment_identification_number: xml.get_text('/*/ShipmentResults/ShipmentIdentificationNumber').to_s,
                      high_value_report: Base64.decode64(xml.get_text('/*/ShipmentResults/ControlLogReceipt/GraphicImage').to_s),
                      packages: packages
                }
          )
        end

        AcceptanceResponse.new(success, message, Hash.from_xml(response).values.first, options)
      end

      def parse_void_response(response)
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        options = {
              xml: response,
              voided: xml.get_text('//StatusType/Code').to_s == '1' ? true : false
        }

        VoidResponse.new(success, message, Hash.from_xml(response).values.first, options)
      end

      def parse_address_validation_response(response, strict = true)
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        options = {
              xml: response
        }

        indicator_node = xml.find_first_recursive { |node| node.name.match /(?:(?:Valid|Ambiguous)Address|NoCandidates)Indicator/ }
        indicator = case indicator_node.name
          when 'ValidAddressIndicator' then
            :valid
          when 'AmbiguousAddressIndicator' then
            :ambiguous
          when 'NoCandidatesIndicator' then
            :no_candidates
        end

        if strict
          %w(PostcodePrimaryLow PoliticalDivision1 PoliticalDivision2).each do |attr|
            from_request = last_request.match(/<#{attr}>(.+)<\/#{attr}>/)[1].downcase.split
            from_response = xml.get_text("/*/AddressKeyFormat/#{attr}").to_s.downcase.split
            indicator = :no_candidates if from_request!= from_response
          end
        end

        options.update(
              {
                    indicator: indicator
              }
        )

        AddressValidationResponse.new(success, message, Hash.from_xml(response).values.first, options)
      end

      def parse_quantum_view_response(response)
        xml = REXML::Document.new(response)
        success = response_success?(xml)
        message = response_message(xml)
        options = {}

        shipped_info = {}
        xml.elements.each('/*/QuantumViewEvents/SubscriptionEvents/SubscriptionFile/Origin') do |origin|
          tracking_number = origin.get_text('TrackingNumber').to_s
          date = origin.get_text('Date').to_s
          time = origin.get_text('Time').to_s
          shipped_info[tracking_number] = DateTime.parse("#{date}#{time}")
        end

        bookmark = (xml.get_text('/*/Bookmark')) ? xml.get_text('/*/Bookmark').to_s : nil
        options.update(shipped_info: shipped_info,
                       bookmark: bookmark)
        QuantumViewResponse.new(success, message, Hash.from_xml(response).values.first, options)
      end

      def location_from_address_node(address)
        return nil unless address
        Location.new(
              :country => node_text_or_nil(address.elements['CountryCode']),
              :postal_code => node_text_or_nil(address.elements['PostalCode']),
              :province => node_text_or_nil(address.elements['StateProvinceCode']),
              :city => node_text_or_nil(address.elements['City']),
              :address1 => node_text_or_nil(address.elements['AddressLine1']),
              :address2 => node_text_or_nil(address.elements['AddressLine2']),
              :address3 => node_text_or_nil(address.elements['AddressLine3'])
        )
      end

      def response_success?(xml)
        xml.get_text('/*/Response/ResponseStatusCode').to_s == '1'
      end

      def response_message(xml)
        xml.get_text('/*/Response/Error/ErrorDescription | /*/Response/ResponseStatusDescription').to_s
      end

      def commit(action, request, test = false)
        ssl_post("#{test ? TEST_URL : LIVE_URL}/#{RESOURCES[action]}", request)
      end

      def service_name_for(origin, code)
        origin = origin.country_code(:alpha2)

        name = case origin
          when "CA" then
            CANADA_ORIGIN_SERVICES[code]
          when "MX" then
            MEXICO_ORIGIN_SERVICES[code]
          when *EU_COUNTRY_CODES then
            EU_ORIGIN_SERVICES[code]
        end

        name ||= OTHER_NON_US_ORIGIN_SERVICES[code] unless name == 'US'
        name ||= DEFAULT_SERVICES[code]
      end

      def build_address_validation_request options
        location = options[:location]

        xml_request = XmlNode.new('AddressValidationRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'XAV')
          end

          root_node << XmlNode.new('AddressKeyFormat') do |format|
            format << XmlNode.new('ConsigneeName', location.name)
            format << XmlNode.new('AddressLine', location.address1)
            format << XmlNode.new('AddressLine', location.address2)
            format << XmlNode.new('PoliticalDivision2', location.city)
            format << XmlNode.new('PoliticalDivision1', location.state)
            format << XmlNode.new('PostcodePrimaryLow', location.postal_code)
            format << XmlNode.new('CountryCode', location.country_code)
          end
        end

        xml_request.to_s
      end

      def build_quantum_view_request(options={})
        xml_request = XmlNode.new('QuantumViewRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'QVEvents')
          end
          if options[:bookmark]
            root_node << XmlNode.new('Bookmark', options[:bookmark])
          end
        end

        xml_request.to_s
      end
    end
  end
end
