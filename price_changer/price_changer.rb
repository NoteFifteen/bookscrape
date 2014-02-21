require 'nokogiri'
require 'trollop'
require 'parse-ruby-client'
require 'mailgun'
require 'time'
require 'pp'

basePath = File.absolute_path(File.dirname(__FILE__))
# linking to custom modules
require File.join(basePath, "..", "ruby_modules", "constants")
require File.join(basePath, "..", "ruby_modules", "selenium_harness")
require File.join(basePath, "..", "ruby_modules", "mail_helper")

$opts = Trollop::options do

   banner <<-EOS
Changes prices of books across our various channels.

   Usage:
            ruby price_changer.rb [--debug [--parseQuery]] [--emailOverride email_address] [--suppressMail] [--headless]
   EOS

   opt :debug, "Turns on debugging mode", :short => 'd'
   opt :parseQuery, "Debugs the initial query for parse. (Stops after query and doesn't open the browser.)", :short => 'q'
   opt :suppressMail, "Suppresses the compeletion email", :short=> 's'
   opt :emailOverride, "Overrides the recipients of the email", :type => :string, :short => 'o'
   opt :headless, "Runs headless", :short => 'h'
   version "0.0.9 2014 Justin Jeffress"

end

$debug_mode = ($opts.debug) ? true : false;
$debug_parse_query = ($debug_mode && $opts.parseQuery) ? true : false;

$should_run_headless = ($opts.headless) ?  true : false

$BT_CONSTANTS = BTConstants.get_constants

#Parse.init :application_id => $BT_CONSTANTS[:parse_application_id],
#	        :api_key        => $BT_CONSTANTS[:parse_api_key]

Parse.init :application_id => "RIaidI3C8TOI7h6e3HwEItxYGs9RLXxhO0xdkdM6",
	        :api_key        => "EQVJvWgCKVp4zCc695szDDwyU5lWcO3ssEJzspxd"

def amazon_change_prices(change_hash)
	class_name = "Price_Changer::Amazon_KDP_Changer"
	results = Selenium_harness.run($should_run_headless, class_name, lambda { | log |	
		url = $BT_CONSTANTS[:amazon_kdp_url]
		
		#getting the amazon kdp page
		Selenium_harness.get(url)
		
		#clicking the login button
		sign_button = Selenium_harness.find_element(:css, "a.a-button-text")
		sign_button.click
		
		#entering the username and password
		username_input = Selenium_harness.find_element(:id, "ap_email")
		username_input.send_keys $BT_CONSTANTS[:amazon_kdp_username]
		
		password_input = Selenium_harness.find_element(:id, "ap_password")
		password_input.send_keys $BT_CONSTANTS[:amazon_kdp_password]
		
		#clicking the login button
		login_button = Selenium_harness.find_element(:id, "signInSubmit-input")
		login_button.click
		
		wait = Selenium::WebDriver::Wait.new(:timeout => 15)
		
		change_hash.each do | key, changeling |
			changeling["status"] = 25
			changeling.save
			
			edit_page_url = changeling["book"]["kdpUrl"]
			edit_page_url = lookup_book_edit_page_url(change_hash, changeling["book"]["asin"]) if edit_page_url.nil? || edit_page_url == ""
			Selenium_harness.get(edit_page_url)
			
			wait.until { Selenium_harness.find_element(:xpath, "//div[@id='title-setup-step2']/div/div").displayed? }

			if !Selenium_harness.find_element(:id, "title-setup-top-warning-alert").displayed?

				step2_link = Selenium_harness.find_element(:xpath, "//div[@id='title-setup-step2']/div/div")
				step2_link.click
				
				us_price = Selenium_harness.find_element(:id, "pricing-grid-US-price-input")
				us_price.clear
				us_price.send_keys changeling["price"]
				
				grid_alerts = Selenium_harness.find_elements(:id, 'pricing-grid-US-error-alert')
				
				if changeling["price"] < 2.99 || changeling["price"] > 9.99 || (grid_alerts.length > 0 && grid_alerts[0].displayed?)
					#make sure 35% Royalty
					thirty_five_percent_royalty = Selenium_harness.find_element(:name, 'royaltyPlan')
					if thirty_five_percent_royalty.methods.selected?
						thirty_five_percent_royalty.click
					end
				else
					#make sure 70% Royalty
					seventy_percent_royalty = Selenium_harness.find_element(:xpath, "(//input[@name='royaltyPlan'])[2]")
					if !seventy_percent_royalty.selected?
						seventy_percent_royalty.click
					end
				end
				
				agreement = Selenium_harness.find_element(:id, "title-setup-agreement")
				agreement.click
				
				save_publish = Selenium_harness.find_element(:css, "span#title-setup-step2-submit input.a-button-input")
				save_publish.click
				
				sleep(15.0)
				wait.until { Selenium_harness.find_element(:class, "a-button-input").displayed? }
				changeling["status"] = 50
				changeling.save
				back_to_shelf = Selenium_harness.find_element(:class, "a-button-input")
				back_to_shelf.click
			else
				log.error "Already Set"
			end
		end
	})
