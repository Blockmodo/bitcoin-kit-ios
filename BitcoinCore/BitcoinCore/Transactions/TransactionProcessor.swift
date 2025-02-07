import RxSwift

class TransactionProcessor {
    private let storage: IStorage
    private let outputExtractor: ITransactionExtractor
    private let inputExtractor: ITransactionExtractor
    private let outputAddressExtractor: ITransactionOutputAddressExtractor
    private let outputsCache: IOutputsCache
    private let addressManager: IAddressManager

    weak var listener: IBlockchainDataListener?
    weak var transactionListener: ITransactionListener?

    private let dateGenerator: () -> Date
    private let queue: DispatchQueue

    init(storage: IStorage, outputExtractor: ITransactionExtractor, inputExtractor: ITransactionExtractor, outputsCache: IOutputsCache, outputAddressExtractor: ITransactionOutputAddressExtractor, addressManager: IAddressManager, listener: IBlockchainDataListener? = nil,
         dateGenerator: @escaping () -> Date = Date.init, queue: DispatchQueue = DispatchQueue(label: "Transactions", qos: .background
    )) {
        self.storage = storage
        self.outputExtractor = outputExtractor
        self.inputExtractor = inputExtractor
        self.outputAddressExtractor = outputAddressExtractor
        self.outputsCache = outputsCache
        self.addressManager = addressManager
        self.listener = listener
        self.dateGenerator = dateGenerator
        self.queue = queue
    }

    private func expiresBloomFilter(outputs: [Output]) -> Bool {
        for output in outputs {
            if output.publicKeyPath != nil, (output.scriptType == .p2wpkh || output.scriptType == .p2pk || output.scriptType == .p2wpkhSh)  {
                return true
            }
        }

        return false
    }

    private func process(transaction: FullTransaction) {
        outputExtractor.extract(transaction: transaction)
        if outputsCache.hasOutputs(forInputs: transaction.inputs) {
            transaction.header.isMine = true
            transaction.header.isOutgoing = true
        }

        guard transaction.header.isMine else {
            return
        }
        outputsCache.add(fromOutputs: transaction.outputs)
        outputAddressExtractor.extractOutputAddresses(transaction: transaction)
        inputExtractor.extract(transaction: transaction)
    }

    private func relay(transaction: Transaction, withOrder order: Int, inBlock block: Block?) {
        transaction.blockHash = block?.headerHash
        transaction.status = .relayed
        transaction.timestamp = block?.timestamp ?? Int(dateGenerator().timeIntervalSince1970)
        transaction.order = order

        if let block = block, !block.hasTransactions {
            block.hasTransactions = true
            storage.update(block: block)
        }
    }

}

extension TransactionProcessor: ITransactionProcessor {

    func processReceived(transactions: [FullTransaction], inBlock block: Block?, skipCheckBloomFilter: Bool) throws {
        var needToUpdateBloomFilter = false

        var updated = [Transaction]()
        var inserted = [Transaction]()

        try queue.sync {
            for (index, transaction) in transactions.inTopologicalOrder().enumerated() {
                if let existingTransaction = self.storage.transaction(byHash: transaction.header.dataHash) {
                    if existingTransaction.blockHash != nil && block == nil {
                        continue
                    }
                    self.relay(transaction: existingTransaction, withOrder: index, inBlock: block)
                    try self.storage.update(transaction: existingTransaction)
                    updated.append(existingTransaction)
                    continue
                }

                self.process(transaction: transaction)
                self.transactionListener?.onReceive(transaction: transaction)

                if transaction.header.isMine {
                    self.relay(transaction: transaction.header, withOrder: index, inBlock: block)
                    try self.storage.add(transaction: transaction)

                    inserted.append(transaction.header)

                    if !skipCheckBloomFilter {
                        needToUpdateBloomFilter = needToUpdateBloomFilter || self.addressManager.gapShifts() || self.expiresBloomFilter(outputs: transaction.outputs)
                    }
                }
            }
        }

        if !updated.isEmpty || !inserted.isEmpty {
            listener?.onUpdate(updated: updated, inserted: inserted, inBlock: block)
        }

        if needToUpdateBloomFilter {
            throw BloomFilterManager.BloomFilterExpired()
        }
    }

    func processCreated(transaction: FullTransaction) throws {
        guard storage.transaction(byHash: transaction.header.dataHash) == nil else {
            throw TransactionCreator.CreationError.transactionAlreadyExists
        }

        process(transaction: transaction)
        try storage.add(transaction: transaction)
        listener?.onUpdate(updated: [], inserted: [transaction.header], inBlock: nil)

        if expiresBloomFilter(outputs: transaction.outputs) {
            throw BloomFilterManager.BloomFilterExpired()
        }
    }

}
