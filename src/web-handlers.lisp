;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.web)

(defun room-rejection-notice (rejection)
  (ecase (room-rejected-reason rejection)
    (:room-not-found "That room was not found.")
    (:invalid-seat "That seat was not understood.")
    (:missing-token "Reload the room and try again.")
    (:already-seated "This browser is already seated in the room.")
    (:seat-occupied "That seat is already taken.")
    (:watcher "Watchers cannot play moves.")
    (:stale-revision "The room changed. Review the latest board and try again.")
    (:wrong-turn "It is not your turn.")
    ((:invalid-board :invalid-cell) "That move was not understood.")
    (:game-over "The game is already over.")
    (:closed-board "That board is already complete.")
    (:wrong-board "That move belongs in the target board.")
    (:occupied-cell "That square is no longer available.")))

(defun room-view-for-request (code)
  (view-room *room-repository* code (room-session-token code)))

(defun room-post-response (code view &key notice)
  (if (htmx-request-p)
      (html-response (render-room-htmx-response view :notice notice))
      (progn
        (remember-room-notice code notice)
        (redirect-response (room-path code)))))

(defun room-mutation-response (code view acceptedp rejection)
  (cond
    ((null view)
     (not-found-response))
    (acceptedp
     (room-post-response code view))
    (t
     (room-post-response code
                         view
                         :notice (room-rejection-notice rejection)))))

(defun respond-after-post (game &key notice)
  (if (htmx-request-p)
      (html-response (render-htmx-response game :notice notice))
      (progn
        (remember-notice notice)
        (redirect-response "/"))))

(defun move-rejection-notice (rejection)
  (ecase (move-rejected-reason rejection)
    ((:invalid-board :invalid-cell)
     "That move was not understood.")
    (:game-over
     "The game is already over.")
    (:closed-board
     "That board is already complete.")
    (:wrong-board
     "That move belongs in the target board.")
    (:occupied-cell
     "That square is no longer available.")))

(defun computer-turn-p (game)
  (and (not (game-over-p game))
       (eql (session-computer-player)
            (game-next-player game))))

(defun maybe-play-computer-turn (game)
  (when (computer-turn-p game)
    (ecase (session-opponent-mode)
      (:easy (play-first-legal-move game))
      (:normal (play-best-tactical-move game))
      (:hard (play-best-strategic-move game))))
  game)

(defun malformed-room-move-response (code)
  (multiple-value-bind (view foundp)
      (room-view-for-request code)
    (if foundp
        (room-post-response code view
                            :notice "That move was not understood.")
        (not-found-response))))

