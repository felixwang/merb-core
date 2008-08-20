require 'tempfile'

module Merb
  module Test
    module RequestHelper
      # FakeRequest sets up a default enviroment which can be overridden either
      # by passing and env into initialize or using request['HTTP_VAR'] = 'foo'
      class FakeRequest < Request

        # ==== Parameters
        # env<Hash>:: Environment options that override the defaults.
        # req<StringIO>:: The request to set as input for Rack.
        def initialize(env = {}, req = StringIO.new)
          env.environmentize_keys!
          env['rack.input'] = req
          super(DEFAULT_ENV.merge(env))
        end

        private
        DEFAULT_ENV = Mash.new({
          'SERVER_NAME' => 'localhost',
          'PATH_INFO' => '/',
          'HTTP_ACCEPT_ENCODING' => 'gzip,deflate',
          'HTTP_USER_AGENT' => 'Mozilla/5.0 (Macintosh; U; PPC Mac OS X Mach-O; en-US; rv:1.8.0.1) Gecko/20060214 Camino/1.0',
          'SCRIPT_NAME' => '/',
          'SERVER_PROTOCOL' => 'HTTP/1.1',
          'HTTP_CACHE_CONTROL' => 'max-age=0',
          'HTTP_ACCEPT_LANGUAGE' => 'en,ja;q=0.9,fr;q=0.9,de;q=0.8,es;q=0.7,it;q=0.7,nl;q=0.6,sv;q=0.5,nb;q=0.5,da;q=0.4,fi;q=0.3,pt;q=0.3,zh-Hans;q=0.2,zh-Hant;q=0.1,ko;q=0.1',
          'HTTP_HOST' => 'localhost',
          'REMOTE_ADDR' => '127.0.0.1',
          'SERVER_SOFTWARE' => 'Mongrel 1.1',
          'HTTP_KEEP_ALIVE' => '300',
          'HTTP_REFERER' => 'http://localhost/',
          'HTTP_ACCEPT_CHARSET' => 'ISO-8859-1,utf-8;q=0.7,*;q=0.7',
          'HTTP_VERSION' => 'HTTP/1.1',
          'REQUEST_URI' => '/',
          'SERVER_PORT' => '80',
          'GATEWAY_INTERFACE' => 'CGI/1.2',
          'HTTP_ACCEPT' => 'text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5',
          'HTTP_CONNECTION' => 'keep-alive',
          'REQUEST_METHOD' => 'GET'
        }) unless defined?(DEFAULT_ENV)
      end

      # ==== Parameters
      # env<Hash>:: A hash of environment keys to be merged into the default list.
      # opt<Hash>:: A hash of options (see below).
      #
      # ==== Options (opt)
      # :post_body<String>:: The post body for the request.
      # :req<String>::
      #   The request string. This will only be used if :post_body is left out.
      #
      # ==== Returns
      # FakeRequest:: A Request object that is built based on the parameters.
      #
      # ==== Notes
      # If you pass a post body, the content-type will be set to URL-encoded.
      #
      #---
      # @public
      def fake_request(env = {}, opt = {})
        if opt[:post_body]
          req = opt[:post_body]
          env[:content_type] ||= "application/x-www-form-urlencoded"
        else
          req = opt[:req]
        end
        FakeRequest.new(env, StringIO.new(req || ''))
      end

      # ==== Parameters
      # session<SessionStore>:: A suitable Merb session store instance.
      # env<Hash>:: A hash of environment keys to be merged into the default list.
      # opt<Hash>:: A hash of options (see below).
      #
      # ==== Returns
      # FakeRequest:: A Request object that is built based on the parameters.
      def fake_request_with_session(session, env = {}, opt = {})
        fake_request(env.merge(Merb::Const::HTTP_COOKIE => "#{Merb::Config[:session_id_key]}=#{session.session_id}"), opt)
      end

      # Dispatches an action to the given class. This bypasses the router and is
      # suitable for unit testing of controllers.
      #
      # ==== Parameters
      # controller_klass<Controller>::
      #   The controller class object that the action should be dispatched to.
      # action<Symbol>:: The action name, as a symbol.
      # params<Hash>::
      #   An optional hash that will end up as params in the controller instance.
      # env<Hash>::
      #   An optional hash that is passed to the fake request. Any request options
      #   should go here (see +fake_request+), including :req or :post_body
      #   for setting the request body itself.
      # &blk::
      #   The controller is yielded to the block provided for actions *prior* to
      #   the action being dispatched.
      #
      # ==== Example
      #   dispatch_to(MyController, :create, :name => 'Homer' ) do |controller|
      #     controller.stub!(:current_user).and_return(@user)
      #   end
      #
      # ==== Notes
      # Does not use routes.
      #
      #---
      # @public
      def dispatch_to(controller_klass, action, params = {}, env = {}, &blk)
        params = merge_controller_and_action(controller_klass, action, params)
        dispatch_request(build_request(params, env), controller_klass, action.to_s, &blk)
      end

      # Dispatches an action to the given class and keeps track of the session_id. 
      # This bypasses the router and is suitable for unit testing of controllers.
      #
      # ==== Parameters
      # controller_klass<Controller>::
      #   The controller class object that the action should be dispatched to.
      # action<Symbol>:: The action name, as a symbol.
      # session<SessionStore>:: A suitable Merb session store instance.
      # params<Hash>::
      #   An optional hash that will end up as params in the controller instance.
      # env<Hash>::
      #   An optional hash that is passed to the fake request. Any request options
      #   should go here (see +fake_request+), including :req or :post_body
      #   for setting the request body itself.
      # &blk::
      #   The controller is yielded to the block provided for actions *prior* to
      #   the action being dispatched.
      #
      # ==== Example
      #   dispatch_to(MyController, :create, session, :name => 'Homer' ) do |controller|
      #     controller.stub!(:current_user).and_return(@user)
      #   end
      #
      # ==== Notes
      # Does not use routes.
      #
      #---
      # @public
      def dispatch_with_session_to(controller_klass, action, session, params = {}, env = {}, &blk)
        dispatch_to(controller_klass, action, params, env) do |controller|
          controller.cookies[controller.request._session_id_key] = session.session_id
          yield controller if block_given?
        end
      end

      # Dispatches an action to the given class and using HTTP Basic Authentication
      # This bypasses the router and is suitable for unit testing of controllers.
      #
      # ==== Parameters
      # controller_klass<Controller>::
      #   The controller class object that the action should be dispatched to.
      # action<Symbol>:: The action name, as a symbol.
      # username<String>:: The username.
      # password<String>:: The password.
      # params<Hash>::
      #   An optional hash that will end up as params in the controller instance.
      # env<Hash>::
      #   An optional hash that is passed to the fake request. Any request options
      #   should go here (see +fake_request+), including :req or :post_body
      #   for setting the request body itself.
      # &blk::
      #   The controller is yielded to the block provided for actions *prior* to
      #   the action being dispatched.
      #
      # ==== Example
      #   dispatch_with_basic_authentication_to(MyController, :create, 'Fred', 'secret', :name => 'Homer' ) do |controller|
      #     controller.stub!(:current_user).and_return(@user)
      #   end
      #
      # ==== Notes
      # Does not use routes.
      #
      #---
      # @public
      def dispatch_with_basic_authentication_to(controller_klass, action, username, password, params = {}, env = {}, &blk)
        env["X_HTTP_AUTHORIZATION"] = "Basic #{Base64.encode64("#{username}:#{password}")}"
        
        params = merge_controller_and_action(controller_klass, action, params)        
        dispatch_request(build_request(params, env), controller_klass, action.to_s, &blk)
      end
      
      def merge_controller_and_action(controller_klass, action, params)
        params[:controller] = controller_klass.name.to_const_path
        params[:action]     = action.to_s
        
        params
      end

      # Prepares and returns a request suitable for dispatching with
      # dispatch_request. If you don't need to modify the request
      # object before dispatching (e.g. to add cookies), you probably
      # want to use dispatch_to instead.
      #
      # ==== Parameters
      # params<Hash>::
      #   An optional hash that will end up as params in the controller instance.
      # env<Hash>::
      #   An optional hash that is passed to the fake request. Any request options
      #   should go here (see +fake_request+), including :req or :post_body
      #   for setting the request body itself.
      #
      # ==== Example
      #   req = build_request(:id => 1)
      #   req.cookies['app_cookie'] = "testing"
      #   dispatch_request(req, MyController, :edit)
      #
      # ==== Notes
      # Does not use routes.
      #
      #---
      # @public      
      def build_request(params = {}, env = {})
        params             = Merb::Request.params_to_query_string(params)
        env[:query_string] = env["QUERY_STRING"] ? "#{env["QUERY_STRING"]}&#{params}" : params
        
        fake_request(env, { :post_body => env[:post_body], :req => env[:req] })
      end

      # An HTTP GET request that operates through the router.
      #
      # ==== Parameters
      # path<String>:: The path that should go to the router as the request uri.
      # params<Hash>::
      #   An optional hash that will end up as params in the controller instance.
      # env<Hash>::
      #   An optional hash that is passed to the fake request. Any request options
      #   should go here (see +fake_request+).
      # &blk::
      #   The controller is yielded to the block provided for actions *prior* to
      #   the action being dispatched.
      #---
      # @public      
      def get(path, params = {}, env = {}, &block)
        env[:request_method] = "GET"
        request(path, params, env, &block)
      end

      # An HTTP POST request that operates through the router.
      #
      # ==== Parameters
      # path<String>:: The path that should go to the router as the request uri.
      # params<Hash>::
      #   An optional hash that will end up as params in the controller instance.
      # env<Hash>::
      #   An optional hash that is passed to the fake request. Any request options
      #   should go here (see fake_request).
      # &blk::
      #   The controller is yielded to the block provided for actions *prior* to
      #   the action being dispatched.
      #---
      # @public      
      def post(path, params = {}, env = {}, &block)
        env[:request_method] = "POST"
        request(path, params, env, &block)
      end

      # An HTTP PUT request that operates through the router.
      #
      # ==== Parameters
      # path<String>:: The path that should go to the router as the request uri.
      # params<Hash>::
      #   An optional hash that will end up as params in the controller instance.
      # env<Hash>::
      #   An optional hash that is passed to the fake request. Any request options
      #   should go here (see fake_request).
      # &blk::
      #   The controller is yielded to the block provided for actions *prior* to
      #   the action being dispatched.
      #---
      # @public      
      def put(path, params = {}, env = {}, &block)
        env[:request_method] = "PUT"
        request(path, params, env, &block)
      end

      # An HTTP DELETE request that operates through the router
      #
      # ==== Parameters
      # path<String>:: The path that should go to the router as the request uri.
      # params<Hash>::
      #   An optional hash that will end up as params in the controller instance.
      # env<Hash>::
      #   An optional hash that is passed to the fake request. Any request options
      #   should go here (see fake_request).
      # &blk::
      #   The controller is yielded to the block provided for actions *prior* to
      #   the action being dispatched.
      #---
      # @public
      def delete(path, params = {}, env = {}, &block)
        env[:request_method] = "DELETE"
        request(path, params, env, &block)
      end

      # A generic request that checks the router for the controller and action.
      # This request goes through the Merb::Router and finishes at the controller.
      #
      # ==== Parameters
      # path<String>:: The path that should go to the router as the request uri.
      # params<Hash>::
      #   An optional hash that will end up as params in the controller instance.
      # env<Hash>::
      #   An optional hash that is passed to the fake request. Any request options
      #   should go here (see +fake_request+).
      # &blk::
      #   The controller is yielded to the block provided for actions *prior* to
      #   the action being dispatched.
      #
      # ==== Example
      #   request(path, { :name => 'Homer' }, { :request_method => "PUT" }) do |controller|
      #     controller.stub!(:current_user).and_return(@user)
      #   end
      #
      # ==== Notes
      # Uses Routes.
      #
      #---
      # @semi-public
      def request(path, params = {}, env= {}, &block)
        env[:request_method] ||= "GET"
        env[:request_uri], env[:query_string] = path.split('?')
        
        multipart = env.delete(:test_with_multipart)

        request = fake_request(env)

        opts = check_request_for_route(request) # Check that the request will be routed correctly
        controller_name = (opts[:namespace] ? opts.delete(:namespace) + '/' : '') + opts.delete(:controller)
        klass = Object.full_const_get(controller_name.snake_case.to_const_string)
        
        action = opts.delete(:action).to_s
        params.merge!(opts)

        multipart.nil? ? dispatch_to(klass, action, params, env, &block) : dispatch_multipart_to(klass, action, params, env, &block)
      end


      # The workhorse for the dispatch*to helpers.
      #
      # ==== Parameters
      # request<Merb::Test::RequestHelper::FakeRequest, Merb::Request>::
      #   A request object that has been setup for testing.
      # controller_klass<Merb::Controller>::
      #   The class object off the controller to dispatch the action to.
      # action<Symbol>:: The action to dispatch the request to.
      # &blk::
      #   The controller is yielded to the block provided for actions *prior* to
      #   the action being dispatched.
      #
      # ==== Returns
      # An instance of +controller_klass+ based on the parameters.
      #
      # ==== Notes
      # Does not use routes.
      #
      #---
      # @public
      def dispatch_request(request, controller_klass, action, &blk)
        controller = controller_klass.new(request)
        yield controller if block_given?
        controller._dispatch(action)

        Merb.logger.info controller._benchmarks.inspect
        Merb.logger.flush

        controller
      end

      # Checks to see that a request is routable.
      #
      # ==== Parameters
      # request<Merb::Test::RequestHelper::FakeRequest, Merb::Request>::
      #   The request object to inspect.
      #
      # ==== Raises
      # Merb::ControllerExceptions::BadRequest::
      #   No matching route was found.
      #
      # ==== Returns
      # Hash:: The parameters built based on the matching route.
      #
      #---
      # @semi-public
      def check_request_for_route(request)
        match =  ::Merb::Router.match(request)
        if match[0].nil? && match[1].empty?
          raise ::Merb::ControllerExceptions::BadRequest, "No routes match the request"
        else
          match[1]
        end
      end # check_request_for_route
    end # RequestHelper
  end # Test
end # Merb
