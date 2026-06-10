module Shipping
  # The three services we offer → their Correios codigoServico. Keyed by our name so
  # callers think in service names (`:sedex`), not vendor codes; `SERVICES.key(code)`
  # maps a response code back to the name. Business knowledge — which services *we*
  # offer — so it's domain, not part of the Correios API client.
  # Insertion order doubles as the canonical UI order for the cart quote
  # (fastest → cheapest). `CreatePrePostagem` / `ShipmentFactory` only do
  # lookups by key or by value, so reordering is safe.
  SERVICES = {
    sedex:       "03220",
    pac:         "03298",
    mini_envios: "04227"
  }.freeze

  # The single package size we ship today (cm). Box dimensions are uniform for
  # the games-only catalog; revisit when other product types ship in different
  # packaging. Read by the Correios price quote and pré-postagem flows.
  PACKAGE_DIMENSIONS = {
    altura_cm:      4,
    largura_cm:     16,
    comprimento_cm: 24
  }.freeze

  # Where every package ships from — the Prisma Games HQ in Cambuí/MG. Pulled
  # out of `Shipping::CreatePrePostagem::SENDER` so both pré-postagem and the
  # price/prazo quote flows read from one place.
  ORIGIN_CEP = "37600000".freeze
end
