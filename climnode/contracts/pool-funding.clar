;; Funding Pool Management Contract
;; Enables investors to contribute to a central fund that supports community projects

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_PROJECT_NOT_FOUND (err u103))
(define-constant ERR_INSUFFICIENT_POOL_FUNDS (err u104))
(define-constant ERR_ALREADY_EXISTS (err u105))
(define-constant ERR_INVALID_PERCENTAGE (err u106))

;; Data Variables
(define-data-var total-pool-balance uint u0)
(define-data-var total-distributed uint u0)
(define-data-var pool-locked bool false)
(define-data-var min-contribution uint u1000000) ;; 1 STX minimum
(define-data-var distribution-fee-percentage uint u200) ;; 2% fee

;; Data Maps
;; Track individual investor contributions
(define-map investor-contributions
    principal
    {
        total-contributed: uint,
        contribution-count: uint,
        last-contribution-block: uint
    }
)

;; Track approved projects for funding
(define-map approved-projects
    uint ;; project-id
    {
        name: (string-ascii 64),
        recipient: principal,
        requested-amount: uint,
        allocated-amount: uint,
        status: (string-ascii 16), ;; "pending", "funded", "completed"
        votes: uint,
        created-block: uint
    }
)

;; Track voting records
(define-map project-votes
    {voter: principal, project-id: uint}
    bool
)

;; Track distribution history
(define-map distribution-history
    uint ;; distribution-id
    {
        project-id: uint,
        amount: uint,
        block-height: uint,
        distributor: principal
    }
)

;; Counter variables
(define-data-var next-project-id uint u1)
(define-data-var next-distribution-id uint u1)

;; Read-only functions

;; Get current pool balance
(define-read-only (get-pool-balance)
    (var-get total-pool-balance)
)

;; Get total amount distributed
(define-read-only (get-total-distributed)
    (var-get total-distributed)
)

;; Get investor contribution details
(define-read-only (get-investor-contributions (investor principal))
    (default-to 
        {total-contributed: u0, contribution-count: u0, last-contribution-block: u0}
        (map-get? investor-contributions investor)
    )
)

;; Get project details
(define-read-only (get-project-details (project-id uint))
    (map-get? approved-projects project-id)
)

;; Check if user has voted for a project
(define-read-only (has-voted (voter principal) (project-id uint))
    (default-to false (map-get? project-votes {voter: voter, project-id: project-id}))
)

;; Get distribution record
(define-read-only (get-distribution-record (distribution-id uint))
    (map-get? distribution-history distribution-id)
)

;; Get pool statistics
(define-read-only (get-pool-stats)
    {
        total-balance: (var-get total-pool-balance),
        total-distributed: (var-get total-distributed),
        available-balance: (- (var-get total-pool-balance) (var-get total-distributed)),
        is-locked: (var-get pool-locked),
        min-contribution: (var-get min-contribution)
    }
)

;; Public functions

;; Contribute to the funding pool
(define-public (contribute-to-pool (amount uint))
    (let (
        (current-contribution (get-investor-contributions tx-sender))
    )
        ;; Validate contribution amount
        (asserts! (>= amount (var-get min-contribution)) ERR_INVALID_AMOUNT)
        (asserts! (not (var-get pool-locked)) ERR_NOT_AUTHORIZED)
        
        ;; Transfer STX to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update pool balance
        (var-set total-pool-balance (+ (var-get total-pool-balance) amount))
        
        ;; Update investor contribution record
        (map-set investor-contributions tx-sender
            {
                total-contributed: (+ (get total-contributed current-contribution) amount),
                contribution-count: (+ (get contribution-count current-contribution) u1),
                last-contribution-block: stacks-block-height
            }
        )
        
        (ok amount)
    )
)

;; Create a new project proposal
(define-public (create-project-proposal (name (string-ascii 64)) (recipient principal) (requested-amount uint))
    (let (
        (project-id (var-get next-project-id))
    )
        ;; Validate inputs
        (asserts! (> requested-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= requested-amount (get-pool-balance)) ERR_INSUFFICIENT_POOL_FUNDS)
        
        ;; Create project record
        (map-set approved-projects project-id
            {
                name: name,
                recipient: recipient,
                requested-amount: requested-amount,
                allocated-amount: u0,
                status: "pending",
                votes: u0,
                created-block: stacks-block-height
            }
        )
        
        ;; Increment project ID counter
        (var-set next-project-id (+ project-id u1))
        
        (ok project-id)
    )
)

