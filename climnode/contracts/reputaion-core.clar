;; Reputation Score Smart Contract
;; Rewards or penalizes users based on contributions, voting activity, and proposal success

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-score (err u104))
(define-constant err-already-voted (err u105))

;; Reputation scoring weights (out of 100)
(define-constant contribution-weight u40)
(define-constant voting-weight u30)
(define-constant proposal-success-weight u30)

;; Score limits
(define-constant max-reputation-score u1000)
(define-constant min-reputation-score u0)
(define-constant initial-reputation u100)

;; Penalty and reward amounts
(define-constant proposal-success-reward u50)
(define-constant proposal-failure-penalty u25)
(define-constant active-voting-reward u10)
(define-constant missed-vote-penalty u5)
(define-constant quality-contribution-reward u30)
(define-constant spam-penalty u20)

;; Data Variables
(define-data-var next-activity-id uint u1)

;; Data Maps

;; Core reputation data for each user
(define-map user-reputation
  { user: principal }
  {
    total-score: uint,
    contribution-score: uint,
    voting-score: uint,
    proposal-success-score: uint,
    last-updated: uint,
    reputation-level: (string-ascii 20)
  }
)

;; Detailed activity tracking
(define-map user-activity-stats
  { user: principal }
  {
    total-contributions: uint,
    quality-contributions: uint,
    total-votes-cast: uint,
    total-votes-eligible: uint,
    proposals-created: uint,
    successful-proposals: uint,
    failed-proposals: uint,
    spam-reports: uint
  }
)

;; Historical reputation changes
(define-map reputation-history
  { user: principal, activity-id: uint }
  {
    activity-type: (string-ascii 50),
    score-change: int,
    new-total-score: uint,
    timestamp: uint,
    description: (string-ascii 200)
  }
)

;; Track voting participation for specific proposals/votes
(define-map voting-participation
  { user: principal, vote-id: uint }
  {
    participated: bool,
    vote-weight: uint,
    timestamp: uint
  }
)

;; Authorized score managers (can update reputation)
(define-map authorized-managers
  { manager: principal }
  { is-authorized: bool }
)

;; Reputation level thresholds
(define-map reputation-levels
  { level: (string-ascii 20) }
  {
    min-score: uint,
    max-score: uint,
    voting-multiplier: uint  ;; Multiplier for voting power (100 = 1x, 150 = 1.5x)
  }
)

;; Public Functions

;; Initialize user reputation (called when user first joins)
(define-public (initialize-user-reputation (user principal))
  (begin
    (asserts! (is-none (map-get? user-reputation { user: user })) (ok false))
    
    (map-set user-reputation
      { user: user }
      {
        total-score: initial-reputation,
        contribution-score: u0,
        voting-score: u0,
        proposal-success-score: u0,
        last-updated: stacks-block-height,
        reputation-level: "Newcomer"
      }
    )
    
    (map-set user-activity-stats
      { user: user }
      {
        total-contributions: u0,
        quality-contributions: u0,
        total-votes-cast: u0,
        total-votes-eligible: u0,
        proposals-created: u0,
        successful-proposals: u0,
        failed-proposals: u0,
        spam-reports: u0
      }
    )
    
    (ok true)
  )
)

;; Record a contribution (authorized managers only)
(define-public (record-contribution 
  (user principal) 
  (contribution-type (string-ascii 50))
  (quality-score uint)  ;; 1-10 scale
)
  (let
    (
      (manager-auth (default-to { is-authorized: false } (map-get? authorized-managers { manager: tx-sender })))
      (current-stats (unwrap! (map-get? user-activity-stats { user: user }) err-not-found))
      (score-change (if (>= quality-score u7) quality-contribution-reward u10))
    )
    (asserts! (get is-authorized manager-auth) err-unauthorized)
    (asserts! (<= quality-score u10) err-invalid-score)
    
    ;; Update activity stats
    (map-set user-activity-stats
      { user: user }
      (merge current-stats {
        total-contributions: (+ (get total-contributions current-stats) u1),
        quality-contributions: (if (>= quality-score u7) 
                                 (+ (get quality-contributions current-stats) u1)
                                 (get quality-contributions current-stats))
      })
    )
    
    ;; Update reputation score
    (try! (update-user-reputation user (to-int score-change) contribution-type "Quality contribution recorded"))
    
    (ok true)
  )
)

