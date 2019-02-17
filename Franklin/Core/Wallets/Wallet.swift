//
//  KeyWallet.swift
//  DiveLane
//
//  Created by Anton Grigorev on 08/09/2018.
//  Copyright © 2018 Matter Inc. All rights reserved.
//

import Foundation
import Web3swift
import EthereumAddress
import CoreData
import BigInt
import PromiseKit
private typealias PromiseResult = PromiseKit.Result

protocol IWallet {
    func getPrivateKey(withPassword: String) throws -> String
    func getHDKey() -> HDKey
    func getPassword() throws -> String
    func addPassword(_ password: String) throws
}

protocol IWalletStorage {
    func select() throws
    func save() throws
    func delete() throws
}

protocol IWalletTokens {
    func select(token: ERC20Token, network: Web3Network) throws
    func setBalance(token: ERC20Token, network: Web3Network, balance: String) throws
    func setUsdBalance(token: ERC20Token, network: Web3Network, usdBalance: String) throws
    func add(token: ERC20Token, network: Web3Network) throws
    func performBackup() throws
    func delete(token: ERC20Token, network: Web3Network) throws
    func getAllTokens(network: Web3Network) throws -> [ERC20Token]
    func getSelectedToken(network: Web3Network) throws -> ERC20Token
}

protocol IWalletBlock {
    func getBlockNumber(_ web3instance: web3?) throws -> BigUInt
    func getBlock(_ web3instance: web3?) throws -> String
}

protocol IWalletTransactions {
    func loadTransactions(txType: TransactionType?,
                          network: Web3Network) throws -> [ETHTransaction]
    func save(transactions: [ETHTransaction]) throws
    func getAllTransactions(for network: Web3Network) throws -> [ETHTransaction]
}

protocol IWalletActions {
    func getFranklinBalance() throws -> String
    func getERC20balance(for token: ERC20Token, web3instance: web3?) throws -> String
    func getETHbalance(web3instance: web3?) throws -> String
    func prepareSendEthTx(web3instance: web3?,
                          toAddress: String,
                          value: String,
                          gasLimit: TransactionOptions.GasLimitPolicy,
                          gasPrice: TransactionOptions.GasPricePolicy) throws -> WriteTransaction
    func prepareSendERC20Tx(web3instance: web3?,
                            token: ERC20Token,
                            toAddress: String,
                            tokenAmount: String,
                            gasLimit: TransactionOptions.GasLimitPolicy,
                            gasPrice: TransactionOptions.GasPricePolicy) throws -> WriteTransaction
    func prepareWriteContractTx(web3instance: web3?,
                                contractABI: String,
                                contractAddress: String,
                                contractMethod: String,
                                value: String,
                                gasLimit: TransactionOptions.GasLimitPolicy,
                                gasPrice: TransactionOptions.GasPricePolicy,
                                parameters: [AnyObject],
                                extraData: Data) throws -> WriteTransaction
    func prepareReadContractTx(web3instance: web3?,
                               contractABI: String,
                               contractAddress: String,
                               contractMethod: String,
                               gasLimit: TransactionOptions.GasLimitPolicy,
                               gasPrice: TransactionOptions.GasPricePolicy,
                               parameters: [AnyObject],
                               extraData: Data) throws -> ReadTransaction
    func sendTx(transaction: WriteTransaction,
                options: TransactionOptions?,
                password: String) throws -> TransactionSendingResult
    func callTx(transaction: ReadTransaction,
                options: TransactionOptions?) throws -> [String : Any]
}

protocol IWalletPlasma {
    func getID() throws -> BigUInt
    func setID(_ id: String) throws
    func getIgnisBalance(network: Web3Network) throws -> String
    func getIgnisNonce(network: Web3Network) throws -> BigUInt
    func sendPlasmaTx(nonce: BigUInt, to: EthereumAddress, value: String, network: Web3Network) throws -> Bool
    //func loadTransactions(network: Web3Network) throws -> [ETHTransaction]
}

protocol IWalletXDAI {
    func getXDAIBalance() throws -> String
    func getXDAITransactions() throws -> [ETHTransaction]
    func getXDAITokens() throws -> [ERC20Token]
    func prepareSendXDaiTx(web3instance: web3?,
                           toAddress: String,
                           value: String,
                           gasLimit: TransactionOptions.GasLimitPolicy,
                           gasPrice: TransactionOptions.GasPricePolicy) throws -> WriteTransaction
    func prepareSendERC20XDaiTx(web3instance: web3?,
                                token: ERC20Token,
                                toAddress: String,
                                tokenAmount: String,
                                gasLimit: TransactionOptions.GasLimitPolicy,
                                gasPrice: TransactionOptions.GasPricePolicy) throws -> WriteTransaction
}

public class Wallet: IWallet {
    let address: String
    let data: Data
    let name: String
    let isHD: Bool
    var plasmaID: String?
    var backup: String?
    
    private func request(url: URL,
                         data: Data?,
                         method: Method,
                         contentType: ContentType) -> URLRequest? {
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = true
        request.httpMethod = method.rawValue
        request.setValue(contentType.rawValue, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        return request
    }
    
    var session: URLSession {
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig,
                                 delegate: nil,
                                 delegateQueue: nil)
        return session
    }
    
    private var web3Instance: web3? {
        get {
            let web3 = CurrentNetwork.currentWeb
            let keystoreManager = self.keystoreManager
            web3?.addKeystoreManager(keystoreManager)
            return web3
        }
        set (web3) {
            let keystoreManager = self.keystoreManager
            web3Instance?.addKeystoreManager(keystoreManager)
        }
    }
    
    public func changeWeb3(_ web3: web3) {
        self.web3Instance = web3
    }
    
    public var keystoreManager: KeystoreManager? {
        if self.isHD {
            guard let keystore = BIP32Keystore(data) else {
                return KeystoreManager.defaultManager
            }
            return KeystoreManager([keystore])
        } else {
            guard let keystore = EthereumKeystoreV3(data) else {
                return KeystoreManager.defaultManager
            }
            return KeystoreManager([keystore])
        }
    }

    public init(crModel: WalletModel) throws {
        guard let address = crModel.address,
            let data = crModel.data,
            let name = crModel.name else {
                throw Web3Error.walletError
        }
        let backup = crModel.backup
        let plasmaID = crModel.plasmaID
        
        self.address = address
        self.data = data
        self.name = name
        self.isHD = crModel.isHD
        self.backup = backup
        self.plasmaID = plasmaID
    }
    
