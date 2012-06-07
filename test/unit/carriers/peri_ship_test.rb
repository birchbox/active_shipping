require_relative '../../test_helper'

class PeriShipTest < Test::Unit::TestCase

  def setup
    @packages  = TestFixtures.packages
    @locations = TestFixtures.locations
    @carrier = PeriShip.new(fixtures(:periship).merge(:test => true))
    @rates_bad_response = xml_fixture('peri_ship/rates_response_error')
  end

  def test_initialize_options_requirements
    assert_raises(ArgumentError) { PeriShip.new }
    assert_raises(ArgumentError) { PeriShip.new(login: 'blah', password: 'bloo') }
    assert_raises(ArgumentError) { PeriShip.new(login: 'blah', key: 'kee') }
    assert_raises(ArgumentError) { PeriShip.new(password: 'bloo', key: 'kee') }
    assert_nothing_raised { PeriShip.new(login: 'blah', password: 'bloo', key: 'kee') }
  end

  def remove_human_spaces_from_xml(xml)
    xml.gsub(/>\s*\n/, ">\n").gsub(/\n\s*</, '<')
  end

  def test_response_message_with_bad_response
    #mock_response = remove_human_spaces_from_xml(xml_fixture('peri_ship/rates_response_error'))
    #@carrier.expects(:commit).returns(mock_response)
    #response = @carrier.find_rates(@locations[:beverly_hills],
    #                               @locations[:real_home_as_residential],
    #                               @packages.values_at(:shipping_container))
    #
    #assert_equal 'Weight must be between 0 and 150 pounds.', @carrier.send(:response_message, mock_response)
  end
end
