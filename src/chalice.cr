# Chalice, a Gemini server
# Made from Crystal by ieve
# Winter 2025

VERSION = "1.0.0"

# -------------------------------------------
# === User Configuration Stuff: ===
HOSTNAME = "localhost"          # "example.com" or "localhost"
PORT = 1965                     # int32, not a string please
SERVE_DIRECTORY = "/srv/gemini" # /srv/{protocol} is canon I think?
DEFAULT_FILE = "index.gmi"      # filename to be served at domain root
MAX_CONNECTIONS = 50
LOG_LOCATION = "/var/log/chalice"
CERT_LOCATION = "/etc/chalice"
# -------------------------------------------

# -------------------------------------------
# === How to generate server certificate using openssl: ===
# openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -subj "/CN={hostname}"
# Use 'localhost' when testing locally
# Or 'example.com' when setting up live server
# -------------------------------------------

require "socket"
require "openssl"
require "log"

CRLF = "\r\n"
SPACE = " "
GEMINI_SCHEME_NAME = "gemini"
HOSTPORT = HOSTNAME + ":" + PORT.to_s
LOG_FILE = LOG_LOCATION + "/chalice.log"
CERT_FILE = CERT_LOCATION + "/server.crt"
PRIVATE_KEY = CERT_LOCATION + "/server.key"

class Error < Exception; end
class URIError < Error; end
class ConnectionError < Error; end

backend = Log::IOBackend.new(File.new(LOG_FILE, "a+"))
Log.setup do |c|
  c.bind "*", :info, backend # Log info and above to LOG_FILE IO
  # Reminder that specifying sources doesn't seem to work at the top level namespace. I think we need to wrap everything in a module to get a namespace if we want to do anything with sources.
end

# Server setup
tcp_server = TCPServer.new(HOSTNAME, PORT)
ssl_context = OpenSSL::SSL::Context::Server.new
ssl_context.certificate_chain = "server.crt"
ssl_context.private_key = "server.key"
ssl_server = OpenSSL::SSL::Server.new(tcp_server, ssl_context)
puts "Chalice Gemini Server - Version #{VERSION}"
puts "Listening on #{tcp_server.local_address}"
Log.info { "Server startup at #{Time.local.to_s}, listening on #{tcp_server.local_address}" }

# Max connections / rate limiting
# I think this is a 'semaphore' pattern kinda?
# We fill up the pool with N tokens (which is literally just the symbol :token) for # of connections allowed.
# When a new fiber is spawned, it pulls a token from the pool before dealing with the request, then ensure block returns the token on cleanup.
# Bug - When you queue up more than N connections, the N+1th will be served, but everybody else in the queue gets a closed stream IO::Error
conn_pool_channel = Channel(Symbol).new(MAX_CONNECTIONS)
MAX_CONNECTIONS.times do
  conn_pool_channel.send(:token)
end

## ----------------------------------------------
# Main Loop:

loop do
  begin
      while connection = ssl_server.accept?
        spawn do
          begin
            conn_pool_channel.receive
            handle_connection(connection)
          ensure
            conn_pool_channel.send(:token)
          end
        end
      end
  rescue e : OpenSSL::SSL::Error | IO::Error
    Log.info { "--------- New Request #{Time.local.to_s} ---------" }
    Log.error { "[SSL/IO Error] " + e.to_s }
  end
end

## ----------------------------------------------
## ----------------------------------------------

# Parse and validate a URI request from connection and returns the response message through the connection pipe.
#
# requests from client are supposed to look like this:
# <URL><CR><LF>
# gemini://domain.net/subfolder/subfolder2/document.gmi\r\n
#
# response = header + body
#
# response header is supposed to look like this:
# <STATUS><SPACE><META><CR><LF>
def handle_connection(connection)
  request = connection.gets
  if request
    Log.info { "--------- New Request #{Time.local.to_s} ---------" }
    Log.info { "Received message #{request} from #{connection.remote_address.to_s}" }

    response = handle_message(request)
    connection.puts response["header"]
    Log.info { "Sent response #{response["header"]} to #{connection.remote_address.to_s}" }
    connection.puts response["body"] if response["body"]
  else
    raise ConnectionError.new("Request data is nil")
    return
  end
ensure
  connection.close
end

## ----------------------------------------------

