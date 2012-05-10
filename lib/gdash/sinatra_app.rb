class GDash
  class SinatraApp < ::Sinatra::Base
    def enum_hosts(query_target)
	uri = '/metrics/find?'
	query = 'format=completer&query=' + query_target
	
	request_url = @graphite_base + uri + query
	puts request_url
	url = request_url
	uri = URI.parse(url)
	http = Net::HTTP::new(uri.host, uri.port)
	#http.use_ssl = false
	req = Net::HTTP::Get.new(uri.request_uri)
	response = http.request(req)
	response = JSON.parse(response.body)
	
	hosts = Array.new
	response.each_value { |arr|
	        arr.each{|host| hosts.push( host["name"]) }
	}
	
	hosts
    end


    def initialize(graphite_base, graph_templates, hosts_file, hosts_enum_metric, options = {})
      # where the whisper data is
      @whisper_dir = options.delete(:whisper_dir) || "/var/lib/carbon/whisper"

      # where graphite lives
      @graphite_base = graphite_base

      # where the graphite renderer is
      @graphite_render = [@graphite_base, "/render/"].join

      # where to find graph, dash etc templates
      @graph_templates = graph_templates

      # the dash site might have a prefix for its css etc
      @prefix = options.delete(:prefix) || ""

      # the page refresh rate
      @refresh_rate = options.delete(:refresh_rate) || 60

      # how many columns of graphs do you want on a page
      @graph_columns = options.delete(:graph_columns) || 2

      # how wide each graph should be
      @graph_width = options.delete(:graph_width)

      # how hight each graph sould be
      @graph_height = options.delete(:graph_height)

      # Dashboard title
      @dash_title = options.delete(:title) || "Graphite Dashboard"

      # Time filters in interface
      @interval_filters = options.delete(:interval_filters) || Array.new

      @intervals = options.delete(:intervals) || []

      hosts_file = File.dirname(__FILE__) + "/../../config/" + hosts_file
     if File.exists?(hosts_file)
      	#puts hosts_file
	@hosts = File.read(hosts_file).collect{|host| host.split(/\,/).collect{|h| h.strip.chomp} }.flatten	
     else
	@hosts = enum_hosts(hosts_enum_metric)
	puts @hosts.inspect
     end	
      
      @top_level = Hash.new
      Dir.entries(@graph_templates).each do |category|
        if File.directory?("#{@graph_templates}/#{category}")
          unless ("#{category}" =~ /^\./ )
            @top_level["#{category}"] = GDash.new(@graphite_base, "/render/", File.join(@graph_templates, "/#{category}"), {:width => @graph_width, :height => @graph_height})
          end
        end
      end

      super()
    end

    set :static, true
    set :views, File.join(File.expand_path(File.dirname(__FILE__)), "../..", "views")
    if Sinatra.const_defined?("VERSION") && Gem::Version.new(Sinatra::VERSION) >= Gem::Version.new("1.3.0")
      set :public_folder, File.join(File.expand_path(File.dirname(__FILE__)), "../..", "public")
    else
      set :public, File.join(File.expand_path(File.dirname(__FILE__)), "../..", "public")
    end

    get '/' do
      if @top_level.empty?
        @error = "No dashboards found in the templates directory"
      end

      erb :index
    end

    get '/:host' do
      if @top_level.empty?
        @error = "No dashboards found in the templates directory"
      end

      erb :index
    end
   
    get '/:category/:dash/:host/' do
    options = {}
      options.merge!(query_params)

      if @top_level["#{params[:category]}"].list.include?(params[:dash])
        @dashboard = @top_level[@params[:category]].dashboard(params[:dash], options)
      else
        @error = "No dashboard called #{params[:dash]} found in #{params[:category]}/#{@top_level[params[:category]].list.join ','}."
      end

      erb :dashboard


    end

    get '/:category/:dash/:host/time/?*' do
    options = {}