    public init(address: String,
                data: Data,
                name: String,
                isHD: Bool,
                backup: String?,
                plasmaID: String?) {
        self.address = address
        self.data = data
        self.name = name
        self.isHD = isHD
        self.backup = backup
        self.plasmaID = plasmaID
    }
    
    public init(wallet: Wallet) {
        self.address = wallet.address
        self.data = wallet.data
        self.name = wallet.name
        self.isHD = wallet.isHD
        self.backup = wallet.backup
        self.plasmaID = wallet.plasmaID
    }
    
    public func getPrivateKey(withPassword: String) throws -> String {
        do {
            guard let ethereumAddress = EthereumAddress(self.address) else {
                throw Web3Error.walletError
            }
            guard let manager = self.keystoreManager else {
                throw Web3Error.keystoreError(err: .invalidAccountError)
            }
            let pkData = try manager.UNSAFE_getPrivateKeyData(password: withPassword, account: ethereumAddress)
            return pkData.toHexString()
        } catch let error {
            throw error
        }
    }
    
    public func getHDKey() -> HDKey {
        return HDKey(name: self.name,
                     address: self.address)
    }
    
    public func getPassword() throws -> String {
        do {
            let passwordItem = KeychainPasswordItem(service: KeychainConfiguration.serviceNameForPassword,
                                                    account: "\(self.name)-password",
                accessGroup: KeychainConfiguration.accessGroup)
            let keychainPassword = try passwordItem.readPassword()
            return keychainPassword
        } catch let error {
            throw error
        }
    }
    
    public func addPassword(_ password: String) throws {
        do {
            let passwordItem = KeychainPasswordItem(service: KeychainConfiguration.serviceNameForPassword,
                                                    account: "\(self.name)-password",
                accessGroup: KeychainConfiguration.accessGroup)
            try passwordItem.savePassword(password)
        } catch let error {
            throw error
        }
    }
}

extension Wallet: IWalletStorage {
    public func save() throws {
        let group = DispatchGroup()
        group.enter()
        var error: Error?
        ContainerCD.persistentContainer.performBackgroundTask { (context) in
            guard let entity = NSEntityDescription.insertNewObject(forEntityName: "WalletModel", into: context) as? WalletModel else {
                error = Errors.StorageErrors.cantCreateWallet
                group.leave()
                return
            }
            entity.address = self.address
            entity.data = self.data
            entity.name = self.name
            entity.isHD = self.isHD
            entity.backup = self.backup
            do {
                try context.save()
                group.leave()
            } catch let someErr {
                error = someErr
                group.leave()
            }
        }
        group.wait()
        if let resErr = error {
            throw resErr
        }
    }
    
    public func select() throws {
        let group = DispatchGroup()
        group.enter()
        var error: Error?
        let requestWallet: NSFetchRequest<WalletModel> = WalletModel.fetchRequest()
        do {
            let results = try ContainerCD.context.fetch(requestWallet)
            for item in results {
                let isEqual = item.address == self.address
                item.isSelected = isEqual
            }
            try ContainerCD.context.save()
            group.leave()
        } catch let someErr {
            error = someErr
            group.leave()
        }
        group.wait()
        if let resErr = error {
            throw resErr
        }
    }
    
    public func performBackup() throws {
        let group = DispatchGroup()
        group.enter()
        var error: Error?
        let requestWallet: NSFetchRequest<WalletModel> = WalletModel.fetchRequest()
        do {
            let results = try ContainerCD.context.fetch(requestWallet)
            for item in results {
                if item.address == self.address {
                    item.backup = nil
                }
            }
            try ContainerCD.context.save()
            group.leave()
        } catch let someErr {
            error = someErr
            group.leave()
        }
        group.wait()
        if let resErr = error {
            throw resErr
        }
    }
    
    public func delete() throws {
        let group = DispatchGroup()
        group.enter()
        var error: Error?
        let requestWallet: NSFetchRequest<WalletModel> = WalletModel.fetchRequest()
        requestWallet.predicate = NSPredicate(format: "address = %@", self.address)
        do {
            let results = try ContainerCD.context.fetch(requestWallet)
            guard let wallet = results.first else {
                error = Errors.StorageErrors.wrongWallet
                group.leave()
                return
            }
            ContainerCD.context.delete(wallet)
            try ContainerCD.context.save()
            group.leave()
        } catch let someErr {
            error = someErr
            group.leave()
        }
        group.wait()
        if let resErr = error {
            throw resErr
        }
    }
}

extension Wallet: IWalletTokens {
    
    func getSelectedToken(network: Web3Network) throws -> ERC20Token {
        do {
            let requestTokens: NSFetchRequest<ERC20TokenModel> = ERC20TokenModel.fetchRequest()
            requestTokens.predicate = NSPredicate(format:
                "networkId == %@ && isAdded == %@ && isSelected == %@ && walletAddress == %@",
                                                  NSNumber(value: network.id),
                                                  NSNumber(value: true),
                                                  NSNumber(value: true),
                                                  NSString(string: self.address)
            )
            let results = try ContainerCD.context.fetch(requestTokens)
            guard let result = results.first else {
                throw Errors.StorageErrors.cantGetToken
            }
            return try ERC20Token(crModel: result)
        } catch let error {
            throw error
        }
    }
    
    public func select(token: ERC20Token, network: Web3Network) throws {
        let group = DispatchGroup()
        group.enter()
        var error: Error?
        let requestToken: NSFetchRequest<ERC20TokenModel> = ERC20TokenModel.fetchRequest()
        requestToken.predicate = NSPredicate(format:
            "networkId == %@ && isAdded == %@ && walletAddress == %@",
                                              NSNumber(value: network.id),
                                              NSNumber(value: true),
                                              NSString(string: self.address)
        )
        do {
            let results = try ContainerCD.context.fetch(requestToken)
            for item in results {
                let isEqual = item.address == token.address
                item.isSelected = isEqual
            }
            try ContainerCD.context.save()
            group.leave()
        } catch let someErr {
            error = someErr
            group.leave()
        }
        group.wait()
        if let resErr = error {
            throw resErr
        }
    }
    
