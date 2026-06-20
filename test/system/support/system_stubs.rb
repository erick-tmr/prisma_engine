module SystemStubs
  CORREIOS    = Correios::Api::BASE_URL
  INFINITEPAY = InfinitePay::Api::BASE_URL

  FAKE_PAYMENT_URL = "data:text/html,%3Ch1%3Efake-psp%3C%2Fh1%3E".freeze

  def stub_external_env
    @prev_correios_token = ENV["CORREIOS_API_TOKEN"]
    @prev_infinitepay    = ENV["INFINITEPAY_HANDLE"]
    ENV["CORREIOS_API_TOKEN"] = "test-api"
    ENV["INFINITEPAY_HANDLE"] = "prisma_games"
  end

  def restore_external_env
    ENV["CORREIOS_API_TOKEN"] = @prev_correios_token
    ENV["INFINITEPAY_HANDLE"] = @prev_infinitepay
  end

  def stub_cep(cep: "01310100", uf: "SP", street: "Av. Paulista", neighborhood: "Bela Vista", city: "São Paulo")
    stub_request(:get, "#{CORREIOS}/cep/v2/enderecos/#{cep}").to_return(
      status:  200,
      body:    { "cep" => cep, "uf" => uf, "logradouro" => street,
                 "bairro" => neighborhood, "nomeMunicipio" => city }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  def stub_preco_prazo(all_eligible: true)
    preco_body = [
      { "coProduto" => "03220", "nuRequisicao" => "03220", "pcFinal" => "19,84" },
      { "coProduto" => "03298", "nuRequisicao" => "03298", "pcFinal" => "20,84" }
    ]
    preco_body << if all_eligible
      { "coProduto" => "04227", "nuRequisicao" => "04227", "pcFinal" => "11,15" }
    else
      { "coProduto" => "04960", "nuRequisicao" => "04227", "pcFinal" => "18,08" }
    end

    stub_request(:post, "#{CORREIOS}/preco/v1/nacional").to_return(
      status: 200, body: preco_body.to_json, headers: { "Content-Type" => "application/json" }
    )
    stub_request(:post, "#{CORREIOS}/prazo/v1/nacional").to_return(
      status:  200,
      body:    [
        { "coProduto" => "03220", "nuRequisicao" => "03220", "prazoEntrega" => 2 },
        { "coProduto" => "03298", "nuRequisicao" => "03298", "prazoEntrega" => 7 },
        { "coProduto" => "04227", "nuRequisicao" => "04227", "prazoEntrega" => 9 }
      ].to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  def stub_infinitepay_links(payment_url: FAKE_PAYMENT_URL)
    stub_request(:post, "#{INFINITEPAY}/links").to_return(
      status: 200, body: { "url" => payment_url }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end
end
