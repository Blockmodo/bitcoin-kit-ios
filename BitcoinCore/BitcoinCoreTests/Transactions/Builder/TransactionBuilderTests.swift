import XCTest
import Cuckoo
@testable import BitcoinCore

public class SegWitAddress: Address, Equatable {
    public let type: AddressType
    public let keyHash: Data
    public let stringValue: String
    public let version: UInt8

    public var scriptType: ScriptType {
        switch type {
        case .pubKeyHash: return .p2wpkh
        case .scriptHash: return .p2wsh
        }
    }

    public init(type: AddressType, keyHash: Data, bech32: String, version: UInt8) {
        self.type = type
        self.keyHash = keyHash
        self.stringValue = bech32
        self.version = version
    }

    static public func ==<T: Address>(lhs: SegWitAddress, rhs: T) -> Bool {
        guard let rhs = rhs as? SegWitAddress else {
            return false
        }
        return lhs.type == rhs.type && lhs.keyHash == rhs.keyHash && lhs.version == rhs.version
    }
}

class TransactionBuilderTests: XCTestCase {

    private var mockUnspentOutputSelector: MockIUnspentOutputSelector!
    private var mockUnspentOutputProvider: MockIUnspentOutputProvider!
    private var mockAddressManager: MockIAddressManager!
    private var mockAddressConverter: MockIAddressConverter!
    private var mockInputSigner: MockIInputSigner!
    private var mockScriptBuilder: MockIScriptBuilder!
    private var mockFactory: MockIFactory!
    private var mockTransactionSizeCalculator: MockITransactionSizeCalculator!

    private var transactionBuilder: TransactionBuilder!

    private var unspentOutputs: SelectedUnspentOutputInfo!
    private var previousTransaction: FullTransaction!
    private var transaction: Transaction!
    private var toOutputPKH: Output!
    private var toOutputWPKH: Output!
    private var toOutputSH: Output!
    private var changeOutput: Output!
    private var inputToSign: InputToSign!
    private var totalInputValue: Int!
    private var value: Int!
    private var feeRate: Int!
    private var fee: Int!
    private var changePubKey: PublicKey!
    private var changePubKeyAddress: String!
    private var toAddressPKH: String!
    private var toAddressSH: String!
    private var toAddressWPKH: String!
    private var signature = Data(hex: "0000000000000000000111111111111222222222222")!
    private var signatureScript = Data(hex: "150000000000000000000111111111111222222222222")!