def handle_message(message)
  request_data = decode_request(message)
  if request_data["error_code"]?
    status = request_data["error_code"]
    meta = error_meta_message(status)
  else
    file_data = look_for_file(request_data["requested_path"])
    if file_data["error_code"]?
      status = file_data["error_code"]
      meta = error_meta_message(status)
    else
      status = "20"
      meta = "text/gemini"
      body = file_data["content"]
    end
  end
  header = status + SPACE + meta + CRLF
  return {"header" => header, "body" => body}
end

## ----------------------------------------------

def decode_request(request)
  request_data = Hash(String, String).new

  # Step 0 - Check for stuff not allowed
  raise URIError.new("Bad URI (exceeds 1024 byte limit)") if request.to_s.bytesize > 1024

  raise URIError.new("Bad URI (contains fragment ('\#'))") if request.to_s =~ /\#/

  raise URIError.new("Bad URI (relative directory references not allowed)") if request.to_s =~ /\/\.\./ || request.to_s =~ /\\\.\./

  # Step 1 - Split and check scheme
  # Incoming request looks something like this:
  # gemini://domain.net/subfolder/subfolder2/document.gmi
  # And we will split to look like this:
  # => ["gemini", "domain.net/subfolder/subfolder2/document.gmi"]
  request = request.split("://")
  raise URIError.new("Bad URI (couldn't split on '://')") unless request.size == 2

  # Check that request is for Gemini protocol
  request_data["scheme"] = request.first
  raise URIError.new("Bad URI (scheme isn't gemini)") unless request_data["scheme"] == GEMINI_SCHEME_NAME

  # Step 2 - Split and check hostname
  request_data["hostname"] = request.last.split("/", 2).first
  raise URIError.new("Bad URI (userinfo is not allowed)") if request_data["hostname"] =~ /@/
  # Check for either hostname or HOSTNAME:PORT (HOSTPORT)
  raise URIError.new("Bad URI (Hostname doesn't match server configuration)") unless request_data["hostname"] == HOSTNAME || request_data["hostname"] == HOSTPORT

  # Step 3 - Grab the request path
  request_data["requested_path"] = request.last.split("/", 2).last

  # If there is no path and no ending slash passed in, eg "gemini://example.com", then the path and hostname end up being the same thing. In this case, manually set the requested path to the index file.
  # (My crude approach to normalization.)
  if request_data["requested_path"] == request_data["hostname"]
    request_data["requested_path"] = DEFAULT_FILE
  end

  # And if only host and slash, then also assign default file path.
  if request_data["requested_path"] == ""
    request_data["requested_path"] = DEFAULT_FILE
  end

  return request_data
rescue e : URIError
  # Return error code 59 -- bad request
  return { "error_message" => e.to_s, "error_code" => "59"}
end

# Takes a requested path (eg "subfolder/subfolder2/document.gmi") and returns the associated Gemini file if it's available in the SERVE_DIRECTORY
def look_for_file(search_path : String)
  search_path = search_path.gsub("\\", "/") # Normalize Windows paths to Unix style



  # Secondary controls for path traversal...


  # Check for symlinks
  raise Path::Error.new("Path is a symlink, not allowed") if File.symlink?(SERVE_DIRECTORY + search_path)

  # Checks that the requested path string starts with the intended serve directory.
  full_path = File.realpath(File.join(SERVE_DIRECTORY, search_path))
  serve_dir = File.realpath(SERVE_DIRECTORY)
  raise Path::Error.new("Requested path '#{search_path}' resolved to '#{full_path}' which is outside of serve directory '#{serve_dir}'.") unless full_path.starts_with?(serve_dir)

  path = Path[full_path] # Cast to Path type to use extension method

  raise Path::Error.new("Requested an invalid extension '#{path.extension}'") unless path.extension.downcase == ".gmi" || path.extension.downcase == ".gemini"



  content = File.read(path)
  return { "content" => content }
rescue e : File::NotFoundError | Path::Error
  # Return error code 51 -- not found
  return { "error_message" => e.to_s, "error_code" => "51"}
end

def error_meta_message(status_code : String)
  case status_code
  when "51"
    meta = "I couldn't find what you requested..."
  when "59"
    meta = "Your request was not formatted in a way I was expecting..."
  else
    meta = "Need to write an error message still..."
  end
end
