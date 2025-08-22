;; Project Registry Smart Contract
;; Maintains persistent, auditable records of all proposals and projects

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-unauthorized (err u201))
(define-constant err-project-not-found (err u202))
(define-constant err-invalid-status (err u203))
(define-constant err-project-exists (err u204))
(define-constant err-invalid-params (err u205))

;; Project Status Constants
(define-constant status-proposed u1)
(define-constant status-under-review u2)
(define-constant status-approved u3)
(define-constant status-in-progress u4)
(define-constant status-completed u5)
(define-constant status-cancelled u6)
(define-constant status-rejected u7)

;; Project Categories
(define-constant category-infrastructure u1)
(define-constant category-defi u2)
(define-constant category-nft u3)
(define-constant category-governance u4)
(define-constant category-education u5)
(define-constant category-tooling u6)
(define-constant category-other u7)

;; Data Variables
(define-data-var next-project-id uint u1)
(define-data-var total-projects uint u0)
(define-data-var registry-paused bool false)

;; Authorization map for project registration
(define-map authorized-registrars principal bool)

;; Main project registry
(define-map projects
  { project-id: uint }
  {
    title: (string-ascii 200),
    description: (string-utf8 1000),
    proposer: principal,
    category: uint,
    status: uint,
    funding-requested: uint,
    funding-approved: uint,
    start-block: uint,
    end-block: (optional uint),
    completion-block: (optional uint),
    metadata-uri: (optional (string-ascii 500)),
    tags: (list 10 (string-ascii 50)),
    created-at: uint,
    updated-at: uint
  }
)

;; Project updates/milestones
(define-map project-updates
  { project-id: uint, update-id: uint }
  {
    title: (string-ascii 100),
    description: (string-utf8 500),
    update-type: uint, ;; 1=milestone, 2=status-change, 3=funding, 4=general
    updated-by: principal,
    block-height: uint,
    metadata-uri: (optional (string-ascii 500))
  }
)

;; Track update counts per project
(define-map project-update-counts
  { project-id: uint }
  { count: uint }
)

;; Project voting/approval records
(define-map project-votes
  { project-id: uint, voter: principal }
  {
    vote: bool, ;; true=approve, false=reject
    vote-weight: uint,
    vote-block: uint,
    comment: (optional (string-utf8 200))
  }
)

;; Project statistics
(define-map project-stats
  { project-id: uint }
  {
    total-votes: uint,
    approval-votes: uint,
    rejection-votes: uint,
    total-funding: uint,
    completion-percentage: uint
  }
)

;; Read-only functions

(define-read-only (get-project (project-id uint))
  (map-get? projects { project-id: project-id })
)

(define-read-only (get-project-stats (project-id uint))
  (map-get? project-stats { project-id: project-id })
)

(define-read-only (get-project-update (project-id uint) (update-id uint))
  (map-get? project-updates { project-id: project-id, update-id: update-id })
)

(define-read-only (get-project-vote (project-id uint) (voter principal))
  (map-get? project-votes { project-id: project-id, voter: voter })
)

(define-read-only (get-total-projects)
  (var-get total-projects)
)

(define-read-only (get-next-project-id)
  (var-get next-project-id)
)

(define-read-only (is-authorized-registrar (user principal))
  (default-to false (map-get? authorized-registrars user))
)

(define-read-only (get-projects-by-status (status uint))
  ;; In a full implementation, this would return a list of project IDs
  ;; For now, returns the status for validation
  (if (and (>= status u1) (<= status u7))
    (ok status)
    (err err-invalid-status)
  )
)

(define-read-only (get-projects-by-category (category uint))
  ;; Similar to above, validates category
  (if (and (>= category u1) (<= category u7))
    (ok category)
    (err err-invalid-params)
  )
)

(define-read-only (get-projects-by-proposer (proposer principal))
  ;; Returns validation for proposer queries
  (ok proposer)
)

(define-read-only (is-registry-paused)
  (var-get registry-paused)
)

;; Public functions

(define-public (register-project
  (title (string-ascii 200))
  (description (string-utf8 1000))
  (category uint)
  (funding-requested uint)
  (estimated-duration uint)
  (metadata-uri (optional (string-ascii 500)))
  (tags (list 10 (string-ascii 50)))
)
  (let 
    (
      (project-id (var-get next-project-id))
      (current-block stacks-block-height)
    )
    ;; Check authorization
    (asserts! (or (is-eq tx-sender contract-owner) 
                  (is-authorized-registrar tx-sender)) err-unauthorized)
    (asserts! (not (var-get registry-paused)) err-unauthorized)
    (asserts! (and (>= category u1) (<= category u7)) err-invalid-params)
    (asserts! (> (len title) u0) err-invalid-params)
    
    ;; Register the project
    (map-set projects
      { project-id: project-id }
      {
        title: title,
        description: description,
        proposer: tx-sender,
        category: category,
        status: status-proposed,
        funding-requested: funding-requested,
        funding-approved: u0,
        start-block: current-block,
        end-block: (if (> estimated-duration u0) 
                      (some (+ current-block estimated-duration)) 
                      none),
        completion-block: none,
        metadata-uri: metadata-uri,
        tags: tags,
        created-at: current-block,
        updated-at: current-block
      }
    )
    
    ;; Initialize project stats
    (map-set project-stats
      { project-id: project-id }
      {
        total-votes: u0,
        approval-votes: u0,
        rejection-votes: u0,
        total-funding: u0,
        completion-percentage: u0
      }
    )
    
    ;; Initialize update count
    (map-set project-update-counts
      { project-id: project-id }
      { count: u0 }
    )
    
    ;; Update counters
    (var-set next-project-id (+ project-id u1))
    (var-set total-projects (+ (var-get total-projects) u1))
    
    (print { 
      event: "project-registered", 
      project-id: project-id, 
      proposer: tx-sender,
      title: title 
    })
    
    (ok project-id)
  )
)