    override func setUp() {
        super.setUp()

        mockUnspentOutputSelector = MockIUnspentOutputSelector()
        mockUnspentOutputProvider = MockIUnspentOutputProvider()
        mockAddressManager = MockIAddressManager()
        mockAddressConverter = MockIAddressConverter()
        mockInputSigner = MockIInputSigner()
        mockScriptBuilder = MockIScriptBuilder()
        mockFactory = MockIFactory()
        mockTransactionSizeCalculator = MockITransactionSizeCalculator()

        transactionBuilder = TransactionBuilder(unspentOutputSelector: mockUnspentOutputSelector, unspentOutputProvider: mockUnspentOutputProvider, addressManager: mockAddressManager, addressConverter: mockAddressConverter, inputSigner: mockInputSigner, scriptBuilder: mockScriptBuilder, factory: mockFactory, transactionSizeCalculator: mockTransactionSizeCalculator)

        changePubKey = TestData.pubKey()
        changePubKeyAddress = "Rsfz3aRmCwTe2J8pSWSYRNYmweJ"

        toAddressPKH = "mzwSXvtPs7MFbW2ysNA4Gw3P2KjrcEWaE5"
        toAddressSH = "2MyQWMrsLsqAMSUeusduAzN6pWuH2V27ykE"
        toAddressWPKH = "bcrt1qsay3z5rn44v6du6c0u0eu352mm0sz3el0f0cs2"

        previousTransaction = TestData.p2pkhTransaction

        unspentOutputs = SelectedUnspentOutputInfo(
                unspentOutputs: [UnspentOutput(output: previousTransaction.outputs[0], publicKey: TestData.pubKey(), transaction: previousTransaction.header, blockHeight: 1000)],
                totalValue: previousTransaction.outputs[0].value, fee: 1008, addChangeOutput: true
        )
        totalInputValue = unspentOutputs.unspentOutputs[0].output.value
        value = 10782000
        feeRate = 6
        fee = 1008

        transaction = Transaction(version: 1, timestamp: 0)
        inputToSign = InputToSign(
                input: Input(withPreviousOutputTxHash: previousTransaction.header.dataHash, previousOutputIndex: unspentOutputs.unspentOutputs[0].output.index, script: Data(), sequence: 0),
                previousOutput: previousTransaction.outputs[0], previousOutputPublicKey: TestData.pubKey()
        )
        toOutputPKH = Output(withValue: value - fee, index: 0, lockingScript: Data(), type: .p2pkh, address: toAddressPKH, keyHash: nil)
        toOutputWPKH = Output(withValue: value - fee, index: 0, lockingScript: Data(), type: .p2wpkh, address: toAddressWPKH, keyHash: nil)
        toOutputSH = Output(withValue: value - fee, index: 0, lockingScript: Data(), type: .p2sh, address: toAddressSH, keyHash: nil)
        changeOutput = Output(withValue: totalInputValue - value, index: 1, lockingScript: Data(), type: .p2pkh, keyHash: changePubKey.keyHash)

        stub(mockUnspentOutputSelector) { mock in
            when(mock.select(value: any(), feeRate: any(), outputScriptType: any(), changeType: any(), senderPay: any())).thenReturn(unspentOutputs)
        }

        stub(mockUnspentOutputProvider) { mock in
            when(mock.allUnspentOutputs.get).thenReturn(unspentOutputs.unspentOutputs)
        }

        stub(mockAddressManager) { mock in
            when(mock.changePublicKey()).thenReturn(changePubKey)
        }

        stub(mockInputSigner) { mock in
            when(mock.sigScriptData(transaction: any(), inputsToSign: any(), outputs: any(), index: any())).thenReturn([signature])
        }

        stub(mockAddressConverter) { mock in
            when(mock.convert(address: toAddressPKH)).thenReturn(LegacyAddress(type: .pubKeyHash, keyHash: Data(hex: "d50bf226c9ff3bcf06f13d8ca129f24bedeef594")!, base58: "mzwSXvtPs7MFbW2ysNA4Gw3P2KjrcEWaE5"))
            when(mock.convert(address: toAddressSH)).thenReturn(LegacyAddress(type: .scriptHash, keyHash: Data(hex: "43922a3f1dc4569f9eccce9a71549d5acabbc0ca")!, base58: toAddressSH))
            when(mock.convert(address: toAddressWPKH)).thenReturn(SegWitAddress(type: .pubKeyHash, keyHash: Data(hex: "43922a3f1dc4569f9eccce9a71549d5acabbc0ca")!, bech32: "bcrt1qsay3z5rn44v6du6c0u0eu352mm0sz3el0f0cs2", version: 0))
            when(mock.convert(address: changePubKeyAddress)).thenReturn(LegacyAddress(type: .pubKeyHash, keyHash: changePubKey.keyHash, base58: changePubKeyAddress))
            when(mock.convert(keyHash: equal(to: changePubKey.keyHash), type: equal(to: .p2pkh))).thenReturn(LegacyAddress(type: .pubKeyHash, keyHash: changePubKey.keyHash, base58: changePubKeyAddress))
            //            when(mock.convert(address: any())).thenReturn(Address(type: .pubKeyHash, keyHash: Data(), base58: ""))
        }

        stub(mockScriptBuilder) { mock in
            when(mock.lockingScript(for: any())).thenReturn(Data())
        }

        stub(mockFactory) { mock in
            when(mock.transaction(version: any(), lockTime: any())).thenReturn(transaction)
            when(mock.inputToSign(withPreviousOutput: any(), script: any(), sequence: any())).thenReturn(inputToSign)
            when(mock.output(withValue: any(), index: any(), lockingScript: any(), type: equal(to: ScriptType.p2pkh), address: equal(to: toAddressPKH), keyHash: any(), publicKey: any())).thenReturn(toOutputPKH)
            when(mock.output(withValue: any(), index: any(), lockingScript: any(), type: equal(to: ScriptType.p2sh), address: equal(to: toAddressSH), keyHash: any(), publicKey: any())).thenReturn(toOutputSH)
            when(mock.output(withValue: any(), index: any(), lockingScript: any(), type: equal(to: ScriptType.p2wpkh), address: equal(to: toAddressWPKH), keyHash: any(), publicKey: any())).thenReturn(toOutputWPKH)
            when(mock.output(withValue: any(), index: any(), lockingScript: any(), type: equal(to: ScriptType.p2pkh), address: equal(to: changePubKeyAddress), keyHash: any(), publicKey: any())).thenReturn(changeOutput)
        }
    }