    public func setBalance(token: ERC20Token, network: Web3Network, balance: String) throws {
        let group = DispatchGroup()
        group.enter()
        var error: Error?
        let requestToken: NSFetchRequest<ERC20TokenModel> = ERC20TokenModel.fetchRequest()
        requestToken.predicate = NSPredicate(format:
            "networkId == %@ && isAdded == %@ && walletAddress == %@",
                                             NSNumber(value: network.id),
                                             NSNumber(value: true),
                                             NSString(string: self.address),
                                             NSString(string: token.address)
        )
        do {
            let results = try ContainerCD.context.fetch(requestToken)
            for item in results {
                if item.address == token.address {
                    item.balance = balance
                }
            }
            try ContainerCD.context.save()
            group.leave()
        } catch let someErr {
            error = someErr
            group.leave()
        }
        group.wait()
        if let resErr = error {
            throw resErr
        }
    }
    
    public func setUsdBalance(token: ERC20Token, network: Web3Network, usdBalance: String) throws {
        let group = DispatchGroup()
        group.enter()
        var error: Error?
        let requestToken: NSFetchRequest<ERC20TokenModel> = ERC20TokenModel.fetchRequest()
        requestToken.predicate = NSPredicate(format:
            "networkId == %@ && isAdded == %@ && walletAddress == %@",
                                             NSNumber(value: network.id),
                                             NSNumber(value: true),
                                             NSString(string: self.address),
                                             NSString(string: token.address)
        )
        do {
            let results = try ContainerCD.context.fetch(requestToken)
            for item in results {
                if item.address == token.address {
                    item.usdBalance = usdBalance
                }
            }
            try ContainerCD.context.save()
            group.leave()
        } catch let someErr {
            error = someErr
            group.leave()
        }
        group.wait()
        if let resErr = error {
            throw resErr
        }
    }
    
    public func add(token: ERC20Token, network: Web3Network) throws {
        let group = DispatchGroup()
        group.enter()
        var error: Error?
        ContainerCD.persistentContainer.performBackgroundTask { (context) in
            guard let entity = NSEntityDescription.insertNewObject(forEntityName: "ERC20TokenModel",
                                                                   into: context) as? ERC20TokenModel else {
                                                                    error = Errors.StorageErrors.cantCreateToken
                                                                    group.leave()
                                                                    return
            }
            entity.address = token.address
            entity.name = token.name
            entity.symbol = token.symbol
            entity.decimals = token.decimals
            entity.isAdded = true
            entity.walletAddress = self.address
            entity.networkId = network.id
            do {
                try context.save()
                group.leave()
            } catch let someErr {
                error = someErr
                group.leave()
            }
        }
        group.wait()
        if let resErr = error {
            throw resErr
        }
    }
    
    public func delete(token: ERC20Token, network: Web3Network) throws {
        let group = DispatchGroup()
        group.enter()
        var error: Error?
        let requestToken: NSFetchRequest<ERC20TokenModel> = ERC20TokenModel.fetchRequest()
        requestToken.predicate = NSPredicate(format:
            "networkId == %@ && isAdded == %@ && walletAddress == %@ && address == %@",
                                             NSNumber(value: network.id),
                                             NSNumber(value: true),
                                             NSString(string: self.address),
                                             NSString(string: token.address)
        )
        do {
            let results = try ContainerCD.context.fetch(requestToken)
            guard let result = results.first else {
                error = Errors.StorageErrors.wrongToken
                group.leave()
                return
            }
            ContainerCD.context.delete(result)
            try ContainerCD.context.save()
            group.leave()
        } catch let someErr {
            error = someErr
            group.leave()
        }
        group.wait()
        if let resErr = error {
            throw resErr
        }
    }
    
    public func getAllTokens(network: Web3Network) throws -> [ERC20Token] {
        do {
            let requestTokens: NSFetchRequest<ERC20TokenModel> = ERC20TokenModel.fetchRequest()
            requestTokens.predicate = NSPredicate(format:
                "networkId == %@ && isAdded == %@ && walletAddress == %@",
                                                  NSNumber(value: network.id),
                                                  NSNumber(value: true),
                                                  NSString(string: self.address)
            )
            let results = try ContainerCD.context.fetch(requestTokens)
            return try results.map {
                return try ERC20Token(crModel: $0)
            }
        } catch let error {
            throw error
        }
    }
}

extension Wallet: IWalletActions {
    
    public func getFranklinBalance() throws -> String {
        let id = try self.getID()
        try self.setID(String(id))
        print(id)
        
        let currentNetwork = CurrentNetwork.currentNetwork
        let balance = try self.getIgnisBalance(network: currentNetwork)
        return balance
    }
    
    public func getETHbalance(web3instance: web3? = nil) throws -> String {
        guard let web3 = web3instance ?? self.web3Instance else {
            throw Web3Error.walletError
        }
        web3.addKeystoreManager(self.keystoreManager)
        guard let walletAddress = EthereumAddress(self.address),
            let balanceResult = try? web3.eth.getBalance(address: walletAddress)
             else {
            throw Web3Error.walletError
        }
        guard let balanceString = Web3.Utils.formatToEthereumUnits(balanceResult, toUnits: .eth, decimals: 3) else {
            throw Web3Error.dataError
        }
        return balanceString
    }
    
    public func getERC20balance(for token: ERC20Token, web3instance: web3? = nil) throws -> String {
        guard let web3 = web3instance ?? self.web3Instance else {
            throw Web3Error.walletError
        }
        web3.addKeystoreManager(self.keystoreManager)
        do {
            guard let walletAddress = EthereumAddress(self.address) else {
                    throw Web3Error.walletError
            }
            let tx = try self.prepareReadContractTx(web3instance: web3,
                                                    contractABI: Web3.Utils.erc20ABI,
                                                    contractAddress: token.address,
                                                    contractMethod: "balanceOf",
                                                    gasLimit: .automatic,
                                                    gasPrice: .automatic,
                                                    parameters: [walletAddress] as [AnyObject],
                                                    extraData: Data())
            let tokenBalance = try self.callTx(transaction: tx)
            guard let balanceResult = tokenBalance["0"] as? BigUInt,
                let balanceString = Web3.Utils.formatToEthereumUnits(balanceResult, toUnits: .eth, decimals: 3) else {
                throw Web3Error.dataError
            }
            return balanceString
        } catch let error {
            throw error
        }
    }
    
