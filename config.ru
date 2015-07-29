require 'websocket'

def server_handshake(env)
  data = "#{env['REQUEST_METHOD']} #{env['REQUEST_URI']} #{env['SERVER_PROTOCOL']}\r\n"
  env.each_pair do |key, val|
    if key =~ /^HTTP_(.*)/
      name = rack_env_key_to_http_header_name($1)
      data << "#{name}: #{val}\r\n"
    end
  end
  data << "\r\n"

  server = WebSocket::Handshake::Server.new
  server << data
  puts "WebSocket request:"
  puts data
  puts
  puts "WebSocket response:"
  puts server
  return server
end

def rack_env_key_to_http_header_name(key)
  name = key.downcase.gsub('_', '-')
  name[0] = name[0].upcase
  name.gsub!(/-(.)/) do |chr|
    chr.upcase
  end
  name
end

def process_input(io, server, input_parser)
  # Slurp as much input as possible.
  begin
    while select([io], nil, nil, 0)
      input_parser << io.readpartial(1024)
    end
  rescue EOFError
  end

  # Parse all input into WebSocket frames and process them.
  while (frame = input_parser.next)
    send_output(io, server, "Echo: #{frame}\n")
  end
end

def send_output(io, server, data)
  frame = WebSocket::Frame::Outgoing::Server.new(
    :version => server.version,
    :data => data,
    :type => :text)
  io.write(frame.to_s)
end

def serve_websocket(env)
  # On every request, hijack the socket using the Rack socket hijacking API
  # (http://blog.phusion.nl/2013/01/23/the-new-rack-socket-hijacking-api/),
  # then operate on the socket directly to send WebSocket messages.
  env['rack.hijack'].call
  io = env['rack.hijack_io']
  begin
    # Parse client handshake message and send server handshake response.
    server = server_handshake(env)
    io.write(server.to_s)

    # Handle input and stream responses.
    input_parser = WebSocket::Frame::Incoming::Server.new(:version => server.version)
    while true
      process_input(io, server, input_parser)
      send_output(io, server, "#{Time.now}\n")
      sleep 1
    end
  ensure
    io.close
  end
end

def serve_static_file(env)
  if env["PATH_INFO"] == "/"
    env["PATH_INFO"] = "/index.html"
  end
  public_dir = File.expand_path(File.dirname(__FILE__)) + "/public"
  Rack::File.new(public_dir).call(env)
end

app = proc do |env|
  if env["PATH_INFO"] == "/websocket"
    serve_websocket(env)
  else
    serve_static_file(env)
  end
end

# See https://www.phusionpassenger.com/library/config/tuning_sse_and_websockets/
if defined?(PhusionPassenger)
  PhusionPassenger.advertised_concurrency_level = 0
end

run app
