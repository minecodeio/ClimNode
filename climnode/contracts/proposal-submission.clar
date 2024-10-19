;; title: proposal-submission
;; version: 1.0.0
;; summary:
;; description: This contract facilitates the submission and management of proposals within a decentralized application. Users can create new proposals by providing a title, description, and funding amount, which are then stored in a data map. Each proposal is assigned a unique identifier and marked as active. Proposers can edit their proposals, ensuring that the information is up-to-date and accurate.

;; traits
;;

;; token definitions
;;

;; constants
(define-constant ERR-EMPTY-TITLE (err u1))
(define-constant ERR-INVALID-AMOUNT (err u2))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u3))
(define-constant ERR-NOT-AUTHORIZED (err u4))
(define-constant ERR-PROPOSAL-INACTIVE (err u5))

;; data vars
(define-data-var proposal-counter uint u0)

;; data maps
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
(define-public (submit-proposal (title (string-ascii 256)) (description (string-ascii 1024)) (funding-amount uint))
    (let 
        ((proposal-id (var-get proposal-counter)))
        (begin
            (asserts! (> (len title) u0) ERR-EMPTY-TITLE)
            (asserts! (> funding-amount u0) ERR-INVALID-AMOUNT)
            
            (map-set proposals proposal-id
                {
                    proposer: tx-sender,
                    title: title,
                    description: description,
                    funding-amount: funding-amount,
                    is-active: true,
                    created-at: block-height,
                    last-modified: block-height
                }
            )
            (var-set proposal-counter (+ proposal-id u1))
            (ok proposal-id)
        )
    )
)

(define-public (edit-proposal (proposal-id uint) (title (string-ascii 256)) (description (string-ascii 1024)) (funding-amount uint))
    (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND)))
        (begin
            (asserts! (is-eq tx-sender (get proposer proposal)) ERR-NOT-AUTHORIZED)
            (asserts! (get is-active proposal) ERR-PROPOSAL-INACTIVE)
            (asserts! (> (len title) u0) ERR-EMPTY-TITLE)
            (asserts! (> funding-amount u0) ERR-INVALID-AMOUNT)
            
            (map-set proposals proposal-id
                (merge proposal
                    {
                        title: title,
                        description: description,
                        funding-amount: funding-amount,
                        last-modified: block-height
                    }
                )
            )
            (ok true)
        )
    )
)

;; read only functions
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-active-proposals)
    (let 
        ((counter (var-get proposal-counter)))
        (filter is-active-proposal (create-sequence u0 counter))
    )
)

;; private functions
(define-private (is-active-proposal (id uint))
    (match (map-get? proposals id)
        proposal (get is-active proposal)
        false
    )
)

(define-private (create-sequence (start uint) (end uint))
    (list start)
)