(defun write-sse-data-lines (stream data)
  (loop with start = 0
        for end = (position #\Newline data :start start)
        do (format stream "data: ~A~%" (subseq data start end))
        if end
          do (setf start (1+ end))
        else
          do (return)))

(defun room-update-event (view request-env)
  (let ((*request-env* request-env))
    (with-output-to-string (stream)
      (format stream "id: ~D~%" (room-view-revision view))
      (format stream "retry: ~D~%" *room-event-retry-milliseconds*)
      (format stream "event: ~A~%" *room-update-event-name*)
      (write-sse-data-lines stream (render-room-game-fragment view))
      (terpri stream))))

(defun room-update-event-needed-p (view request-env)
  (let ((last-event-id (request-last-event-id request-env)))
    (or (null last-event-id)
        (< last-event-id (room-view-revision view)))))

(defun room-event-stream-response (view request-env)
  (lambda (respond)
    (let ((writer
            (funcall respond
                     (list 200
                           (response-headers
                            :content-type *event-stream-content-type*
                            :headers (list :cache-control "no-store"
                                           :x-accel-buffering "no"))))))
      (funcall writer
               (when (room-update-event-needed-p view request-env)
                 (room-update-event view request-env))
               :close t))))

(defun room-events-handler (params)
  (let ((code (request-room-code params)))
    (multiple-value-bind (view foundp)
        (and code (room-view-for-request code))
      (if foundp
          (room-event-stream-response view *request-env*)
          (not-found-response)))))

(defun room-page-handler (params)
  (let ((code (request-room-code params)))
    (multiple-value-bind (view foundp)
        (and code (room-view-for-request code))
      (if foundp
          (html-response
           (render-room-page view :notice (pop-room-notice code)))
          (not-found-response)))))

(defun room-game-handler (params)
  (let ((code (request-room-code params)))
    (multiple-value-bind (view foundp)
        (and code (room-view-for-request code))
      (if foundp
          (html-response (render-room-game-fragment view))
          (not-found-response)))))

(defun rooms-handler (params)
  (with-valid-csrf (params)
    (let ((view (create-room *room-repository*)))
      (redirect-response (room-path (room-view-code view))))))

(defun room-seat-handler (params)
  (with-valid-csrf (params)
    (let* ((code (request-room-code params))
           (mark (parse-player-mark (route-parameter params :mark))))
      (if code
          (multiple-value-call #'room-mutation-response
            code
            (claim-seat *room-repository*
                        code
                        mark
                        (ensure-room-session-token code)))
          (not-found-response)))))

(defun room-move-handler (params)
  (with-valid-csrf (params)
    (let* ((code (request-room-code params))
           (board-index (parse-index (form-parameter params "board")))
           (cell-index (parse-index (form-parameter params "cell")))
           (revision (parse-room-revision (form-parameter params "revision"))))
      (cond
        ((null code)
         (not-found-response))
        ((not (and board-index cell-index revision))
         (malformed-room-move-response code))
        (t
         (multiple-value-call #'room-mutation-response
           code
           (play-room-move *room-repository*
                           code
                           (room-session-token code)
                           revision
                           board-index
                           cell-index)))))))

(defun home-handler (params)
  (declare (ignore params))
  (with-current-game-locked ()
    (multiple-value-bind (game recoveredp)
        (current-game)
      (let ((notice (pop-notice)))
        (setf game (maybe-play-computer-turn game))
        (html-response
         (render-page game
                      :notice (if recoveredp
                                  *recovered-game-notice*
                                  notice)))))))

(defun current-game-handler (params)
  (declare (ignore params))
  (with-current-game-locked ()
    (multiple-value-bind (game recoveredp)
        (current-game)
      (setf game (maybe-play-computer-turn game))
      (html-response
       (if (htmx-request-p)
           (render-htmx-response
            game
            :notice (and recoveredp *recovered-game-notice*))
           (render-page
            game
            :notice (and recoveredp *recovered-game-notice*)))))))

(defun legal-notices-handler (params)
  (declare (ignore params))
  (html-response (render-legal-notices-page)))

(defun health-handler (params)
  (declare (ignore params))
  (clack-response 200
                  (format nil "ok~%")
                  :content-type *plain-text-content-type*
                  :headers (list :cache-control "no-store")))

(defun version-handler (params)
  (declare (ignore params))
  (clack-response 200
                  (format nil "ultimate-tic-tac-toe ~A~%" (app-version))
                  :content-type *plain-text-content-type*
                  :headers (list :cache-control "no-store")))

(defun respond-to-local-move (game board-index cell-index)
  (if (and board-index cell-index)
      (multiple-value-bind (updated-game acceptedp rejection)
          (play-move game board-index cell-index)
        (declare (ignore updated-game))
        (when acceptedp
          (maybe-play-computer-turn game))
        (respond-after-post game
                            :notice (unless acceptedp
                                      (move-rejection-notice rejection))))
      (respond-after-post game
                          :notice "That move was not understood.")))

(defun move-handler (params)
  (with-valid-csrf (params)
    (with-current-game-locked ()
      (multiple-value-bind (game recoveredp)
          (current-game)
        (let ((board-index (parse-index (form-parameter params "board")))
              (cell-index (parse-index (form-parameter params "cell"))))
          (if recoveredp
              (respond-after-post
               (maybe-play-computer-turn game)
               :notice *recovered-game-notice*)
              (respond-to-local-move game board-index cell-index)))))))

(defun games-handler (params)
  (with-valid-csrf (params)
    (with-current-game-locked ()
      (let ((first-mark (parse-player-mark
                         (form-parameter params "first-player"))))
        (when (form-submitted-p params "player-x" "player-o" "first-player"
                                "opponent")
          (remember-player-settings (form-parameter params "player-x")
                                    (form-parameter params "player-o")
                                    first-mark
                                    (form-parameter params "opponent")))
        (respond-after-post
         (maybe-play-computer-turn
          (replace-current-game :first-player first-mark)))))))

(defun make-asset-handler (relative-path content-type)
  (lambda (params)
    (declare (ignore params))
    (asset-response relative-path content-type)))

(defun install-route (app method path handler)
  (setf (ningle:route app path :method method) handler)
  app)

(defun install-routes (app routes)
  (dolist (route routes app)
    (destructuring-bind (method path handler) route
      (install-route app method path handler))))

(defun install-static-asset-routes (app)
  (dolist (asset *static-assets* app)
    (destructuring-bind (path relative-path content-type) asset
      (install-route app :get path
                     (make-asset-handler relative-path content-type)))))

(defun make-routes ()
  (let ((app (make-instance 'ningle:app)))
    (install-routes
     app
     (list (list :get "/" #'home-handler)
           (list :get *legal-notices-path* #'legal-notices-handler)
           (list :get *health-path* #'health-handler)
           (list :get *version-path* #'version-handler)
           (list :get *current-game-path* #'current-game-handler)
           (list :post *rooms-path* #'rooms-handler)
           (list :get "/rooms/:code/events" #'room-events-handler)
           (list :get "/rooms/:code/game" #'room-game-handler)
           (list :get "/rooms/:code" #'room-page-handler)
           (list :post "/rooms/:code/seats/:mark" #'room-seat-handler)
           (list :post "/rooms/:code/moves" #'room-move-handler)
           (list :post *games-path* #'games-handler)
           (list :post *current-game-moves-path* #'move-handler)
           (list :post "/move" #'move-handler)
           (list :post "/players" #'games-handler)
           (list :post "/reset" #'games-handler)))
    (install-static-asset-routes app)
    app))

(defun make-app ()
  (wrap-default-headers
   (lack:builder
     (configured-session-middleware)
     (configured-session-cleanup-middleware)
     #'wrap-request-env
     (make-routes))))

(defun clack-hunchentoot-symbol (name)
  (let ((package (find-package *clack-hunchentoot-package-name*)))
    (or (and package (find-symbol name package))
        (error "Could not find ~A in ~A." name *clack-hunchentoot-package-name*))))

;; Clack's exported Hunchentoot runner blocks and owns shutdown. The test
;; lifecycle keeps Hunchentoot's acceptor directly so failures are synchronous
;; and shutdown is clean; keep the private adapter names quarantined here.
(defun initialize-clack-hunchentoot ()
  (funcall (symbol-function (clack-hunchentoot-symbol "INITIALIZE"))))

(defun make-clack-hunchentoot-acceptor (port debug)
  (make-instance (clack-hunchentoot-symbol "CLACK-ACCEPTOR")
                 :app (make-app)
                 :address "127.0.0.1"
                 :port port
                 :debug debug
                 :access-log-destination nil
                 :error-template-directory nil
                 :persistent-connections-p nil))

(defun start-hunchentoot (port debug)
  (initialize-clack-hunchentoot)
  (hunchentoot:start (make-clack-hunchentoot-acceptor port debug)))

(defun start (&key (port 4242) (server :woo) (debug nil) silent
              (room-db (configured-room-database-path)))
  (stop)
  (let ((room-db (normalized-room-database-path room-db)))
    (setf *room-database-path* room-db
          *room-repository* (configured-room-repository room-db)))
  (setf *server*
        (if (eql server :hunchentoot)
            (start-hunchentoot port debug)
            (clack:clackup (make-app)
                           :server server
                           :port port
                           :debug debug
                           :silent silent
                           :use-default-middlewares nil
                           :persistent-connections-p nil))
        *server-port* port)
  *server*)

(defun stop ()
  (when *server*
    (if (typep *server* 'hunchentoot:acceptor)
        (hunchentoot:stop *server*)
        (clack:stop *server*))
    (setf *server* nil
          *server-port* nil))
  nil)

(defun server-port ()
  *server-port*)
