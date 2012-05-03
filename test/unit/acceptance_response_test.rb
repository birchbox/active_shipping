require_relative '../test_helper'

class AcceptanceResponseTest < Test::Unit::TestCase
  def setup
    @carrier = UPS.new(fixtures(:ups).merge(:test => true))
    @acceptance_response = @carrier.send(:parse_acceptance_response, xml_fixture('ups/shipment_accept_response_real'))
    @acceptance_response_high_value = @carrier.send(:parse_acceptance_response, xml_fixture('ups/shipment_accept_response_real_high_value'))
  end

  def test_save_image_file
    file_path_1 = '/tmp'
    file_path_2 = '/tmp'

    @acceptance_response.save_files_for_package_with_tracking_number '1Z9196170297067329', file_path_1
    @acceptance_response.save_files_for_package_with_tracking_number '1Z9196170295190136', file_path_2

    file_contents_1_gif = open("#{file_path_1}/label1Z9196170297067329.gif", 'rb') { |io| io.read }
    file_contents_1_html = open("#{file_path_1}/label1Z9196170297067329.html", 'rb') { |io| io.read }
    file_contents_2_gif = open("#{file_path_2}/label1Z9196170295190136.gif", 'rb') { |io| io.read }
    file_contents_2_html = open("#{file_path_2}/label1Z9196170295190136.html", 'rb') { |io| io.read }

    assert_equal file_contents_1_gif, @acceptance_response.packages.first[:image_data]
    assert_equal file_contents_1_html, @acceptance_response.packages.first[:label_html]
    assert_equal file_contents_2_gif, @acceptance_response.packages.second[:image_data]
    assert_equal file_contents_2_html, @acceptance_response.packages.second[:label_html]

    File.delete "#{file_path_1}/label1Z9196170297067329.gif"
    File.delete "#{file_path_1}/label1Z9196170297067329.html"
    File.delete "#{file_path_2}/label1Z9196170295190136.gif"
    File.delete "#{file_path_2}/label1Z9196170295190136.html"

    error = assert_raise RuntimeError do
      @acceptance_response.save_files_for_package_with_tracking_number 'INVALID', file_path_1
    end
    assert_equal 'Invalid Tracking Number', error.message
  end

  def test_save_high_value_report
    file_path = '/tmp/test_save_hvr.html'
    @acceptance_response_high_value.save_high_value_report_for_shipment file_path

    file_contents = open(file_path, 'rb') { |io| io.read }
    assert_equal file_contents, @acceptance_response_high_value.high_value_report

    File.delete file_path
  end
end