;; Vote for a project
(define-public (vote-for-project (project-id uint))
    (let (
        (project (unwrap! (map-get? approved-projects project-id) ERR_PROJECT_NOT_FOUND))
        (investor-info (get-investor-contributions tx-sender))
    )
        ;; Check if investor has contributed to pool
        (asserts! (> (get total-contributed investor-info) u0) ERR_NOT_AUTHORIZED)
        
        ;; Check if already voted
        (asserts! (not (has-voted tx-sender project-id)) ERR_ALREADY_EXISTS)
        
        ;; Record vote
        (map-set project-votes {voter: tx-sender, project-id: project-id} true)
        
        ;; Update project vote count
        (map-set approved-projects project-id
            (merge project {votes: (+ (get votes project) u1)})
        )
        
        (ok true)
    )
)

;; Distribute funds to approved projects (governance function)
(define-public (distribute-pool-funds (project-id uint) (amount uint))
    (let (
        (project (unwrap! (map-get? approved-projects project-id) ERR_PROJECT_NOT_FOUND))
        (available-balance (- (var-get total-pool-balance) (var-get total-distributed)))
        (distribution-id (var-get next-distribution-id))
        (fee-amount (/ (* amount (var-get distribution-fee-percentage)) u10000))
        (net-amount (- amount fee-amount))
    )
        ;; Only contract owner can distribute funds (in production, this would be governance)
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        ;; Validate amount
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount available-balance) ERR_INSUFFICIENT_POOL_FUNDS)
        (asserts! (<= amount (get requested-amount project)) ERR_INVALID_AMOUNT)
        
        ;; Transfer funds to project recipient
        (try! (as-contract (stx-transfer? net-amount tx-sender (get recipient project))))
        
        ;; Transfer fee to contract owner
        (if (> fee-amount u0)
            (try! (as-contract (stx-transfer? fee-amount tx-sender CONTRACT_OWNER)))
            true
        )
        
        ;; Update total distributed
        (var-set total-distributed (+ (var-get total-distributed) amount))
        
        ;; Update project allocation
        (map-set approved-projects project-id
            (merge project 
                {
                    allocated-amount: (+ (get allocated-amount project) amount),
                    status: "funded"
                }
            )
        )
        
        ;; Record distribution history
        (map-set distribution-history distribution-id
            {
                project-id: project-id,
                amount: amount,
                block-height: stacks-block-height,
                distributor: tx-sender
            }
        )
        
        ;; Increment distribution ID
        (var-set next-distribution-id (+ distribution-id u1))
        
        (ok net-amount)
    )
)

;; Emergency withdraw (owner only)
(define-public (emergency-withdraw (amount uint))
    (let (
        (available-balance (- (var-get total-pool-balance) (var-get total-distributed)))
    )
        ;; Only owner can perform emergency withdrawal
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (<= amount available-balance) ERR_INSUFFICIENT_FUNDS)
        
        ;; Transfer funds to owner
        (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
        
        ;; Update total distributed
        (var-set total-distributed (+ (var-get total-distributed) amount))
        
        (ok amount)
    )
)

;; Administrative functions

;; Set minimum contribution amount
(define-public (set-min-contribution (new-min uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set min-contribution new-min)
        (ok new-min)
    )
)

;; Set distribution fee percentage (in basis points, e.g., 200 = 2%)
(define-public (set-distribution-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (<= new-fee u1000) ERR_INVALID_PERCENTAGE) ;; Max 10%
        (var-set distribution-fee-percentage new-fee)
        (ok new-fee)
    )
)

;; Lock/unlock pool for contributions
(define-public (set-pool-lock (locked bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (var-set pool-locked locked)
        (ok locked)
    )
)

;; Update project status
(define-public (update-project-status (project-id uint) (new-status (string-ascii 16)))
    (let (
        (project (unwrap! (map-get? approved-projects project-id) ERR_PROJECT_NOT_FOUND))
    )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set approved-projects project-id
            (merge project {status: new-status})
        )
        
        (ok true)
    )
)