end

def lookup_book_edit_page_url(change_hash, current_asin)

	result = ""
	wait = Selenium::WebDriver::Wait.new(:timeout => 15)
	done = false
	i = 0
	hash_count = 0
	while(!done)
		puts "Page: #{i+1}"
		books = Selenium_harness.find_elements(:xpath, "//tr[@class='mt-row']")
		books.each do | book |
			asin_elements = book.find_elements(:css, "div.asinText")
			if asin_elements.count > 0
				asin = asin_elements[0].text.strip.gsub(/\(ASIN: /, "").gsub(/\)$/, "")
				
				if change_hash.has_key? asin
					hash_count = hash_count + 1
					anchor = book.find_element(:css, "div.kdpTitleField.kdpTitleLabel a.a-link-normal.mt-link-content")
					edit_page_url = anchor.attribute("href")
					puts "#{asin}\t#{edit_page_url}"
					if change_hash[asin]["book"]["kdpUrl"] == "" || change_hash[asin]["book"]["kdpUrl"]
						change_hash[asin]["book"]["kdpUrl"] = edit_page_url
						puts "saving kdpUrl #{edit_page_url} for asin #{asin}"
						change_hash[asin]["book"].save
						sleep(1.0)
					end
					result = edit_page_url if asin == current_asin
					if hash_count == change_hash.length
						done = true
						break
					end
				end
			end
		end
		#break if change_hash.size <= 0
		next_button = Selenium_harness.find_elements(:xpath, "//a[contains(@href, '#next')]")
		if next_button.count > 0
			next_button[0].click
			sleep(5.0)
			wait.until { Selenium_harness.find_element(:xpath, "//tr[@class='mt-row']").displayed? }				
		else
			done = true 
		end
		i = i + 1
	end
	return result
end

def nook_change_prices(change_hash)

	class_name = "Price_Changer::Nookpress_Changer"
	results = Selenium_harness.run($should_run_headless, class_name, lambda { | log |

		results = Array.new

		url = $BT_CONSTANTS[:nookpress_url]
	
		#requesting the page
		Selenium_harness.get(url)
	
		#finding and clicking the login button
		upper_login_button = Selenium_harness.find_element(:id, "clickclick")
		upper_login_button.click
	
		#entering credentials
		username_input = Selenium_harness.find_element(:id, "email")
		username_input.send_keys $BT_CONSTANTS[:nookpress_username]
	
		password_input = Selenium_harness.find_element(:id, "password")
		password_input.send_keys $BT_CONSTANTS[:nookpress_password]
	
		#clicking on the login button
		login_button = Selenium_harness.find_element(:id, "login_button")
		login_button.click
		
	})
end

def lookup_book_edit_page_url(change_hash)
	done = false
		
	nook_url_list = Array.new
	while(!done)		
		wait = Selenium::WebDriver::Wait.new(:timeout => 15)
		wait.until { Selenium_harness.find_element(:class, "project-list").displayed? }

		nook_project_list = Selenium_harness.find_elements(:css, "table.project-list tbody tr td.title a")
			nook_project_list.each do | nook_book |
			nook_url_list.push nook_book.attribute("href")
			puts nook_book.attribute("href")
		end
			
		next_button = Selenium_harness.find_element(:css, "li.next.next_page")
		
		if next_button.attribute("class").include? "disabled"
			done = true
		else
			next_button.find_element(:css, "a").click
		end
	end
		
	nook_url_list.each do | nook_url |
		Selenium_harness.get(nook_url)
		
		nook_id = Selenium_harness.find_element(:css, "div.row div.project-body.columns p").text.strip.gsub(/B&N Identifier:/,"").gsub(/\s/,"")
		puts "#{nook_id}\t#{nook_url}"
		
		sleep(5.0)
	end
end