    override func tearDown() {
        unspentOutputs = nil
        mockUnspentOutputSelector = nil
        mockUnspentOutputProvider = nil
        mockAddressConverter = nil
        mockInputSigner = nil
        mockFactory = nil
        mockTransactionSizeCalculator = nil
        transactionBuilder = nil
        changePubKey = nil
        toAddressPKH = nil
        toAddressSH = nil
        value = nil
        feeRate = nil
        fee = nil

        super.tearDown()
    }

    func testFee_AddressGiven() {
        let resultFee = try! transactionBuilder.fee(for: value, feeRate: feeRate, senderPay: false, address: toAddressPKH, changeScriptType: .p2pkh)
        XCTAssertEqual(resultFee, 546)
    }

    func testFee_AddressGiven_Error() {
        stub(mockAddressConverter) { mock in
            when(mock.convert(address: toAddressPKH)).thenThrow(BitcoinCoreErrors.AddressConversion.invalidAddressLength)
        }

        do {
            let _ = try transactionBuilder.fee(for: value, feeRate: feeRate, senderPay: false, address: toAddressPKH, changeScriptType: .p2pkh)
        } catch let error as BitcoinCoreErrors.AddressConversion {
            XCTAssertEqual(error, BitcoinCoreErrors.AddressConversion.invalidAddressLength)
        } catch let error {
            XCTFail(error.localizedDescription)
        }
    }

    func testFee_AddressNotGiven_Error() {
        let resultFee = try! transactionBuilder.fee(for: value, feeRate: feeRate, senderPay: false, changeScriptType: .p2pkh)
        XCTAssertEqual(resultFee, fee)
    }

