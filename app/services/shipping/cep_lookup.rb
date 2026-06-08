module Shipping
  # Domain wrapper around Correios::Api::Cep: takes a normalized CEP, hands back
  # the Address fields the form can autofill (street/neighborhood/city/state).
  # The Correios response shape varies by CEP type:
  #
  #   - Street-specific CEP → logradouro + bairro + nomeMunicipio + uf
  #   - Town-wide ("CEP único") → localidade + localidadeSuperior + uf, no street
  #
  # And the per-Correios convention for bairro: when bairro is absent but the
  # localidade differs from the municipality name, the localidade plays the
  # bairro role. We only emit fields that came back populated, so a partial
  # response never blanks out a value the customer already typed.
  class CepLookup
    def self.call(cep)
      new(cep).call
    end

    def initialize(cep)
      @cep = cep
    end

    def call
      payload = Correios::Api::Cep.find(cep)
      {
        cep: payload["cep"].presence || cep,
        street: payload["logradouro"].presence,
        neighborhood: neighborhood_for(payload),
        city: city_for(payload),
        state: payload["uf"].presence
      }.compact
    end

    private

    attr_reader :cep

    def city_for(payload)
      (payload["nomeMunicipio"].presence ||
        payload["localidadeSuperior"].presence ||
        payload["localidade"].presence)
    end

    # bairro wins when present; otherwise localidade fills it in when it names
    # something other than the municipality itself (the town-wide CEP case).
    def neighborhood_for(payload)
      return payload["bairro"] if payload["bairro"].present?

      localidade = payload["localidade"].to_s
      return nil if localidade.empty? || localidade == city_for(payload)

      localidade
    end
  end
end
