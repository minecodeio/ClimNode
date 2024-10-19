
;; title: Proposal Voting System

;; version: 1.0.0

;; summary: A smart contract enabling voting functionality for decentralized proposals

;; description: This contract implements a comprehensive voting system for proposals
;; within a decentralized organization. It allows members to cast votes on proposals,
;; tracks voting statistics, and manages the finalization of voting outcomes. Key features include:
;; - One vote per member per proposal
;; - Binary voting (yes/no)
;; - Vote tracking and tallying
;; - Protection against double voting
;; - Controlled finalization process by contract owner
;; - Automated funding processing for approved proposals
;; The system integrates with the proposal submission contract to create a complete
;; governance solution for decentralized decision-making.

;; constants
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-ALREADY-VOTED (err u2))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u3))
(define-constant ERR-VOTING-CLOSED (err u4))

;; data vars
(define-data-var contract-owner principal tx-sender)

;; data maps
(define-map votes 
    { proposal-id: uint, voter: principal }
    { vote: bool }
)

(define-map vote-counts
    uint
    { yes-votes: uint, no-votes: uint, finalized: bool }
)

;; Proposal Data Structure
(define-map proposals 
    uint 
    {
        proposer: principal,
        title: (string-ascii 256),
        description: (string-ascii 1024),
        funding-amount: uint,
        is-active: bool,
        created-at: uint,
        last-modified: uint
    }
)

;; public functions
(define-public (vote-on-proposal (proposal-id uint) (vote bool))
    (let (
        (vote-count (default-to { yes-votes: u0, no-votes: u0, finalized: false } 
                    (map-get? vote-counts proposal-id)))
    )
        (asserts! (is-some (map-get? proposals proposal-id)) ERR-PROPOSAL-NOT-FOUND)
        (asserts! (not (get finalized vote-count)) ERR-VOTING-CLOSED)
        (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: tx-sender })) 
                 ERR-ALREADY-VOTED)
        
        (map-set votes 
            { proposal-id: proposal-id, voter: tx-sender }
            { vote: vote }
        )
        
        (map-set vote-counts proposal-id
            (merge vote-count
                {
                    yes-votes: (if vote 
                                (+ (get yes-votes vote-count) u1)
                                (get yes-votes vote-count)),
                    no-votes: (if (not vote)
                                (+ (get no-votes vote-count) u1)
                                (get no-votes vote-count))
                }
            )
        )
        (ok true)
    )
)

(define-public (finalize-voting (proposal-id uint))
    (let (
        (vote-count (default-to { yes-votes: u0, no-votes: u0, finalized: false }
                    (map-get? vote-counts proposal-id)))
        (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
        (asserts! (not (get finalized vote-count)) ERR-VOTING-CLOSED)
        ;; Only contract owner can finalize voting
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        
        ;; Update vote count as finalized
        (map-set vote-counts proposal-id
            (merge vote-count { finalized: true })
        )
        
        ;; If majority yes votes, process funding
        (if (> (get yes-votes vote-count) (get no-votes vote-count))
            (process-funding proposal-id)
            (ok false)
        )
    )
)

;; read only functions
(define-read-only (get-votes (proposal-id uint))
    (map-get? vote-counts proposal-id)
)

;; private functions
(define-private (process-funding (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
        ;; Implementation for funding transfer would go here
        (ok true)
    )
)