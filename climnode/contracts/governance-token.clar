
;; title: governance-token
;; version:
;; summary:
;; description:

;; Define the contract owner
(define-constant contract-owner tx-sender)

;; Define error codes
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))

;; Define the data map to store token balances
(define-map token-balances principal uint)

;; Mint tokens for a member
(define-public (mint-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set token-balances recipient 
                 (+ (default-to u0 (map-get? token-balances recipient)) amount))))
)

;; Transfer tokens between accounts
(define-public (transfer-tokens (amount uint) (sender principal) (recipient principal))
  (let ((sender-balance (default-to u0 (map-get? token-balances sender))))
    (asserts! (>= sender-balance amount) err-insufficient-balance)
    (map-set token-balances sender (- sender-balance amount))
    (map-set token-balances recipient 
             (+ (default-to u0 (map-get? token-balances recipient)) amount))
    (ok true))
)

;; Get token balance of a member
(define-read-only (get-token-balance (account principal))
  (ok (default-to u0 (map-get? token-balances account)))
)

;; Initialize the contract
(begin
  (map-set token-balances contract-owner u1000000)
)