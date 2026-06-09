module Account
  class AddressesController < BaseController
    before_action :set_address, only: %i[edit update destroy default]

    def index
      @addresses = current_user.addresses.default_first
    end

    def new
      @address = current_user.addresses.build
    end

    def create
      @address = current_user.addresses.build(address_params)
      if @address.save
        redirect_to account_addresses_path, notice: t("account.addresses.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @address.update(address_params)
        redirect_to account_addresses_path, notice: t("account.addresses.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @address.destroy!
      redirect_to account_addresses_path, notice: t("account.addresses.destroyed")
    end

    def default
      @address.mark_default!
      redirect_to account_addresses_path, notice: t("account.addresses.default_set")
    end

    # Autofill endpoint hit by the address form on CEP blur. Returns a JSON Hash
    # with whichever of {street, neighborhood, city, state} Correios knows for
    # this CEP. Empty fields stay empty so the JS can't overwrite typed values.
    def lookup_cep
      cep = params[:cep].to_s.gsub(/\D/, "")
      return head :unprocessable_entity unless cep.match?(/\A\d{8}\z/)

      render json: Shipping::CepLookup.call(cep)
    rescue Correios::Api::InvalidObjectError
      head :not_found
    rescue Correios::Api::Error
      head :bad_gateway
    end

    private

    def set_address
      @address = current_user.addresses.find(params[:id])
    end

    def address_params
      params.expect(address: %i[zip street number complement neighborhood city state receiver_name receiver_cpf])
    end
  end
end