    public func prepareSendEthTx(web3instance: web3? = nil,
                                 toAddress: String,
                                 value: String = "0.0",
                                 gasLimit: TransactionOptions.GasLimitPolicy = .automatic,
                                 gasPrice: TransactionOptions.GasPricePolicy = .automatic) throws -> WriteTransaction {
        guard let web3 = web3instance ?? self.web3Instance else {
            throw Web3Error.walletError
        }
        web3.addKeystoreManager(self.keystoreManager)
        guard let ethAddress = EthereumAddress(toAddress),
            let contract = web3.contract(Web3.Utils.coldWalletABI, at: ethAddress, abiVersion: 2) else {
                throw Web3Error.dataError
        }
        let amount = Web3.Utils.parseToBigUInt(value, units: .eth)
        var options = self.defaultOptions()
        options.value = amount
        options.gasPrice = gasPrice
        options.gasLimit = gasLimit
        guard let tx = contract.write("fallback",
                                      parameters: [AnyObject](),
                                      extraData: Data(),
                                      transactionOptions: options) else {
                                        throw Web3Error.transactionSerializationError
        }
        return tx
    }
    
    public func prepareSendERC20Tx(web3instance: web3? = nil,
                                   token: ERC20Token,
                                   toAddress: String,
                                   tokenAmount: String = "0.0",
                                   gasLimit: TransactionOptions.GasLimitPolicy = .automatic,
                                   gasPrice: TransactionOptions.GasPricePolicy = .automatic) throws -> WriteTransaction {
        guard let web3 = web3instance ?? self.web3Instance else {
            throw Web3Error.walletError
        }
        web3.addKeystoreManager(self.keystoreManager)
        guard let ethTokenAddress = EthereumAddress(token.address),
            let ethToAddress = EthereumAddress(toAddress),
            let contract = web3.contract(Web3.Utils.erc20ABI, at: ethTokenAddress, abiVersion: 2) else {
                throw Web3Error.dataError
        }
        
        let amount = Web3.Utils.parseToBigUInt(tokenAmount, units: .eth)
        var options = self.defaultOptions()
        options.gasPrice = gasPrice
        options.gasLimit = gasLimit
        guard let tx = contract.write("transfer",
                                      parameters: [ethToAddress, amount] as [AnyObject],
                                      extraData: Data(),
                                      transactionOptions: options) else {
                                        throw Web3Error.transactionSerializationError
        }
        return tx
    }
    
    public func prepareWriteContractTx(web3instance: web3? = nil,
                                       contractABI: String,
                                       contractAddress: String,
                                       contractMethod: String,
                                       value: String = "0.0",
                                       gasLimit: TransactionOptions.GasLimitPolicy = .automatic,
                                       gasPrice: TransactionOptions.GasPricePolicy = .automatic,
                                       parameters: [AnyObject] = [AnyObject](),
                                       extraData: Data = Data()) throws -> WriteTransaction {
        guard let web3 = web3instance ?? self.web3Instance else {
            throw Web3Error.walletError
        }
        web3.addKeystoreManager(self.keystoreManager)
        guard let ethContractAddress = EthereumAddress(contractAddress),
            let contract = web3.contract(contractABI, at: ethContractAddress, abiVersion: 2) else {
                throw Web3Error.dataError
        }
        let amount = Web3.Utils.parseToBigUInt(value, units: .eth)
        var options = self.defaultOptions()
        options.gasPrice = gasPrice
        options.gasLimit = gasLimit
        options.value = amount
        guard let tx = contract.write(contractMethod,
                                      parameters: parameters,
                                      extraData: extraData,
                                      transactionOptions: options) else {
                                        throw Web3Error.transactionSerializationError
        }
        return tx
    }
    
    public func prepareReadContractTx(web3instance: web3? = nil,
                                      contractABI: String,
                                      contractAddress: String,
                                      contractMethod: String,
                                      gasLimit: TransactionOptions.GasLimitPolicy = .automatic,
                                      gasPrice: TransactionOptions.GasPricePolicy = .automatic,
                                      parameters: [AnyObject] = [AnyObject](),
                                      extraData: Data = Data()) throws -> ReadTransaction {
        guard let web3 = web3instance ?? self.web3Instance else {
            throw Web3Error.walletError
        }
        web3.addKeystoreManager(self.keystoreManager)
        guard let ethContractAddress = EthereumAddress(contractAddress),
            let contract = web3.contract(contractABI, at: ethContractAddress, abiVersion: 2) else {
                throw Web3Error.dataError
        }
        var options = self.defaultOptions()
        options.gasPrice = gasPrice
        options.gasLimit = gasLimit
        guard let tx = contract.read(contractMethod,
                                     parameters: parameters,
                                     extraData: extraData,
                                     transactionOptions: options) else {
                                        throw Web3Error.transactionSerializationError
        }
        return tx
    }
    
    public func sendTx(transaction: WriteTransaction,
                       options: TransactionOptions? = nil,
                       password: String) throws -> TransactionSendingResult {
        do {
            let txOptions = options ?? transaction.transactionOptions
            let result = try transaction.send(password: password, transactionOptions: txOptions)
            return result
        } catch let error {
            throw error
        }
    }
    
    public func callTx(transaction: ReadTransaction,
                       options: TransactionOptions? = nil) throws -> [String : Any] {
        do {
            let txOptions = options ?? transaction.transactionOptions
            let result = try transaction.call(transactionOptions: txOptions)
            return result
        } catch let error {
            throw error
        }
    }
    
    private func defaultOptions() -> TransactionOptions {
        var options = TransactionOptions.defaultOptions
        let address = EthereumAddress(self.address)
        options.from = address
        return options
    }
}

extension Wallet: IWalletTransactions {
    
