require "cono_storage/response"
require "cono_storage/request_methods"

module ConoStorage
  class Client

    include RequestMethods

    DEFAULT_HEADERS = {
      "Accept" => "application/json",
      "User-Agent" => "ConoStorage Ruby Gem v#{ConoStorage::VERSION}",
      "Content-Type" => "application/json"
    }

    # @param web_mode [Boolean] true でコンテナやオブジェクトを作成/更新すると公開状態になります。
    # @param auth_url [String]
    # @param tenant_id [String]
    # @param username [String]
    # @param password [String]
    # @param endpoint [String]
    def initialize(web_mode: false,
                   auth_url: , tenant_id: , username: , password: , endpoint: )
      @auth_url  = auth_url
      @web_mode  = web_mode
      @tenant_id = tenant_id
      @username  = username
      @password  = password
      @endpoint  = endpoint
    end

    %w( get head put delete post ).each do |method|
      class_eval <<-RUBY
        def #{method}(path, params, headers)
          request(:#{method}, path, params, headers)
        end
      RUBY
    end

    def upload(path, file, params, headers)
      if file.is_a?(String)
        file = File.open(file)
      end

      content_type = MimeMagic.by_magic(file).type

      io = Faraday::UploadIO.new(file, content_type)
      extra_headers = {
        'X-Detect-Content-Type' => 'True',
        'Transfer-Encoding' => 'chunked',
        'Content-Type' => content_type
      }
      path = path + '?' + params.to_query if params
      request(:put, path, io, extra_headers.merge(headers))
    end

    def prepare_token
      return if cached_token_avaiable?
      fetch_token
      File.write(cached_token_path, @token.to_json)
    end

    def cached_token_path
      File.join(File.dirname($0), ".#{@tenant_id}-#{@username}")
    end

    def cached_token_avaiable?
      return true  if valid_token? @token
      return false if !File.exist?(cached_token_path)

      token = JSON.parse File.read(cached_token_path)
      if valid_token? token
        @token = token
        true
      else
        false
      end
    end

    def valid_token?(token)
      token && Time.parse(token.fetch("expires")) >= Time.now
    end

    def fetch_token
      res = connection.post do |req|
        req.url @auth_url + '/tokens'
        req.body = auth_params.to_json
      end
      json = JSON.parse(res.body)
      @token = json['access']['token']
    end

    def auth_params
      {
        auth: {
          tenantId: @tenant_id,
          passwordCredentials: {
            username: @username,
            password: @password
          }
        }
      }
    end

    def default_headers
      headers = DEFAULT_HEADERS.clone
      headers['Content-Type'] = 'application/json'
      if @web_mode
        headers['X-Web-Mode'] = 'True'
        headers['X-Container-Read'] = '.r:*'
      end
      headers
    end

    def request(request_method, path, params, headers)
      prepare_token
      Response.new(
        connection.send(
          request_method,
          @endpoint + path,
          params,
          headers.merge('X-Auth-Token' => @token['id'])
        )
      )
    end

    def connection
      @connection ||= Faraday.new(headers: default_headers) do |connection|
        connection.request :json
        connection.adapter Faraday.default_adapter
      end
    end
  end
end
