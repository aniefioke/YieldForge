;; Title: YieldForge Protocol - Cross-Chain Yield Optimization Engine

;; Summary: Secure, Bitcoin-compliant yield farming aggregator built on Stacks Layer 2

;; Description: 
;; YieldForge Protocol is a decentralized yield optimization platform that enables trustless participation in multiple 
;; DeFi protocols while maintaining Bitcoin network security. Designed specifically for the Stacks Layer 2 ecosystem,
;; this contract implements:
;; - Multi-protocol yield aggregation with dynamic APY calculations
;; - Bitcoin-native compliance through Stacks transaction finality
;; - Institutional-grade risk management parameters
;; - Automated allocation balancing across integrated protocols
;; - Non-custodial asset management with transparent yield verification

;; Error Constants
(define-constant ERR-UNAUTHORIZED (err u1))
(define-constant ERR-INSUFFICIENT-FUNDS (err u2))
(define-constant ERR-INVALID-PROTOCOL (err u3))
(define-constant ERR-WITHDRAWAL-FAILED (err u4))
(define-constant ERR-DEPOSIT-FAILED (err u5))
(define-constant ERR-PROTOCOL-LIMIT-REACHED (err u6))
(define-constant ERR-INVALID-INPUT (err u7))

;; Protocol Storage
(define-map supported-protocols 
    {protocol-id: uint} 
    {
        name: (string-ascii 50),
        base-apy: uint,
        max-allocation-percentage: uint,
        active: bool
    }
)

;; Protocol Counter
(define-data-var total-protocols uint u0)

;; User Deposit Storage
(define-map user-deposits 
    {user: principal, protocol-id: uint} 
    {
        amount: uint,
        deposit-time: uint
    }
)

;; Protocol Total Deposits
(define-map protocol-total-deposits 
    {protocol-id: uint} 
    {total-deposit: uint}
)

;; Contract Configuration
(define-constant CONTRACT-OWNER tx-sender)

;; Protocol Constants
(define-constant MAX-PROTOCOLS u5)
(define-constant MAX-ALLOCATION-PERCENTAGE u100)
(define-constant BASE-DENOMINATION u1000000)
(define-constant MAX-PROTOCOL-NAME-LENGTH u50)
(define-constant MAX-BASE-APY u10000)  ;; 100%
(define-constant MAX-DEPOSIT-AMOUNT u1000000000)  ;; 1 billion base units

;; Input Validation Functions
(define-private (is-valid-protocol-id (protocol-id uint))
    (and (> protocol-id u0) (<= protocol-id MAX-PROTOCOLS))
)

(define-private (is-valid-protocol-name (name (string-ascii 50)))
    (and 
        (> (len name) u0) 
        (<= (len name) MAX-PROTOCOL-NAME-LENGTH)
    )
)

(define-private (is-valid-base-apy (base-apy uint))
    (<= base-apy MAX-BASE-APY)
)

(define-private (is-valid-allocation-percentage (percentage uint))
    (and (> percentage u0) (<= percentage MAX-ALLOCATION-PERCENTAGE))
)