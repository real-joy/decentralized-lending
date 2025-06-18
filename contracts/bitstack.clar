;; BitStack: Decentralized Bitcoin-Backed Lending Protocol
;;
;; Title: BitStack Collateral Lending Protocol
;;
;; Summary: A trustless lending platform enabling Bitcoin holders to unlock 
;; liquidity without selling their assets through over-collateralized loans
;;
;; Description: BitStack revolutionizes Bitcoin DeFi by providing a secure,
;; transparent lending protocol built on Stacks Layer 2. Users can deposit
;; Bitcoin as collateral to borrow against their holdings while maintaining
;; exposure to Bitcoin's price appreciation. The protocol features automated
;; liquidation protection, dynamic interest rates, and oracle-based pricing
;; to ensure system stability and user security.
;;
;; Key Features:
;; - Over-collateralized lending with configurable ratios
;; - Automated liquidation system for risk management  
;; - Multi-asset collateral support (BTC, STX)
;; - Oracle-integrated price feeds for accurate valuations
;; - Transparent fee structure and platform governance

;; CONSTANTS & ERROR CODES

;; Authorization and Access Control
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))

;; Lending Operation Errors
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u101))
(define-constant ERR-BELOW-MINIMUM (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-LOAN-NOT-FOUND (err u107))
(define-constant ERR-LOAN-NOT-ACTIVE (err u108))

;; System State Errors
(define-constant ERR-ALREADY-INITIALIZED (err u104))
(define-constant ERR-NOT-INITIALIZED (err u105))
(define-constant ERR-INVALID-LIQUIDATION (err u106))

;; Validation Errors
(define-constant ERR-INVALID-LOAN-ID (err u109))
(define-constant ERR-INVALID-PRICE (err u110))
(define-constant ERR-INVALID-ASSET (err u111))

;; Protocol Configuration
(define-constant VALID-ASSETS (list "BTC" "STX"))

;; DATA VARIABLES - PROTOCOL STATE

;; Platform Initialization Status
(define-data-var platform-initialized bool false)

;; Risk Management Parameters
(define-data-var minimum-collateral-ratio uint u150) ;; 150% minimum collateral ratio
(define-data-var liquidation-threshold uint u120) ;; 120% liquidation trigger
(define-data-var platform-fee-rate uint u1) ;; 1% platform fee

;; Protocol Metrics
(define-data-var total-btc-locked uint u0) ;; Total BTC locked as collateral
(define-data-var total-loans-issued uint u0) ;; Total number of loans created

;; DATA MAPS - CORE STORAGE

;; Primary Loan Storage
(define-map loans
  { loan-id: uint }
  {
    borrower: principal,
    collateral-amount: uint,
    loan-amount: uint,
    interest-rate: uint,
    start-height: uint,
    last-interest-calc: uint,
    status: (string-ascii 20),
  }
)

;; User Loan Tracking
(define-map user-loans
  { user: principal }
  { active-loans: (list 10 uint) }
)

;; Oracle Price Feeds
(define-map collateral-prices
  { asset: (string-ascii 3) }
  { price: uint }
)

;; PRIVATE FUNCTIONS - INTERNAL CALCULATIONS

;; Calculate Current Collateral-to-Loan Ratio
;; Calculates the current collateral ratio as a percentage
(define-private (calculate-collateral-ratio
    (collateral uint)
    (loan uint)
    (btc-price uint)
  )
  (let (
      (collateral-value (* collateral btc-price))
      (ratio (* (/ collateral-value loan) u100))
    )
    ratio
  )
)

;; Calculate Interest Accrued Over Time
;; Computes interest owed based on principal, rate, and time elapsed
(define-private (calculate-interest
    (principal uint)
    (rate uint)
    (blocks uint)
  )
  (let (
      (interest-per-block (/ (* principal rate) (* u100 u144))) ;; Daily rate / blocks per day
      (total-interest (* interest-per-block blocks))
    )
    total-interest
  )
)

;; Liquidation Risk Assessment
;; Checks if a loan position needs liquidation and executes if necessary
(define-private (check-liquidation (loan-id uint))
  (let (
      (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
      (btc-price (unwrap! (get price (map-get? collateral-prices { asset: "BTC" }))
        ERR-NOT-INITIALIZED
      ))
      (current-ratio (calculate-collateral-ratio (get collateral-amount loan)
        (get loan-amount loan) btc-price
      ))
    )
    (if (<= current-ratio (var-get liquidation-threshold))
      (liquidate-position loan-id)
      (ok true)
    )
  )
)

;; Execute Position Liquidation
;; Liquidates an undercollateralized loan position
(define-private (liquidate-position (loan-id uint))
  (let (
      (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
      (borrower (get borrower loan))
    )
    (begin
      (map-set loans { loan-id: loan-id } (merge loan { status: "liquidated" }))
      (map-delete user-loans { user: borrower })
      (ok true)
    )
  )
)

;; Loan ID Validation
;; Validates that a loan ID is within acceptable range
(define-private (validate-loan-id (loan-id uint))
  (and
    (> loan-id u0)
    (<= loan-id (var-get total-loans-issued))
  )
)

;; Asset Validation
;; Verifies that an asset is supported by the protocol
(define-private (is-valid-asset (asset (string-ascii 3)))
  (is-some (index-of VALID-ASSETS asset))
)

;; Price Validation
;; Ensures price data is reasonable and non-zero
(define-private (is-valid-price (price uint))
  (and
    (> price u0)
    (<= price u1000000000000) ;; Reasonable upper bound
  )
)

;; Loan Filtering Helper
;; Helper function for filtering loan arrays
(define-private (not-equal-loan-id (id uint))
  (not (is-eq id id))
)

;; PUBLIC FUNCTIONS - PLATFORM ADMINISTRATION

;; Initialize BitStack Protocol
;; Initializes the platform - must be called before any operations
(define-public (initialize-platform)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get platform-initialized)) ERR-ALREADY-INITIALIZED)
    (var-set platform-initialized true)
    (ok true)
  )
)