    func save(transactions: [ETHTransaction]) throws {
        let group = DispatchGroup()
        group.enter()
        var error: Error?
        ContainerCD.persistentContainer.performBackgroundTask { (context) in
            do {
                for transaction in transactions {
                    let fr: NSFetchRequest<ETHTransactionModel> = ETHTransactionModel.fetchRequest()
                    fr.predicate = NSPredicate(format: "transactionHash = %@", transaction.transactionHash)
                    let result = try context.fetch(fr).first
                    if let result = result {
                        result.amount = transaction.amount
                        result.data = transaction.data
                        result.date = transaction.date
                        result.from = transaction.from
                        result.networkId = transaction.networkId
                        result.to = transaction.to
                        result.isPending = false
                        //Update information stored in local storage.
                    } else {
                        guard let newTransaction = NSEntityDescription.insertNewObject(forEntityName: "ETHTransactionModel", into: context) as? ETHTransactionModel else {
                            error = Errors.StorageErrors.cantCreateTransaction
                            group.leave()
                            return
                        }
                        newTransaction.amount = transaction.amount
                        newTransaction.data = transaction.data
                        newTransaction.date = transaction.date
                        newTransaction.from = transaction.from
                        newTransaction.networkId = transaction.networkId
                        newTransaction.to = transaction.to
                        newTransaction.isPending = false
                        
                        if let contractAddress = transaction.token?.address {
                            //In case of ERC20 tokens
                            let result = try context.fetch(self.fetchTokenRequest(withAddress: contractAddress)).first
                            if let token = result {
                                newTransaction.token = token
                            } else {
                                let newToken = NSEntityDescription.insertNewObject(forEntityName: "ERC20TokenModel", into: context) as? ERC20TokenModel
                                newToken?.address = transaction.token?.address
                                newToken?.decimals = transaction.token?.decimals
                                newToken?.name = transaction.token?.name
                                newToken?.symbol = transaction.token?.symbol
                                newToken?.networkId = transaction.networkId
                                newTransaction.token = newToken
                            }
                        } else {
                            //In case of custom ETH transaction
                            let result = try context.fetch(self.fetchTokenRequest(withAddress: ""))
                            if let ethToken = result.first {
                                newTransaction.token = ethToken
                            } else {
                                let newToken = NSEntityDescription.insertNewObject(forEntityName: "ERC20TokenModel", into: context) as? ERC20TokenModel
                                newToken?.address = ""
                                newToken?.name = "Ether"
                                newToken?.decimals = "18"
                                newToken?.symbol = "ETH"
                                newTransaction.token = newToken
                            }
                            
                        }
                        newTransaction.transactionHash = transaction.transactionHash
                        // MARK: - Fetch wallet from core data, and if there is no one wallet - create.
                        let walletCD = try context.fetch(self.fetchWalletRequest(with: self.address)).first
                        if let walletCD = walletCD {
                            newTransaction.wallet = walletCD
                        } else {
                            let newWallet = NSEntityDescription.insertNewObject(forEntityName: "WalletModel", into: context) as? WalletModel
                            newWallet?.address = self.address
                            newWallet?.isHD = self.isHD
                            newWallet?.data = self.data
                            newWallet?.name = self.name
                            newWallet?.isSelected = true
                        }
                    }
                }
                try context.save()
                group.leave()
            } catch let someErr {
                error = someErr
                group.leave()
            }
        }
        group.wait()
        if let resErr = error {
            throw resErr
        }
    }
    
    func getAllTransactions(for network: Web3Network) throws -> [ETHTransaction] {
        do {
            guard let result = try ContainerCD.context.fetch(self.fetchWalletRequest(with: self.address)).first else {
                throw Errors.StorageErrors.cantGetTransaction
            }
            guard var transactions = result.transactions?.allObjects as? [ETHTransactionModel] else {
                throw Errors.StorageErrors.cantGetTransaction
            }
            transactions = transactions.filter {
                $0.networkId == network.id
            }
            return transactions.map {
                return ETHTransaction(transactionHash: $0.transactionHash!,
                                      from: $0.from!,
                                      to: $0.to!,
                                      amount: $0.amount!,
                                      date: $0.date!,
                                      data: $0.data,
                                      token: $0.token.flatMap {
                                        return ERC20Token(name: $0.name!,
                                                          address: $0.address!,
                                                          decimals: $0.decimals!,
                                                          symbol: $0.symbol!)
                    }, networkId: $0.networkId,
                       isPending: $0.isPending)
            }
        } catch let error {
            throw error
        }
    }
    
    private func buildTokenslist(from results: [[String: Any]]) throws -> [ERC20Token] {
        var tokens = [ERC20Token]()
        for result in results {
            guard let balance = result["balance"] as? String,
                let contractAddress = result["contractAddress"] as? String,
                let decimals = result["decimals"] as? String,
                let name = result["name"] as? String,
                let symbol = result["symbol"] as? String else {
                    throw Errors.NetworkErrors.wrongJSON
            }
            var token = ERC20Token(name: name, address: contractAddress, decimals: decimals, symbol: symbol)
            token.balance = balance
            tokens.append(token)
        }
        return tokens
    }
    
    private func buildTXlist(from results: [[String: Any]],
                             txType: TransactionType,
                             networkId: Int64) throws -> [ETHTransaction] {
        var transactions = [ETHTransaction]()
        for result in results {
            guard let from = result["from"] as? String,
                let to = result["to"] as? String,
                let timestamp = Double((result["timeStamp"] as? String)!),
                let value = result["value"] as? String,
                let hash = result["hash"] as? String else {
                    throw Errors.NetworkErrors.wrongJSON
            }
            guard let data = result["input"] as? String else {
                throw Errors.NetworkErrors.wrongJSON
            }
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            var tokenModel: ERC20Token?
            if txType == .arbitraryMethodWithParams {
                guard let tokenName = result["tokenName"] as? String,
                    let tokenSymbol = result["tokenSymbol"] as? String,
                    let tokenDecimal = result["tokenDecimal"] as? String,
                    let tokenAddress = result["contractAddress"] as? String else {
                        throw Errors.NetworkErrors.wrongJSON
                }
                tokenModel = ERC20Token(name: tokenName,
                                        address: tokenAddress,
                                        decimals: tokenDecimal,
                                        symbol: tokenSymbol)
            } else {
                tokenModel = nil
            }
            guard let amount = BigUInt(value) else {
                throw Errors.NetworkErrors.wrongJSON
            }
            guard let amountString = Web3.Utils.formatToEthereumUnits(amount) else {
                throw Errors.NetworkErrors.wrongJSON
            }
            let transaction = ETHTransaction(transactionHash: hash,
                                             from: from,
                                             to: to,
                                             amount: amountString,
                                             date: date,
                                             data: Data.fromHex(data),
                                             token: tokenModel,
                                             networkId: networkId,
                                             isPending: false)
            transactions.append(transaction)
        }
        return transactions
    }
    
