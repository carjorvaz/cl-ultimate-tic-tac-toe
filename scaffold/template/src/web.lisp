;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:app.web)

(defparameter *server* nil)
(defparameter *server-port* nil)
(defparameter *html-content-type* "text/html; charset=utf-8")
(defparameter *plain-text-content-type* "text/plain; charset=utf-8")
(defparameter *source-code-url* "https://example.com/source")
(defparameter *static-assets*
  '(("/style.css" "static/style.css" "text/css; charset=utf-8")
    ("/app.js" "static/app.js" "application/javascript; charset=utf-8")
    ("/htmx.min.js" "static/htmx.min.js" "application/javascript; charset=utf-8")))
(defparameter *security-headers*
  (list :x-content-type-options "nosniff"
        :x-frame-options "DENY"
        :referrer-policy "same-origin"
        :permissions-policy "camera=(), microphone=(), geolocation=()"
        :content-security-policy
        "default-src 'self'; base-uri 'none'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; img-src 'self'; object-src 'none'; script-src 'self'; style-src 'self'"))

(defun configured-source-code-url ()
  (or (uiop:getenv "SOURCE_CODE_URL") *source-code-url*))
(defun configured-version ()
  (or (uiop:getenv "APP_VERSION") "dev"))
(defun system-path (relative-path)
  (merge-pathnames relative-path (asdf:system-source-directory :app)))
(defun header-key-name (key)
  (etypecase key (keyword (string-downcase (symbol-name key))) (string (string-downcase key))))
(defun header-present-p (headers key)
  (loop for rest on headers by #'cddr for name = (first rest)
        thereis (string= (header-key-name name) (header-key-name key))))
(defun missing-default-headers (headers defaults)
  (loop for (name value) on defaults by #'cddr unless (header-present-p headers name) append (list name value)))
(defun response-headers (&key content-type headers)
  (let ((explicit (append (when content-type (list :content-type content-type)) headers)))
    (append explicit (missing-default-headers explicit *security-headers*))))
(defun clack-response (status body &key content-type headers)
  (list status (response-headers :content-type content-type :headers headers) (list body)))
(defun response-with-default-headers (response)
  (destructuring-bind (status headers &optional (body nil body-p)) response
    (let ((headers (append headers (missing-default-headers headers *security-headers*))))
      (if body-p (list status headers body) (list status headers)))))
(defun wrap-default-headers (app)
  (lambda (env) (response-with-default-headers (funcall app env))))
(defun html-response (body)
  (clack-response 200 body :content-type *html-content-type*))
(defun not-found-response ()
  (clack-response 404 "Not found" :content-type *plain-text-content-type*))
(defun asset-response (relative-path content-type)
  (let ((path (system-path relative-path)))
    (if (probe-file path)
        (clack-response 200 (uiop:read-file-string path) :content-type content-type
                        :headers (list :cache-control "public, max-age=3600"))
        (not-found-response))))

(defun render-page ()
  (spinneret:with-html-string
    (:doctype)
    (:html :lang "en"
      (:head
        (:meta :charset "utf-8")
        (:meta :name "viewport" :content "width=device-width, initial-scale=1")
        (:title (app-title))
        (:link :rel "stylesheet" :href "/style.css")
        (:script :src "/htmx.min.js" :defer t)
        (:script :src "/app.js" :defer t))
      (:body
        (:main :class "app"
          (:section :class "shell" :aria-labelledby "app-title"
            (:p :class "visually-hidden" "Server-rendered Common Lisp scaffold")
            (:h1 :id "app-title" (app-title))
            (:p (app-summary))
            (:ul (dolist (line (status-lines)) (:li line)))
            (:nav :class "actions" :aria-label "Application links"
              (:a :href "/health" "Health")
              (:a :href "/version" "Version")
              (:a :href (configured-source-code-url) "Source"))))))))

(defun home-handler (params) (declare (ignore params)) (html-response (render-page)))
(defun health-handler (params) (declare (ignore params)) (clack-response 200 (format nil "ok~%") :content-type *plain-text-content-type*))
(defun version-handler (params) (declare (ignore params)) (clack-response 200 (format nil "~A~%" (configured-version)) :content-type *plain-text-content-type*))
(defun make-asset-handler (relative-path content-type)
  (lambda (params) (declare (ignore params)) (asset-response relative-path content-type)))
(defun install-route (app method path handler)
  (setf (ningle:route app path :method method) handler) app)
(defun make-routes ()
  (let ((app (make-instance 'ningle:app)))
    (install-route app :get "/" #'home-handler)
    (install-route app :get "/health" #'health-handler)
    (install-route app :get "/version" #'version-handler)
    (dolist (asset *static-assets* app)
      (destructuring-bind (path relative-path content-type) asset
        (install-route app :get path (make-asset-handler relative-path content-type))))))
(defun make-app ()
  (wrap-default-headers (lack:builder (make-routes))))
(defun start (&key (port 4242) (server :woo) (debug nil) silent)
  (stop)
  (setf *server* (clack:clackup (make-app) :server server :port port :debug debug :silent silent :use-default-middlewares nil :persistent-connections-p nil)
        *server-port* port)
  *server*)
(defun stop ()
  (when *server* (clack:stop *server*) (setf *server* nil *server-port* nil))
  nil)
(defun server-port () *server-port*)
