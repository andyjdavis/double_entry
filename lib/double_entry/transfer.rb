# encoding: utf-8
module DoubleEntry
  class Transfer
    class Set < Array
      def find(from, to, code)
        _find(from.identifier, to.identifier, code)
      end

      def <<(transfer)
        if _find(transfer.from, transfer.to, transfer.code)
          raise DuplicateTransfer.new
        else
          super(transfer)
        end
      end

    private

      def _find(from, to, code)
        detect do |transfer|
          transfer.from == from and transfer.to == to and transfer.code == code
        end
      end
    end

    attr_accessor :code, :from, :to, :description, :meta_requirement

    def initialize(attributes)
      @meta_requirement = []
      attributes.each { |name, value| send("#{name}=", value) }
    end

    def process!(amount, from, to, code, meta, detail)
      if from.scope_identity == to.scope_identity and from.identifier == to.identifier
        raise TransferNotAllowed.new
      end

      meta_requirement.each do |key|
        if meta[key].nil?
          raise RequiredMetaMissing.new
        end
      end

      Locking.lock_accounts(from, to) do
        credit, debit = Line.new, Line.new

        credit_balance = Locking.balance_for_locked_account(from)
        debit_balance  = Locking.balance_for_locked_account(to)

        credit_balance.update_attribute :balance, credit_balance.balance - amount
        debit_balance.update_attribute  :balance, debit_balance.balance  + amount

        credit.amount,  debit.amount  = -amount, amount
        credit.account, debit.account = from, to
        credit.code,    debit.code    = code, code
        credit.meta,    debit.meta    = meta, meta
        credit.detail,  debit.detail  = detail, detail
        credit.balance, debit.balance = credit_balance.balance, debit_balance.balance

        # FIXME: I don't think we use this.
        credit.partner_account, debit.partner_account = to, from

        credit.save!
        debit.partner_id = credit.id
        debit.save!
        credit.update_attribute :partner_id, debit.id
      end
    end

  end
end