    func testBuildTransaction_P2PKH() {
        let resultTx = try! transactionBuilder.buildTransaction(value: value, feeRate: feeRate, senderPay: false, toAddress: toAddressPKH, changeScriptType: .p2pkh)

        XCTAssertNotEqual(resultTx.header.dataHash, Data())
        XCTAssertEqual(resultTx.header.status, .new)
        XCTAssertEqual(resultTx.header.isMine, true)
        XCTAssertEqual(resultTx.header.segWit, false)
        XCTAssertEqual(resultTx.inputs.count, 1)
        XCTAssertEqual(resultTx.inputs[0].signatureScript, signatureScript)
        XCTAssertEqual(resultTx.inputs[0].witnessData.count, 0)
        XCTAssertEqual(resultTx.inputs[0].previousOutputTxHash, unspentOutputs.unspentOutputs[0].output.transactionHash)
        XCTAssertEqual(resultTx.inputs[0].previousOutputIndex, unspentOutputs.unspentOutputs[0].output.index)
        XCTAssertEqual(resultTx.outputs.count, 2)
        XCTAssertEqual(resultTx.outputs[0].address, toAddressPKH)
        XCTAssertEqual(resultTx.outputs[0].value, value - fee)
        XCTAssertEqual(resultTx.outputs[1].keyHash, changePubKey.keyHash)
        XCTAssertEqual(resultTx.outputs[1].value, unspentOutputs.unspentOutputs[0].output.value - value)

        verify(mockFactory).output(withValue: value - fee, index: 0, lockingScript: any(), type: equal(to: ScriptType.p2pkh), address: equal(to: toAddressPKH), keyHash: any(), publicKey: any())
        verify(mockFactory).output(withValue: unspentOutputs.unspentOutputs[0].output.value - value, index: 1, lockingScript: any(), type: equal(to: ScriptType.p2pkh), address: equal(to: changePubKeyAddress), keyHash: any(), publicKey: any())
    }

// todo: Extrect build witness transaction data to bitcoinKit chain
//    func testBuildTransaction_P2WPKH() {
//        let previousTransaction = TestData.p2wpkhTransaction
//
//        unspentOutputs = SelectedUnspentOutputInfo(
//                unspentOutputs: [UnspentOutput(output: previousTransaction.outputs[0], publicKey: TestData.pubKey(), transaction: previousTransaction.header, blockHeight: nil)],
//                totalValue: previousTransaction.outputs[0].value, fee: 1008, addChangeOutput: true
//        )
//        totalInputValue = unspentOutputs.unspentOutputs[0].output.value
//        value = 10782000
//        feeRate = 6
//        fee = 1008
//        inputToSign = InputToSign(
//                input: Input(withPreviousOutputTxReversedHex: previousTransaction.header.dataHashReversedHex, previousOutputIndex: unspentOutputs.unspentOutputs[0].output.index, script: Data(), sequence: 0),
//                previousOutput: previousTransaction.outputs[0], previousOutputPublicKey: TestData.pubKey()
//        )
//
//        stub(mockFactory) { mock in
//            when(mock.inputToSign(withPreviousOutput: any(), script: any(), sequence: any())).thenReturn(inputToSign)
//        }
//        stub(mockUnspentOutputSelector) { mock in
//            when(mock.select(value: any(), feeRate: any(), outputScriptType: any(), changeType: any(), senderPay: any(), unspentOutputs: any())).thenReturn(unspentOutputs)
//        }
//
//        stub(mockUnspentOutputProvider) { mock in
//            when(mock.allUnspentOutputs.get).thenReturn(unspentOutputs.unspentOutputs)
//        }
//
//        let resultTx = try! transactionBuilder.buildTransaction(value: value, feeRate: feeRate, senderPay: false, toAddress: toAddressWPKH)
//
//        XCTAssertNotEqual(resultTx.header.dataHashReversedHex, "")
//        XCTAssertEqual(resultTx.header.status, .new)
//        XCTAssertEqual(resultTx.header.isMine, true)
//        XCTAssertEqual(resultTx.header.segWit, true)
//        XCTAssertEqual(resultTx.inputs.count, 1)
//        XCTAssertEqual(resultTx.inputs[0].signatureScript.count, 0)
//        XCTAssertEqual(resultTx.inputs[0].witnessData.count, 1)
//        XCTAssertEqual(resultTx.inputs[0].witnessData[0], signature)
//        XCTAssertEqual(resultTx.inputs[0].previousOutputTxReversedHex, unspentOutputs.unspentOutputs[0].output.transactionHash)
//        XCTAssertEqual(resultTx.inputs[0].previousOutputIndex, unspentOutputs.unspentOutputs[0].output.index)
//        XCTAssertEqual(resultTx.outputs.count, 2)
//        XCTAssertEqual(resultTx.outputs[0].address, toAddressWPKH)
//        XCTAssertEqual(resultTx.outputs[1].keyHash, changePubKey.keyHash)
//
//        verify(mockFactory).output(withValue: value - fee, index: 0, lockingScript: any(), type: equal(to: ScriptType.p2wpkh), address: equal(to: toAddressWPKH), keyHash: any(), publicKey: any())
//        verify(mockFactory).output(withValue: unspentOutputs.unspentOutputs[0].output.value - value, index: 1, lockingScript: any(), type: equal(to: ScriptType.p2pkh), address: equal(to: changePubKeyAddress), keyHash: any(), publicKey: any())
//
//    }

