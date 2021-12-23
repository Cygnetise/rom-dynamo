require 'rom'
require 'date'
require 'aws-sdk-dynamodb'
require 'rom/dynamo/version'
require 'rom/dynamo/dataset'
require 'rom/dynamo/relation'
require 'rom/dynamo/commands'
require 'rom/dynamo/gateway'

# Register adapter with ROM-rb
ROM.register_adapter(:dynamo, Rom::Dynamo)
