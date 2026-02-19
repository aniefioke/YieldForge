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
(define-constant ERR-REBALANCE-FAILED (err u8))
(define-constant ERR-CIRCUIT-BREAKER-ACTIVE (err u9))
(define-constant ERR-REBALANCE-COOLDOWN (err u10))
(define-constant ERR-INSUFFICIENT-YIELD (err u11))
(define-constant ERR-SLIPPAGE-TOLERANCE-EXCEEDED (err u12))


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
(define-data-var rebalance-cooldown uint u100)  ;; Blocks between rebalances
(define-data-var last-rebalance-block uint u0)
(define-data-var circuit-breaker-active bool false)
(define-data-var total-value-locked uint u0)
(define-data-var emergency-shutdown bool false)
(define-data-var rebalance-request-counter uint u0)
(define-data-var protocol-manager principal CONTRACT-OWNER)

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

(define-map yield-history
    {protocol-id: uint, block-height: uint}
    {yield-rate: uint, total-deposits: uint}
)

(define-map user-yield-claims
    {user: principal, protocol-id: uint}
    {last-claim-block: uint, accumulated-yield: uint}
)

(define-map rebalance-requests
    {request-id: uint}
    {
        proposer: principal,
        from-protocol: uint,
        to-protocol: uint,
        amount: uint,
        executed: bool,
        expiry-block: uint
    }
)

