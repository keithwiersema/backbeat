require 'grape'
require 'backbeat/web/middleware/log'
require 'backbeat/web/middleware/health'
require 'backbeat/web/middleware/heartbeat'
require 'backbeat/web/middleware/sidekiq_stats'
require 'backbeat/web/middleware/camel_json_formatter'
require 'backbeat/web/middleware/authenticate'
require 'backbeat/web/middleware/camel_case'
require 'backbeat/web/events_api'
require 'backbeat/web/workflows_api'
require 'backbeat/web/debug_api'

module Backbeat
  class API < Grape::API
    format :json

    before do
      HashKeyTransformations.underscore_keys(params)
    end

    rescue_from :all do |e|
      Logger.error({error_type: e.class, error: e.message, backtrace: e.backtrace})
      Rack::Response.new({error: e.message }.to_json, 500, { "Content-type" => "application/json" }).finish
    end

    rescue_from ActiveRecord::RecordNotFound do |e|
      Logger.info(e)
      Rack::Response.new({error: e.message }.to_json, 404, { "Content-type" => "application/json" }).finish
    end

    RESCUED_ERRORS = [
      WorkflowComplete,
      Grape::Exceptions::Validation,
      Grape::Exceptions::ValidationErrors
    ]

    rescue_from *RESCUED_ERRORS do |e|
      Logger.info(e)
      Rack::Response.new({ error: e.message }.to_json, 400, { "Content-type" => "application/json" }).finish
    end

    rescue_from Backbeat::InvalidServerStatusChange do |e|
      Logger.info(e)
      Rack::Response.new({ error: e.message }.to_json, 500, { "Content-type" => "application/json" }).finish
    end

    rescue_from Backbeat::InvalidClientStatusChange do |e|
      Logger.info(e)
      Rack::Response.new(e.data.merge(error: e.message).to_json, 409, { "Content-type" => "application/json" }).finish
    end

    mount Web::WorkflowsApi
    mount Web::EventsApi
    mount Web::WorkflowEventsApi
    mount Web::DebugApi
  end
end