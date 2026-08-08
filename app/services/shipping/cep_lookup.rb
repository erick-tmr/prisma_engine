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
        cep: read(payload, "cep").presence || cep,
        street: read(payload, "logradouro").presence,
        neighborhood: neighborhood_for(payload),
        city: city_for(payload),
        state: read(payload, "uf").presence
      }.compact
    end

    private

    attr_reader :cep

    def read(payload, key)
      Correios::Api::Payload.string(payload, key)
    end

    def city_for(payload)
      (read(payload, "nomeMunicipio").presence ||
        read(payload, "localidadeSuperior").presence ||
        read(payload, "localidade").presence)
    end

    # bairro wins when present; otherwise localidade fills it in when it names
    # something other than the municipality itself (the town-wide CEP case).
    def neighborhood_for(payload)
      bairro = read(payload, "bairro")
      return bairro if bairro.present?

      localidade = read(payload, "localidade")
      return nil if localidade.empty? || localidade == city_for(payload)

      localidade
    end
  end
end
