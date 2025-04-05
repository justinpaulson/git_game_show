module GitGameShow
  # WebSocket server management
  class Server
    attr_reader :port
    
    def initialize(port, message_handler)
      @port = port
      @message_handler = message_handler
    end

    def start
      WebSocket::EventMachine::Server.start(host: '0.0.0.0', port: @port) do |ws|
        ws.onopen do
          # Connection is logged when a player successfully joins
        end

        ws.onmessage do |msg|
          @message_handler.handle_message(ws, msg)
        end

        ws.onclose do
          @message_handler.handle_player_disconnect(ws)
        end
      end
    end

    def broadcast_message(message, exclude: nil)
      return if message.nil?

      begin
        # Convert message to JSON safely
        json_message = nil
        begin
          json_message = message.to_json
        rescue => e
          # Try to simplify the message to make it JSON-compatible
          simplified_message = {
            type: message[:type] || "unknown",
            message: "Error processing full message"
          }
          json_message = simplified_message.to_json
        end

        return unless json_message

        @message_handler.broadcast(json_message, exclude)
      rescue => e
        # Silently fail for now
      end
    end
  end
end