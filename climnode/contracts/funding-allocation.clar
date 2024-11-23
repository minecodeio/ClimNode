
;; title: funding-allocation
;; version:
;; summary:
;; description:

;; Define the contract owner
(define-constant contract-owner tx-sender)

;; Define error codes
(define-constant err-owner-only (err u100))
(define-constant err-project-not-found (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-already-funded (err u103))

;; Define the governance token contract
(define-constant governance-token .governance-token)

;; Define the data map to store project funding status
(define-map projects
  { project-id: uint }
  { amount: uint, funded: bool })

;; Define the contract's balance
(define-data-var contract-balance uint u0)

;; Allocate funds to a project
(define-public (allocate-funds (project-id uint) (amount uint))
  (let (
    (project (unwrap! (map-get? projects { project-id: project-id }) err-project-not-found))
    (current-balance (var-get contract-balance))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (>= current-balance amount) err-insufficient-funds)
    (asserts! (not (get funded project)) err-already-funded)
    
    (map-set projects
      { project-id: project-id }
      { amount: amount, funded: true })
    
    (var-set contract-balance (- current-balance amount))
    (ok true)
  )
)

;; Get funding status of a project
(define-read-only (get-funding-status (project-id uint))
  (match (map-get? projects { project-id: project-id })
    project (ok project)
    err-project-not-found
  )
)

;; Add funds to the contract
(define-public (add-funds (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-ok (contract-call? governance-token transfer-tokens amount tx-sender (as-contract tx-sender))) err-insufficient-funds)
    (var-set contract-balance (+ (var-get contract-balance) amount))
    (ok true)
  )
)

;; Initialize the contract
(begin
  (map-set projects { project-id: u1 } { amount: u0, funded: false })
  (map-set projects { project-id: u2 } { amount: u0, funded: false })
)