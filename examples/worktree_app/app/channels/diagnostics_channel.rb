class DiagnosticsChannel < ApplicationCable::Channel
  def echo(data)
    transmit({ echo: data["message"].to_s.first(120) })
  end
end