(define-public (update-project-status (project-id uint) (new-status uint))
  (let 
    (
      (project-data (unwrap! (map-get? projects { project-id: project-id }) err-project-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (and (>= new-status u1) (<= new-status u7)) err-invalid-status)
    
    (map-set projects
      { project-id: project-id }
      (merge project-data { 
        status: new-status, 
        updated-at: stacks-block-height,
        completion-block: (if (is-eq new-status status-completed)
                            (some stacks-block-height)
                            (get completion-block project-data))
      })
    )
    
    ;; Fixed intermediary response handling by using try! to check the response
    (try! (add-project-update project-id 
                             "Status Update" 
                             (if (is-eq new-status status-completed) 
                                 u"Project completed" 
                                 u"Status changed")
                             u2 ;; status-change type
                             none))
    
    (print { 
      event: "project-status-updated", 
      project-id: project-id, 
      new-status: new-status 
    })
    
    (ok true)
  )
)


(define-public (add-project-update
  (project-id uint)
  (title (string-ascii 100))
  (description (string-utf8 500))
  (update-type uint)
  (metadata-uri (optional (string-ascii 500)))
)
  (let 
    (
      (project-data (unwrap! (map-get? projects { project-id: project-id }) err-project-not-found))
      (update-count-data (default-to { count: u0 } 
                                    (map-get? project-update-counts { project-id: project-id })))
      (update-id (+ (get count update-count-data) u1))
    )
    ;; Only project proposer or owner can add updates
    (asserts! (or (is-eq tx-sender (get proposer project-data))
                  (is-eq tx-sender contract-owner)) err-unauthorized)
    (asserts! (and (>= update-type u1) (<= update-type u4)) err-invalid-params)
    
    (map-set project-updates
      { project-id: project-id, update-id: update-id }
      {
        title: title,
        description: description,
        update-type: update-type,
        updated-by: tx-sender,
        block-height: stacks-block-height,
        metadata-uri: metadata-uri
      }
    )
    
    (map-set project-update-counts
      { project-id: project-id }
      { count: update-id }
    )
    
    (print { 
      event: "project-updated", 
      project-id: project-id, 
      update-id: update-id,
      title: title 
    })
    
    (ok update-id)
  )
)

(define-public (vote-on-project 
  (project-id uint) 
  (vote bool) 
  (vote-weight uint)
  (comment (optional (string-utf8 200)))
)
  (let 
    (
      (project-data (unwrap! (map-get? projects { project-id: project-id }) err-project-not-found))
      (current-stats (default-to 
                       { total-votes: u0, approval-votes: u0, rejection-votes: u0, 
                         total-funding: u0, completion-percentage: u0 }
                       (map-get? project-stats { project-id: project-id })))
    )
    ;; Only allow voting on proposed or under-review projects
    (asserts! (or (is-eq (get status project-data) status-proposed)
                  (is-eq (get status project-data) status-under-review)) err-invalid-status)
    
    ;; Record the vote
    (map-set project-votes
      { project-id: project-id, voter: tx-sender }
      {
        vote: vote,
        vote-weight: vote-weight,
        vote-block: stacks-block-height,
        comment: comment
      }
    )
    
    ;; Update project stats
    (map-set project-stats
      { project-id: project-id }
      {
        total-votes: (+ (get total-votes current-stats) u1),
        approval-votes: (if vote 
                          (+ (get approval-votes current-stats) u1)
                          (get approval-votes current-stats)),
        rejection-votes: (if vote 
                           (get rejection-votes current-stats)
                           (+ (get rejection-votes current-stats) u1)),
        total-funding: (get total-funding current-stats),
        completion-percentage: (get completion-percentage current-stats)
      }
    )
    
    (print { 
      event: "project-vote-cast", 
      project-id: project-id, 
      voter: tx-sender,
      vote: vote 
    })
    
    (ok true)
  )
)

;; Administrative functions

(define-public (authorize-registrar (user principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-registrars user true)
    (ok true)
  )
)

(define-public (revoke-registrar (user principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-delete authorized-registrars user)
    (ok true)
  )
)

(define-public (pause-registry)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set registry-paused true)
    (ok true)
  )
)

(define-public (unpause-registry)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set registry-paused false)
    (ok true)
  )
)

;; Initialize contract
(begin
  (map-set authorized-registrars contract-owner true)
  (print "Project Registry contract deployed")
)