;; Record voting participation
(define-public (record-vote-participation 
  (user principal) 
  (vote-id uint) 
  (participated bool)
)
  (let
    (
      (manager-auth (default-to { is-authorized: false } (map-get? authorized-managers { manager: tx-sender })))
      (current-stats (unwrap! (map-get? user-activity-stats { user: user }) err-not-found))
      (score-change (if participated (to-int active-voting-reward) (to-int (- u0 missed-vote-penalty))))
    )
    (asserts! (get is-authorized manager-auth) err-unauthorized)
    (asserts! (is-none (map-get? voting-participation { user: user, vote-id: vote-id })) err-already-voted)
    
    ;; Record participation
    (map-set voting-participation
      { user: user, vote-id: vote-id }
      {
        participated: participated,
        vote-weight: u1,  ;; Base weight, can be modified by reputation
        timestamp: stacks-block-height
      }
    )
    
    ;; Update activity stats
    (map-set user-activity-stats
      { user: user }
      (merge current-stats {
        total-votes-cast: (if participated (+ (get total-votes-cast current-stats) u1) (get total-votes-cast current-stats)),
        total-votes-eligible: (+ (get total-votes-eligible current-stats) u1)
      })
    )
    
    ;; Update reputation
    (try! (update-user-reputation user score-change "voting-participation" 
                                 (if participated "Active voting participation" "Missed vote opportunity")))
    
    (ok true)
  )
)

;; Record proposal outcome
(define-public (record-proposal-outcome 
  (user principal) 
  (proposal-id uint) 
  (successful bool)
)
  (let
    (
      (manager-auth (default-to { is-authorized: false } (map-get? authorized-managers { manager: tx-sender })))
      (current-stats (unwrap! (map-get? user-activity-stats { user: user }) err-not-found))
      (score-change (if successful (to-int proposal-success-reward) (to-int (- u0 proposal-failure-penalty))))
    )
    (asserts! (get is-authorized manager-auth) err-unauthorized)
    
    ;; Update activity stats
    (map-set user-activity-stats
      { user: user }
      (merge current-stats {
        proposals-created: (+ (get proposals-created current-stats) u1),
        successful-proposals: (if successful (+ (get successful-proposals current-stats) u1) (get successful-proposals current-stats)),
        failed-proposals: (if successful (get failed-proposals current-stats) (+ (get failed-proposals current-stats) u1))
      })
    )
    
    ;; Update reputation
    (try! (update-user-reputation user score-change "proposal-outcome" 
                                 (if successful "Successful proposal" "Failed proposal")))
    
    (ok true)
  )
)

;; Apply penalty for spam or bad behavior
(define-public (apply-penalty 
  (user principal) 
  (penalty-amount uint) 
  (reason (string-ascii 200))
)
  (let
    (
      (manager-auth (default-to { is-authorized: false } (map-get? authorized-managers { manager: tx-sender })))
      (current-stats (unwrap! (map-get? user-activity-stats { user: user }) err-not-found))
    )
    (asserts! (get is-authorized manager-auth) err-unauthorized)
    (asserts! (<= penalty-amount u100) err-invalid-amount)
    
    ;; Update spam reports
    (map-set user-activity-stats
      { user: user }
      (merge current-stats {
        spam-reports: (+ (get spam-reports current-stats) u1)
      })
    )
    
    ;; Apply penalty
    (try! (update-user-reputation user (to-int (- u0 penalty-amount)) "penalty" reason))
    
    (ok true)
  )
)

;; Add authorized manager (owner only)
(define-public (add-manager (manager principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-managers
      { manager: manager }
      { is-authorized: true }
    )
    (ok true)
  )
)

;; Remove authorized manager (owner only)
(define-public (remove-manager (manager principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-managers
      { manager: manager }
      { is-authorized: false }
    )
    (ok true)
  )
)

;; Set reputation level thresholds (owner only)
(define-public (set-reputation-level 
  (level (string-ascii 20)) 
  (min-score uint) 
  (max-score uint) 
  (voting-multiplier uint)
)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (< min-score max-score) err-invalid-score)
    
    (map-set reputation-levels
      { level: level }
      {
        min-score: min-score,
        max-score: max-score,
        voting-multiplier: voting-multiplier
      }
    )
    (ok true)
  )
)

;; Private Functions

;; Update user reputation score
(define-private (update-user-reputation 
  (user principal) 
  (score-change int) 
  (activity-type (string-ascii 50)) 
  (description (string-ascii 200))
)
  (let
    (
      (current-rep (unwrap! (map-get? user-reputation { user: user }) err-not-found))
      (current-score (get total-score current-rep))
      (new-score (if (< score-change 0)
                    (if (> (to-uint (- score-change)) current-score) 
                        min-reputation-score 
                        (- current-score (to-uint (- score-change))))
                    (if (> (+ current-score (to-uint score-change)) max-reputation-score)
                        max-reputation-score
                        (+ current-score (to-uint score-change)))))
      (new-level (calculate-reputation-level new-score))
      (activity-id (var-get next-activity-id))
    )
    
    ;; Update reputation
    (map-set user-reputation
      { user: user }
      (merge current-rep {
        total-score: new-score,
        last-updated: stacks-block-height,
        reputation-level: new-level
      })
    )
    
    ;; Record history
    (map-set reputation-history
      { user: user, activity-id: activity-id }
      {
        activity-type: activity-type,
        score-change: score-change,
        new-total-score: new-score,
        timestamp: stacks-block-height,
        description: description
      }
    )
    
    (var-set next-activity-id (+ activity-id u1))
    (ok true)
  )
)

