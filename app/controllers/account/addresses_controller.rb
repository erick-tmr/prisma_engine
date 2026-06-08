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

    private

    def set_address
      @address = current_user.addresses.find(params[:id])
    end

    def address_params
      params.expect(address: %i[zip street number complement neighborhood city state])
    end
  end
end
