basePath = File.absolute_path(File.dirname(__FILE__))
require File.join(basePath, "parse-ruby-client-monkey")
module Booktrope
  class ParseHelper

    $parse_initialized = false

    #generic initializer
    def ParseHelper.init(data = {})
      Parse.init(data)
      $parse_initialized = true
    end

    # initializer for dev
    def ParseHelper.init_development()
      constants = Booktrope::Constants.instance
      ParseHelper.init(:application_id => constants[:parse_dev_application_id],
                       :api_key        => constants[:parse_dev_api_key])
    end

    # initializer for production
    def ParseHelper.init_production()
      constants = Booktrope::Constants.instance
      ParseHelper.init(:application_id => constants[:parse_application_id],
                       :api_key        => constants[:parse_api_key])
    end

    # returns true if ParseHelper initialized parse.
    # calling .client on Parse before it's initialized throws an error.
    # might want to update this to begin/rescue and return false if .client throws
    def ParseHelper.initialized?
      return $parse_initialized
    end

    # Helper function to load all books. Iteratively loads all books if there are more
    # books in parse than the limit of 1000 per request.
    # :exists is an array of fields to ensure exist
    def ParseHelper.get_books(data = {})

      skip_by = 1000
      skip = 0
      done = false
      books = Array.new

      data[:exists] = [] if data[:exists].nil?

      while !done
        response = Parse::Query.new("Book").tap do | q |

          data[:exists].each do | field |
            q.exists(field)
          end
          q.count = 1
          q.limit = skip_by
          q.skip = skip
        end.get
        books.concat response["results"]
        skip += skip_by
        done = true if skip >= response["count"]
      end

      return books
    end

    # gets books from parse with a set of constraints.
    def ParseHelper.get_books_with_constraints(options = [])
      skip_by = 1000
      skip = 0
      done = false
      books = Array.new

      while !done
        response = Parse::Query.new("Book").tap do | q |
          options.each do | option |
            ParseHelper.add_constraint option, q
          end

          q.count = 1
          q.limit = skip_by
          q.skip = skip
        end.get

        books.concat response["results"]
        skip += skip_by
        done = true #if skip >= response["count"]
      end

      return books
    end

    def ParseHelper.get_price_change_queue(options = [])
      change_queue = Parse::Query.new("PriceChangeQueue").tap do | q |
        options.each do | option |
          ParseHelper.add_constraint option, q
        end
      end.get
    end

    private
    #VALID_OPTIONS = [ :less_than, :less_eq, :greater_than, :greater_eq, :not_eq, :eq, :value_in, :exists ]
    def ParseHelper.add_constraint(constraint, query)
      case constraint.option
      when :less_than
        query.less_than(constraint.field_name, constraint.value)
      when :less_eq
        query.less_eq(constraint.field_name, constraint.value)
      when :greater_than
        query.greater_than(constraint.field_name, constraint.value)
      when :greater_eq
        query.greater_eq(constraint.field_name, constraint.value)
      when :not_eq
        query.not_eq(constraint.field_name, constraint.value)
      when :eq
        query.eq(constraint.field_name, constraint.value)
      when :value_in
        query.value_in(constraint.field_name, constraint.value)
      when :exists
        query.exists(constraint.field_name, constraint.value)
      when :order_by
        query.order_by = constraint.value
      when :order
        query.order = constraint.value
      when :limit
        query.limit = constraint.value
      when :skip
        query.skip = constraint.value
      when :include
        query.include = constraint.value
      else
        #TODO:: warn about unsupported constraint
      end
    end

  end

  class Constraint
    attr_accessor :option, :field_name, :value

    def initialize(option, field_name, value)
      @option = option
      @field_name = field_name
      @value = value
    end

    def to_s
      "Option: #{@option} \nField Name: #{@field_name}\nValue: #{@value}\n"
    end
  end
end
