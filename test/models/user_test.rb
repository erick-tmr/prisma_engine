require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  VALID_CPF = "11144477735"
  OTHER_VALID_CPF = "12345678909"

  def base_attrs(overrides = {})
    {
      email: "novo@example.com",
      password: "password123",
      password_confirmation: "password123",
      full_name: "Novo Cliente",
      cpf: VALID_CPF,
      phone: "11988887777"
    }.merge(overrides)
  end

  def pending_account
    users(:unconfirmed).tap { |user| user.update_column(:phone, "(11) 98888-7777") }
  end

  test "a fully-populated record is valid" do
    user = User.new(base_attrs(cpf: "52998224725"))
    assert user.valid?, user.errors.full_messages.to_sentence
  end

  test "full_name is required" do
    user = User.new(base_attrs(full_name: nil))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :full_name
  end

  test "cpf is required" do
    user = User.new(base_attrs(cpf: nil))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :cpf
  end

  test "cpf must be unique" do
    duplicate = User.new(base_attrs(cpf: users(:confirmed).cpf, email: "outro@example.com"))
    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :cpf
  end

  test "cpf with an invalid checksum is rejected" do
    user = User.new(base_attrs(cpf: "11144477700"))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :cpf
  end

  test "cpf is normalized to digits on validation" do
    user = User.new(base_attrs(cpf: "111.444.777-35"))
    user.valid?
    assert_equal "11144477735", user.cpf
  end

  test "cpf made of only formatting characters normalizes to nil" do
    user = User.new(base_attrs(cpf: "...-/"))
    assert_not user.valid?
    assert_nil user.cpf
    assert_includes user.errors.attribute_names, :cpf
  end

  test "phone is required" do
    user = User.new(base_attrs(phone: nil, cpf: "52998224725"))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :phone
  end

  test "phone over 20 characters is rejected" do
    user = User.new(base_attrs(phone: "1" * 21))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :phone
  end

  test "a phone missing its area code is rejected instead of reaching the payment link" do
    user = User.new(base_attrs(phone: "99942-4875", cpf: "52998224725"))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :phone
  end

  test "a country code swallowed by the fixed-width mask is rejected" do
    user = User.new(base_attrs(phone: "(55) 21976-0285", cpf: "52998224725"))
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :phone
  end

  test "the rejected phone is kept as typed so the customer can see what to correct" do
    user = User.new(base_attrs(phone: "99942-4875", cpf: "52998224725"))
    user.valid?
    assert_equal "99942-4875", user.phone
  end

  test "a valid phone is normalized to one stored shape" do
    user = User.new(base_attrs(phone: "+55 11 98765-4321", cpf: "52998224725"))
    assert user.valid?, user.errors.full_messages.to_sentence
    assert_equal "(11) 98765-4321", user.phone
  end

  test "a landline is accepted and normalized" do
    user = User.new(base_attrs(phone: "1133334444", cpf: "52998224725"))
    assert user.valid?, user.errors.full_messages.to_sentence
    assert_equal "(11) 3333-4444", user.phone
  end

  test "first_name returns the first whitespace-separated token" do
    assert_equal "Cliente", users(:confirmed).first_name
  end

  test "first_name returns the single token when full_name has no spaces" do
    user = users(:confirmed)
    user.full_name = "Madonna"
    assert_equal "Madonna", user.first_name
  end

  test "first_name returns nil when full_name is blank" do
    user = users(:confirmed)
    user.full_name = nil
    assert_nil user.first_name
  end

  test "default_address returns the address flagged default" do
    user = users(:confirmed)
    user.addresses.create!(
      zip: "12345678", street: "X", number: "1", neighborhood: "Y",
      city: "Z", state: "SP",
      receiver_name: "Maria", receiver_cpf: "52998224725"
    )
    second = user.addresses.create!(
      zip: "12345678", street: "Outra", number: "2", neighborhood: "Y",
      city: "Z", state: "SP",
      receiver_name: "Maria", receiver_cpf: "52998224725"
    )
    second.mark_default!
    assert_equal second, user.default_address
  end

  test "update_contact swaps the login e-mail at once, without a reconfirmation round-trip" do
    user = users(:confirmed)

    delivered = capture_emails do
      assert user.update_contact(email: "Novo.Login@Example.com", phone: "11977776666")
    end

    assert_equal [ [ "confirmed@example.com" ], [ "novo.login@example.com" ] ], delivered.map(&:to).sort
    assert_equal [ "Este é o novo e-mail da sua conta", "Seu e-mail de acesso foi alterado" ], delivered.map(&:subject).sort

    user.reload
    assert_equal "novo.login@example.com", user.email
    assert_nil user.unconfirmed_email
    assert_equal "(11) 97777-6666", user.phone
  end

  test "update_contact drops a pending self-service e-mail change it replaces" do
    user = users(:confirmed)
    user.update_column(:unconfirmed_email, "pendente.antigo@example.com")

    assert user.update_contact(email: "outro@example.com", phone: user.phone)
    assert_nil user.reload.unconfirmed_email
  end

  test "update_contact leaves a pending e-mail change alone when only the phone moves" do
    user = users(:confirmed)
    user.update_column(:unconfirmed_email, "pendente.antigo@example.com")

    assert user.update_contact(email: " #{user.email.upcase} ", phone: "11977776666")
    assert_equal "pendente.antigo@example.com", user.reload.unconfirmed_email
  end

  test "update_contact leaves both addresses alone when only the phone moves" do
    user = users(:confirmed)

    assert_no_enqueued_emails do
      assert user.update_contact(email: user.email, phone: "11977776666")
    end
  end

  test "update_contact confirms a pending account whose e-mail the admin corrects" do
    user = users(:unconfirmed)
    user.update_columns(phone: "11977776666", confirmation_token: "link-to-the-typo")

    assert user.update_contact(email: "corrigido@example.com", phone: user.phone)

    user.reload
    assert user.confirmed?
    assert_in_delta Time.current, user.confirmed_at, 5.seconds
    assert_nil user.confirmation_token
    assert user.active_for_authentication?
  end

  test "update_contact keeps the original confirmation date of an account that was already confirmed" do
    user = users(:confirmed)
    confirmed_at = user.confirmed_at

    assert user.update_contact(email: "outro@example.com", phone: user.phone)
    assert_equal confirmed_at.to_i, user.reload.confirmed_at.to_i
  end

  test "update_contact leaves a pending account pending when only the phone moves" do
    user = users(:unconfirmed)

    assert user.update_contact(email: user.email, phone: "11977776666")
    assert_not user.reload.confirmed?
  end

  test "update_contact refuses an e-mail another account already logs in with" do
    user = users(:confirmed)

    assert_no_enqueued_emails do
      assert_not user.update_contact(email: users(:locked).email, phone: user.phone)
    end
    assert user.errors.of_kind?(:email, :taken)
    assert_equal "confirmed@example.com", user.reload.email
  end

  test "correct_signup_email moves a pending account to the new address and sends the link only there" do
    user = pending_account

    delivered = capture_emails do
      assert user.correct_signup_email("Certo@Example.com")
    end

    assert_equal [ [ "certo@example.com" ] ], delivered.map(&:to)
    user.reload
    assert_equal "certo@example.com", user.email
    assert_nil user.unconfirmed_email
    assert_not user.confirmed?
  end

  test "correct_signup_email kills the link that went to the mistyped address" do
    user = pending_account

    user.correct_signup_email("certo@example.com")

    assert_nil User.confirm_by_token("raw-token-pendente").id
    assert_not user.reload.confirmed?
  end

  test "correct_signup_email restarts the confirmation window" do
    user = pending_account
    user.update_column(:confirmation_sent_at, 6.days.ago)

    user.correct_signup_email("certo@example.com")

    assert_in_delta Time.current, user.reload.confirmation_sent_at, 5.seconds
  end

  test "correct_signup_email sends nothing when the address does not change" do
    user = pending_account

    assert_no_emails do
      assert user.correct_signup_email(" #{user.email.upcase} ")
    end
  end

  test "correct_signup_email refuses an account that is already confirmed" do
    user = users(:confirmed)

    assert_no_emails do
      assert_not user.correct_signup_email("certo@example.com")
    end
    assert_equal "confirmed@example.com", user.reload.email
  end

  test "correct_signup_email refuses an address another account logs in with" do
    user = pending_account

    assert_no_emails do
      assert_not user.correct_signup_email(users(:confirmed).email)
    end
    assert user.errors.of_kind?(:email, :taken)
    assert_equal "pendente@example.com", user.reload.email
  end

  test "pending_signup finds the unconfirmed holder of a CPF when the password matches" do
    assert_equal users(:unconfirmed), User.pending_signup(cpf: "123.456.789-09", password: "password123")
  end

  test "pending_signup ignores a wrong password" do
    assert_nil User.pending_signup(cpf: users(:unconfirmed).cpf, password: "outra-senha")
  end

  test "pending_signup ignores a confirmed account" do
    assert_nil User.pending_signup(cpf: users(:confirmed).cpf, password: "password123")
  end

  test "a signup does not take the CPF of a pending account still inside its confirmation window" do
    holder = pending_account

    user = User.new(base_attrs(cpf: holder.cpf))

    assert_not user.save
    assert user.errors.of_kind?(:cpf, :taken)
    assert User.exists?(holder.id)
  end

  test "a signup takes the CPF of a pending account whose confirmation window expired" do
    holder = pending_account
    holder.update_column(:confirmation_sent_at, (User.confirm_within + 1.day).ago)

    user = User.new(base_attrs(cpf: holder.cpf))

    assert user.save, user.errors.full_messages.to_sentence
    assert_not User.exists?(holder.id)
  end

  test "a failed signup leaves the expired pending account in place" do
    holder = pending_account
    holder.update_column(:confirmation_sent_at, (User.confirm_within + 1.day).ago)

    user = User.new(base_attrs(cpf: holder.cpf, password: "curta", password_confirmation: "curta"))

    assert_not user.save
    assert User.exists?(holder.id)
  end

  test "an updated account still cannot share a CPF" do
    user = pending_account
    user.cpf = users(:confirmed).cpf

    assert_not user.valid?
    assert user.errors.of_kind?(:cpf, :taken)
  end
end
