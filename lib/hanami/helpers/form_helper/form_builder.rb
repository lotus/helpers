require 'hanami/helpers/form_helper/html_node'
require 'hanami/helpers/form_helper/values'
require 'hanami/helpers/html_helper/html_builder'
require 'hanami/utils/string'

module Hanami
  module Helpers
    module FormHelper
      # Form builder
      #
      # @since 0.2.0
      #
      # @see Hanami::Helpers::HtmlHelper::HtmlBuilder
      class FormBuilder < ::Hanami::Helpers::HtmlHelper::HtmlBuilder # rubocop:disable Metrics/ClassLength
        # Set of HTTP methods that are understood by web browsers
        #
        # @since 0.2.0
        # @api private
        BROWSER_METHODS = %w(GET POST).freeze

        # Set of HTTP methods that should NOT generate CSRF token
        #
        # @since 0.2.0
        # @api private
        EXCLUDED_CSRF_METHODS = %w(GET).freeze

        # Checked attribute value
        #
        # @since 0.2.0
        # @api private
        #
        # @see Hanami::Helpers::FormHelper::FormBuilder#radio_button
        CHECKED = 'checked'.freeze

        # Selected attribute value for option
        #
        # @since 0.2.0
        # @api private
        #
        # @see Hanami::Helpers::FormHelper::FormBuilder#select
        SELECTED = 'selected'.freeze

        # Separator for accept attribute of file input
        #
        # @since 0.2.0
        # @api private
        #
        # @see Hanami::Helpers::FormHelper::FormBuilder#file_input
        ACCEPT_SEPARATOR = ','.freeze

        # Replacement for input id interpolation
        #
        # @since 0.2.0
        # @api private
        #
        # @see Hanami::Helpers::FormHelper::FormBuilder#_input_id
        INPUT_ID_REPLACEMENT = '-\k<token>'.freeze

        # Default value for unchecked check box
        #
        # @since 0.2.0
        # @api private
        #
        # @see Hanami::Helpers::FormHelper::FormBuilder#check_box
        DEFAULT_UNCHECKED_VALUE = '0'.freeze

        # Default value for checked check box
        #
        # @since 0.2.0
        # @api private
        #
        # @see Hanami::Helpers::FormHelper::FormBuilder#check_box
        DEFAULT_CHECKED_VALUE = '1'.freeze

        # ENCTYPE_MULTIPART = 'multipart/form-data'.freeze

        self.html_node = ::Hanami::Helpers::FormHelper::HtmlNode

        # Instantiate a form builder
        #
        # @overload initialize(form, attributes, params, &blk)
        #   Top level form
        #   @param form [Hanami::Helpers:FormHelper::Form] the form
        #   @param attributes [::Hash] a set of HTML attributes
        #   @param params [Hanami::Action::Params] request params
        #   @param blk [Proc] a block that describes the contents of the form
        #
        # @overload initialize(form, attributes, params, &blk)
        #   Nested form
        #   @param form [Hanami::Helpers:FormHelper::Form] the form
        #   @param attributes [Hanami::Helpers::FormHelper::Values] user defined
        #     values
        #   @param blk [Proc] a block that describes the contents of the form
        #
        # @return [Hanami::Helpers::FormHelper::FormBuilder] the form builder
        #
        # @since 0.2.0
        # @api private
        def initialize(form, attributes, context = nil, &blk) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          super()

          @context    = context
          @blk        = blk
          @verb       = nil
          @csrf_token = nil

          # Nested form
          if @context.nil? && attributes.is_a?(Values)
            @values      = attributes
            @attributes  = {}
            @name        = form
          else
            @form        = form
            @name        = form.name
            @values      = Values.new(form.values, @context.params)
            @attributes  = attributes
            @verb_method = verb_method
            @csrf_token  = csrf_token
          end
        end

        # Resolves all the nodes and generates the markup
        #
        # @return [Hanami::Utils::Escape::SafeString] the output
        #
        # @since 0.2.0
        # @api private
        #
        # @see Hanami::Helpers::HtmlHelper::HtmlBuilder#to_s
        # @see http://www.rubydoc.info/gems/hanami-utils/Hanami/Utils/Escape/SafeString
        def to_s
          if toplevel?
            _method_override!
            form(@blk, @attributes)
          end

          super
        end

        # Nested fields
        #
        # The inputs generated by the wrapped block will be prefixed with the given name
        # It supports infinite levels of nesting.
        #
        # @param name [Symbol] the nested name, it's used to generate input
        #   names, ids, and to lookup params to fill values.
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     form_for :delivery, routes.deliveries_path do
        #       text_field :customer_name
        #
        #       fields_for :address do
        #         text_field :street
        #       end
        #
        #       submit 'Create'
        #     end
        #   %>
        #
        #   Output:
        #     # <form action="/deliveries" method="POST" accept-charset="utf-8" id="delivery-form">
        #     #   <input type="text" name="delivery[customer_name]" id="delivery-customer-name" value="">
        #     #   <input type="text" name="delivery[address][street]" id="delivery-address-street" value="">
        #     #
        #     #   <button type="submit">Create</button>
        #     # </form>
        #
        # @example Multiple levels of nesting
        #   <%=
        #     form_for :delivery, routes.deliveries_path do
        #       text_field :customer_name
        #
        #       fields_for :address do
        #         text_field :street
        #
        #         fields_for :location do
        #           text_field :city
        #           text_field :country
        #         end
        #       end
        #
        #       submit 'Create'
        #     end
        #   %>
        #
        #   Output:
        #     # <form action="/deliveries" method="POST" accept-charset="utf-8" id="delivery-form">
        #     #   <input type="text" name="delivery[customer_name]" id="delivery-customer-name" value="">
        #     #   <input type="text" name="delivery[address][street]" id="delivery-address-street" value="">
        #     #   <input type="text" name="delivery[address][location][city]" id="delivery-address-location-city" value="">
        #     #   <input type="text" name="delivery[address][location][country]" id="delivery-address-location-country" value="">
        #     #
        #     #   <button type="submit">Create</button>
        #     # </form>
        def fields_for(name)
          current_name = @name
          @name        = _input_name(name)
          yield
        ensure
          @name = current_name
        end

        # Label tag
        #
        # The first param <tt>content</tt> can be a <tt>Symbol</tt> that represents
        # the target field (Eg. <tt>:extended_title</tt>), or a <tt>String</tt>
        # which is used as it is.
        #
        # @param content [Symbol,String] the field name or a content string
        # @param attributes [Hash] HTML attributes to pass to the label tag
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     label :extended_title
        #   %>
        #
        #  # Output:
        #  #  <label for="book-extended-title">Extended title</label>
        #
        # @example Custom content
        #   <%=
        #     # ...
        #     label 'Title', for: :extended_title
        #   %>
        #
        #  # Output:
        #  #  <label for="book-extended-title">Title</label>
        #
        # @example Custom "for" attribute
        #   <%=
        #     # ...
        #     label :extended_title, for: 'ext-title'
        #   %>
        #
        #  # Output:
        #  #  <label for="ext-title">Extended title</label>
        #
        # @example Nested fields usage
        #   <%=
        #     # ...
        #     fields_for :address do
        #       label :city
        #       text_field :city
        #     end
        #   %>
        #
        #  # Output:
        #  #  <label for="delivery-address-city">City</label>
        #  #  <input type="text" name="delivery[address][city] id="delivery-address-city" value="">
        def label(content, attributes = {})
          attributes = { for: _for(content, attributes.delete(:for)) }.merge(attributes)
          content    = case content
                       when String, Hanami::Utils::String
                         content
                       else
                         Utils::String.new(content).capitalize
                       end

          super(content, attributes)
        end

        # Check box
        #
        # It renders a check box input.
        #
        # When a form is submitted, browsers don't send the value of unchecked
        # check boxes. If an user unchecks a check box, their browser won't send
        # the unchecked value. On the server side the corresponding value is
        # missing, so the application will assume that the user action never
        # happened.
        #
        # To solve this problem the form renders a hidden field with the
        # "unchecked value". When the user unchecks the input, the browser will
        # ignore it, but it will still send the value of the hidden input. See
        # the examples below.
        #
        # When editing a resource, the form automatically assigns the
        # <tt>checked="checked"</tt> attribute.
        #
        # @param name [Symbol] the input name
        # @param attributes [Hash] HTML attributes to pass to the input tag
        # @option attributes [String] :checked_value (defaults to "1")
        # @option attributes [String] :unchecked_value (defaults to "0")
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     check_box :free_shipping
        #   %>
        #
        #   # Output:
        #   #  <input type="hidden" name="delivery[free_shipping]" value="0">
        #   #  <input type="checkbox" name="delivery[free_shipping]" id="delivery-free-shipping" value="1">
        #
        # @example Specify (un)checked values
        #   <%=
        #     check_box :free_shipping, checked_value: 'true', unchecked_value: 'false'
        #   %>
        #
        #   # Output:
        #   #  <input type="hidden" name="delivery[free_shipping]" value="false">
        #   #  <input type="checkbox" name="delivery[free_shipping]" id="delivery-free-shipping" value="true">
        #
        # @example Automatic "checked" attribute
        #   # For this example the params are:
        #   #
        #   #  { delivery: { free_shipping: '1' } }
        #   <%=
        #     check_box :free_shipping
        #   %>
        #
        #   # Output:
        #   #  <input type="hidden" name="delivery[free_shipping]" value="0">
        #   #  <input type="checkbox" name="delivery[free_shipping]" id="delivery-free-shipping" value="1" checked="checked">
        #
        # @example Force "checked" attribute
        #   # For this example the params are:
        #   #
        #   #  { delivery: { free_shipping: '0' } }
        #   <%=
        #     check_box :free_shipping, checked: 'checked'
        #   %>
        #
        #   # Output:
        #   #  <input type="hidden" name="delivery[free_shipping]" value="0">
        #   #  <input type="checkbox" name="delivery[free_shipping]" id="delivery-free-shipping" value="1" checked="checked">
        #
        # @example Multiple check boxes
        #   <%=
        #     check_box :languages, name: 'book[languages][]', value: 'italian', id: nil
        #     check_box :languages, name: 'book[languages][]', value: 'english', id: nil
        #   %>
        #
        #   # Output:
        #   #  <input type="checkbox" name="book[languages][]" value="italian">
        #   #  <input type="checkbox" name="book[languages][]" value="english">
        #
        # @example Automatic "checked" attribute for multiple check boxes
        #   # For this example the params are:
        #   #
        #   #  { book: { languages: ['italian'] } }
        #   <%=
        #     check_box :languages, name: 'book[languages][]', value: 'italian', id: nil
        #     check_box :languages, name: 'book[languages][]', value: 'english', id: nil
        #   %>
        #
        #   # Output:
        #   #  <input type="checkbox" name="book[languages][]" value="italian" checked="checked">
        #   #  <input type="checkbox" name="book[languages][]" value="english">
        def check_box(name, attributes = {})
          _hidden_field_for_check_box(name, attributes)
          input _attributes_for_check_box(name, attributes)
        end

        # Color input
        #
        # @param name [Symbol] the input name
        # @param attributes [Hash] HTML attributes to pass to the input tag
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     color_field :background
        #   %>
        #
        #   # Output:
        #   #  <input type="color" name="user[background]" id="user-background" value="">
        def color_field(name, attributes = {})
          input _attributes(:color, name, attributes)
        end

        # Date input
        #
        # @param name [Symbol] the input name
        # @param attributes [Hash] HTML attributes to pass to the input tag
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     date_field :birth_date
        #   %>
        #
        #   # Output:
        #   #  <input type="date" name="user[birth_date]" id="user-birth-date" value="">
        def date_field(name, attributes = {})
          input _attributes(:date, name, attributes)
        end

        # Datetime input
        #
        # @param name [Symbol] the input name
        # @param attributes [Hash] HTML attributes to pass to the input tag
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     datetime_field :delivered_at
        #   %>
        #
        #   # Output:
        #   #  <input type="datetime" name="delivery[delivered_at]" id="delivery-delivered-at" value="">
        def datetime_field(name, attributes = {})
          input _attributes(:datetime, name, attributes)
        end

        # Datetime Local input
        #
        # @param name [Symbol] the input name
        # @param attributes [Hash] HTML attributes to pass to the input tag
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     datetime_local_field :delivered_at
        #   %>
        #
        #   # Output:
        #   #  <input type="datetime-local" name="delivery[delivered_at]" id="delivery-delivered-at" value="">
        def datetime_local_field(name, attributes = {})
          input _attributes(:'datetime-local', name, attributes)
        end

        # Email input
        #
        # @param name [Symbol] the input name
        # @param attributes [Hash] HTML attributes to pass to the input tag
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     email_field :email
        #   %>
        #
        #   # Output:
        #   #  <input type="email" name="user[email]" id="user-email" value="">
        def email_field(name, attributes = {})
          input _attributes(:email, name, attributes)
        end

        # Hidden input
        #
        # @param name [Symbol] the input name
        # @param attributes [Hash] HTML attributes to pass to the input tag
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     hidden_field :customer_id
        #   %>
        #
        #   # Output:
        #   #  <input type="hidden" name="delivery[customer_id]" id="delivery-customer-id" value="">
        def hidden_field(name, attributes = {})
          input _attributes(:hidden, name, attributes)
        end

        # File input
        #
        # PLEASE REMEMBER TO ADD <tt>enctype: 'multipart/form-data'</tt> ATTRIBUTE TO THE FORM
        #
        # @param name [Symbol] the input name
        # @param attributes [Hash] HTML attributes to pass to the input tag
        # @option attributes [String,Array] :accept Optional set of accepted MIME Types
        # @option attributes [TrueClass,FalseClass] :multiple Optional, allow multiple file upload
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     file_field :avatar
        #   %>
        #
        #   # Output:
        #   #  <input type="file" name="user[avatar]" id="user-avatar">
        #
        # @example Accepted mime types
        #   <%=
        #     # ...
        #     file_field :resume, accept: 'application/pdf,application/ms-word'
        #   %>
        #
        #   # Output:
        #   #  <input type="file" name="user[resume]" id="user-resume" accept="application/pdf,application/ms-word">
        #
        # @example Accepted mime types (as array)
        #   <%=
        #     # ...
        #     file_field :resume, accept: ['application/pdf', 'application/ms-word']
        #   %>
        #
        #   # Output:
        #   #  <input type="file" name="user[resume]" id="user-resume" accept="application/pdf,application/ms-word">
        #
        # @example Accepted multiple file upload (as array)
        #   <%=
        #     # ...
        #     file_field :resume, multiple: true
        #   %>
        #
        #   # Output:
        #   #  <input type="file" name="user[resume]" id="user-resume" multiple="multiple">
        def file_field(name, attributes = {})
          attributes[:accept] = Array(attributes[:accept]).join(ACCEPT_SEPARATOR) if attributes.key?(:accept)
          attributes = { type: :file, name: _input_name(name), id: _input_id(name) }.merge(attributes)

          input(attributes)
        end

        # Number input
        #
        # @param name [Symbol] the input name
        # @param attributes [Hash] HTML attributes to pass to the number input
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     number_field :percent_read
        #   %>
        #
        #   # Output:
        #   #  <input type="number" name="book[percent_read]" id="book-percent-read" value="">
        #
        # You can also make use of the 'max', 'min', and 'step' attributes for
        # the HTML5 number field.
        #
        # @example Advanced attributes
        #   <%=
        #     # ...
        #     number_field :priority, min: 1, max: 10, step: 1
        #   %>
        #
        #   # Output:
        #   #  <input type="number" name="book[percent_read]" id="book-precent-read" value="" min="1" max="10" step="1">
        def number_field(name, attributes = {})
          input _attributes(:number, name, attributes)
        end

        # Text-area input
        #
        # @param name [Symbol] the input name
        # @param content [String] the content of the textarea
        # @param attributes [Hash] HTML attributes to pass to the textarea tag
        #
        # @since 0.2.5
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     text_area :hobby
        #   %>
        #
        #   # Output:
        #   #  <textarea name="user[hobby]" id="user-hobby"></textarea>
        #
        # @example Set content
        #   <%=
        #     # ...
        #     text_area :hobby, 'Football'
        #   %>
        #
        #   # Output:
        #   #  <textarea name="user[hobby]" id="user-hobby">Football</textarea>
        #
        # @example Set content and HTML attributes
        #   <%=
        #     # ...
        #     text_area :hobby, 'Football', class: 'form-control'
        #   %>
        #
        #   # Output:
        #   #  <textarea name="user[hobby]" id="user-hobby" class="form-control">Football</textarea>
        #
        # @example Omit content and specify HTML attributes
        #   <%=
        #     # ...
        #     text_area :hobby, class: 'form-control'
        #   %>
        #
        #   # Output:
        #   #  <textarea name="user[hobby]" id="user-hobby" class="form-control"></textarea>
        #
        # @example Force blank value
        #   <%=
        #     # ...
        #     text_area :hobby, '', class: 'form-control'
        #   %>
        #
        #   # Output:
        #   #  <textarea name="user[hobby]" id="user-hobby" class="form-control"></textarea>
        def text_area(name, content = nil, attributes = {})
          if content.respond_to?(:to_hash)
            attributes = content
            content    = nil
          end

          attributes = { name: _input_name(name), id: _input_id(name) }.merge(attributes)
          textarea(content || _value(name), attributes)
        end

        # Text input
        #
        # @param name [Symbol] the input name
        # @param attributes [Hash] HTML attributes to pass to the input tag
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     text_field :first_name
        #   %>
        #
        #   # Output:
        #   #  <input type="text" name="user[first_name]" id="user-first-name" value="">
        def text_field(name, attributes = {})
          input _attributes(:text, name, attributes)
        end
        alias input_text text_field

        # Radio input
        #
        # If request params have a value that corresponds to the given value,
        # it automatically sets the <tt>checked</tt> attribute.
        # This Hanami::Controller integration happens without any developer intervention.
        #
        # @param name [Symbol] the input name
        # @param value [String] the input value
        # @param attributes [Hash] HTML attributes to pass to the input tag
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     radio_button :category, 'Fiction'
        #     radio_button :category, 'Non-Fiction'
        #   %>
        #
        #   # Output:
        #   #  <input type="radio" name="book[category]" value="Fiction">
        #   #  <input type="radio" name="book[category]" value="Non-Fiction">
        #
        # @example Automatic checked value
        #   # Given the following params:
        #   #
        #   # book: {
        #   #   category: 'Non-Fiction'
        #   # }
        #
        #   <%=
        #     # ...
        #     radio_button :category, 'Fiction'
        #     radio_button :category, 'Non-Fiction'
        #   %>
        #
        #   # Output:
        #   #  <input type="radio" name="book[category]" value="Fiction">
        #   #  <input type="radio" name="book[category]" value="Non-Fiction" checked="checked">
        def radio_button(name, value, attributes = {})
          attributes = { type: :radio, name: _input_name(name), value: value }.merge(attributes)
          attributes[:checked] = CHECKED if _value(name) == value
          input(attributes)
        end

        # Password input
        #
        # @param name [Symbol] the input name
        # @param attributes [Hash] HTML attributes to pass to the input tag
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     password_field :password
        #   %>
        #
        #   # Output:
        #   #  <input type="password" name="signup[password]" id="signup-password" value="">
        def password_field(name, attributes = {})
          input({ type: :password, name: _input_name(name), id: _input_id(name), value: nil }.merge(attributes))
        end

        # Select input
        #
        # @param name [Symbol] the input name
        # @param values [Hash] a Hash to generate <tt><option></tt> tags.
        #   Values correspond to <tt>value</tt> and keys correspond to the content.
        # @param attributes [Hash] HTML attributes to pass to the input tag
        #
        # If request params have a value that corresponds to one of the given values,
        # it automatically sets the <tt>selected</tt> attribute on the <tt><option></tt> tag.
        # This Hanami::Controller integration happens without any developer intervention.
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     values = Hash['Italy' => 'it', 'United States' => 'us']
        #     select :stores, values
        #   %>
        #
        #   # Output:
        #   #  <select name="book[store]" id="book-store">
        #   #    <option value="it">Italy</option>
        #   #    <option value="us">United States</option>
        #   #  </select>
        #
        # @example Automatic selected option
        #   # Given the following params:
        #   #
        #   # book: {
        #   #   store: 'it'
        #   # }
        #
        #   <%=
        #     # ...
        #     values = Hash['it' => 'Italy', 'us' => 'United States']
        #     select :stores, values
        #   %>
        #
        #   # Output:
        #   #  <select name="book[store]" id="book-store">
        #   #    <option value="it" selected="selected">Italy</option>
        #   #    <option value="us">United States</option>
        #   #  </select>
        #
        # @example Prompt option
        #   <%=
        #     # ...
        #     values = Hash['it' => 'Italy', 'us' => 'United States']
        #     select :stores, values, options: {prompt: 'Select a store'}
        #   %>
        #
        #   # Output:
        #   #  <select name="book[store]" id="book-store">
        #   #    <option>Select a store</option>
        #   #    <option value="it">Italy</option>
        #   #    <option value="us">United States</option>
        #   #  </select>
        #
        # @example Selected option
        #   <%=
        #     # ...
        #     values = Hash['it' => 'Italy', 'us' => 'United States']
        #     select :stores, values, options: {selected: book.store}
        #   %>
        #
        #   # Output:
        #   #  <select name="book[store]" id="book-store">
        #   #    <option value="it" selected="selected">Italy</option>
        #   #    <option value="us">United States</option>
        #   #  </select>
        #
        # @example Multiple select
        #   <%=
        #     # ...
        #     values = Hash['it' => 'Italy', 'us' => 'United States']
        #     select :stores, values, multiple: true
        #   %>
        #
        #   # Output:
        #   # <select name="book[store][]" id="book-store" multiple="multiple">
        #   #   <option value="it">Italy</option>
        #   #    <option value="us">United States</option>
        #   #  </select>
        def select(name, values, attributes = {}) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          options    = attributes.delete(:options) { {} }
          attributes = { name: _select_input_name(name, attributes[:multiple]), id: _input_id(name) }.merge(attributes)
          prompt     = options.delete(:prompt)
          selected   = options.delete(:selected)

          super(attributes) do
            option(prompt) unless prompt.nil?

            values.each do |content, value|
              if _select_option_selected?(value, selected, _value(name), attributes[:multiple])
                option(content, { value: value, selected: SELECTED }.merge(options))
              else
                option(content, { value: value }.merge(options))
              end
            end
          end
        end

        # Datalist input
        #
        # @param name [Symbol] the input name
        # @param values [Array,Hash] a collection that is transformed into <tt><option></tt> tags.
        # @param list [String] the name of list for the text input, it's also the id of datalist
        # @param attributes [Hash] HTML attributes to pass to the input tag
        #
        # @since 0.4.0
        #
        # @example Basic Usage
        #   <%=
        #     # ...
        #     values = ['Italy', 'United States']
        #     datalist :stores, values, 'books'
        #   %>
        #
        #   # Output:
        #   #  <input type="text" name="book[store]" id="book-store" value="" list="books">
        #   #  <datalist id="books">
        #   #    <option value="Italy"></option>
        #   #    <option value="United States"></option>
        #   #  </datalist>
        #
        # @example Options As Hash
        #   <%=
        #     # ...
        #     values = Hash['Italy' => 'it', 'United States' => 'us']
        #     datalist :stores, values, 'books'
        #   %>
        #
        #   # Output:
        #   #  <input type="text" name="book[store]" id="book-store" value="" list="books">
        #   #  <datalist id="books">
        #   #    <option value="Italy">it</option>
        #   #    <option value="United States">us</option>
        #   #  </datalist>
        #
        # @example Specify Custom Attributes For Datalist Input
        #   <%=
        #     # ...
        #     values = ['Italy', 'United States']
        #     datalist :stores, values, 'books', datalist: { class: 'form-control' }
        #   %>
        #
        #   # Output:
        #   #  <input type="text" name="book[store]" id="book-store" value="" list="books">
        #   #  <datalist id="books" class="form-control">
        #   #    <option value="Italy"></option>
        #   #    <option value="United States"></option>
        #   #  </datalist>
        #
        # @example Specify Custom Attributes For Options List
        #   <%=
        #     # ...
        #     values = ['Italy', 'United States']
        #     datalist :stores, values, 'books', options: { class: 'form-control' }
        #   %>
        #
        #   # Output:
        #   #  <input type="text" name="book[store]" id="book-store" value="" list="books">
        #   #  <datalist id="books">
        #   #    <option value="Italy" class="form-control"></option>
        #   #    <option value="United States" class="form-control"></option>
        #   #  </datalist>
        def datalist(name, values, list, attributes = {}) # rubocop:disable Metrics/MethodLength
          attrs    = attributes.dup
          options  = attrs.delete(:options)  || {}
          datalist = attrs.delete(:datalist) || {}

          attrs[:list]  = list
          datalist[:id] = list

          text_field(name, attrs)
          super(datalist) do
            values.each do |value, content|
              option(content, { value: value }.merge(options))
            end
          end
        end

        # Submit button
        #
        # @param content [String] The content
        # @param attributes [Hash] HTML attributes to pass to the button tag
        #
        # @since 0.2.0
        #
        # @example Basic usage
        #   <%=
        #     # ...
        #     submit 'Create'
        #   %>
        #
        #   # Output:
        #   #  <button type="submit">Create</button>
        def submit(content, attributes = {})
          attributes = { type: :submit }.merge(attributes)
          button(content, attributes)
        end

        protected

        # A set of options to pass to the sub form helpers.
        #
        # @api private
        # @since 0.2.0
        def options
          Hash[name: @name, values: @values, verb: @verb, csrf_token: @csrf_token]
        end

        private

        # Check the current builder is top-level
        #
        # @api private
        # @since 0.2.0
        def toplevel?
          @attributes.any?
        end

        # Prepare for method override
        #
        # @api private
        # @since 0.2.0
        def _method_override!
          if BROWSER_METHODS.include?(@verb_method)
            @attributes[:method] = @verb_method
          else
            @attributes[:method] = DEFAULT_METHOD
            @verb                = @verb_method
          end
        end

        # Return the method from attributes
        #
        # @api private
        def verb_method
          (@attributes.fetch(:method) { DEFAULT_METHOD }).to_s.upcase
        end

        # Return CSRF Protection token from view context
        #
        # @api private
        # @since 0.2.0
        def csrf_token
          @context.csrf_token if @context.respond_to?(:csrf_token) && !EXCLUDED_CSRF_METHODS.include?(@verb_method)
        end

        # Return a set of default HTML attributes
        #
        # @api private
        # @since 0.2.0
        def _attributes(type, name, attributes)
          { type: type, name: _input_name(name), id: _input_id(name), value: _value(name) }.merge(attributes)
        end

        # Input <tt>name</tt> HTML attribute
        #
        # @api private
        # @since 0.2.0
        def _input_name(name)
          "#{@name}[#{name}]"
        end

        # Input <tt>id</tt> HTML attribute
        #
        # @api private
        # @since 0.2.0
        def _input_id(name)
          name = _input_name(name).gsub(/\[(?<token>[[[:word:]]\-]*)\]/, INPUT_ID_REPLACEMENT)
          Utils::String.new(name).dasherize
        end

        # Input <tt>value</tt> HTML attribute
        #
        # @api private
        # @since 0.2.0
        def _value(name)
          @values.get(
            *_input_name(name).split(/[\[\]]+/).map(&:to_sym)
          )
        end

        # Input <tt>for</tt> HTML attribute
        #
        # @api private
        # @since 0.2.0
        def _for(content, name)
          case name
          when String, Hanami::Utils::String
            name
          else
            _input_id(name || content)
          end
        end

        # Hidden field for check box
        #
        # @api private
        # @since 0.2.0
        #
        # @see Hanami::Helpers::FormHelper::FormBuilder#check_box
        def _hidden_field_for_check_box(name, attributes)
          return unless attributes[:value].nil? || !attributes[:unchecked_value].nil?

          input(
            type:  :hidden,
            name:  attributes[:name] || _input_name(name),
            value: attributes.delete(:unchecked_value) || DEFAULT_UNCHECKED_VALUE
          )
        end

        # HTML attributes for check box
        #
        # @api private
        # @since 0.2.0
        #
        # @see Hanami::Helpers::FormHelper::FormBuilder#check_box
        def _attributes_for_check_box(name, attributes)
          attributes = {
            type:  :checkbox,
            name:  _input_name(name),
            id:    _input_id(name),
            value: attributes.delete(:checked_value) || DEFAULT_CHECKED_VALUE
          }.merge(attributes)

          attributes[:checked] = CHECKED if _check_box_checked?(attributes[:value], _value(name))

          attributes
        end

        def _select_input_name(name, multiple)
          select_name = _input_name(name)
          select_name = "#{select_name}[]" if multiple
          select_name
        end

        # TODO: this has to be refactored
        #
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def _select_option_selected?(value, selected, input_value, multiple)
          value == selected || (multiple && (selected.is_a?(Array) && selected.include?(value))) ||
            value == input_value || (multiple && (input_value.is_a?(Array) && input_value.include?(value)))
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/CyclomaticComplexity

        def _check_box_checked?(value, input_value)
          !input_value.nil? &&
            (input_value.to_s == value.to_s || input_value.is_a?(TrueClass) ||
            input_value.is_a?(Array) && input_value.include?(value))
        end
      end
    end
  end
end
