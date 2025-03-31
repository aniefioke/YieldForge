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

(define-private (is-valid-deposit-amount (amount uint))
    (and (> amount u0) (<= amount MAX-DEPOSIT-AMOUNT))
)

;; Authorization Check
(define-private (is-contract-owner (sender principal))
    (is-eq sender CONTRACT-OWNER)
)

;; Protocol Management Functions
(define-public (add-protocol 
    (protocol-id uint) 
    (name (string-ascii 50)) 
    (base-apy uint) 
    (max-allocation-percentage uint)
)
    (begin 
        (asserts! (is-contract-owner tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-valid-protocol-id protocol-id) ERR-INVALID-INPUT)
        (asserts! (is-valid-protocol-name name) ERR-INVALID-INPUT)
        (asserts! (is-valid-base-apy base-apy) ERR-INVALID-INPUT)
        (asserts! (is-valid-allocation-percentage max-allocation-percentage) ERR-INVALID-INPUT)
        (asserts! (< (var-get total-protocols) MAX-PROTOCOLS) ERR-PROTOCOL-LIMIT-REACHED)
        
        (map-set supported-protocols 
            {protocol-id: protocol-id} 
            {
                name: name,
                base-apy: base-apy,
                max-allocation-percentage: max-allocation-percentage,
                active: true
            }
        )
        (var-set total-protocols (+ (var-get total-protocols) u1))
        (ok true)
    )
)

;; Deposit Management Functions
(define-public (deposit 
    (protocol-id uint) 
    (amount uint)
)
    (let 
        (
            (protocol (unwrap! 
                (map-get? supported-protocols {protocol-id: protocol-id}) 
                ERR-INVALID-PROTOCOL
            ))
            (current-total-deposits (default-to 
                {total-deposit: u0} 
                (map-get? protocol-total-deposits {protocol-id: protocol-id})
            ))
            (max-protocol-deposit (/ 
                (* (get max-allocation-percentage protocol) BASE-DENOMINATION) 
                u100
            ))
        )
        (asserts! (is-valid-protocol-id protocol-id) ERR-INVALID-INPUT)
        (asserts! (is-valid-deposit-amount amount) ERR-INVALID-INPUT)
        (asserts! (get active protocol) ERR-INVALID-PROTOCOL)
        (asserts! 
            (<= (+ (get total-deposit current-total-deposits) amount) max-protocol-deposit) 
            ERR-PROTOCOL-LIMIT-REACHED
        )

        (map-set user-deposits 
            {user: tx-sender, protocol-id: protocol-id}
            {amount: amount, deposit-time: stacks-block-height}
        )
        (map-set protocol-total-deposits 
            {protocol-id: protocol-id} 
            {total-deposit: (+ (get total-deposit current-total-deposits) amount)}
        )

        (ok true)
    )
)

;; Yield Management Functions
(define-read-only (calculate-yield 
    (protocol-id uint) 
    (user principal)
)
    (let 
        (
            (protocol (unwrap! 
                (map-get? supported-protocols {protocol-id: protocol-id}) 
                ERR-INVALID-PROTOCOL
            ))
            (user-deposit (unwrap! 
                (map-get? user-deposits {user: user, protocol-id: protocol-id}) 
                ERR-INSUFFICIENT-FUNDS
            ))
            (blocks-since-deposit (- stacks-block-height (get deposit-time user-deposit)))
            (annual-yield (/ 
                (* (get base-apy protocol) (get amount user-deposit)) 
                BASE-DENOMINATION
            ))
        )
        (asserts! (is-valid-protocol-id protocol-id) ERR-INVALID-INPUT)
        
        (ok (/ 
            (* annual-yield blocks-since-deposit) 
            u52596  ;; Approximate blocks in a year
        ))
    )
)

;; Withdrawal Management Functions
(define-public (withdraw 
    (protocol-id uint) 
    (amount uint)
)
    (let 
        (
            (user-deposit (unwrap! 
                (map-get? user-deposits {user: tx-sender, protocol-id: protocol-id}) 
                ERR-INSUFFICIENT-FUNDS
            ))
            (yield (unwrap! (calculate-yield protocol-id tx-sender) ERR-WITHDRAWAL-FAILED))
            (current-protocol-deposits (default-to 
                {total-deposit: u0}
                (map-get? protocol-total-deposits {protocol-id: protocol-id})
            ))
        )
        (asserts! (is-valid-protocol-id protocol-id) ERR-INVALID-INPUT)
        (asserts! (is-valid-deposit-amount amount) ERR-INVALID-INPUT)
        (asserts! (>= (get amount user-deposit) amount) ERR-INSUFFICIENT-FUNDS)

        (map-set user-deposits 
            {user: tx-sender, protocol-id: protocol-id}
            {amount: (- (get amount user-deposit) amount), deposit-time: stacks-block-height}
        )
        (map-set protocol-total-deposits 
            {protocol-id: protocol-id} 
            {total-deposit: (- (get total-deposit current-protocol-deposits) amount)}
        )

        (ok (+ amount yield))
    )
)

;; Risk Management Functions
(define-public (deactivate-protocol (protocol-id uint))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR-UNAUTHORIZED)
        (asserts! (is-valid-protocol-id protocol-id) ERR-INVALID-INPUT)
        (map-set supported-protocols 
            {protocol-id: protocol-id} 
            (merge 
                (unwrap! 
                    (map-get? supported-protocols {protocol-id: protocol-id}) 
                    ERR-INVALID-PROTOCOL
                )
                {active: false}
            )
        )
        (var-set total-protocols (- (var-get total-protocols) u1))
        (ok true)
    )
)

;; Contract Initialization
(define-public (initialize-protocols)
    (begin
        (try! (add-protocol u1 "Stacks Core Yield" u500 u20))
        (try! (add-protocol u2 "Bitcoin Bridge Yield" u750 u30))
        (ok true)
    )
)

;; Initialize Contract
(try! (initialize-protocols))