    func testBuildTransaction_P2SH() {
        let resultTx = try! transactionBuilder.buildTransaction(value: value, feeRate: feeRate, senderPay: false, toAddress: toAddressSH, changeScriptType: .p2pkh)

        XCTAssertNotEqual(resultTx.header.dataHash, Data())
        XCTAssertEqual(resultTx.header.status, .new)
        XCTAssertEqual(resultTx.header.isMine, true)
        XCTAssertEqual(resultTx.inputs.count, 1)
        XCTAssertEqual(resultTx.inputs[0].previousOutputTxHash, unspentOutputs.unspentOutputs[0].output.transactionHash)
        XCTAssertEqual(resultTx.inputs[0].previousOutputIndex, unspentOutputs.unspentOutputs[0].output.index)
        XCTAssertEqual(resultTx.outputs.count, 2)
        XCTAssertEqual(resultTx.outputs[0].address, toAddressSH)
        XCTAssertEqual(resultTx.outputs[0].value, value - fee)
        XCTAssertEqual(resultTx.outputs[1].keyHash, changePubKey.keyHash)

        verify(mockFactory).output(withValue: value - fee, index: 0, lockingScript: any(), type: equal(to: ScriptType.p2sh), address: equal(to: toAddressSH), keyHash: any(), publicKey: any())
        verify(mockFactory).output(withValue: unspentOutputs.unspentOutputs[0].output.value - value, index: 1, lockingScript: any(), type: equal(to: ScriptType.p2pkh), address: equal(to: changePubKeyAddress), keyHash: any(), publicKey: any())
    }

    func testBuildTransactionSenderPay() {
        _ = try! transactionBuilder.buildTransaction(value: value, feeRate: feeRate, senderPay: true, toAddress: toAddressPKH, changeScriptType: .p2pkh)

        verify(mockFactory).output(withValue: value, index: 0, lockingScript: any(), type: equal(to: ScriptType.p2pkh), address: equal(to: toAddressPKH), keyHash: any(), publicKey: any())
        verify(mockFactory).output(withValue: unspentOutputs.unspentOutputs[0].output.value - value - fee, index: 1, lockingScript: any(), type: equal(to: ScriptType.p2pkh), address: equal(to: changePubKeyAddress), keyHash: any(), publicKey: any())
    }

    func testBuildTransaction_WithoutChangeOutput() {
        value = totalInputValue
        unspentOutputs = SelectedUnspentOutputInfo(unspentOutputs: unspentOutputs.unspentOutputs, totalValue: unspentOutputs.totalValue, fee: unspentOutputs.fee, addChangeOutput: false)
        stub(mockUnspentOutputSelector) { mock in
            when(mock.select(value: any(), feeRate: any(), outputScriptType: any(), changeType: any(), senderPay: any())).thenReturn(unspentOutputs)
        }

        let resultTx = try! transactionBuilder.buildTransaction(value: value, feeRate: feeRate, senderPay: false, toAddress: toAddressPKH, changeScriptType: .p2pkh)

        XCTAssertEqual(resultTx.inputs.count, 1)
        XCTAssertEqual(resultTx.inputs[0].previousOutputTxHash, unspentOutputs.unspentOutputs[0].output.transactionHash)
        XCTAssertEqual(resultTx.inputs[0].previousOutputIndex, unspentOutputs.unspentOutputs[0].output.index)
        XCTAssertEqual(resultTx.outputs.count, 1)
        XCTAssertEqual(resultTx.outputs[0].address, toAddressPKH)
        verify(mockFactory).output(withValue: Int(value - fee), index: 0, lockingScript: equal(to: Data()), type: equal(to: ScriptType.p2pkh), address: equal(to: toAddressPKH), keyHash: any(), publicKey: any())
    }