    public func loadTransactions(txType: TransactionType?,
                                 network: Web3Network) throws -> [ETHTransaction] {
        let type = txType ?? .arbitraryMethodWithParams
        return try self.loadTransactionsPromise(for: self.address, txType: type, networkId: network.id).wait()
    }
    
    private func loadTransactionsPromise(for address: String,
                                         txType: TransactionType,
                                         networkId: Int64) -> Promise<[ETHTransaction]> {
        let returnPromise = Promise<[ETHTransaction]> { (seal) in
            guard let url = URLs().getEtherscanURL(for: txType, address: address, networkId: networkId) else {
                seal.reject(Errors.NetworkErrors.wrongURL)
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let dataTask = URLSession.shared.dataTask(with: request) { (data, _, error) in
                if let error = error {
                    seal.reject(error)
                }
                guard let data = data else {
                    seal.reject(Errors.NetworkErrors.noData)
                    return
                }
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    guard let results = json["result"] as? [[String: Any]] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    do {
                        let transaction = try self.buildTXlist(from: results,
                                                               txType: txType,
                                                               networkId: networkId)
                        seal.fulfill(transaction)
                    } catch let err {
                        seal.reject(err)
                    }
                } catch let err {
                    seal.reject(err)
                }
            }
            dataTask.resume()
        }
        return returnPromise
    }
    
    private func fetchTokenRequest(withAddress address: String) -> NSFetchRequest<ERC20TokenModel> {
        let fr: NSFetchRequest<ERC20TokenModel> = ERC20TokenModel.fetchRequest()
        fr.predicate = NSPredicate(format: "address = %@", address)
        return fr
    }
    
    private func fetchWalletRequest(with address: String) -> NSFetchRequest<WalletModel> {
        let fr: NSFetchRequest<WalletModel> = WalletModel.fetchRequest()
        fr.predicate = NSPredicate(format: "address = %@", address)
        return fr
    }
}

extension Wallet: IWalletPlasma {
    
    public func getID() throws -> BigUInt {
        let plasmaService = IgnisService()
        do {
            let id = try plasmaService.getID(for: EthereumAddress(self.address)!)
            return id
        } catch let error {
            throw error
        }
    }
    
    public func setID(_ id: String) throws {
        let group = DispatchGroup()
        group.enter()
        var error: Error?
        let requestWallet: NSFetchRequest<WalletModel> = WalletModel.fetchRequest()
        do {
            let results = try ContainerCD.context.fetch(requestWallet)
            for item in results {
                if item.address == self.address {
                    item.plasmaID = id
                    self.plasmaID = id
                }
            }
            try ContainerCD.context.save()
            group.leave()
        } catch let someErr {
            error = someErr
            group.leave()
        }
        group.wait()
        if let resErr = error {
            throw resErr
        }
    }
    
    public func getIgnisBalance(network: Web3Network) throws -> String {
        if network.id != 1 && network.id != 4 {
            throw Errors.NetworkErrors.wrongURL
        }
        let onTestnet = network.id == 4 ? true : false
        return try self.getIgnisBalancePromise(onTestnet: onTestnet).wait()
    }
    
    private func getIgnisBalancePromise(onTestnet: Bool) -> Promise<String> {
        let returnPromise = Promise<String> { (seal) in
            guard let id = self.plasmaID else {
                seal.reject(Errors.NetworkErrors.noData)
                return
            }
            guard let url = URL(string: (onTestnet ? IgnisURLs.getDataTestnet : IgnisURLs.getDataMainnet) + id) else {
                seal.reject(Errors.NetworkErrors.wrongURL)
                return
            }
            guard let request = request(url: url,
                                        data: nil,
                                        method: .get,
                                        contentType: .json) else {
                                            seal.reject(PlasmaErrors.NetErrors.cantCreateRequest)
                                            return
            }
            session.dataTask(with: request, completionHandler: { (data, response, error) in
                if let error = error {
                    seal.reject(error)
                }
                guard let data = data else {
                    seal.reject(Errors.NetworkErrors.noData)
                    return
                }
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    print(json)
                    guard let verified = json["verified"] as? [String: Any] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    guard let balance = verified["balance"] as? String else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    guard let floatBalance = Float(balance) else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    let trueBalance = String(floatBalance/1000000)
                    seal.fulfill(trueBalance)
                } catch let err {
                    seal.reject(err)
                }
            }).resume()
        }
        return returnPromise
    }
    
    public func getIgnisNonce(network: Web3Network) throws -> BigUInt {
        if network.id != 1 && network.id != 4 {
            throw Errors.NetworkErrors.wrongURL
        }
        let onTestnet = network.id == 4 ? true : false
        return try self.getIgnisNoncePromise(onTestnet: onTestnet).wait()
    }
    
    private func getIgnisNoncePromise(onTestnet: Bool) -> Promise<BigUInt> {
        let returnPromise = Promise<BigUInt> { (seal) in
            guard let id = self.plasmaID else {
                seal.reject(Errors.NetworkErrors.noData)
                return
            }
            guard let url = URL(string: (onTestnet ? IgnisURLs.getDataTestnet : IgnisURLs.getDataMainnet) + id) else {
                seal.reject(Errors.NetworkErrors.wrongURL)
                return
            }
            guard let request = request(url: url,
                                        data: nil,
                                        method: .get,
                                        contentType: .json) else {
                                            seal.reject(PlasmaErrors.NetErrors.cantCreateRequest)
                                            return
            }
            session.dataTask(with: request, completionHandler: { (data, response, error) in
                if let error = error {
                    seal.reject(error)
                }
                guard let data = data else {
                    seal.reject(Errors.NetworkErrors.noData)
                    return
                }
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    print(json)
                    guard let verified = json["verified"] as? [String: Any] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    guard let nonce = verified["nonce"] as? UInt else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    let bnNonce = BigUInt(nonce)
                    seal.fulfill(bnNonce)
                } catch let err {
                    seal.reject(err)
                }
            }).resume()
        }
        return returnPromise
    }
    
    public func sendPlasmaTx(nonce: BigUInt, to: EthereumAddress, value: String, network: Web3Network) throws -> Bool {
        if network.id != 1 && network.id != 4 {
            throw Errors.NetworkErrors.wrongURL
        }
        let onTestnet = network.id == 4 ? true : false
        guard let fromid = self.plasmaID else {
            throw Errors.CommonErrors.unknown
        }
        guard let fromID = BigUInt(fromid) else {
            throw Errors.CommonErrors.unknown
        }
        let toID = try IgnisService().getID(for: to)
        let nonce = try self.getIgnisNonce(network: network)
        guard let amount = BigUInt(value) else {
            throw Errors.CommonErrors.unknown
        }
        let trueAmount = amount * 1000000
        let tx = TransactionIgnis()
        do {
            let pv = try self.getPassword()
            let pk = try self.getPrivateKey(withPassword: pv)
            let transaction = try tx.createTransaction(from: fromID, to: toID, amount: trueAmount, nonce: nonce, privateKey: pk)
            
            return try self.sendPlasmaTxPromise(transaction: transaction, onTestnet: onTestnet).wait()
        } catch let error {
            throw error
        }
    }
    
    private func sendPlasmaTxPromise(transaction: [AnyHashable : Any], onTestnet: Bool) -> Promise<Bool> {
        
        let returnPromise = Promise<Bool> { (seal) in
            guard let theJSONData = try? JSONSerialization.data(withJSONObject: transaction,
                                                                options: [.prettyPrinted]) else {
                                                                    seal.reject(Errors.NetworkErrors.wrongJSON)
                                                                    return
            }
            let url = onTestnet ? IgnisURLs.sendRawTXTestnet : IgnisURLs.sendRawTXMainnet
            guard let request = request(url: url,
                                        data: theJSONData,
                                        method: .post,
                                        contentType: .json) else {
                                            seal.reject(PlasmaErrors.NetErrors.cantCreateRequest)
                                            return
            }
            session.dataTask(with: request, completionHandler: { (data, response, error) in
                if let error = error {
                    seal.reject(error)
                }
                guard let data = data else {
                    seal.reject(Errors.NetworkErrors.noData)
                    return
                }
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    print(json)
                    guard let accepted = json["accepted"] as? Bool else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    seal.fulfill(accepted)
                } catch let err {
                    seal.reject(err)
                }
            }).resume()
        }
        return returnPromise
    }
    
