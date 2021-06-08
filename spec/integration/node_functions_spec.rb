require 'spec_helper'

describe 'Test node functions against testrpc', integration: true do
  # client is loaded by the spec_helper

  describe "#accounts" do
    it "returns accounts managed by the node" do
      expect(client.accounts.length).to be > 0
      expect(client.accounts.first).to be_a Etherlite::Account::Local
    end
  end

  describe "#default_account" do
    it "returns the first account managed by the node" do
      expect(client.accounts.first).to eq client.default_account
    end
  end

  describe "#anonymous_account" do
    it "returns a readonly account" do
      expect(client.anonymous_account.normalized_address).to be nil
    end
  end

  context "given a transaction" do
    let(:pk) { '5265130d78f73a53aeac4ffc0fa03f42a3d3526fee8f9af31be0807b11c5233a' }
    let(:pk_address) { '0xe8C1b5A6ac249b8f01AA042B5819607bbf06C557' }
    let!(:hash) { client.transfer_to(pk_address, amount: 1e18.to_i).tx_hash }

    describe "#load_address" do
      it "returns an address object that can be queried for balance" do
        expect(client.load_address(pk_address).get_balance).to be > 0
      end

      it "fails if address has the wrong format" do
        expect { client.load_address('64e1c9bf6519350d1c46b0cc79b8675bd9fd5fef') }
          .to raise_error(ArgumentError)
      end
    end

    describe "#load_account" do
      let(:other_address) { '0x64e1c9bf6519350d1c46b0cc79b8675bd9fd5fef' }

      it "allows loading and account from its private key" do
        other_address = '0x64e1c9bf6519350d1c46b0cc79b8675bd9fd5fef'
        amount = 1e6.to_i

        account = client.load_account from_pk: pk

        expect { account.transfer_to(other_address, amount: amount) }
          .to change { client.load_address(other_address).get_balance }.by amount
      end
    end

    describe "#load_transaction" do
      it "returns an transaction object that can be queried for transaction status" do
        expect(client.load_transaction(hash).refresh.succeeded?).to be true
        expect(client.load_transaction(hash).refresh.mined?).to be true
      end

      it "returns an transaction object that can be queried for transaction gas usage" do
        expect(client.load_transaction(hash).refresh.gas_used).to eq 21000
      end

      it "returns an transaction object that can be queried for transaction block number" do
        expect(client.load_transaction(hash).refresh.block_number).to eq 1
      end

      it "returns an transaction object that can be queried for transaction confirmations" do
        expect(client.load_transaction(hash).refresh.confirmations).to eq 1
        client.connection.evm_mine
        expect(client.load_transaction(hash).refresh.confirmations).to eq 2
      end
    end
  end

  context "given some contract interaction" do
    let(:abi_location) do
      File.expand_path('./spec/test_contract/build/contracts/TestContract.json')
    end

    let(:contract_class) { Etherlite::Abi.load_contract_at abi_location }

    let!(:contract) do
      tx = contract_class.deploy client: client, gas: 1000000
      tx.wait_for_block
      contract_class.at tx.contract_address, client: client
    end

    describe "#anonymous_account" do
      let(:anon_contract) { contract_class.at(contract.address, as: client.anonymous_account) }

      it "properly handles calls to constant functions" do
        expect(anon_contract.test_uint(726261)).to eq 726261
      end

      it "fails when calling non constant functions" do
        expect { anon_contract.test_events }.to raise_error(Etherlite::NotSupportedError)
      end
    end

    describe "#get_logs" do
      it "properly retrieves events generated by a contract" do
        expect { contract.test_event(-10, 30, 'foo') }
          .to change { client.get_logs(events: contract_class::TestEvent).count }
          .by(1)

        last_log = contract.get_logs.last
        expect(last_log).to be_a contract_class::TestEvent
      end

      it "properly filters logs by address if provided" do
        expect { contract.test_event(-10, 30, 'foo') }
          .to change { client.get_logs(address: contract.address).count }
          .by(1)

        expect { contract.test_event(-10, 30, 'foo') }
          .to change { client.get_logs(address: client.accounts.first.address).count }
          .by(0)
      end
    end
  end
end
