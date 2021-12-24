require 'rom/commands'

module Rom
  module Dynamo
    module Commands
      # DynamoDB create command
      class Create < ROM::Commands::Create
        adapter :dynamodb

        use :schema

        after :finalize

        def execute(tuples)
          Array([tuples]).flatten.map do |tuple|
            attributes = input[tuple]
            dataset.insert(attributes)
            attributes
          end
        end

        def dataset
          relation.dataset
        end

        private

        def finalize(tuples)
          tuples.map { |t| relation.output_schema[t] }
        end
      end

      # DynamoDB update command
      class Update < ROM::Commands::Update
        adapter :dynamodb

        use :schema

        after :finalize

        def execute(params)
          attributes = input[params]
          relation.map do |tuple|
            dataset.update(tuple, attributes.to_h)
          end
        end

        def dataset
          relation.dataset
        end

        private

        def finalize(tuples)
          tuples.map { |t| relation.output_schema[t] }
        end
      end

      # DynamoDB delete command
      class Delete < ROM::Commands::Delete
        adapter :dynamodb

        use :schema

        def execute
          relation.to_a.tap do |tuples|
            tuples.each { |t| dataset.delete(input[t]) }
          end
        end

        def dataset
          relation.dataset
        end
      end

      class Increment < ROM::Commands::Update
        adapter :dynamo

        use :schema

        after :finalize

        def execute(params)
          relation.map do |tuple|
            dataset.increment(tuple, params)
          end
        end

        private

        def dataset
          relation.dataset
        end

        def finalize(tuples)
          tuples.map { |t| relation.output_schema[t] }
        end
      end
    end
  end
end
