require 'trollop'
require 'time'
require 'mailgun'
require 'csv'
require 'fileutils'

$basePath = File.absolute_path(File.dirname(__FILE__))
require File.join($basePath, '..', 'booktrope-modules')

$opts = Trollop::options do

   banner <<-EOS
Extracts book sales data from iTunes Connect by downloading the report file, uncompressing it,
and parsing the TSV file using ruby CSV. The data is then saved into parse.com
   Usage:
            ruby apple_reporter.rb [--dontSaveToParse] [--headless] -- dropFolder file_path --archiveFolder file_path
   EOS

   opt :dontSaveToParse, "Turns off parse", :short => 'x'
   opt :headless, "Runs headless", :short => 'h'
   opt :downloadFolder, "The archive folder to drop the unzipped file into for posterity", :type => :string, :short => 'd'
   opt :archiveFolder, "The folder to save the report file from iTunes Connect into.", :type => :string, :short => 'a'
   version "2.0.0 2014 Justin Jeffress"

end

should_run_headless = ($opts.headless) ? true : false

$BT_CONSTANTS = BTConstants.get_constants

Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
	        :api_key        => $BT_CONSTANTS[:parse_api_key]

$batch = Parse::Batch.new
$batch.max_requests = 50

Watir_harness.download_folder = $opts.downloadFolder
class_name = "Salesdata_Extraction::Apple_reporter"
Watir_harness.run(should_run_headless, class_name, lambda { | log | 

	results = Array.new

	url = $BT_CONSTANTS[:itunes_connect_url]
	
	Watir_harness.browser.goto url
	
	Watir_harness.browser.text_field(:id, "accountname").set($BT_CONSTANTS[:itunes_connect_username])
	Watir_harness.browser.text_field(:id, "accountpassword").set($BT_CONSTANTS[:itunes_connect_password])

	Watir_harness.browser.button(:class, "sign-in").click
	
	Watir_harness.browser.goto "https://reportingitc2.apple.com/reports.html"
	
	Watir_harness.browser.button(:xpath => "//div[@id='reportGroups']/div[2]/div[5]/div/button").wait_until_present
	sleep 5.0
	Watir_harness.browser.button(:xpath => "//div[@id='reportGroups']/div[2]/div[5]/div/button").click
	sleep(5.0)
	while !Dir.glob($opts.downloadFolder+"*.part").empty?
		sleep(5.0)
	end
})

def get_book_hash()
	book_hash = Hash.new

	#getting the number of books in parse
	book_count = Parse::Query.new("Book").tap do |q|
   	q.exists("appleId")
   	q.limit = 0
   	q.count = 1
	end.get	 

	#requesting all books at once
	#TODO: parse is limited to 1000 rows per query. Need to update this to loop requests 
	#using skip to get everything.
	book_list = Parse::Query.new("Book").tap do |q|
		q.exists("appleId")
		q.limit = book_count["count"]
	end.get

	book_list.each do | book |
		book_hash[book["appleId"]] = book
	end
	return book_hash
end

def send_report_email(results)

	top = "Apple Sales Numbers for #{results[0][:crawl_date]} PST <br /><br />\n"
	mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
	email_parameters = {
		:to      => 'justin.jeffress@booktrope.com, andy@booktrope.com, heather.ludviksson@booktrope.com, Katherine Sears <ksears@booktrope.com>, Kenneth Shear <ken@booktrope.com>',
		:from    =>	'"Booktrope Daily Crawler 2.0" <justin.jeffress@booktrope.com>',
		:subject => 'Apple Sales Numbers',
		:html    => top + Mail_helper.alternating_table_body(results.sort_by{|k| k[:units_sold]}.reverse, "Apple ID" => :apple_id, "Title" => :title, "Country" => :country, "Daily Sales" => :units_sold, :total => [:units_sold])
	}

	mailgun.messages.send_email(email_parameters)
end

def process_zip_file(zip_path)
	contents = ""
	
	Zlib::GzipReader.open(zip_path) do |gz|
		contents = gz.read
	end
	
	file_name = File.basename(zip_path, ".gz")
	File.open(File.join($opts.archiveFolder, file_name), "w") do |f|
		f.write contents
	end
	FileUtils.rm zip_path
	csv_to_parse(contents)

end

def csv_to_parse(contents)
	results = Array.new
	csv = CSV.parse(contents, :headers => true, :col_sep => "\t")
	csv.each do | row |
		if row["Product Type Identifier"] == "EB1"
			row_hash = Hash.new	
			row_hash[:title] = row["Title"]
			row_hash[:units_sold] = row["Units"].to_i
			row_hash[:country] = row["Country Code"]
			row_hash[:apple_id] = row["Apple Identifier"]
			date = row["Begin Date"].split "/"
			row_hash[:crawl_date] = "#{date[2]}-#{date[0]}-#{date[1]} 00:00:00"

			apple_sales_data = Parse::Object.new("AppleSalesData")
			if $book_hash.has_key? row_hash[:apple_id]
				apple_sales_data["book"] = $book_hash[row_hash[:apple_id]]
			end
			apple_sales_data["appleId"] = row_hash[:apple_id].to_i
			apple_sales_data["dailySales"] = row_hash[:units_sold].to_i
			apple_sales_data["country"] = row_hash[:country]
			apple_sales_data["crawlDate"] = Parse::Date.new(row_hash[:crawl_date])

			$batch.create_object_run_when_full! apple_sales_data if !$opts.dontSaveToParse
			puts "#{row["Title"]}\t#{row["Units"]}\t#{row["Country Code"]}\t#{row["Product Type Identifier"]}\t#{row["Begin Date"]}\t#{row["End Date"]}\t#{row["Apple Identifier"]}"
			results.push row_hash
		end
	end
	send_report_email results
end

def process_download_folder()
	puts "processing the download folder: #{$opts.downloadFolder}"
	Dir.foreach($opts.downloadFolder) do | item |
		next if item == '.' or item == '..' or item.start_with?('.')
		gzip_file = File.join($opts.downloadFolder, item)
		process_zip_file gzip_file
	end
end

$book_hash = get_book_hash()
process_download_folder()

if $batch.requests.length > 0 && !$opts.dontSaveToParse
	puts $batch.run!
	$batch.requests.clear
end