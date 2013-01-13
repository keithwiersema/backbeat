require 'grape'
require 'workflow_server'

module Api
  class Workflow < Grape::API
    format :json

    rescue_from :all do |e|
      Rack::Response.new({error: e.message }.to_json, 500, { "Content-type" => "application/json" }).finish
    end

    rescue_from WorkflowServer::EventNotFound do |e|
      Rack::Response.new({error: e.message }.to_json, 404, { "Content-type" => "application/json" }).finish
    end

    rescue_from WorkflowServer::EventComplete, WorkflowServer::InvalidParameters, WorkflowServer::InvalidEventStatus, WorkflowServer::InvalidDecisionSelection do |e|
      Rack::Response.new({error: e.message }.to_json, 400, { "Content-type" => "application/json" }).finish
    end

    helpers do
      def current_user
        @current_user ||= env['WORKFLOW_CURRENT_USER']
      end

      def find_workflow(id)
        wf = current_user.workflows.find(id)
        raise WorkflowServer::EventNotFound, "Workflow with id(#{id}) not found" unless wf
        wf
      end

      def find_event(event_id, workflow_id = nil, event_type = nil)
        event = nil
        if workflow_id
          wf = find_workflow(workflow_id)
          event_type ||= :events #all events
          event = wf.__send__(event_type).find(event_id)
          raise WorkflowServer::EventNotFound, "Event with id(#{event_id}) not found" unless event
        else
          event = WorkflowServer::Models::Event.find(event_id)
          unless event && event.workflow.user == current_user
            raise WorkflowServer::EventNotFound, "Event with id(#{event_id}) not found"
          end
        end
        event
      end
    end

    resource 'workflows' do
      post "/" do
        params[:user] = current_user
        wf = WorkflowServer::Manager.find_or_create_workflow(params)

        if wf.valid?
          wf
        else
          raise WorkflowServer::InvalidParameters, wf.errors.to_hash
        end
      end

      get "/:id" do
        find_workflow(params[:id])
      end

      [:flags, :signals, :activities, :timers, :events].each do |event_type|
        get "/:id/#{event_type}" do
          wf = find_workflow(params[:id])
          wf.__send__(event_type)
        end
      end

      post "/:id/signal/:name" do
        wf = find_workflow(params[:id])
        signal = wf.signal(params[:name])
        signal
      end


      segment '/:workflow_id' do
        resource 'events' do
          get "/:id" do
            find_event(params[:id], params[:workflow_id])
          end

          put "/:id/change_status" do
            event = find_event(params[:id], params[:workflow_id])
            event.change_status(params[:status], HashWithIndifferentAccess.new(JSON.parse(params[:args] || "{}")))
            {success: true}
          end

          put "/:id/run_sub_activity" do
            event = find_event(params[:id], params[:workflow_id], :activities)
            sub_activity = event.run_sub_activity(HashWithIndifferentAccess.new(JSON.parse(params[:sub_activity] || "{}")))
            if sub_activity.blocking?
              header("WAIT_FOR_SUB_ACTIVITY", "true")
            end
            sub_activity
          end
        end
      end
    end
    resource "events" do
      get "/:id" do
        find_event(params[:id])
      end
    end
  end
end