;; Voting Mechanism Smart Contract
;; Supports multiple voting types, delegation, and quadratic voting

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-VOTING-CLOSED (err u102))
(define-constant ERR-VOTING-NOT-STARTED (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-INVALID-VOTE (err u105))
(define-constant ERR-INSUFFICIENT-TOKENS (err u106))
(define-constant ERR-QUORUM-NOT-MET (err u107))
(define-constant ERR-INVALID-DELEGATION (err u108))
(define-constant ERR-TOKEN-CALL-FAILED (err u109))

;; Data Variables
(define-data-var proposal-counter uint u0)
(define-data-var voting-token principal .voting-token)


;; Voting Types
(define-constant VOTE-TYPE-YES-NO u1)
(define-constant VOTE-TYPE-RANKED-CHOICE u2)
(define-constant VOTE-TYPE-QUADRATIC u3)

;; Data Maps
(define-map proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    vote-type: uint,
    options: (list 10 (string-ascii 50)),
    start-block: uint,
    end-block: uint,
    quorum-threshold: uint,
    created-at: uint,
    executed: bool
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  {
    vote-data: (list 10 uint), ;; For ranked choice or multiple options
    vote-weight: uint,
    stacks-block-height: uint
  }
)

(define-map vote-delegations
  { delegator: principal }
  { delegate: principal, active: bool }
)

(define-map proposal-results
  { proposal-id: uint }
  {
    total-votes: uint,
    option-votes: (list 10 uint),
    quorum-met: bool,
    winning-option: uint
  }
)

(define-map voter-power
  { voter: principal, proposal-id: uint }
  { power: uint, used-power: uint }
)

;; Read-only functions
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-delegation (delegator principal))
  (map-get? vote-delegations { delegator: delegator })
)

(define-read-only (get-proposal-results (proposal-id uint))
  (map-get? proposal-results { proposal-id: proposal-id })
)

(define-read-only (get-current-proposal-id)
  (var-get proposal-counter)
)