#	puts params.inspect
	#{"category"=>"system", "splat"=>["-1hour/now"], "captures"=>["system", "cpu_procs", "md-5", "-1hour/now"], "host"=>"md-5", "dash"=>"cpu_procs"}
	#params["splat"]	 = params["splat"].split("/")
	 params["splat"] = params["splat"][0].split("/")

         options[:from] = params["splat"][0] || "-1hour"
         options[:until] = params["splat"][1] || "now"

      options.merge!(query_params)

      if @top_level["#{params[:category]}"].list.include?(params[:dash])

        @dashboard = @top_level[@params[:category]].dashboard(params[:dash], options)
      else
        @error = "No dashboard called #{params[:dash]} found in #{params[:category]}/#{@top_level[params[:category]].list.join ','}."
      end

      erb :dashboard


    end

#    get '/:category/:dash/debox/:host' do
#	puts params[:host]
#	 if @top_level["#{params[:category]}"].list.include?(params[:dash])
#        	@dashboard = @top_level[@params[:category]].dashboard(params[:dash])
#     	 else
#        	@error = "No dashboard called #{params[:dash]} found in #{params[:category]}/#{@top_level[params[:category]].list.join ','}."
#      end


#	erb :host_dashboard
 #   end

    
    get '/:category/:dash/:host/details/:name' do
      if @top_level["#{params[:category]}"].list.include?(params[:dash])
        @dashboard = @top_level[@params[:category]].dashboard(params[:dash])
      else
        @error = "No dashboard called #{params[:dash]} found in #{params[:category]}/#{@top_level[params[:category]].list.join ','}."
      end

      if @intervals.empty?
        @error = "No intervals defined in configuration"
      end

      if main_graph = @dashboard.graphs[params[:name].to_i][:graphite]
        @graphs = @intervals.map do |e|
          new_props = {:from => e[0], :title => "#{main_graph.properties[:title]} - #{e[1]}"}
          new_props = main_graph.properties.merge new_props
          GraphiteGraph.new(main_graph.file, new_props)
        end
      else
        @error = "No such graph available"
      end

      erb :detailed_dashboard
    end
        get '/:category/:dash/:host/full/?*' do
      options = {}
      params["splat"] = params["splat"].first.split("/")
	puts params["splat"].inspect
      params["columns"] = params["splat"][0].to_i || @graph_columns

      if params["splat"].size == 3
        options[:width] = params["splat"][1].to_i
        options[:height] = params["splat"][2].to_i
      else
        options[:width] = @graph_width
        options[:height] = @graph_height
      end

      options.merge!(query_params)

      if @top_level["#{params[:category]}"].list.include?(params[:dash])
        @dashboard = @top_level[@params[:category]].dashboard(params[:dash], options)
      else
        @error = "No dashboard called #{params[:dash]} found in #{params[:category]}/#{@top_level[params[:category]].list.join ','}"
      end

      erb :full_size_dashboard, :layout => false
    end

#    get '/:category/:dash/?*' do
#      options = {}
#      params["splat"] = params["splat"].first.split("/")
#
#      case params["splat"][0]
#        when 'time'
#          options[:from] = params["splat"][1] || "-1hour"
#          options[:until] = params["splat"][2] || "now"
#        end
#
#      options.merge!(query_params)
#
#      if @top_level["#{params[:category]}"].list.include?(params[:dash])
#        @dashboard = @top_level[@params[:category]].dashboard(params[:dash], options)
#      else
#        @error = "No dashboard called #{params[:dash]} found in #{params[:category]}/#{@top_level[params[:category]].list.join ','}."
#      end
#
#      erb :dashboard
#    end

    get '/docs/' do
      markdown :README, :layout_engine => :erb
    end

    helpers do
      include Rack::Utils

      alias_method :h, :escape_html

      def link_to_interval(options)
	if !params[:host]
	        "<a href=\"#{ [@prefix, params[:category], params[:dash], 'time', h(options[:from]), h(options[:to])].join('/') }\">#{ h(options[:label]) }</a>"
	else
	        "<a href=\"#{ [@prefix, params[:category], params[:dash], params[:host], 'time', h(options[:from]), h(options[:to])].join('/') }\">#{ h(options[:label]) }</a>"
	end	
      end

      def query_params
        hash = {}
        protected_keys = [:category, :dash, :splat, :host]

        params.each do |k, v|
          hash[k.to_sym] = v unless protected_keys.include?(k.to_sym)
        end

        hash
      end
    end
  end
end
