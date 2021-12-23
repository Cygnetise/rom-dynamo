require 'addressable/uri'
require 'rom/gateway'

module Rom
  module Dynamo
    class Gateway < ROM::Gateway
      attr_reader :datasets, :connection

      def initialize(connection)
        @connection = connection
        @datasets = {}
      end

      def dataset(name)
        name = "#{@prefix}#{name}"
        @datasets[name] ||= _has?(name) && Dataset.new(connection: @connection, name: name)
      end

      def dataset?(name)
        !!self[name]
      end

      def [](name)
        @datasets["#{@prefix}#{name}"]
      end

      private

      def _has?(name)
        @connection.describe_table(table_name: name)
      rescue Aws::DynamoDB::Errors::ResourceNotFoundException
        false
      end
    end
  end
end