(define-read-only (is-voting-active (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal-data
    (and 
      (>= stacks-block-height (get start-block proposal-data))
      (<= stacks-block-height (get end-block proposal-data))
    )
    false
  )
)

;; Option 2: Use unwrap-panic if you're certain it won't fail
(define-read-only (get-voter-token-balance (voter principal))
  (ok (unwrap-panic (contract-call? .voting-token get-balance voter)))
)

;; Helper function to get balance as uint (for internal use)
;; Option 2: Using unwrap! with a default value
(define-private (get-voter-balance-internal (voter principal))
  (unwrap! (contract-call? .voting-token get-balance voter) u0)
)


;; Option 1: Using 'num-votes'
(define-read-only (calculate-quadratic-cost (num-votes uint))
  (* num-votes num-votes)
)


;; Private functions
(define-private (get-effective-voter (voter principal))
  (match (get-delegation voter)
    delegation-data
    (if (get active delegation-data)
      (get delegate delegation-data)
      voter
    )
    voter
  )
)

;; Simple iterative square root
(define-private (sqrt-newton (n uint))
  (let (
    (guess1 (/ n u2))
    (guess2 (/ (+ guess1 (/ n guess1)) u2))
    (guess3 (/ (+ guess2 (/ n guess2)) u2))
    (guess4 (/ (+ guess3 (/ n guess3)) u2))
    (guess5 (/ (+ guess4 (/ n guess4)) u2))
  )
    guess5
  )
)

;; Helper function for absolute difference
(define-private (abs-diff (a uint) (b uint))
  (if (>= a b)
    (- a b)
    (- b a)
  )
)

;; Simplified square root function (moved before calculate-voting-power)
(define-private (sqrt (n uint))
  (if (<= n u1)
    n
    (sqrt-newton n)
  )
)




;; Updated calculate-voting-power function (now placed after sqrt functions)
(define-private (calculate-voting-power (voter principal) (proposal-id uint) (vote-type uint))
  (let (
    (token-balance (get-voter-balance-internal voter))
  )
    (if (is-eq vote-type VOTE-TYPE-QUADRATIC)
      ;; For quadratic voting, power is square root of tokens
      (if (> token-balance u0) 
        (sqrt token-balance)
        u0
      )
      ;; For other types, power equals token balance
      token-balance
    )
  )
)

(define-private (update-proposal-results (proposal-id uint))
  (let (
    (proposal-data (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (vote-type (get vote-type proposal-data))
  )
    (if (is-eq vote-type VOTE-TYPE-YES-NO)
      (calculate-yes-no-results proposal-id)
      (if (is-eq vote-type VOTE-TYPE-RANKED-CHOICE)
        (calculate-ranked-choice-results proposal-id)
        (calculate-quadratic-results proposal-id)
      )
    )
  )
)

(define-private (calculate-yes-no-results (proposal-id uint))
  ;; Simplified yes/no calculation
  (ok true)
)

(define-private (calculate-ranked-choice-results (proposal-id uint))
  ;; Simplified ranked choice calculation
  (ok true)
)

(define-private (calculate-quadratic-results (proposal-id uint))
  ;; Simplified quadratic voting calculation
  (ok true)
)

;; Public functions

;; Create a new proposal
(define-public (create-proposal 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (vote-type uint)
  (options (list 10 (string-ascii 50)))
  (voting-duration uint)
  (quorum-threshold uint)
)
  (let (
    (proposal-id (+ (var-get proposal-counter) u1))
    (start-block (+ stacks-block-height u10)) ;; Start voting 10 blocks from now
    (end-block (+ start-block voting-duration))
  )
    (asserts! (> (len options) u0) ERR-INVALID-VOTE)
    (asserts! (> voting-duration u0) ERR-INVALID-VOTE)
    
    (map-set proposals
      { proposal-id: proposal-id }
      {
        title: title,
        description: description,
        proposer: tx-sender,
        vote-type: vote-type,
        options: options,
        start-block: start-block,
        end-block: end-block,
        quorum-threshold: quorum-threshold,
        created-at: stacks-block-height,
        executed: false
      }
    )
    
    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)

;; Cast a vote
(define-public (cast-vote 
  (proposal-id uint)
  (vote-data (list 10 uint))
)
  (let (
    (proposal-data (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (effective-voter (get-effective-voter tx-sender))
    (vote-type (get vote-type proposal-data))
    (voting-power (calculate-voting-power effective-voter proposal-id vote-type))
  )
    ;; Check if voting is active
    (asserts! (is-voting-active proposal-id) ERR-VOTING-CLOSED)
    
    ;; Check if already voted
    (asserts! (is-none (get-vote proposal-id effective-voter)) ERR-ALREADY-VOTED)
    
    ;; Validate vote data based on vote type
    (asserts! (validate-vote-data vote-data vote-type) ERR-INVALID-VOTE)
    
    ;; For quadratic voting, check if voter has enough tokens
    (if (is-eq vote-type VOTE-TYPE-QUADRATIC)
      (let (
        (total-votes (fold + vote-data u0))
        (required-tokens (calculate-quadratic-cost total-votes))
      )
        (asserts! (>= (get-voter-balance-internal effective-voter) required-tokens) ERR-INSUFFICIENT-TOKENS)
      )
      true
    )
    
    ;; Record the vote
    (map-set votes
      { proposal-id: proposal-id, voter: effective-voter }
      {
        vote-data: vote-data,
        vote-weight: voting-power,
        stacks-block-height: stacks-block-height
      }
    )
    
    (ok true)
  )
)

;; Delegate voting power
(define-public (delegate-vote (delegate principal))
  (begin
    (asserts! (not (is-eq tx-sender delegate)) ERR-INVALID-DELEGATION)
    
    (map-set vote-delegations
      { delegator: tx-sender }
      { delegate: delegate, active: true }
    )
    
    (ok true)
  )
)

;; Revoke delegation
(define-public (revoke-delegation)
  (begin
    (map-delete vote-delegations { delegator: tx-sender })
    (ok true)
  )
)

;; Finalize proposal results
(define-public (finalize-proposal (proposal-id uint))
  (let (
    (proposal-data (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    ;; Check if voting period has ended
    (asserts! (> stacks-block-height (get end-block proposal-data)) ERR-VOTING-CLOSED)
    
    ;; Calculate and store results
    (try! (update-proposal-results proposal-id))
    
    (ok true)
  )
)

;; Execute proposal (placeholder for actual execution logic)
(define-public (execute-proposal (proposal-id uint))
  (let (
    (proposal-data (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (results (unwrap! (get-proposal-results proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    ;; Check if proposal can be executed
    (asserts! (get quorum-met results) ERR-QUORUM-NOT-MET)
    (asserts! (not (get executed proposal-data)) ERR-UNAUTHORIZED)
    
    ;; Mark as executed
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal-data { executed: true })
    )
    
    ;; Add execution logic here based on proposal type
    
    (ok true)
  )
)

;; Helper function to validate vote data
(define-private (validate-vote-data (vote-data (list 10 uint)) (vote-type uint))
  (if (is-eq vote-type VOTE-TYPE-YES-NO)
    ;; For yes/no, should have exactly one vote of 1 or 0
    (and 
      (is-eq (len vote-data) u2)
      (or 
        (and (is-eq (unwrap-panic (element-at vote-data u0)) u1) (is-eq (unwrap-panic (element-at vote-data u1)) u0))
        (and (is-eq (unwrap-panic (element-at vote-data u0)) u0) (is-eq (unwrap-panic (element-at vote-data u1)) u1))
      )
    )
    ;; For other types, basic validation
    (> (len vote-data) u0)
  )
)

;; Admin functions
(define-public (set-voting-token (new-token principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set voting-token new-token)
    (ok true)
  )
)

;; Distribute initial voting tokens (for testing/setup)
(define-public (distribute-tokens (recipients (list 100 principal)) (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)

    (begin
  (try! (contract-call? .voting-token mint amount recipient))
  amount
)
    (ok true)
  )
)



;; Option 2: Use unwrap! with error handling
(define-private (distribute-to-recipient (recipient principal) (amount uint))
  (begin
    (unwrap! (contract-call? .voting-token mint amount recipient) (err u500))
    (ok amount)
  )
)