    func testBuildTransaction_ChangeNotAddedForDust() {
        value = totalInputValue - TransactionSizeCalculator().outputSize(type: .p2pkh) * feeRate
        unspentOutputs = SelectedUnspentOutputInfo(unspentOutputs: unspentOutputs.unspentOutputs, totalValue: unspentOutputs.totalValue, fee: unspentOutputs.fee, addChangeOutput: false)
        stub(mockUnspentOutputSelector) { mock in
            when(mock.select(value: any(), feeRate: any(), outputScriptType: any(), changeType: any(), senderPay: any())).thenReturn(unspentOutputs)
        }

        let resultTx = try! transactionBuilder.buildTransaction(value: value, feeRate: feeRate, senderPay: false, toAddress: toAddressPKH, changeScriptType: .p2pkh)

        XCTAssertEqual(resultTx.inputs.count, 1)
        XCTAssertEqual(resultTx.inputs[0].previousOutputTxHash, unspentOutputs.unspentOutputs[0].output.transactionHash)
        XCTAssertEqual(resultTx.inputs[0].previousOutputIndex, unspentOutputs.unspentOutputs[0].output.index)
        XCTAssertEqual(resultTx.outputs.count, 1)
        XCTAssertEqual(resultTx.outputs[0].address, toAddressPKH)
        verify(mockFactory).output(withValue: Int(value - fee), index: 0, lockingScript: equal(to: Data()), type: equal(to: ScriptType.p2pkh), address: equal(to: toAddressPKH), keyHash: any(), publicKey: any())
    }

    func testBuildTransaction_InputsSigned() {
        let sigData = [Data(hex: "000001")!, Data(hex: "000002")!]
        let sigScript = Data(hex: "0300000103000002")!

        stub(mockInputSigner) { mock in
            when(mock.sigScriptData(transaction: any(), inputsToSign: any(), outputs: any(), index: any())).thenReturn(sigData)
        }

        let resultTx = try! transactionBuilder.buildTransaction(value: value, feeRate: feeRate, senderPay: false, toAddress: toAddressPKH, changeScriptType: .p2pkh)
        XCTAssertEqual(resultTx.inputs[0].signatureScript, sigScript)
    }

    func testBuildTransaction_feeMoreThanValue() {
        unspentOutputs = SelectedUnspentOutputInfo(
                unspentOutputs: [UnspentOutput(output: previousTransaction.outputs[0], publicKey: TestData.pubKey(), transaction: previousTransaction.header, blockHeight: nil)],
                totalValue: previousTransaction.outputs[0].value, fee: value, addChangeOutput: true
        )

        do {
            let _ = try transactionBuilder.buildTransaction(value: value, feeRate: feeRate, senderPay: false, toAddress: toAddressPKH, changeScriptType: .p2pkh)
        } catch let error as TransactionBuilder.BuildError {
            XCTAssertEqual(error, TransactionBuilder.BuildError.feeMoreThanValue)
        } catch let error {
            XCTFail(error.localizedDescription)
        }
    }

    func testBuildTransaction_noChangeAddress() {
        stub(mockAddressManager) { mock in
            when(mock.changePublicKey()).thenThrow(AddressManager.AddressManagerError.noUnusedPublicKey)
        }

        do {
            let _ = try transactionBuilder.buildTransaction(value: value, feeRate: feeRate, senderPay: false, toAddress: toAddressPKH, changeScriptType: .p2pkh)
            XCTFail("No exception!")
        } catch let error as TransactionBuilder.BuildError {
            XCTAssertEqual(error, TransactionBuilder.BuildError.noChangeAddress)
        } catch {
            XCTFail("Unexpected exception!")
        }
    }

