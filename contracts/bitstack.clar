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