;; title: Proposal Submission and Management Contract
;; version: 1.0.0
;; summary: A smart contract for managing project proposals in a DAO
;; description: This contract enables users to submit, edit, and view project proposals.
;; Each proposal includes details like title, description, funding amount, and tracks its
;; active status and modification history. The contract implements access controls to ensure
;; only proposal creators can edit their submissions.

;; traits
;; No traits are currently implemented

;; token definitions
;; No token definitions are required for basic proposal management

;; constants
;; Error codes for various failure conditions
(define-constant ERR-EMPTY-TITLE (err u1))        
(define-constant ERR-INVALID-AMOUNT (err u2))    
(define-constant ERR-PROPOSAL-NOT-FOUND (err u3)) 
(define-constant ERR-NOT-AUTHORIZED (err u4))   
(define-constant ERR-PROPOSAL-INACTIVE (err u5)) 

;; data vars
;; Counter to track the total number of proposals and generate unique IDs
(define-data-var proposal-counter uint u0)

;; data maps
;; Main storage for proposal data, mapping proposal IDs to their details
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
;; Creates a new proposal with provided details
(define-public (submit-proposal (title (string-ascii 256)) (description (string-ascii 1024)) (funding-amount uint))
    (let 
        ((proposal-id (var-get proposal-counter)))  ;; Get current counter value as new ID
        (begin
            ;; Validate inputs
            (asserts! (> (len title) u0) ERR-EMPTY-TITLE)
            (asserts! (> funding-amount u0) ERR-INVALID-AMOUNT)
            
            ;; Store new proposal in map
            (map-set proposals proposal-id
                {
                    proposer: tx-sender,            ;; Set creator as current sender
                    title: title,
                    description: description,
                    funding-amount: funding-amount,
                    is-active: true,                ;; New proposals are active by default
                    created-at: block-height,
                    last-modified: block-height
                }
            )
            ;; Increment counter for next proposal
            (var-set proposal-counter (+ proposal-id u1))
            (ok proposal-id)  ;; Return new proposal ID
        )
    )
)

;; Allows proposal owner to modify proposal details
(define-public (edit-proposal (proposal-id uint) (title (string-ascii 256)) (description (string-ascii 1024)) (funding-amount uint))
    (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND)))
        (begin
            ;; Verify sender is proposal owner
            (asserts! (is-eq tx-sender (get proposer proposal)) ERR-NOT-AUTHORIZED)
            ;; Check proposal is still active
            (asserts! (get is-active proposal) ERR-PROPOSAL-INACTIVE)
            ;; Validate new inputs
            (asserts! (> (len title) u0) ERR-EMPTY-TITLE)
            (asserts! (> funding-amount u0) ERR-INVALID-AMOUNT)
            
            ;; Update proposal with new details
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
;; Retrieves full details of a specific proposal
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

;; Returns a list of all active proposal IDs
(define-read-only (get-active-proposals)
    (let 
        ((counter (var-get proposal-counter)))
        (filter is-active-proposal (create-sequence u0 counter))
    )
)

;; private functions
;; Helper function to check if a proposal is active
(define-private (is-active-proposal (id uint))
    (match (map-get? proposals id)
        proposal (get is-active proposal)  ;; Return is-active status if proposal exists
        false                             ;; Return false if proposal doesn't exist
    )
)

;; Helper function to create a sequence of numbers
;; Note: Currently only returns single number, needs enhancement for proper sequence
(define-private (create-sequence (start uint) (end uint))
    (list start)
)