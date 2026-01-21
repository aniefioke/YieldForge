# YieldForge Protocol - Smart Contract Documentation

## Table of Contents

- [YieldForge Protocol - Smart Contract Documentation](#yieldforge-protocol---smart-contract-documentation)
	- [Table of Contents](#table-of-contents)
	- [Protocol Overview ](#protocol-overview-)
	- [Key Features ](#key-features-)
	- [Technical Specifications ](#technical-specifications-)
	- [Contract Architecture ](#contract-architecture-)
		- [Core Data Structures](#core-data-structures)
		- [Key Functionality Matrix](#key-functionality-matrix)
	- [Error Handling ](#error-handling-)
	- [Usage Guide ](#usage-guide-)
		- [Protocol Administration](#protocol-administration)
		- [User Operations](#user-operations)
	- [Security Considerations ](#security-considerations-)

## Protocol Overview <a name="protocol-overview"></a>

YieldForge is a non-custodial yield optimization engine built on Stacks Layer 2, designed to enable secure cross-protocol yield farming while maintaining Bitcoin network compliance. The protocol implements institutional-grade risk parameters and automated allocation strategies across integrated DeFi protocols.

## Key Features <a name="key-features"></a>

- **Multi-Protocol Yield Aggregation**
- **Bitcoin-Native Compliance Framework**
- **Dynamic APY Calculations**
- **Institutional Risk Parameters**
- **Non-Custodial Asset Management**
- **Automated Allocation Balancing**

## Technical Specifications <a name="technical-specifications"></a>

| Category           | Details                         |
| ------------------ | ------------------------------- |
| Language           | Clarity v2.1+                   |
| Compatibility      | Stacks 2.1+                     |
| Mainnet Deployment | [Pending]                       |
| Testnet Deployment | [Pending]                       |
| Error Codes        | 7 Defined Error States          |
| Security Model     | Owner-restricted administration |

## Contract Architecture <a name="contract-architecture"></a>

### Core Data Structures

```clarity
;; Protocol Configuration
(define-map supported-protocols
    {protocol-id: uint}
    {
        name: (string-ascii 50),
        base-apy: uint,
        max-allocation-percentage: uint,
        active: bool
    }
)

;; User Position Tracking
(define-map user-deposits
    {user: principal, protocol-id: uint}
    {
        amount: uint,
        deposit-time: uint
    }
)
```

### Key Functionality Matrix

| Function              | Description                   | Permission Level |
| --------------------- | ----------------------------- | ---------------- |
| `add-protocol`        | Register new yield protocol   | Contract Owner   |
| `deposit`             | Allocate funds to protocol    | Any User         |
| `withdraw`            | Withdraw principal + yield    | Position Owner   |
| `deactivate-protocol` | Emergency protocol suspension | Contract Owner   |
| `calculate-yield`     | Real-time yield estimation    | Public Read      |

## Error Handling <a name="error-handling"></a>

| Error Code               | Hex Value | Description                            |
| ------------------------ | --------- | -------------------------------------- |
| `ERR-UNAUTHORIZED`       | 0x01      | Unauthorized access attempt            |
| `ERR-INSUFFICIENT-FUNDS` | 0x02      | Insufficient deposit balance           |
| `ERR-INVALID-PROTOCOL`   | 0x03      | Protocol not found or inactive         |
| `ERR-PROTOCOL-LIMIT`     | 0x06      | Protocol allocation threshold exceeded |

## Usage Guide <a name="usage-guide"></a>

### Protocol Administration

```clarity
;; Add new yield protocol (Owner only)
(contract-call? 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.add-protocol
    u3
    "Bitcoin Yield Fund"
    u800
    u25
)

;; Deactivate protocol (Owner only)
(contract-call? 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.deactivate-protocol u2)
```

### User Operations

```clarity
;; Deposit 1,000,000 uSTX to Protocol 1
(contract-call? 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.deposit u1 u1000000)

;; Withdraw 500,000 uSTX from Protocol 2
(contract-call? 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.withdraw u2 u500000)
```

## Security Considerations <a name="security-considerations"></a>

1. **Ownership Controls**

   - Critical protocol configuration limited to verified owner address
   - Multi-sig implementation recommended for production deployment

2. **Input Validation**

   - Strict parameter boundaries for APY values (0-10000 = 0-100%)
   - Protocol allocation limits enforced at deposit time

3. **Deposit Safeguards**

   - Minimum/Maximum deposit thresholds
   - Time-locked withdrawals (implemented via block-height checks)

4. **Protocol Deactivation**
   - Emergency shutdown capability for individual protocols
   - Automatic allocation redistribution mechanism (v2 roadmap)
