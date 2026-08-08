issuer = User.find_by(email: "backoffice@prismagames.dev")

offenders = [
  [ "Felipe Andrade", [
    [ "pokemon-yellow-version", 3,
      "GANHE DINHEIRO EM CASA! Entre no meu grupo VIP de sinais e fature 500 reais por dia sem sair do sofá. " \
      "Chama no zap 11 90000-0000 que eu mando o link do grupo." ]
  ] ],
  [ "Natália Prado", [
    [ "the-legend-of-zelda-oracle-of-ages", 26,
      "Compre seguidores e curtidas baratinho, entrega em 24h para Instagram e TikTok. " \
      "Acesse promo-seguidores-br.example e use o cupom RETRO10." ]
  ] ],
  [ "Isabela Cunha", [
    [ "metroid-ii-return-of-samus", 41,
      "Vendo cartucho mais barato que os daqui, chama no direto @loja_retro_barato que eu faço por metade do preço " \
      "com frete grátis para todo o Brasil." ],
    [ "pokemon-blue-version", 6,
      "Invista em cripto agora! Meu robô de trade dobra o investimento em 7 dias, mínimo de 100 reais. " \
      "Peça o link do robô no meu perfil, vagas limitadas." ]
  ] ],
  [ "Bruno Tanaka", [
    [ "kirbys-dream-land-2", 120,
      "Trabalhe em casa digitando textos e receba toda semana no Pix. Vagas abertas em todo o Brasil, " \
      "sem precisar de experiência. Cadastro pelo link do meu perfil." ],
    [ "pokemon-red-version", 88,
      "Compre esse mesmo cartucho por 30 reais no meu site, entrega rápida. " \
      "Passa lá em retro-liquida.example antes que acabe o estoque." ]
  ] ],
  [ "Henrique Sales", [
    [ "the-legend-of-zelda-oracle-of-seasons", 95,
      "Vendo lista de e-mails de clientes de lojas retro, 50 mil contatos por 90 reais. " \
      "Ideal para quem quer divulgar. Chama no zap." ],
    [ "pokemon-green-version", 60,
      "Empréstimo liberado na hora, sem consulta ao SPC, até 20 mil reais no Pix. " \
      "Só chamar no WhatsApp que a análise sai em 5 minutos." ],
    [ "pokemon-yellow-legacy-romhack", 21,
      "APOSTE E GANHE! Plataforma nova pagando 300% de bônus no primeiro depósito, " \
      "link no meu perfil, saque em 2 minutos pelo Pix." ]
  ] ]
]

def strike_client(name)
  User.find_by(email: "#{name.parameterize}@prismagames.dev")
end

def spam_question(product, client, body, marked_at)
  question = Question.find_or_initialize_by(product: product, user: client, body: body)
  return question unless question.new_record?

  question.assign_attributes(status: "spam", created_at: marked_at - 2.hours, updated_at: marked_at)
  question.save!
  question
end

def issue_strike(question, issuer, marked_at)
  return 0 if QuestionStrike.exists?(question: question)

  QuestionStrike.insert_all!([ {
    user_id: question.user_id, question_id: question.id, issued_by_id: issuer.id,
    created_at: marked_at, updated_at: marked_at
  } ])
  1
end

def ban_state(ban)
  return "permanent" if ban.permanent?
  return "banned until #{ban.expires_at.strftime('%d/%m/%Y')}" if ban.active?

  "served"
end

def ban_summary(client)
  ban = Questions::Ban.new(client)
  "#{client.email}: #{ban.strikes} strike(s), #{ban.penalty}, #{ban_state(ban)}"
end

created = offenders.sum do |name, offences|
  client = strike_client(name)
  next 0 unless client && issuer

  offences.sum do |slug, days_ago, body|
    product = Product.find_by(slug: slug)
    next 0 unless product

    marked_at = days_ago.days.ago
    issue_strike(spam_question(product, client, body, marked_at), issuer, marked_at)
  end
end

puts "Client strikes: #{created} new, #{QuestionStrike.count} total (password cliente123)."
offenders.filter_map { |name, _| strike_client(name) }.each { |client| puts "  #{ban_summary(client)}" }
