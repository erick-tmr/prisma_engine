require "test_helper"

module Shipping
  class CepLookupTest < ActiveSupport::TestCase
    BASE = Correios::Api::BASE_URL

    test "maps a street-specific response to street/neighborhood/city/state" do
      stub_cep("01310100",
        "logradouro" => "Avenida Paulista",
        "bairro" => "Bela Vista",
        "nomeMunicipio" => "São Paulo",
        "uf" => "SP")

      assert_equal(
        { cep: "01310100", street: "Avenida Paulista", neighborhood: "Bela Vista",
          city: "São Paulo", state: "SP" },
        Shipping::CepLookup.call("01310100")
      )
    end

    test "town-wide CEP: uses localidade as neighborhood and localidadeSuperior as city" do
      # The user's example: 37665000, Costas (distrito) de Paraisópolis/MG. No
      # logradouro, no bairro; the Correios convention is to surface the
      # district as the bairro and the municipality as the city.
      stub_cep("37665000",
        "cep" => "37665000",
        "uf" => "MG",
        "localidade" => "Costas",
        "localidadeSuperior" => "Paraisópolis")

      assert_equal(
        { cep: "37665000", neighborhood: "Costas", city: "Paraisópolis", state: "MG" },
        Shipping::CepLookup.call("37665000")
      )
    end

    test "town-wide CEP where localidade matches the city: emits no neighborhood" do
      # Pure municipal CEP: nothing useful to put in bairro.
      stub_cep("11000000",
        "uf" => "SP",
        "localidade" => "Santos",
        "nomeMunicipio" => "Santos")

      result = Shipping::CepLookup.call("11000000")
      assert_nil result[:neighborhood]
      assert_equal "Santos", result[:city]
    end

    test "real Cambuí response (37600000): only state + city, no street or neighborhood" do
      # Captured from the live API: the v2 endpoint omits localidadeSuperior
      # and nomeMunicipio for town-wide CEPs; localidade IS the city. The
      # response also has no bairro and no logradouro, so the client has to
      # clear those fields rather than keep stale values from a prior CEP.
      stub_cep("37600000",
        "cep" => "37600000", "uf" => "MG", "numeroLocalidade" => 28441,
        "localidade" => "Cambuí", "tipoCEP" => 1, "codigoIbge" => "3110608")

      assert_equal(
        { cep: "37600000", city: "Cambuí", state: "MG" },
        Shipping::CepLookup.call("37600000")
      )
    end

    test "real Orfanato response (03131010): full street + bairro + city + state" do
      # Captured from the live API: confirms that for a street CEP, localidade
      # holds the municipality (there is no nomeMunicipio in the v2 payload).
      stub_cep("03131010",
        "cep" => "03131010", "uf" => "SP", "logradouro" => "Rua Orfanato",
        "bairro" => "Vila Prudente", "localidade" => "São Paulo", "tipoCEP" => 2)

      assert_equal(
        { cep: "03131010", street: "Rua Orfanato", neighborhood: "Vila Prudente",
          city: "São Paulo", state: "SP" },
        Shipping::CepLookup.call("03131010")
      )
    end

    test "prefers bairro over localidade when both are present" do
      stub_cep("80000000",
        "logradouro" => "Rua A",
        "bairro" => "Centro",
        "localidade" => "Sub-Centro",
        "nomeMunicipio" => "Curitiba",
        "uf" => "PR")

      assert_equal "Centro", Shipping::CepLookup.call("80000000")[:neighborhood]
    end

    test "city falls back through nomeMunicipio → localidadeSuperior → localidade" do
      stub_cep("24000000", "uf" => "RJ", "localidade" => "Niterói")
      assert_equal "Niterói", Shipping::CepLookup.call("24000000")[:city]

      stub_cep("24000001", "uf" => "RJ", "localidade" => "X", "localidadeSuperior" => "Y")
      assert_equal "Y", Shipping::CepLookup.call("24000001")[:city]

      stub_cep("24000002",
        "uf" => "RJ", "localidade" => "X", "localidadeSuperior" => "Y", "nomeMunicipio" => "Z")
      assert_equal "Z", Shipping::CepLookup.call("24000002")[:city]
    end

    test "echoes the typed CEP when the payload omits it" do
      stub_cep("01000000", "uf" => "SP")

      assert_equal "01000000", Shipping::CepLookup.call("01000000")[:cep]
    end

    test "drops nil/blank fields so the caller can't blank typed values" do
      stub_cep("01000000", "logradouro" => "", "bairro" => nil, "uf" => "SP")

      result = Shipping::CepLookup.call("01000000")
      refute result.key?(:street)
      refute result.key?(:neighborhood)
      assert_equal "SP", result[:state]
    end

    test "re-raises Correios::Api::InvalidObjectError so the controller maps it to 404" do
      stub_request(:get, "#{BASE}/cep/v2/enderecos/00000000")
        .to_return(status: 404, body: "{}", headers: { "Content-Type" => "application/json" })

      assert_raises(Correios::Api::InvalidObjectError) { Shipping::CepLookup.call("00000000") }
    end

    test "re-raises Correios::Api::TransientError so the controller maps it to 502" do
      stub_request(:get, "#{BASE}/cep/v2/enderecos/00000000")
        .to_return(status: 503, body: "boom")

      assert_raises(Correios::Api::TransientError) { Shipping::CepLookup.call("00000000") }
    end

    private

    def stub_cep(cep, payload)
      stub_request(:get, "#{BASE}/cep/v2/enderecos/#{cep}")
        .to_return(status: 200, body: payload.to_json,
                   headers: { "Content-Type" => "application/json" })
    end
  end
end
