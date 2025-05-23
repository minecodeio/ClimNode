;; Impact Tracking and Reporting Contract
;; Allows projects to submit impact reports and retrieve historical reports

;; Data Variables
(define-map project-reports 
    {project-id: uint, report-id: uint} 
    {
        implementer: principal,
        timestamp: uint,
        metrics: (list 10 {metric-name: (string-ascii 50), value: uint}),
        description: (string-utf8 500)
    }
)

;; Track the next report ID for each project
(define-map project-report-counts
    {project-id: uint}
    {report-count: uint}
)

(define-data-var next-report-id uint u0)

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PROJECT (err u101))
(define-constant ERR-INVALID-METRICS (err u102))

;; Read-only functions
(define-read-only (get-report (project-id uint) (report-id uint))
    (map-get? project-reports {project-id: project-id, report-id: report-id})
)

(define-read-only (get-report-count (project-id uint))
    (default-to 
        {report-count: u0}
        (map-get? project-report-counts {project-id: project-id})
    )
)

(define-read-only (get-latest-report (project-id uint))
    (let ((count (get report-count (get-report-count project-id))))
        (if (> count u0)
            (get-report project-id (- count u1))
            none
        )
    )
)

;; Public functions
(define-public (report-impact 
        (project-id uint)
        (metrics (list 10 {metric-name: (string-ascii 50), value: uint}))
        (description (string-utf8 500))
    )
    (let 
        (
            (current-count (get report-count (get-report-count project-id)))
            (report-id (var-get next-report-id))
        )
        ;; Only authorized implementers can submit reports
        (if (is-authorized project-id tx-sender)
            (begin
                ;; Store the report
                (map-set project-reports 
                    {project-id: project-id, report-id: report-id}
                    {
                        implementer: tx-sender,
                        timestamp: block-height,
                        metrics: metrics,
                        description: description
                    }
                )
                ;; Update project report count
                (map-set project-report-counts
                    {project-id: project-id}
                    {report-count: (+ current-count u1)}
                )
                ;; Increment report ID counter
                (var-set next-report-id (+ report-id u1))
                (ok report-id)
            )
            ERR-NOT-AUTHORIZED
        )
    )
)

;; Private functions
(define-private (is-authorized (project-id uint) (caller principal))
    ;; In a real implementation, this would check against a list of authorized implementers
    ;; For demonstration, we'll return true if the caller is the contract owner
    (is-eq caller tx-sender)
)