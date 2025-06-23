;; Voting Token Contract (SIP-010 Fungible Token)
;; This token represents voting power in the governance system

(impl-trait .sip-010-trait.sip-010-trait)

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-TOKEN-OWNER (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))

;; Token definition
(define-fungible-token voting-token)

;; Data variables
(define-data-var token-name (string-ascii 32) "Voting Token")
(define-data-var token-symbol (string-ascii 10) "VOTE")
(define-data-var token-uri (optional (string-utf8 256)) none)
(define-data-var token-decimals uint u6)

;; SIP-010 Functions

(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
  (begin
    (asserts! (or (is-eq tx-sender from) (is-eq contract-caller from)) ERR-UNAUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (ft-transfer? voting-token amount from to)
  )
)

(define-read-only (get-name)
  (ok (var-get token-name))
)

(define-read-only (get-symbol)
  (ok (var-get token-symbol))
)

(define-read-only (get-decimals)
  (ok (var-get token-decimals))
)

(define-read-only (get-balance (who principal))
  (ok (ft-get-balance voting-token who))
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply voting-token))
)

(define-read-only (get-token-uri)
  (ok (var-get token-uri))
)

;; Additional functions for governance

(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (ft-mint? voting-token amount recipient)
  )
)

(define-public (burn (amount uint) (owner principal))
  (begin
    (asserts! (or (is-eq tx-sender owner) (is-eq tx-sender CONTRACT-OWNER)) ERR-UNAUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (ft-burn? voting-token amount owner)
  )
)

;; Initialize token supply
(define-public (initialize (initial-supply uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (ft-mint? voting-token initial-supply CONTRACT-OWNER)
  )
)
