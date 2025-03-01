require_relative 'dataset/transform_items'

module Rom
  module Dynamo
    class Dataset
      include Enumerable
      include Dry::Equalizer(:name, :connection)
      extend Dry::Initializer[undefined: false]

      EmptyQuery = { key_conditions: {}.freeze }.freeze

      option :connection
      option :name, proc(&:to_s)
      option :table_keys, optional: true, reader: false
      option :query, default: proc { EmptyQuery }, reader: false
      option :transform_items, default: proc { Rom::Dynamo::Dataset::TransformItems.new }, reader: false

      ######### ENUMERATE ###########

      def each(&block)
        return enum_for(:each) if block.nil?
        each_page do |page|
          items = @transform_items.call(page.items)
          items.each(&block)
        end
      end

      def each_page(&block)
        return enum_for(:each_page) if block.nil?
        result = start_query(consistent_read: true)
        result.each_page(&block)
      end

      ############# QUERY #############

      def restrict(query = nil)
        return self if query.nil?
        dup_with_query(self.class, query)
      end

      def batch_restrict(keys)
        dup_as(BatchGetDataset, keys: keys.map do |k|
          Hash[table_keys.zip(k.is_a?(Array) ? k : [k])]
        end)
      end

      def index_restrict(index, query)
        dup_with_query(GlobalIndexDataset, query, index_name: index.to_s)
      end

      ############# PAGINATE #############

      def limit(limit)
        opts = limit.nil? ? {} : { limit: limit.to_i }
        dup_with_query(self.class, nil, opts)
      end

      def offset(key)
        opts = key.nil? ? {} : { exclusive_start_key: key }
        dup_with_query(self.class, nil, opts)
      end

      def reversed
        dup_with_query(self.class, nil, scan_index_forward: false)
      end

      ############# WRITE #############
      def insert(hash)
        opts = { table_name: name, item: stringify_keys(hash), condition_expression: condition_expression }
        connection.put_item(opts)
      end

      def delete(hash)
        hash = stringify_keys(hash)
        opts = {
          table_name: name,
          key: hash_to_key(hash),
          expected: to_expected(hash)
        }
        connection.delete_item(opts).attributes
      end

      def update(keys, hash)
        opts = {
          table_name: name, 
          key: hash_to_key(stringify_keys(keys)),
          return_values: 'ALL_NEW',
          attribute_updates: hash.each_with_object({}) do |(k, v), out|
            out[k] = { value: v, action: 'PUT' }
          end
        }
        item = connection.update_item(opts).attributes
        @transform_items.call([item]).first
      end

      def increment(keys, hash)
        opts = {
          table_name: name, 
          key: hash_to_key(stringify_keys(keys)),
          return_values: 'ALL_NEW',
          attribute_updates: hash.each_with_object({}) do |(k, v), out|
            out[k] = { value: v, action: 'ADD' }
          end
        }
        item = connection.update_item(opts).attributes
        @transform_items.call([item]).first
      end

      ############# HELPERS #############
    private

    def condition_expression
      raise "support for composite keys not in place yet" if table_keys.size > 1
      "attribute_not_exists(#{table_keys.first})"
    end

      def batch_get_each_page(keys, &block)
        !keys.empty? && connection.batch_get_item({
          request_items: { name => { keys: keys } },
        }).each_page do |page|
          block.call(page[:responses][name])
        end
      end

      def dup_with_query(klass, key_hash, opts = {})
        opts = @query.merge(opts)

        if key_hash && !key_hash.empty?
          conditions = @query[:key_conditions]
          opts[:key_conditions] = conditions.merge(Hash[
            key_hash.map do |key, value|
              [key, {
                attribute_value_list: [value],
                comparison_operator:  "EQ"
              }]
            end
          ]).freeze
        end

        dup_as(klass, query: opts.freeze)
      end

      def to_expected(hash)
        hash && Hash[hash.map do |k, v|
          [k, { value: v }]
        end]
      end

      def hash_to_key(hash)
        table_keys.each_with_object({}) do |k, out|
          out[k] = hash[k] if hash.has_key?(k)
        end
      end

      def table_keys
        @table_keys ||= begin
          r = connection.describe_table(table_name: name)
          r[:table][:key_schema].map(&:attribute_name)
        end
      end

      def start_query(opts = {}, &block)
        opts = @query.merge(table_name: name).merge!(opts)
        # puts "Querying DDB: #{opts.inspect}"
        connection.query(opts)
      end

      def dup_as(klass, opts = {})
        table_keys # To populate keys once at top-level Dataset
        attrs = Dataset.dry_initializer.attributes(self)
        klass.new(**attrs.merge(opts))
      end

      # String modifiers
      def stringify_keys(hash)
        hash.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
      end
    end

    # Batch get using an array of key queries
    # [{ key => val }, { key => val }, ...]
    class BatchGetDataset < Dataset
      option :keys

      # Query for records
      def each_page(&block)
        return enum_for(:each_page) if block.nil?
        batch_get_each_page(@keys) do |items|
          klass = Aws::DynamoDB::Types::QueryOutput
          block.call(klass.new(items: items, count: items.size))
        end
      end
    end

    # Dataset queried via a Global Secondary Index
    # Paginate through keys from Global Index and
    # call BatchGetItem for keys from each page
    class GlobalIndexDataset < Dataset
      def each_page(&block)
        return enum_for(:each_page) if block.nil?
        if @query[:limit]
          block.call(populated_results(start_query))
        else
          start_query(limit: 100).each_page do |p|
            block.call(populated_results(p))
          end
        end
      end

      private def populated_results(result, &block)
        klass = Aws::DynamoDB::Types::QueryOutput
        keys = result.items.map { |h| hash_to_key(h) }
        klass.new(result.to_hash.merge(items: [].tap do |out|
          batch_get_each_page(keys) { |i| out.concat(i) }
        end))
      end

    end
  end
end