    func testBuildTransaction_FromUnspentOutput_P2SH() {
        let sigData = [Data(hex: "000001")!, Data(hex: "000002")!]
        let value = 1000000

        stub(mockInputSigner) { mock in
            when(mock.sigScriptData(transaction: any(), inputsToSign: any(), outputs: any(), index: any())).thenReturn(sigData)
        }
        stub(mockTransactionSizeCalculator) { mock in
            when(mock.transactionSize(inputs: equal(to: [ScriptType.p2sh]), outputScriptTypes: equal(to: [ScriptType.p2pkh]))).thenReturn(90)
        }

        let previousTransaction = TestData.p2shTransaction
        previousTransaction.outputs[0].value = value
        let unspentOutput = UnspentOutput(output: previousTransaction.outputs[0], publicKey: TestData.pubKey(), transaction: previousTransaction.header, blockHeight: nil)
        let signatureScript = Data(repeating: 0, count: 10)
        var calledWithSignatureAndPublicKey = false
        let signatureScriptFunction: ((Data, Data) -> Data) = { (signature: Data, publicKey: Data) in
            if signature == sigData[0] {
                XCTAssertEqual(signature, sigData[0])
                XCTAssertEqual(publicKey, sigData[1])
                calledWithSignatureAndPublicKey = true
            }
            return signatureScript
        }
        let fee = (10 + 90) * feeRate

        let resultTx = try! transactionBuilder.buildTransaction(from: unspentOutput, to: toAddressPKH, feeRate: feeRate, signatureScriptFunction: signatureScriptFunction)

        XCTAssertNotEqual(resultTx.header.dataHash, Data())
        XCTAssertEqual(resultTx.header.status, .new)
        XCTAssertEqual(resultTx.header.isMine, true)
        XCTAssertEqual(resultTx.header.segWit, false)
        XCTAssertEqual(resultTx.header.isOutgoing, false)
        XCTAssertEqual(resultTx.inputs.count, 1)
        XCTAssertEqual(resultTx.outputs.count, 1)
        XCTAssertEqual(resultTx.inputs[0].signatureScript, signatureScript)

        verify(mockFactory).inputToSign(withPreviousOutput: equal(to: unspentOutput), script: equal(to: Data()), sequence: 0xFFFFFFFF)
        verify(mockFactory).output(withValue: value - fee, index: 0, lockingScript: any(), type: equal(to: ScriptType.p2pkh), address: equal(to: toAddressPKH), keyHash: any(), publicKey: any())
        XCTAssertTrue(calledWithSignatureAndPublicKey)
    }

    func testBuildTransaction_FromUnspentOutput_FeeMoreThanValue() {
        let sigData = [Data(hex: "000001")!, Data(hex: "000002")!]
        stub(mockInputSigner) { mock in
            when(mock.sigScriptData(transaction: any(), inputsToSign: any(), outputs: any(), index: any())).thenReturn(sigData)
        }
        stub(mockTransactionSizeCalculator) { mock in
            when(mock.transactionSize(inputs: equal(to: [ScriptType.p2sh]), outputScriptTypes: equal(to: [ScriptType.p2pkh]))).thenReturn(90)
        }

        let previousTransaction = TestData.p2shTransaction
        let unspentOutput = UnspentOutput(output: previousTransaction.outputs[0], publicKey: TestData.pubKey(), transaction: previousTransaction.header, blockHeight: nil)
        let signatureScript = Data(repeating: 0, count: 10)
        let signatureScriptFunction: ((Data, Data) -> Data) = { (signature: Data, publicKey: Data) in
            return signatureScript
        }
        let fee = (10 + 90) * feeRate
        previousTransaction.outputs[0].value = fee - 1

        do {
            _ = try transactionBuilder.buildTransaction(from: unspentOutput, to: toAddressPKH, feeRate: feeRate, signatureScriptFunction: signatureScriptFunction)
        } catch let error as TransactionBuilder.BuildError {
            XCTAssertEqual(error, TransactionBuilder.BuildError.feeMoreThanValue)
        } catch let error {
            XCTFail(error.localizedDescription)
        }

    }

}
