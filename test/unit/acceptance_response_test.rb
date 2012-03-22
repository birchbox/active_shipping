require_relative '../test_helper'

class AcceptanceResponseTest < Test::Unit::TestCase
  def setup
    @carrier = UPS.new(fixtures(:ups).merge(:test => true))
    @acceptance_response = @carrier.send(:parse_acceptance_response, xml_fixture('ups/shipment_accept_response_real'))
  end

  def test_save_image_file
    file_path_1 = '/tmp/test_save_image_file_1.gif'
    file_path_2 = '/tmp/test_save_image_file_2.gif'

    @acceptance_response.save_image_for_package_with_tracking_number '1Z9196170297067329', file_path_1
    @acceptance_response.save_image_for_package_with_tracking_number '1Z9196170295190136', file_path_2

    file_contents_1 = open(file_path_1, 'rb') { |io| io.read }
    file_contents_2 = open(file_path_2, 'rb') { |io| io.read }

    assert_equal file_contents_1, @acceptance_response.packages.first[:image_data]
    assert_equal file_contents_2, @acceptance_response.packages.second[:image_data]

    File.delete file_path_1
    File.delete file_path_2

    error = assert_raise RuntimeError do
      @acceptance_response.save_image_for_package_with_tracking_number 'INVALID', file_path_1
    end
    assert_equal 'Invalid Tracking Number', error.message
  end
end