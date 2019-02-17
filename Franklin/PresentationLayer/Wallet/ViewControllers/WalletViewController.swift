//
//  WalletViewController.swift
//  DiveLane
//
//  Created by Anton Grigorev on 08/09/2018.
//  Copyright © 2018 Matter Inc. All rights reserved.
//

import UIKit
import Web3swift
import EthereumAddress
import BigInt
import SideMenu
import QRCodeReader
import secp256k1_swift

enum WalletSections: Int {
    case card = 0
    case tokens = 1
}

class WalletViewController: BasicViewController, ModalViewDelegate {

    @IBOutlet weak var walletTableView: BasicTableView!
    @IBOutlet weak var sendMoneyButton: BasicBlueButton!
    @IBOutlet weak var scanQrButton: ScanButton!
    @IBOutlet weak var marker: UIImageView!
    
    private let userKeys = UserDefaultKeys()
    private var tokensService = TokensService()
    private var walletsService = WalletsService()
    private var tokensArray: [TableToken] = []
    
    private let walletSections: [WalletSections] = [.card, .tokens]

    private let alerts = Alerts()
    private let etherCoordinator = EtherCoordinator()
    
    let topViewForModalAnimation = UIView(frame: UIScreen.main.bounds)

    lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action:
        #selector(self.handleRefresh(_:)),
                for: UIControl.Event.valueChanged)
        //refreshControl.alpha = 0
        refreshControl.tintColor = Colors.mainBlue

        return refreshControl
    }()
    
    lazy var readerVC: QRCodeReaderViewController = {
        let builder = QRCodeReaderViewControllerBuilder {
            $0.reader = QRCodeReader(metadataObjectTypes: [.qr], captureDevicePosition: .back)
        }

        return QRCodeReaderViewController(builder: builder)
    }()
    
    @IBAction func qrScanTapped(_ sender: Any) {
        readerVC.delegate = self

        readerVC.completionBlock = { (result: QRCodeReaderResult?) in
        }
        readerVC.modalPresentationStyle = .formSheet
        present(readerVC, animated: true, completion: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.parent?.view.backgroundColor = .white
        self.view.alpha = 0
        self.view.backgroundColor = Colors.background
        self.setupNavigation()
        self.setupTableView()
        self.additionalSetup()
        self.setupSideBar()
        self.additionalSetup()
        
//        guard let wallet = CurrentWallet.currentWallet else {return}
//        do {
//            let pv = try wallet.getPassword()
//            let pk = try wallet.getPrivateKey(withPassword: pv)
//            let nonce = try CurrentWallet.currentWallet!.getIgnisNonce(network: CurrentNetwork.currentNetwork)
//            let transaction = TransactionIgnis()
//            try transaction.createTransaction(from: 150, to: 151, amount: 10, privateKey: pk)
//            print("ho")
//        } catch {
//            return
//        }
    }
    
    func setupMarker() {
        self.marker.isUserInteractionEnabled = false
        guard let wallet = CurrentWallet.currentWallet else {
            return
        }
        if userKeys.isBackupReady(for: wallet) {
            self.marker.alpha = 0
        } else {
            self.marker.alpha = 1
        }
    }
    
    func additionalSetup() {
        self.sendMoneyButton.setTitle("Send money", for: .normal)
        self.topViewForModalAnimation.blurView()
        self.topViewForModalAnimation.alpha = 0
        self.topViewForModalAnimation.tag = Constants.ModalView.ShadowView.tag
        self.topViewForModalAnimation.isUserInteractionEnabled = false
        self.tabBarController?.view.addSubview(topViewForModalAnimation)
    }
    
    func setupSideBar() {
        let menuLeftNavigationController = UISideMenuNavigationController(rootViewController: SettingsViewController())
        SideMenuManager.default.menuLeftNavigationController = menuLeftNavigationController
        SideMenuManager.default.menuAddScreenEdgePanGesturesToPresent(toView: self.view)
        
        SideMenuManager.default.menuFadeStatusBar = false
        SideMenuManager.default.menuPresentMode = .menuSlideIn
        SideMenuManager.default.menuWidth = Constants.SideMenu.widthCoeff * UIScreen.main.bounds.width
        SideMenuManager.default.menuShadowOpacity = Constants.SideMenu.shadowOpacity
        SideMenuManager.default.menuShadowColor = UIColor.black
        SideMenuManager.default.menuShadowRadius = Constants.SideMenu.shadowRadius
    }

    func setupTableView() {
        let nibCard = UINib.init(nibName: "CardCell", bundle: nil)
        let nibToken = UINib.init(nibName: "TokenCell", bundle: nil)
        self.walletTableView.delegate = self
        self.walletTableView.dataSource = self
        let footerView = UIView()
        footerView.backgroundColor = Colors.background
        self.walletTableView.tableFooterView = footerView
        self.walletTableView.addSubview(self.refreshControl)
        self.walletTableView.register(nibToken, forCellReuseIdentifier: "TokenCell")
        self.walletTableView.register(nibCard, forCellReuseIdentifier: "CardCell")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.setupMarker()
        self.appearAnimation()
        switch CurrentNetwork.currentNetwork.id {
        case 100:
            self.setXDai()
        default:
            self.setTokensList()
        }
        
//        print(CurrentWallet.currentWallet?.address)
//        print(try? walletsService.getSelectedWallet().address)
//        guard let wallets = try? walletsService.getAllWallets() else {return}
//        for w in wallets {
//            print(w.address)
//        }
    }
    
    func appearAnimation() {
        UIView.animate(withDuration: Constants.ModalView.animationDuration) { [unowned self] in
            self.view.alpha = 1
        }
    }

    func setupNavigation() {
        self.navigationController?.navigationBar.isHidden = true
    }

    func clearData() {
        tokensArray.removeAll()
    }
    
    func setXDai() {
        DispatchQueue.global().async { [unowned self] in
            let wallet = CurrentWallet.currentWallet!
            var tokens = self.etherCoordinator.getTokens()
//            if let ercTokens = try? wallet.getXDAITokens() {
//                let tableTokens: [TableToken] = ercTokens.map {
//                    TableToken(token: $0, inWallet: wallet, isSelected: false)
//                }
//                tokens.append(contentsOf: tableTokens)
//            }
            self.tokensArray = tokens
            self.reloadDataInTable(completion: { [unowned self] in
                self.updateTokensBalances(tokens: tokens) { [unowned self] uTokens in
                    self.saveTokensBalances(tokens: uTokens)
                    self.tokensArray = uTokens
                    self.reloadDataInTable {
                        self.refreshControl.endRefreshing()
                        print("Updated")
                    }
                    //                    self.reloadDataInTable { [unowned self] in
                    //                        self.saveTokensBalances()
                    //                        // TODO: - need to update rates?
                    //                    }
                }
            })
        }
    }
    
    func setTokensList() {
        //self.clearData()
        DispatchQueue.global().async { [unowned self] in
            let tokens = self.etherCoordinator.getTokens()
            self.tokensArray = tokens
            self.reloadDataInTable(completion: { [unowned self] in
                self.updateTokensBalances(tokens: tokens) { [unowned self] uTokens in
                    self.saveTokensBalances(tokens: uTokens)
                    self.tokensArray = uTokens
                    self.reloadDataInTable {
                        self.refreshControl.endRefreshing()
                        print("Updated")
                    }
//                    self.reloadDataInTable { [unowned self] in
//                        self.saveTokensBalances()
//                        // TODO: - need to update rates?
//                    }
                }
            })
        }
    }
    
    @IBAction func showMenu(_ sender: Any) {
        present(SideMenuManager.default.menuLeftNavigationController!, animated: true, completion: nil)
    }

    @objc func handleRefresh(_ refreshControl: UIRefreshControl) {
        self.updateTokensBalances(tokens: self.tokensArray) { [unowned self] uTokens in
            self.saveTokensBalances(tokens: uTokens)
            self.tokensArray = uTokens
            self.reloadDataInTable {
                self.refreshControl.endRefreshing()
                print("Updated")
            }
            //            self.reloadDataInTable { [unowned self] in
            //                self.refreshControl.endRefreshing()
            //            }
        }
    }

    func reloadDataInTable(completion: @escaping () -> Void) {
        DispatchQueue.main.async { [unowned self] in
            self.walletTableView.reloadData()
            completion()
        }
    }

    func updateTokenRow(rowIndexPath: IndexPath) {
        DispatchQueue.main.async { [unowned self] in
            self.walletTableView.reloadRows(at: [rowIndexPath], with: .none)
        }
    }

    func updateTokensBalances(tokens: [TableToken], completion: @escaping ([TableToken]) -> Void) {
        DispatchQueue.global().async { [unowned self] in
//            var index = 0
            var newTokens = [TableToken]()
            var xdaiTokens: [ERC20Token] = []
            if CurrentNetwork().isXDai() {
                if let wallet = tokens.first?.inWallet {
                    if let ts = try? wallet.getXDAITokens() {
                        xdaiTokens = ts
                    }
                }
            }
            for tabToken in tokens {
                var currentTableToken = tabToken
                let currentToken = tabToken.token
                let currentWallet = tabToken.inWallet
                var balance: String
                if CurrentNetwork().isXDai() && currentToken.isXDai() {
                    balance = "0.0"
                    if let xdaiBalance = try? currentWallet.getXDAIBalance() {
                        if let db = Double(xdaiBalance) {
                            let rnd = Double(round(1000*db)/1000)
                            let str = String(rnd)
                            balance = str
                        }
                    }
                } else if !CurrentNetwork().isXDai() || (currentToken.isEther() || currentToken.isDai()) {
                    balance = self.etherCoordinator.getBalance(for: currentToken, wallet: currentWallet)
                } else if CurrentNetwork().isXDai() {
                    balance = "0.0"
                    for t in xdaiTokens where t == currentToken {
                        if let b = t.balance {
                            if let bn = BigUInt(b) {
                                var fl = Double(bn)/1000000000000000000
                                fl = Double(round(1000*fl)/1000)
                                let str = String(fl)
                                balance = str
                            }
                        }
                    }
                } else {
                    continue
                }
                currentToken.balance = balance
                currentTableToken.token = currentToken
                newTokens.append(currentTableToken)
//                self.tokensArray[index] = currentTableToken
//                index += 1
            }
            completion(newTokens)
        }
    }
    
    func saveTokensBalances(tokens: [TableToken]) {
        for tabToken in tokens {
            let currentToken = tabToken.token
            let currentWallet = tabToken.inWallet
            let currentNetwork = CurrentNetwork.currentNetwork
            if let balance = currentToken.balance {
                
                try? currentToken.saveBalance(in: currentWallet, network: currentNetwork, balance: balance)
            }
        }
    }
    
//        guard !self.ratesUpdating else {return}
//        self.ratesUpdating = true
//        guard !self.twoDimensionalTokensArray.isEmpty else {return}
//        var indexPath = IndexPath(row: 0, section: 0)
//        for wallet in self.twoDimensionalTokensArray {
//            for token in wallet.tokens {
//                var currentTableToken = token
//                let currentToken = token.token
//                let currentWallet = token.inWallet
//                let balance = self.etherCoordinator.getBalance(for: currentToken, wallet: currentWallet)
//                currentToken.balance = balance
//                let balanceInDollars = self.etherCoordinator.getBalanceInDollars(for: token.token, withBalance: balance)
//                currentToken.usdBalance = balanceInDollars
//                currentTableToken.token = currentToken
//                self.twoDimensionalTokensArray[indexPath.section].tokens[indexPath.row] = currentTableToken
////                    let ip = indexPath
////                    self.updateTokenRow(rowIndexPath: ip)
//                try? token.inWallet.setBalance(token: currentToken, network: CurrentNetwork.currentNetwork, balance: balance)
//                try? token.inWallet.setUsdBalance(token: currentToken, network: CurrentNetwork.currentNetwork, usdBalance: balanceInDollars)
//                indexPath.row += 1
//            }
//            indexPath.section += 1
//            indexPath.row = 0
//        }
//        self.ratesUpdating = false
//        completion()
//    }

    func deleteToken(in indexPath: IndexPath) {
        let token = self.tokensArray[indexPath.row].token
        let wallet = self.tokensArray[indexPath.row].inWallet
        let network = CurrentNetwork.currentNetwork
        let isEtherToken = token.isEther()
        let isDaiToken = token.isDai()
        let isCard = token.isFranklin() || token.isXDai()
        if isEtherToken {return}
        if isDaiToken {return}
        if isCard {return}
        do {
            try wallet.delete(token: token, network: network)
            CurrentToken.currentToken = self.tokensArray[0].token
            self.setTokensList()
        } catch let error {
            self.alerts.showErrorAlert(for: self, error: error, completion: nil)
        }
    }

//    func didPressAdd(sender: UIButton) {
//        guard let wallet = CurrentWallet.currentWallet else {
//            self.alerts.showErrorAlert(for: self, error: "Can't select wallet", completion: nil)
//            return
//        }
//        let searchTokenController = SearchTokenViewController(for: wallet)
//        self.navigationController?.pushViewController(searchTokenController, animated: true)
//    }
    
    func modalViewBeenDismissed(updateNeeded: Bool) {
        DispatchQueue.main.async { [unowned self] in
            if updateNeeded { self.setTokensList() }
            UIView.animate(withDuration: Constants.ModalView.animationDuration, animations: {
                self.topViewForModalAnimation.alpha = 0
            })
        }
    }
    
    func modalViewAppeared() {
        DispatchQueue.main.async { [unowned self] in
            UIView.animate(withDuration: Constants.ModalView.animationDuration, animations: {
                self.topViewForModalAnimation.alpha = Constants.ModalView.ShadowView.alpha
            })
        }
    }
    
    @IBAction func writeCheque(_ sender: UIButton) {
        let token = tokensArray[0].token
        self.showSend(token: token)
    }
    
    func showSend(token: ERC20Token) {
        self.modalViewAppeared()
        let sendMoneyVC = SendMoneyController(token: token)
        sendMoneyVC.delegate = self
        sendMoneyVC.modalPresentationStyle = .overCurrentContext
        sendMoneyVC.view.layer.speed = Constants.ModalView.animationSpeed
        self.tabBarController?.present(sendMoneyVC, animated: true, completion: nil)
    }
    
    func showAlert(error: String? = nil) {
        DispatchQueue.main.async { [unowned self] in
            self.alerts.showErrorAlert(for: self, error: error ?? "Unknown error", completion: nil)
        }
    }
    
    func showWithdraw() {
        let alert = UIAlertController(title: "Withdraw to \(CurrentNetwork.currentNetwork.name)", message: nil, preferredStyle: UIAlertController.Style.alert)
        
        alert.addTextField { (textField) in
            textField.placeholder = "Enter amount"
            textField.keyboardType = .decimalPad
        }
        
        let enterAction = UIAlertAction(title: "Apply", style: .default) { [unowned self] (_) in
            guard let wallet = CurrentWallet.currentWallet else {
                self.showAlert(error: "Cant get wallet")
                return
            }
            DispatchQueue.global().async {
                do {
                    let password = try wallet.getPassword()
                    let maxIteractions = BigUInt(1)
                    let tx = try wallet.prepareWriteContractTx(contractABI: ignisABI, contractAddress: ignisAddress, contractMethod: "withdrawUserBalance", value: "0", gasLimit: .automatic, gasPrice: .automatic, parameters: [maxIteractions] as [AnyObject], extraData: Data())
                    let result = try wallet.sendTx(transaction: tx, options: nil, password: password)
                } catch let error {
                    self.showAlert(error: error.localizedDescription)
                }
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            
        }
        
        alert.addAction(enterAction)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func showBuy(token: ERC20Token) {
        let alert = UIAlertController(title: "Buy \(token.name)", message: nil, preferredStyle: UIAlertController.Style.alert)
        
        alert.addTextField { (textField) in
            textField.placeholder = "Enter amount in ETH"
            textField.keyboardType = .decimalPad
        }
        
        let enterAction = UIAlertAction(title: "Apply", style: .default) { [unowned self] (_) in
            guard let wallet = CurrentWallet.currentWallet else {
                self.showAlert(error: "Cant get wallet")
                return
            }
            guard let amount = alert.textFields![0].text else {
                self.showAlert(error: "Cant get amount")
                return
            }
            guard Float(amount)! > 0 else {
                self.showAlert(error: "Can't be zero")
                return
            }
            DispatchQueue.global().async {
                do {
                    let timestamp = BigUInt(Date().timestamp+300)
                    let minTokens = BigUInt(1)
                    let web3 = CurrentNetwork().isXDai() ? Web3.InfuraMainnetWeb3() : nil
                    
                    let password = try wallet.getPassword()
                    let tx = try wallet.prepareWriteContractTx(web3instance: web3, contractABI: ABIs.uniswap, contractAddress: Addresses.uniswapDai, contractMethod: "ethToTokenSwapInput", value: amount, gasLimit: .automatic, gasPrice: .automatic, parameters: [minTokens, timestamp] as [AnyObject], extraData: Data())
                    let result = try wallet.sendTx(transaction: tx, options: nil, password: password)
                } catch let error {
                    self.showAlert(error: error.localizedDescription)
                }
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            
        }
        
        alert.addAction(enterAction)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func showSell(token: ERC20Token) {
        let alert = UIAlertController(title: "Sell \(token.name)", message: nil, preferredStyle: UIAlertController.Style.alert)
        
        alert.addTextField { (textField) in
            textField.placeholder = "Enter amount in \(token.symbol.uppercased())"
            textField.keyboardType = .decimalPad
        }
        
        let enterAction = UIAlertAction(title: "Apply", style: .default) { [unowned self] (_) in
            guard let wallet = CurrentWallet.currentWallet else {
                self.showAlert(error: "Cant get wallet")
                return
            }
            guard let amount = alert.textFields![0].text else {
                self.showAlert(error: "Cant get amount")
                return
            }
            guard Float(amount)! > 0 else {
                self.showAlert(error: "Can't be zero")
                return
            }
            DispatchQueue.global().async {
                do {
                    let timestamp = BigUInt(Date().timestamp+300)
                    let minEth = BigUInt(1)
                    let tokens = Web3.Utils.parseToBigUInt(amount, units: .eth)
                    let web3 = CurrentNetwork().isXDai() ? Web3.InfuraMainnetWeb3() : nil
                    
                    let password = try wallet.getPassword()
                    let tx = try wallet.prepareWriteContractTx(web3instance: web3, contractABI: ABIs.uniswap, contractAddress: Addresses.uniswapDai, contractMethod: "tokenToEthSwapInput", value: "0.0", gasLimit: .automatic, gasPrice: .automatic, parameters: [tokens, minEth, timestamp] as [AnyObject], extraData: Data())
                    let result = try wallet.sendTx(transaction: tx, options: nil, password: password)
                } catch let error {
                    self.showAlert(error: error.localizedDescription)
                }
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            
        }
        
        alert.addAction(enterAction)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func showConvertToXDai(token: ERC20Token) {
        let alert = UIAlertController(title: "Convert to xDai", message: nil, preferredStyle: UIAlertController.Style.alert)
        
        alert.addTextField { (textField) in
            textField.placeholder = "Enter amount in \(token.symbol.uppercased())"
            textField.keyboardType = .decimalPad
        }
        
        let enterAction = UIAlertAction(title: "Apply", style: .default) { [unowned self] (_) in
            guard let wallet = CurrentWallet.currentWallet else {
                self.showAlert(error: "Cant get wallet")
                return
            }
            guard let amount = alert.textFields![0].text else {
                self.showAlert(error: "Cant get amount")
                return
            }
            guard Float(amount)! > 0 else {
                self.showAlert(error: "Can't be zero")
                return
            }
            DispatchQueue.global().async {
                do {
                    let xdaiContract = EthereumAddress(Addresses.daiToXDai)!
                    let tokens = Web3.Utils.parseToBigUInt(amount, units: .eth)
                    let web3 = CurrentNetwork().isXDai() ? Web3.InfuraMainnetWeb3() : nil
                    
                    let password = try wallet.getPassword()
                    let tx = try wallet.prepareWriteContractTx(web3instance: web3, contractABI: ABIs.dai, contractAddress: Addresses.dai, contractMethod: "transfer", value: "0.0", gasLimit: .automatic, gasPrice: .automatic, parameters: [xdaiContract, tokens] as [AnyObject], extraData: Data())
                    let result = try wallet.sendTx(transaction: tx, options: nil, password: password)
                } catch let error {
                    self.showAlert(error: error.localizedDescription)
                }
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            
        }
        
        alert.addAction(enterAction)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func showConvertToDai(token: ERC20Token) {
        let alert = UIAlertController(title: "Convert to Dai", message: nil, preferredStyle: UIAlertController.Style.alert)
        
        alert.addTextField { (textField) in
            textField.placeholder = "Enter amount in \(token.symbol.uppercased())"
            textField.keyboardType = .decimalPad
        }
        
        let enterAction = UIAlertAction(title: "Apply", style: .default) { [unowned self] (_) in
            guard let wallet = CurrentWallet.currentWallet else {
                self.showAlert(error: "Cant get wallet")
                return
            }
            guard let amount = alert.textFields![0].text else {
                self.showAlert(error: "Cant get amount")
                return
            }
            guard Float(amount)! > 0 else {
                self.showAlert(error: "Can't be zero")
                return
            }
            DispatchQueue.global().async {
                do {
                    let password = try wallet.getPassword()
                    let tx = try wallet.prepareSendXDaiTx(toAddress: Addresses.xDaiToDai, value: amount)
                    let result = try wallet.sendTx(transaction: tx, options: nil, password: password)
                } catch let error {
                    self.showAlert(error: error.localizedDescription)
                }
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            
        }
        
        alert.addAction(enterAction)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func showDeposit() {
        let alert = UIAlertController(title: "Deposit to Franklin", message: nil, preferredStyle: UIAlertController.Style.alert)
        
        alert.addTextField { (textField) in
            textField.placeholder = "Enter amount"
            textField.keyboardType = .decimalPad
        }
        
        let enterAction = UIAlertAction(title: "Apply", style: .default) { [unowned self] (_) in
            guard let wallet = CurrentWallet.currentWallet else {
                self.showAlert(error: "Cant get wallet")
                return
            }
            guard let amount = alert.textFields![0].text else {
                self.showAlert(error: "Cant get amount")
                return
            }
            guard Float(amount)! > 0 else {
                self.showAlert(error: "Can't be zero")
                return
            }
            DispatchQueue.global().async {
                do {
                    let password = try wallet.getPassword()
                    let pk = try wallet.getPrivateKey(withPassword: password)
                    let dataPK = Data(hex: pk)
                    guard let publicKey = SECP256K1.privateToPublic(privateKey: dataPK) else {
                        self.showAlert(error: "Cant get public key")
                        return
                    }
                    var stringPublicKey = publicKey.toHexString()
                    stringPublicKey.removeFirst(2)
                    let count = stringPublicKey.count
                    let x = String(stringPublicKey.prefix(count/2))
                    let y = String(stringPublicKey.suffix(count/2))
                    guard let bnY = BigUInt(y, radix: 16) else {
                        self.showAlert(error: "Cant get public key y")
                        return
                    }
                    guard let bnX = BigUInt(x, radix: 16) else {
                        self.showAlert(error: "Cant get public key x")
                        return
                    }
                    let fee = BigUInt(0)
                    let tx = try wallet.prepareWriteContractTx(contractABI: ignisABI, contractAddress: ignisAddress, contractMethod: "deposit", value: amount, gasLimit: .automatic, gasPrice: .automatic, parameters: [[bnX, bnY], fee] as [AnyObject], extraData: Data())
                    let result = try wallet.sendTx(transaction: tx, options: nil, password: password)
                } catch let error {
                    self.showAlert(error: error.localizedDescription)
                }
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (_) in
            
        }
        
        alert.addAction(enterAction)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func showCardAlert(token: ERC20Token) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Send", style: .default, handler: { [unowned self] (action) in
            self.showSend(token: token)
        }))
        if token.isFranklin() {
            alert.addAction(UIAlertAction(title: "Deposit", style: .default, handler: { [unowned self] (action) in
                self.showDeposit()
            }))
            alert.addAction(UIAlertAction(title: "Withdraw", style: .default, handler: { [unowned self] (action) in
                self.showWithdraw()
            }))
        }
        if token.isXDai() {
            alert.addAction(UIAlertAction(title: "Dai to xDai", style: .default, handler: { [unowned self] (action) in
                self.showConvertToXDai(token: Dai())
            }))
            alert.addAction(UIAlertAction(title: "xDai to Dai", style: .default, handler: { [unowned self] (action) in
                self.showConvertToDai(token: token)
            }))
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    func showTokenAlert(token: ERC20Token) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Send", style: .default, handler: { [unowned self] (action) in
            self.showSend(token: token)
        }))
//        if !token.isEther() {
//            alert.addAction(UIAlertAction(title: "Buy by Ether", style: .default, handler: { [unowned self] (action) in
//                self.showBuy(token: token)
//            }))
////            alert.addAction(UIAlertAction(title: "Sell for Ether", style: .default, handler: { [unowned self] (action) in
////                self.showSell(token: token)
////            }))
//        }
        if token.isDai() {
            alert.addAction(UIAlertAction(title: "Buy by Ether", style: .default, handler: { [unowned self] (action) in
                self.showBuy(token: token)
            }))
            alert.addAction(UIAlertAction(title: "Convert to xDai", style: .default, handler: { [unowned self] (action) in
                self.showConvertToXDai(token: token)
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
}

extension WalletViewController: UITableViewDelegate, UITableViewDataSource, TableHeaderDelegate {
    
    func didPressAdd(sender: UIButton) {
        self.modalViewAppeared()
        guard let wallet = CurrentWallet.currentWallet else {return}
        let sendMoneyVC = SearchTokenViewController(for: wallet)
        sendMoneyVC.delegate = self
        sendMoneyVC.modalPresentationStyle = .overCurrentContext
        sendMoneyVC.view.layer.speed = Constants.ModalView.animationSpeed
        self.tabBarController?.present(sendMoneyVC, animated: true, completion: nil)
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if CurrentNetwork().isXDai() {
            return nil
        }
        guard let wallet = CurrentWallet.currentWallet else {return nil}
        let background: TableHeader = TableHeader(for: wallet)
        background.delegate = self
        return background
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if CurrentNetwork().isXDai() {
            return 0
        }
        switch section {
        case WalletSections.card.rawValue:
            return 0
        case WalletSections.tokens.rawValue:
            return Constants.Headers.Heights.tokens
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case WalletSections.card.rawValue:
            return UIScreen.main.bounds.height * Constants.CardCell.heightCoef
        case WalletSections.tokens.rawValue:
            return UIScreen.main.bounds.height * Constants.TokenCell.heightCoef
        default:
            return 0
        }
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
//        if CurrentNetwork().isXDai() {
//            return 1
//        }
        return walletSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
//        if CurrentNetwork().isXDai() {
//            return 1
//        }
        switch section {
        case WalletSections.card.rawValue:
            return 1
        case WalletSections.tokens.rawValue:
            return tokensArray.count - 1
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tokensArray.isEmpty {return UITableViewCell()}
        let card = tokensArray[0]
        var tokens = tokensArray
        tokens.removeFirst()
        switch indexPath.section {
        case WalletSections.card.rawValue:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "CardCell",
                                                           for: indexPath) as? CardCell else {
                                                            return UITableViewCell()
            }
            let tableToken = card
            cell.configure(token: tableToken)
            cell.delegate = self
            return cell
        case WalletSections.tokens.rawValue:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "TokenCell",
                                                           for: indexPath) as? TokenCell else {
                                                            return UITableViewCell()
            }
            let tableToken = tokens[indexPath.row]
            cell.configure(token: tableToken)
            return cell
        default:
            return UITableViewCell()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let indexPathForSelectedRow = tableView.indexPathForSelectedRow else {
            return
        }
        let isCard = indexPath.section == WalletSections.card.rawValue
        let cell = isCard ?
            tableView.cellForRow(at: indexPathForSelectedRow) as? CardCell :
            tableView.cellForRow(at: indexPathForSelectedRow) as? TokenCell
        guard let selectedCell = cell else {
            return
        }
        guard let indexPathTapped = self.walletTableView.indexPath(for: selectedCell) else {
            return
        }
        let tableToken = isCard ?
            self.tokensArray[0] :
            self.tokensArray[indexPathTapped.row+1]
        
        if isCard {
            self.showCardAlert(token: tableToken.token)
        } else {
            self.showTokenAlert(token: tableToken.token)
        }
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            self.deleteToken(in: indexPath)
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if CurrentNetwork().isXDai() {
            return false
        }
        if indexPath.section == WalletSections.card.rawValue {
            return false
        }
        let cell = tableView.cellForRow(at: indexPath) as? TokenCell
        guard let selectedCell = cell else {
            return false
        }
        guard let indexPathTapped = self.walletTableView.indexPath(for: selectedCell) else {
            return false
        }
        let token = self.tokensArray[indexPathTapped.row].token
        if token.isEther() || token.isDai() {
            return false
        }
        return true
    }
}

extension WalletViewController: CardCellDelegate {
    func cardInfoTapped(_ sender: CardCell) {
        guard let indexPathTapped = self.walletTableView.indexPath(for: sender) else {
            return
        }
        let wallet = self.tokensArray[indexPathTapped.row].inWallet
        self.modalViewAppeared()
        let publicKeyController = PublicKeyViewController(for: wallet)
        publicKeyController.delegate = self
        publicKeyController.modalPresentationStyle = .overCurrentContext
        publicKeyController.view.layer.speed = Constants.ModalView.animationSpeed
        self.tabBarController?.present(publicKeyController, animated: true, completion: nil)
    }
}

extension WalletViewController: UISideMenuNavigationControllerDelegate {
    func sideMenuWillAppear(menu: UISideMenuNavigationController, animated: Bool) {
        modalViewAppeared()
    }
    
    func sideMenuWillDisappear(menu: UISideMenuNavigationController, animated: Bool) {
        modalViewBeenDismissed(updateNeeded: false)
    }
}

extension WalletViewController: QRCodeReaderViewControllerDelegate {
    func reader(_ reader: QRCodeReaderViewController, didScanResult result: QRCodeReaderResult) {
        reader.stopScanning()
        reader.dismiss(animated: true) { [unowned self] in
            self.modalViewAppeared()
            let token = self.tokensArray[0].token
            self.showSend(token: token)
        }
    }

    func readerDidCancel(_ reader: QRCodeReaderViewController) {
        reader.stopScanning()
        reader.dismiss(animated: true, completion: nil)
    }
}

extension WalletViewController: IFundsDelegate {
    func makeDeposit() {
        print("deposit")
    }
    
    func makeWithdraw() {
        print("withdraw")
    }
}