;; Update Minimum Collateral Ratio
;; Adjusts the minimum collateral ratio requirement for new loans
(define-public (update-collateral-ratio (new-ratio uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (>= new-ratio u110) ERR-INVALID-AMOUNT)
    (var-set minimum-collateral-ratio new-ratio)
    (ok true)
  )
)

;; Update Liquidation Threshold
;; Modifies the threshold at which loans become eligible for liquidation
(define-public (update-liquidation-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (>= new-threshold u100) ERR-INVALID-AMOUNT)
    (var-set liquidation-threshold new-threshold)
    (ok true)
  )
)

;; Update Oracle Price Feed
;; Updates price data from trusted oracle sources
(define-public (update-price-feed
    (asset (string-ascii 3))
    (new-price uint)
  )
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-asset asset) ERR-INVALID-ASSET)
    (asserts! (is-valid-price new-price) ERR-INVALID-PRICE)
    (ok (map-set collateral-prices { asset: asset } { price: new-price }))
  )
)

;; PUBLIC FUNCTIONS - LENDING OPERATIONS

;; Deposit Collateral
;; Deposits Bitcoin collateral into the protocol
(define-public (deposit-collateral (amount uint))
  (begin
    (asserts! (var-get platform-initialized) ERR-NOT-INITIALIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (var-set total-btc-locked (+ (var-get total-btc-locked) amount))
    (ok true)
  )
)

;; Request Loan Against Collateral
;; Creates a new loan backed by deposited collateral
(define-public (request-loan
    (collateral uint)
    (loan-amount uint)
  )
  (let (
      (btc-price (unwrap! (get price (map-get? collateral-prices { asset: "BTC" }))
        ERR-NOT-INITIALIZED
      ))
      (collateral-value (* collateral btc-price))
      (required-collateral (* loan-amount (var-get minimum-collateral-ratio)))
      (loan-id (+ (var-get total-loans-issued) u1))
    )
    (begin
      (asserts! (var-get platform-initialized) ERR-NOT-INITIALIZED)
      (asserts! (>= collateral-value required-collateral)
        ERR-INSUFFICIENT-COLLATERAL
      )
      ;; Create new loan record
      (map-set loans { loan-id: loan-id } {
        borrower: tx-sender,
        collateral-amount: collateral,
        loan-amount: loan-amount,
        interest-rate: u5, ;; 5% annual interest rate
        start-height: stacks-block-height,
        last-interest-calc: stacks-block-height,
        status: "active",
      })
      ;; Update user's active loans list
      (match (map-get? user-loans { user: tx-sender })
        existing-loans (map-set user-loans { user: tx-sender } { active-loans: (unwrap!
          (as-max-len? (append (get active-loans existing-loans) loan-id) u10)
          ERR-INVALID-AMOUNT
        ) }
        )
        (map-set user-loans { user: tx-sender } { active-loans: (list loan-id) })
      )
      (var-set total-loans-issued (+ (var-get total-loans-issued) u1))
      (ok loan-id)
    )
  )
)