 # Chalice, a Gemini server
# Made from Crystal by ieve
# January 2025

# -------------------------------------------
# === User Configuration Stuff: ===
HOSTNAME = "localhost"
SERVE_DIRECTORY = "/home/cameron/play/serve/"
DEFAULT_FILE = "index.gmi"
# -------------------------------------------

# -------------------------------------------
# === How to generate server certificate using openssl: ===
# openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -subj "/CN={hostname}"
# Use 'localhost' when testing locally
# Or 'example.com' when setting up live server
# -------------------------------------------

require "socket"
require "openssl"

CRLF = "\r\n"
SPACE = " "
GEMINI_SCHEME_NAME = "gemini"

class Error < Exception; end
class URIError < Error; end
class ConnectionError < Error; end

## ----------------------------------------------
# Main Loop:

tcp_server = TCPServer.new("localhost", 1965)
ssl_context = OpenSSL::SSL::Context::Server.new
ssl_context.certificate_chain = "server.crt"
ssl_context.private_key = "server.key"
ssl_server = OpenSSL::SSL::Server.new(tcp_server, ssl_context)
puts "Listening on #{tcp_server.local_address}"

while connection = ssl_server.accept?
  spawn handle_connection(connection)
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
    puts ""
    puts "--------- New Request #{Time.local.to_s}---------"
    puts "Received message #{request} from #{connection}"

    response = handle_message(request)
    connection.puts response["header"]
    connection.puts response["body"] if response["body"]
    puts "Sent response #{response["header"]} to #{connection}"
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
  puts request_data.inspect
  if request_data["error_code"]?
    status = request_data["error_code"]
    meta = request_data["error_message"]
  else
    file_data = look_for_file(request_data["requested_path"])
    if file_data["error_code"]?
      status = file_data["error_code"]
      meta = file_data["error_message"]
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

  raise URIError.new("Bad URI (relative directory references not allowed)") if request.to_s =~ /\/\.\./

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
  raise URIError.new("Bad URI (Hostname doesn't match server configuration)") unless request_data["hostname"] == HOSTNAME


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
  content = File.read(SERVE_DIRECTORY + search_path)
  return { "content" => content }
rescue e : File::NotFoundError
  # Return error code 51 -- not found
  return { "error_message" => "Not found.", "error_code" => "51"}
end
