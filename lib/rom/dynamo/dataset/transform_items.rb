module Rom
  module Dynamo
    class Dataset
      class TransformItems < Transproc::Transformer
        import Transproc::ArrayTransformations
        import Transproc::HashTransformations

        define! do
          map_array do
            symbolize_keys
          end
        end
      end
    end
  end
end