def apple_change_prices(change_hash)
	class_name = "Price_Changer::iTunesConnect_Changer"
	results = Selenium_harness.run($should_run_headless, class_name, lambda { | log |
		url = $BT_CONSTANTS[:itunes_connect_url]
	
		
		Selenium_harness.get(url)	
	
		username_input = Selenium_harness.find_element(:id, "accountname")
		username_input.send_keys $BT_CONSTANTS[:itunes_connect_username]
	
		password_input = Selenium_harness.find_element(:id, "accountpassword")
		password_input.send_keys $BT_CONSTANTS[:itunes_connect_password]
	
		login_button = Selenium_harness.find_element(:xpath, "(//input[@name='1.Continue'])[2]")
		login_button.click
		
		manage_books_link = Selenium_harness.find_element(:link, "Manage Your Books")
		manage_books_link.click
		
		change_hash.each do | key, changeling |
			apple_id_input = Selenium_harness.find_element(:xpath, "//td[@id='search-param-value-appleId']/input")
			puts changeling["book"]["appleId"]
			apple_id_input.send_keys changeling["book"]["appleId"].to_s
			
			sleep(5.0)
			search_button = Selenium_harness.find_element(:xpath, "//div[@id='titleSearch']/table/tbody/tr[11]/td[2]/input")
			search_button.click
			
			book_link = Selenium_harness.find_element(:xpath, "//div[@id='book-list']/div[2]/table/tbody/tr[2]/td/div/p/a")
			book_link.click
			sleep(5.0)
			
			rights_and_pricing_link = Selenium_harness.find_element(:link, "Rights and Pricing")
			rights_and_pricing_link.click
			
			edit_territories_btn = Selenium_harness.find_element(:xpath, "//span[@id='lcBoxWrapperHeaderUpdateContainer']/span/a/img")
			edit_territories_btn.click
			
			currency_dropdown = Selenium_harness.find_element(:xpath, "//td[@id='baseCurr']/select")
			options = currency_dropdown.find_elements(:tag_name, "option")
			options.each do | option |
				if(option.attribute("text") == "USD - US Dollar")
					option.click
					break
				end
			end
			sleep(10.0)
			price_input = Selenium_harness.find_element(:xpath, "//span[@id='InputContainer']/table/tbody/tr[7]/td[2]/span/input")
			price_input.send_keys changeling["price"]
			
			start_date = Selenium_harness.find_element(:id, "startdate")
			start_date.click
			
			today_button = Selenium_harness.find_element(:css, "button.ui-datepicker-nonebtn")
			today_button.click
			
			end_date = Selenium_harness.find_element(:id, "enddate")
			end_date.click
			
			none_button = Selenium_harness.find_element(:css, "button.ui-datepicker-nonebtn")
			none_button.click			
			
			select_all = Selenium_harness.find_element(:link, "Select All")
			select_all.click
			
			continue_button = Selenium_harness.find_element(:css , "span.wrapper-right-button input.continueActionButton")
			continue_button.click
			
			sleep(5.0)
			
		end
	})
end

def sendEmail(change_hash)
	mailgun = Mailgun(:api_key => $BT_CONSTANTS[:mailgun_api_key], :domain => $BT_CONSTANTS[:mailgun_domain])
	top = "Prices Changed for #{Date.today} PST<br />\n<br />\n"
	email_parameters = {
		:to      => (!$opts.emailOverride.nil?) ? $opts.emailOverride : 'justin.jeffress@booktrope.com, andy@booktrope.com, heather.ludviksson@booktrope.com, Katherine Sears <ksears@booktrope.com>, Kenneth Shear <ken@booktrope.com>',
		:from    =>	'"KDP Price Changer" <justin.jeffress@booktrope.com>',
		:subject => ($debug_parse_query) ? 'Price Changes (DEBUG changes not actually made)' : 'Price Changes',
		:html    => top + Mail_helper.alternating_table_body_for_hash_of_parse_objects(change_hash, :col_data => [ "asin" => {:object => "", :field => "asin"}, "Title" => {:object => "book", :field => "title"}, "Author" => {:object => "book", :field => "author"}, "Price" => {:object => "", :field => "price"}])
	}
	mailgun.messages.send_email(email_parameters)
end

changelings = Parse::Query.new("PriceChangeQueue").tap do |q|
   change_date = Time.parse((Date.today+1).strftime("%Y/%m/%d")+" "+"00:00:00").utc.strftime("%Y/%m/%d %H:00:00")
   puts change_date
   change_date = Parse::Date.new(change_date)
	q.less_eq("changeDate", change_date)
	q.less_eq("status", 25)
	q.order_by ="changeDate"
	q.in_query("salesChannel", Parse::Query.new("SalesChannel").tap do | inner_query |
		inner_query.eq("name", "Apple")
	end)
	q.include = "book"
end.get

change_hash = Hash.new

changelings.each do | changeling |
	puts "#{changeling["book"]["appleId"]}\t#{changeling["status"]}\t#{changeling["book"]["title"]}\t#{changeling["book"]["author"]}\t#{changeling["price"]}"
	change_hash[changeling["asin"]] = changeling
end

#nook_change_prices(change_hash) if !$debug_parse_query
#amazon_change_prices(change_hash) if !$debug_parse_query
apple_change_prices(change_hash) if !$debug_parse_query
#sendEmail(change_hash) if !$opts.suppressMail && change_hash.length > 0