//    public func loadTransactions(network: Web3Network) throws -> [ETHTransaction] {
//        if network.id != 1 && network.id != 4 {
//            throw Errors.NetworkErrors.wrongURL
//        }
//        let onTestnet = network.id == 4 ? true : false
//        return try self.loadTransactionsPromise(onTestnet: onTestnet).wait()
//    }
//
//    private func loadTransactionsPromise(onTestnet: Bool) -> Promise<[ETHTransaction]> {
//        let returnPromise = Promise<[ETHTransaction]> { (seal) in
//            guard let id = self.plasmaID else {
//                seal.reject(Errors.NetworkErrors.noData)
//                return
//            }
//            let url = onTestnet ? IgnisURLs.getTXsTestnet : IgnisURLs.getTXsMainnet
//            let json: [String: Any] = ["address": id]
//            let jsonData = try? JSONSerialization.data(withJSONObject: json)
//            guard let request = request(url: url,
//                                        data: jsonData,
//                                        method: .get,
//                                        contentType: .json) else {
//                                            seal.reject(PlasmaErrors.NetErrors.cantCreateRequest)
//                                            return
//            }
//            session.dataTask(with: request, completionHandler: { (data, response, error) in
//                if let error = error {
//                    seal.reject(error)
//                }
//                guard let data = data else {
//                    seal.reject(Errors.NetworkErrors.noData)
//                    return
//                }
//                do {
//                    guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
//                        seal.reject(Errors.NetworkErrors.wrongJSON)
//                        return
//                    }
//                    guard let results = json["result"] as? [[String: Any]] else {
//                        seal.reject(Errors.NetworkErrors.wrongJSON)
//                        return
//                    }
//                    do {
//                        let transaction = try self.buildTXlist(from: results,
//                                                               txType: .custom,
//                                                               networkId: onTestnet ? 4 : 1)
//                        seal.fulfill(transaction)
//                    } catch let err {
//                        seal.reject(err)
//                    }
//                } catch let err {
//                    seal.reject(err)
//                }
//            }).resume()
//        }
//        return returnPromise
//    }
}

extension Wallet: IWalletXDAI {
    public func getXDAIBalance() throws -> String {
        let balance = try self.getXDAIBalancePromise().wait()
        let floatBalance = Float(balance)!
        let amount = floatBalance / ("1000000000000000000" as NSString).floatValue
        return String(amount)
    }
    