;; Calculate reputation level based on score
(define-private (calculate-reputation-level (score uint))
  (if (<= score u50) "Newcomer"
    (if (<= score u150) "Contributor"
      (if (<= score u300) "Active Member"
        (if (<= score u500) "Trusted Member"
          (if (<= score u750) "Expert"
            "Legend")))))
)

;; Read-only Functions

;; Get user reputation
(define-read-only (get-user-reputation (user principal))
  (map-get? user-reputation { user: user })
)

;; Get user activity stats
(define-read-only (get-user-activity-stats (user principal))
  (map-get? user-activity-stats { user: user })
)

;; Get user's voting power multiplier based on reputation
(define-read-only (get-voting-power-multiplier (user principal))
  (match (map-get? user-reputation { user: user })
    rep-data (let
               (
                 (level (get reputation-level rep-data))
                 (level-data (map-get? reputation-levels { level: level }))
               )
               (match level-data
                 data (get voting-multiplier data)
                 u100  ;; Default 1x multiplier
               ))
    u100
  )
)

;; Calculate effective voting power
(define-read-only (get-effective-voting-power (user principal) (base-power uint))
  (let
    (
      (multiplier (get-voting-power-multiplier user))
    )
    (/ (* base-power multiplier) u100)
  )
)

;; Get reputation history entry
(define-read-only (get-reputation-history (user principal) (activity-id uint))
  (map-get? reputation-history { user: user, activity-id: activity-id })
)

;; Check if user participated in specific vote
(define-read-only (get-vote-participation (user principal) (vote-id uint))
  (map-get? voting-participation { user: user, vote-id: vote-id })
)

;; Calculate contribution rate
(define-read-only (get-contribution-quality-rate (user principal))
  (match (map-get? user-activity-stats { user: user })
    stats (if (> (get total-contributions stats) u0)
            (/ (* (get quality-contributions stats) u100) (get total-contributions stats))
            u0)
    u0
  )
)

;; Calculate voting participation rate
(define-read-only (get-voting-participation-rate (user principal))
  (match (map-get? user-activity-stats { user: user })
    stats (if (> (get total-votes-eligible stats) u0)
            (/ (* (get total-votes-cast stats) u100) (get total-votes-eligible stats))
            u0)
    u0
  )
)

;; Calculate proposal success rate
(define-read-only (get-proposal-success-rate (user principal))
  (match (map-get? user-activity-stats { user: user })
    stats (if (> (get proposals-created stats) u0)
            (/ (* (get successful-proposals stats) u100) (get proposals-created stats))
            u0)
    u0
  )
)

;; Get reputation level info
(define-read-only (get-reputation-level-info (level (string-ascii 20)))
  (map-get? reputation-levels { level: level })
)

;; Check if manager is authorized
(define-read-only (is-authorized-manager (manager principal))
  (default-to { is-authorized: false } (map-get? authorized-managers { manager: manager }))
)

;; Get user's reputation rank (simplified - returns level)
(define-read-only (get-user-reputation-rank (user principal))
  (match (map-get? user-reputation { user: user })
    rep-data (get reputation-level rep-data)
    "Unranked"
  )
)

;; Initialize default reputation levels
(define-private (init-reputation-levels)
  (begin
    (map-set reputation-levels { level: "Newcomer" } { min-score: u0, max-score: u50, voting-multiplier: u80 })
    (map-set reputation-levels { level: "Contributor" } { min-score: u51, max-score: u150, voting-multiplier: u100 })
    (map-set reputation-levels { level: "Active Member" } { min-score: u151, max-score: u300, voting-multiplier: u120 })
    (map-set reputation-levels { level: "Trusted Member" } { min-score: u301, max-score: u500, voting-multiplier: u140 })
    (map-set reputation-levels { level: "Expert" } { min-score: u501, max-score: u750, voting-multiplier: u160 })
    (map-set reputation-levels { level: "Legend" } { min-score: u751, max-score: u1000, voting-multiplier: u200 })
  )
)

;; Initialize the contract
(init-reputation-levels)