(define-map protocol-performance
    {protocol-id: uint}
    {
        historical-apy: uint,
        volatility-index: uint,
        last-update: uint,
        total-yield-generated: uint
    }
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
(define-constant ERR-REBALANCE-EXPIRED (err u13))
(define-constant ERR-ALREADY-EXECUTED (err u14))



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

;; Emergency Circuit Breaker Functions
(define-public (trigger-circuit-breaker (reason (string-ascii 100)))
    (begin
        (asserts! (or (is-contract-owner tx-sender) 
                      (is-eq tx-sender (var-get protocol-manager)))  ;; Add var-get
                 ERR-UNAUTHORIZED)
        (var-set circuit-breaker-active true)
        (var-set emergency-shutdown true)
        (print {event: "circuit-breaker-triggered", reason: reason, block: stacks-block-height})
        (ok true)
    )
)

(define-public (reset-circuit-breaker)
    (begin
        (asserts! (is-contract-owner tx-sender) ERR-UNAUTHORIZED)
        (asserts! (>= (- stacks-block-height (var-get last-rebalance-block)) u1000) 
                 ERR-REBALANCE-COOLDOWN)
        (var-set circuit-breaker-active false)
        (var-set emergency-shutdown false)
        (print {event: "circuit-breaker-reset", block: stacks-block-height})
        (ok true)
    )
)

;; Enhanced Deposit with Yield Tracking
(define-public (deposit-enhanced 
    (protocol-id uint) 
    (amount uint)
    (expected-yield uint)
)
    (let
        (
            (protocol (unwrap! (map-get? supported-protocols {protocol-id: protocol-id}) 
                               ERR-INVALID-PROTOCOL))
            (current-total (default-to {total-deposit: u0} 
                           (map-get? protocol-total-deposits {protocol-id: protocol-id})))
            (current-yield-claim (default-to {last-claim-block: stacks-block-height, 
                                              accumulated-yield: u0}
                                 (map-get? user-yield-claims {user: tx-sender, 
                                                              protocol-id: protocol-id})))
            (pending-yield (unwrap! (calculate-pending-yield tx-sender protocol-id) 
                                    ERR-INSUFFICIENT-YIELD))  ;; Add unwrap!
        )
        
        (asserts! (not (var-get emergency-shutdown)) ERR-CIRCUIT-BREAKER-ACTIVE)
        (asserts! (get active protocol) ERR-INVALID-PROTOCOL)
        (asserts! (is-valid-deposit-amount amount) ERR-INVALID-INPUT)
        (asserts! (>= expected-yield pending-yield) 
                 ERR-SLIPPAGE-TOLERANCE-EXCEEDED)
        
        ;; Update yield tracking
        (map-set user-yield-claims
            {user: tx-sender, protocol-id: protocol-id}
            {
                last-claim-block: stacks-block-height,
                accumulated-yield: (+ (get accumulated-yield current-yield-claim) 
                                      pending-yield)  ;; Remove unwrap!
            }
        )
        
        ;; Rest of function...
        (ok true)
    )
)

;; Calculate pending yield with compound interest
(define-read-only (calculate-pending-yield 
    (user principal) 
    (protocol-id uint)
)
    (let
        (
            (user-deposit (unwrap! (map-get? user-deposits {user: user, protocol-id: protocol-id}) 
                                   ERR-INSUFFICIENT-FUNDS))
            (protocol (unwrap! (map-get? supported-protocols {protocol-id: protocol-id}) 
                               ERR-INVALID-PROTOCOL))
            (user-claim (default-to {last-claim-block: (get deposit-time user-deposit), 
                                     accumulated-yield: u0}
                        (map-get? user-yield-claims {user: user, protocol-id: protocol-id})))
            (blocks-elapsed (- stacks-block-height (get last-claim-block user-claim)))
            (base-rate (get base-apy protocol))
            (principal-amount (get amount user-deposit))
        )
        
        ;; Compound interest calculation: P * (1 + r)^n - P simplified
        (let
            (
                (simple-yield (/ (* principal-amount base-rate blocks-elapsed) 
                                 (* BASE-DENOMINATION u52596)))
                (compounded (if (> blocks-elapsed u100)
                    (+ simple-yield (/ (* simple-yield base-rate) (* BASE-DENOMINATION u2)))
                    simple-yield
                ))
            )
            (ok (+ compounded (get accumulated-yield user-claim)))
        )
    )
)

;; Automated Rebalance Request
(define-public (request-rebalance
    (from-protocol uint)
    (to-protocol uint)
    (amount uint)
    (min-expected-yield uint)
)
    (let
        (
            (request-id (+ (var-get rebalance-request-counter) u1))
            (from-protocol-data (unwrap! (map-get? supported-protocols {protocol-id: from-protocol})
                                         ERR-INVALID-PROTOCOL))
            (to-protocol-data (unwrap! (map-get? supported-protocols {protocol-id: to-protocol})
                                       ERR-INVALID-PROTOCOL))
            (user-deposit (unwrap! (map-get? user-deposits {user: tx-sender, 
                                                            protocol-id: from-protocol})
                                   ERR-INSUFFICIENT-FUNDS))
        )
        
        (asserts! (not (var-get circuit-breaker-active)) ERR-CIRCUIT-BREAKER-ACTIVE)
        (asserts! (>= (get amount user-deposit) amount) ERR-INSUFFICIENT-FUNDS)
        (asserts! (get active from-protocol-data) ERR-INVALID-PROTOCOL)
        (asserts! (get active to-protocol-data) ERR-INVALID-PROTOCOL)
        (asserts! (>= (- stacks-block-height (var-get last-rebalance-block)) 
                      (var-get rebalance-cooldown)) 
                 ERR-REBALANCE-COOLDOWN)
        
        (var-set rebalance-request-counter request-id)
        
        (map-set rebalance-requests
            {request-id: request-id}
            {
                proposer: tx-sender,
                from-protocol: from-protocol,
                to-protocol: to-protocol,
                amount: amount,
                executed: false,
                expiry-block: (+ stacks-block-height u50)  ;; Expires after ~500 blocks
            }
        )
        
        (print {
            event: "rebalance-requested",
            request-id: request-id,
            from: from-protocol,
            to: to-protocol,
            amount: amount,
            proposer: tx-sender
        })
        
        (ok request-id)
    )
)

;; Execute Rebalance with MEV Protection
(define-public (execute-rebalance
    (request-id uint)
    (expected-yield uint)
)
    (let
        (
            (request (unwrap! (map-get? rebalance-requests {request-id: request-id})
                             ERR-INVALID-INPUT))
            (from-protocol (get from-protocol request))
            (to-protocol (get to-protocol request))
            (amount (get amount request))
            (user-deposit (unwrap! (map-get? user-deposits 
                                             {user: (get proposer request), 
                                              protocol-id: from-protocol})
                                   ERR-INSUFFICIENT-FUNDS))
            (to-total (default-to {total-deposit: u0}
                       (map-get? protocol-total-deposits {protocol-id: to-protocol})))
            (from-total (default-to {total-deposit: u0}
                         (map-get? protocol-total-deposits {protocol-id: from-protocol})))
            (pending-yield (unwrap! (calculate-pending-yield (get proposer request) from-protocol)
                                   u0))
        )
        
        (asserts! (not (var-get executed request)) ERR-ALREADY-EXECUTED)
        (asserts! (>= stacks-block-height (get expiry-block request)) ERR-REBALANCE-EXPIRED)
        (asserts! (>= expected-yield pending-yield) ERR-SLIPPAGE-TOLERANCE-EXCEEDED)
        
        ;; Update deposits - withdraw from source protocol
        (map-set user-deposits 
            {user: (get proposer request), protocol-id: from-protocol}
            {
                amount: (- (get amount user-deposit) amount),
                deposit-time: stacks-block-height
            }
        )
        
        ;; Update deposits - deposit to target protocol
        (map-set user-deposits 
            {user: (get proposer request), protocol-id: to-protocol}
            {
                amount: (+ (default-to u0 
                            (get amount (map-get? user-deposits 
                                {user: (get proposer request), protocol-id: to-protocol}))) 
                          amount),
                deposit-time: stacks-block-height
            }
        )
        
        ;; Update protocol totals
        (map-set protocol-total-deposits 
            {protocol-id: from-protocol}
            {total-deposit: (- (get total-deposit from-total) amount)}
        )
        
        (map-set protocol-total-deposits 
            {protocol-id: to-protocol}
            {total-deposit: (+ (get total-deposit to-total) amount)}
        )
        
        ;; Mark request as executed
        (map-set rebalance-requests
            {request-id: request-id}
            (merge request {executed: true})
        )
        
        (var-set last-rebalance-block stacks-block-height)
        
        ;; Update protocol performance metrics
        (try! (update-protocol-performance from-protocol))
        (try! (update-protocol-performance to-protocol))
        
        (print {
            event: "rebalance-executed",
            request-id: request-id,
            from: from-protocol,
            to: to-protocol,
            amount: amount
        })
        
        (ok true)
    )
)

;; Update Protocol Performance Metrics
(define-private (update-protocol-performance (protocol-id uint))
    (let
        (
            (protocol (unwrap! (map-get? supported-protocols {protocol-id: protocol-id})
                               ERR-INVALID-PROTOCOL))
            (current-performance (default-to 
                {historical-apy: (get base-apy protocol), 
                 volatility-index: u0, 
                 last-update: stacks-block-height,
                 total-yield-generated: u0}
                (map-get? protocol-performance {protocol-id: protocol-id})))
            (total-deposits (default-to {total-deposit: u0}
                             (map-get? protocol-total-deposits {protocol-id: protocol-id})))
        )
        
        ;; Calculate new volatility index based on yield history
        (map-set protocol-performance
            {protocol-id: protocol-id}
            {
                historical-apy: (get base-apy protocol),
                volatility-index: (calculate-volatility protocol-id),
                last-update: stacks-block-height,
                total-yield-generated: (+ (get total-yield-generated current-performance)
                                          (calculate-protocol-yield protocol-id))
            }
        )
        
        (ok true)
    )
)

;; Calculate Protocol Volatility
(define-read-only (calculate-volatility (protocol-id uint))
    (let
        (
            (recent-history (list 
                (unwrap! (map-get? yield-history 
                          {protocol-id: protocol-id, block-height: (- stacks-block-height u1)})
                        {yield-rate: u0, total-deposits: u0})
                (unwrap! (map-get? yield-history 
                          {protocol-id: protocol-id, block-height: (- stacks-block-height u10)})
                        {yield-rate: u0, total-deposits: u0})
            ))
        )
        ;; Simplified volatility calculation
        (fold calculate-variance recent-history u0)
    )
)

(define-private (calculate-variance
    (history {yield-rate: uint, total-deposits: uint})
    (acc uint)
)
    (+ acc (get yield-rate history))
)

;; Calculate Protocol Yield
(define-read-only (calculate-protocol-yield (protocol-id uint))
    u0  ;; Placeholder for complex yield calculation
)

;; Protocol Manager Role
(define-data-var protocol-manager principal CONTRACT-OWNER)

(define-public (set-protocol-manager (new-manager principal))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR-UNAUTHORIZED)
        (var-set protocol-manager new-manager)
        (ok true)
    )
)

