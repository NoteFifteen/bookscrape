require 'trollop'
require 'json'
require 'time'
require 'mailgun'

# linking to custom modules
$basePath   = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')

$log = Bt_logging.create_logging('cn_mapper::Mapper')

$BT_CONSTANTS = Booktrope::Constants.instance

Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
	        :api_key        => $BT_CONSTANTS[:parse_api_key]

#TODO: create a better way to manage TO/FROM emails
def send_report_email(body)
	top = "We were unable to map daily sales data to a book for the following sales records #{Date.today} PST <br /><br />\n"
	top += "Please add the control numbers below to the corresponding project in teamtrope.<br /><br />"
	mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
	email_parameters = {
		:to      => 'Justin Jeffress <justin.jeffress@booktrope.com>, Andy Roberts <andy@booktrope.com>, Kelsey Wong <kelsey@booktrope.com>', #, Adam Bodendieck <adam.bodendieck@booktrope.com>',
		:from    =>	'"Booktrope Mapper" <justin.jeffress@booktrope.com>',
		:subject => 'Unable to Map Sales Data to Book',
		:html    => top + body
	}
	mailgun.messages.send_email(email_parameters)
end


def load_book_hash(book_list, key, control_number_name)
	book_hash = Hash.new
	book_list.each do | book |
		if !book[key].nil? && book[key] != 0
			control_number = (control_number_name == "asin") ? book[key] : book[key].to_i
			book_hash[control_number] = book
		end
	end
	return book_hash
end

def convert_ISBN10_to_ISBN13(isbn10)
	prefix = "978"
	result = prefix + isbn10[0, isbn10.size-1]
	bound = 10

	factor = 1
	check_digit = 0
	result.size.times do | digit |
		check_digit = check_digit + (result[digit].to_i() * factor)
		factor = (factor == 1) ? 3 : 1
	end
	check_digit = check_digit % bound

	if check_digit > 0
		check_digit = bound - check_digit	
	end
	result = result + check_digit.to_s
	return result
end

def map_sales_data_to_book(book_hash, sales_data_cn, table_name, url, shouldToI = false)

	$log.info "Performing query on #{table_name}"

	ls_query = Parse::Query.new(table_name).tap do | q |
		q.limit = 1000
		q.eq("book", nil)
	end.get

	not_found = Array.new
	already_inserted = Hash.new

	batch = Parse::Batch.new
	batch.max_requests = 50


	ls_query.each do | ls_stat |
		isbn = ls_stat[sales_data_cn]
		isbn_10 = ""
		if table_name.eql? "CreateSpaceSalesData"
			isbn_10 = ls_stat[sales_data_cn]
			isbn = convert_ISBN10_to_ISBN13(isbn_10)
			#puts "#{ls_stat[sales_data_cn]} #{isbn}"
		end

		isbn = isbn.to_i if shouldToI

		if isbn != 0 && book_hash.has_key?(isbn)
			book = book_hash[isbn]
			
			$log.info "found"
			ls_stat["book"] = book
						
			batch.update_object_run_when_full! ls_stat
		else
			$log.info "Not found: #{isbn} class: #{isbn.class}"
			
			if !already_inserted.has_key? isbn
				not_found.push({:cn => isbn ,
				 :url => url.gsub(/\{0\}/, (isbn_10 != "") ? isbn_10.to_s : isbn.to_s),
				 :object_id => ls_stat.parse_object_id})
				already_inserted[isbn] = true
			else
				$log.info "Already inserted this item. #{isbn}"
			end
		end
	end

	if batch.requests.length > 0
		batch.run!
	end
	return not_found
end


def map_no_book_sales_to_book_per_channel(sales_channels_to_map)
	book_list = Parse::Query.new("Book").tap do | q |
		q.limit = 1000
	end.get

	body = ""
	sales_channels_to_map.each do | channel |
		book_hash = load_book_hash(book_list, channel[:book_control_number], channel[:sales_control_number])
		not_found = map_sales_data_to_book(book_hash, channel[:sales_control_number], channel[:sales_table_name], channel[:url], (channel[:should_to_i]) ? true : false)
		cn_text = channel[:control_number_title]
		
		body += "<h2>#{channel[:title]}</h2>\n<br />\n"
		body += Mail_helper.alternating_table_body(not_found, "Parse Object ID" => :object_id, cn_text => :cn, "URL" => :url)
	end
	send_report_email body if body.length > 0
end

sales_channels_to_map = [
{:title => "Amazon", :control_number_title => "ASIN", :book_control_number => "asin", :sales_table_name => "AmazonSalesData", :sales_control_number => "asin", :url => "<a href=\"http://amzn.com/{0}\">Amazon Store<a/>"},
{:title => "Apple",  :control_number_title => "Apple ID", :book_control_number => "appleId", :sales_table_name => "AppleSalesData", :sales_control_number => "appleId", :url => "<a href=\"https://itunes.apple.com/book/id{0}\">iBooks Store</a>"},
{:title => "Createspace", :control_number_title => "ISBN", :book_control_number => "createspaceIsbn", :sales_table_name => "CreateSpaceSalesData", :sales_control_number => "asin", :url => "<a href=\"http://amzn.com/{0}\">Amazon Store</a>"},
{:title => "Google Play", :control_number_title => "ISBN", :book_control_number => "epubIsbnItunes", :sales_table_name => "GooglePlaySalesData", :sales_control_number => "epubIsbn", :url => "NA", :should_to_i => true} ,
{:title => "Lightning Source", :control_number_title => "ISBN", :book_control_number => "lightningSource", :sales_table_name => "LightningSalesData", :sales_control_number => "isbn", :url => "NA"},
{:title => "Nook", :control_number_title => "BNID", :book_control_number => "bnid", :sales_table_name => "NookSalesData", :sales_control_number => "nookId", :url => "<a href=\"http://www.barnesandnoble.com/s/{0}?keyword={0}&store=nookstore\">Nook Store</a>"},
]

map_no_book_sales_to_book_per_channel sales_channels_to_map