    private func getXDAIBalancePromise() -> Promise<String> {
        let returnPromise = Promise<String> { (seal) in
            guard let url = try? XDaiURLs().balance(address: self.address) else {
                seal.reject(Errors.NetworkErrors.wrongURL)
                return
            }
//            let balanceJSON = BalanceXDAI(["params": [self.address,"latest"]])
//            let jsonEncoder = JSONEncoder()
//            let jsonData = try jsonEncoder.encode(balanceJSON)
//            print(jsonData)
//            let jsonString = String(data: jsonData, encoding: .utf8)
//            print(jsonString)
            guard let request = request(url: url,
                                        data: nil,
                                        method: .post,
                                        contentType: .json) else {
                                            seal.reject(PlasmaErrors.NetErrors.cantCreateRequest)
                                            return
            }
            session.dataTask(with: request, completionHandler: { (data, response, error) in
                if let error = error {
                    seal.reject(error)
                }
                guard let data = data else {
                    seal.reject(Errors.NetworkErrors.noData)
                    return
                }
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    print(json)
                    guard let balance = json["result"] as? String else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    seal.fulfill(balance)
                } catch let err {
                    seal.reject(err)
                }
            }).resume()
        }
        return returnPromise
    }
    
    public func getXDAITransactions() throws -> [ETHTransaction] {
        return try self.getXDAITransactionsPromise().wait()
    }
    
    private func getXDAITransactionsPromise() -> Promise<[ETHTransaction]> {
        let returnPromise = Promise<[ETHTransaction]> { (seal) in
            guard let url = try? XDaiURLs().transactions(address: self.address) else {
                seal.reject(Errors.NetworkErrors.wrongURL)
                return
            }
            //            let balanceJSON = BalanceXDAI(["params": [self.address,"latest"]])
            //            let jsonEncoder = JSONEncoder()
            //            let jsonData = try jsonEncoder.encode(balanceJSON)
            //            print(jsonData)
            //            let jsonString = String(data: jsonData, encoding: .utf8)
            //            print(jsonString)
            guard let request = request(url: url,
                                        data: nil,
                                        method: .post,
                                        contentType: .json) else {
                                            seal.reject(PlasmaErrors.NetErrors.cantCreateRequest)
                                            return
            }
            session.dataTask(with: request, completionHandler: { (data, response, error) in
                if let error = error {
                    seal.reject(error)
                }
                guard let data = data else {
                    seal.reject(Errors.NetworkErrors.noData)
                    return
                }
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    print(json)
                    guard let results = json["result"] as? [[String: Any]] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    do {
                        let transaction = try self.buildTXlist(from: results,
                                                               txType: .custom,
                                                               networkId: 100)
                        seal.fulfill(transaction)
                    } catch let err {
                        seal.reject(err)
                    }
                } catch let err {
                    seal.reject(err)
                }
            }).resume()
        }
        return returnPromise
    }
    
    public func getXDAITokens() throws -> [ERC20Token] {
        return try self.getXDAITokensPromise().wait()
    }
    
    private func getXDAITokensPromise() -> Promise<[ERC20Token]> {
        let returnPromise = Promise<[ERC20Token]> { (seal) in
            guard let url = try? XDaiURLs().tokens(address: self.address) else {
                seal.reject(Errors.NetworkErrors.wrongURL)
                return
            }
            //            let balanceJSON = BalanceXDAI(["params": [self.address,"latest"]])
            //            let jsonEncoder = JSONEncoder()
            //            let jsonData = try jsonEncoder.encode(balanceJSON)
            //            print(jsonData)
            //            let jsonString = String(data: jsonData, encoding: .utf8)
            //            print(jsonString)
            guard let request = request(url: url,
                                        data: nil,
                                        method: .post,
                                        contentType: .json) else {
                                            seal.reject(PlasmaErrors.NetErrors.cantCreateRequest)
                                            return
            }
            session.dataTask(with: request, completionHandler: { (data, response, error) in
                if let error = error {
                    seal.reject(error)
                }
                guard let data = data else {
                    seal.reject(Errors.NetworkErrors.noData)
                    return
                }
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    print(json)
                    guard let results = json["result"] as? [[String: Any]] else {
                        seal.reject(Errors.NetworkErrors.wrongJSON)
                        return
                    }
                    do {
                        let tokens = try self.buildTokenslist(from: results)
                        seal.fulfill(tokens)
                    } catch let err {
                        seal.reject(err)
                    }
                } catch let err {
                    seal.reject(err)
                }
            }).resume()
        }
        return returnPromise
    }
    
    public func prepareSendXDaiTx(web3instance: web3? = nil,
                                  toAddress: String,
                                  value: String = "0.0",
                                  gasLimit: TransactionOptions.GasLimitPolicy = .automatic,
                                  gasPrice: TransactionOptions.GasPricePolicy = .automatic) throws -> WriteTransaction {
        guard let web3 = web3instance ?? self.web3Instance else {
            throw Web3Error.walletError
        }
        web3.addKeystoreManager(self.keystoreManager)
        guard let ethAddress = EthereumAddress(toAddress),
            let contract = web3.contract(ABIs.xdai, at: ethAddress, abiVersion: 2) else {
                throw Web3Error.dataError
        }
        let amount = Web3.Utils.parseToBigUInt(value, units: .eth)
        var options = self.defaultOptions()
        options.value = amount
        options.gasPrice = gasPrice
        options.gasLimit = gasLimit
        guard let tx = contract.write("fallback",
                                      parameters: [AnyObject](),
                                      extraData: Data(),
                                      transactionOptions: options) else {
                                        throw Web3Error.transactionSerializationError
        }
        return tx
    }
    
    public func prepareSendERC20XDaiTx(web3instance: web3? = nil,
                                       token: ERC20Token,
                                       toAddress: String,
                                       tokenAmount: String = "0.0",
                                       gasLimit: TransactionOptions.GasLimitPolicy,
                                       gasPrice: TransactionOptions.GasPricePolicy) throws -> WriteTransaction {
        guard let web3 = web3instance ?? self.web3Instance else {
            throw Web3Error.walletError
        }
        web3.addKeystoreManager(self.keystoreManager)
        guard let ethTokenAddress = EthereumAddress(token.address),
            let ethToAddress = EthereumAddress(toAddress),
            let contract = web3.contract(ABIs.xdaiERC20, at: ethTokenAddress, abiVersion: 2) else {
                throw Web3Error.dataError
        }
        let amount = Web3.Utils.parseToBigUInt(tokenAmount, units: .eth)
        var options = self.defaultOptions()
        options.gasPrice = gasPrice
        options.gasLimit = gasLimit
        guard let tx = contract.write("transfer",
                                      parameters: [ethToAddress, amount] as [AnyObject],
                                      extraData: Data(),
                                      transactionOptions: options) else {
                                        throw Web3Error.transactionSerializationError
        }
        return tx
    }
}

extension Wallet: IWalletBlock {
    public func getBlockNumber(_ web3instance: web3? = nil) throws -> BigUInt {
        guard let web3 = web3instance ?? self.web3Instance else {
            throw Web3Error.walletError
        }
        web3.addKeystoreManager(self.keystoreManager)
        do {
            let blockNumber = try web3.eth.getBlockNumber()
            return blockNumber
        } catch let error {
            throw error
        }
    }
    
    public func getBlock(_ web3instance: web3? = nil) throws -> String {
        guard let web3 = web3instance ?? self.web3Instance else {
            throw Web3Error.walletError
        }
        web3.addKeystoreManager(self.keystoreManager)
        do {
            let block = try web3.eth.getBlock()
            return block
        } catch let error {
            throw error
        }
    }
}

extension Wallet: Equatable {
    public static func ==(lhs: Wallet, rhs: Wallet) -> Bool {
        return lhs.address == rhs.address
    }
}

public struct HDKey {
    let name: String?
    let address: String
}

private enum Method: String {
    case post = "POST"
    case get = "GET"
}

private enum ContentType: String {
    case json = "application/json"
    case octet = "application/octet-stream"
}
