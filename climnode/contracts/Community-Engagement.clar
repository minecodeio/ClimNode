;; title: Community-Engagement
;; version: 1.0.0
;; summary: Community engagement contract for managing proposals and projects
;; description: This contract manages member proposals and project details to encourage participation and transparency

;; Define data variables
(define-data-var proposal-count uint u0)
(define-data-var project-count uint u0)

;; Define maps
(define-map proposals
  { proposal-id: uint }
  {
    member: principal,
    title: (string-utf8 100),
    description: (string-utf8 500),
    status: (string-ascii 20)
  }
)

(define-map projects
  { project-id: uint }
  {
    title: (string-utf8 100),
    description: (string-utf8 500),
    funding: uint,
    impact: (string-utf8 200),
    status: (string-ascii 20)
  }
)

(define-map member-proposals
  { member: principal }
  (list 50 uint)
)

;; Define constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATUS (err u102))

;; Define public functions

;; Submit a new proposal
(define-public (submit-proposal (title (string-utf8 100)) (description (string-utf8 500)))
  (let
    (
      (new-proposal-id (+ (var-get proposal-count) u1))
      (member tx-sender)
      (member-proposal-list (default-to (list) (map-get? member-proposals { member: member })))
    )
    (map-set proposals
      { proposal-id: new-proposal-id }
      {
        member: member,
        title: title,
        description: description,
        status: "pending"
      }
    )
    (map-set member-proposals
      { member: member }
      (unwrap! (as-max-len? (append member-proposal-list new-proposal-id) u50) ERR-NOT-AUTHORIZED)
    )
    (var-set proposal-count new-proposal-id)
    (ok new-proposal-id)
  )
)

;; Add a new project (only contract owner can add projects)
(define-public (add-project (title (string-utf8 100)) (description (string-utf8 500)) (funding uint) (impact (string-utf8 200)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (let
      (
        (new-project-id (+ (var-get project-count) u1))
      )
      (map-set projects
        { project-id: new-project-id }
        {
          title: title,
          description: description,
          funding: funding,
          impact: impact,
          status: "active"
        }
      )
      (var-set project-count new-project-id)
      (ok new-project-id)
    )
  )
)

;; Update project status
(define-public (update-project-status (project-id uint) (new-status (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (or (is-eq new-status "active") (is-eq new-status "completed") (is-eq new-status "cancelled")) ERR-INVALID-STATUS)
    (match (map-get? projects { project-id: project-id })
      project (ok (map-set projects
                    { project-id: project-id }
                    (merge project { status: new-status })))
      ERR-NOT-FOUND
    )
  )
)

;; Update proposal status (only contract owner)
(define-public (update-proposal-status (proposal-id uint) (new-status (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (or (is-eq new-status "pending") (is-eq new-status "approved") (is-eq new-status "rejected")) ERR-INVALID-STATUS)
    (match (map-get? proposals { proposal-id: proposal-id })
      proposal (ok (map-set proposals
                    { proposal-id: proposal-id }
                    (merge proposal { status: new-status })))
      ERR-NOT-FOUND
    )
  )
)

;; Define read-only functions

;; Get member proposals
(define-read-only (get-member-proposals (member principal))
  (ok (default-to (list) (map-get? member-proposals { member: member })))
)

;; Get project details
(define-read-only (get-project-details (project-id uint))
  (match (map-get? projects { project-id: project-id })
    project (ok project)
    ERR-NOT-FOUND
  )
)

;; Get proposal details
(define-read-only (get-proposal-details (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal (ok proposal)
    ERR-NOT-FOUND
  )
)

;; Get total proposal count
(define-read-only (get-proposal-count)
  (ok (var-get proposal-count))
)

;; Get total project count
(define-read-only (get-project-count)
  (ok (var-get project-count))
)

;; Check if a project exists
(define-read-only (project-exists (project-id uint))
  (is-some (map-get? projects { project-id: project-id }))
)

;; Check if a proposal exists
(define-read-only (proposal-exists (proposal-id uint))
  (is-some (map-get? proposals { proposal-id: proposal-id }))
)

;; Get project status only
(define-read-only (get-project-status (project-id uint))
  (match (map-get? projects { project-id: project-id })
    project (ok (get status project))
    ERR-NOT-FOUND
  )
)

;; Get proposal status only
(define-read-only (get-proposal-status (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal (ok (get status proposal))
    ERR-NOT-FOUND
  )
)

;; Get project funding amount
(define-read-only (get-project-funding (project-id uint))
  (match (map-get? projects { project-id: project-id })
    project (ok (get funding project))
    ERR-NOT-FOUND
  )
)

;; Check if user is contract owner
(define-read-only (is-contract-owner (user principal))
  (is-eq user CONTRACT-OWNER)
)
