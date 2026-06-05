module Shipping
  # The three services we offer → their Correios codigoServico. Keyed by our name so
  # callers think in service names (`:sedex`), not vendor codes; `SERVICES.key(code)`
  # maps a response code back to the name. Business knowledge — which services *we*
  # offer — so it's domain, not part of the Correios API client.
  SERVICES = {
    sedex: "03220",
    mini_envios: "04227",
    pac: "03298"
  }.freeze
end