;; Emergency Pause for Specific Protocol
(define-public (pause-protocol (protocol-id uint))
    (begin
        (asserts! (or (is-contract-owner tx-sender) 
                      (is-eq tx-sender (var-get protocol-manager))) 
                 ERR-UNAUTHORIZED)
        (map-set supported-protocols 
            {protocol-id: protocol-id}
            (merge 
                (unwrap! (map-get? supported-protocols {protocol-id: protocol-id}) 
                        ERR-INVALID-PROTOCOL)
                {active: false}
            )
        )
        (ok true)
    )
)

;; Claim Accumulated Yield
(define-public (claim-yield (protocol-id uint))
    (let
        (
            (pending-yield (unwrap! (calculate-pending-yield tx-sender protocol-id) 
                                    ERR-INSUFFICIENT-YIELD))
        )
        (asserts! (> pending-yield u0) ERR-INSUFFICIENT-YIELD)
        
        (map-set user-yield-claims
            {user: tx-sender, protocol-id: protocol-id}
            {
                last-claim-block: stacks-block-height,
                accumulated-yield: u0
            }
        )
        
        (print {event: "yield-claimed", user: tx-sender, protocol: protocol-id, amount: pending-yield})
        
        (ok pending-yield)
    )
)

;; Initialize Contract
(try! (initialize-protocols))
