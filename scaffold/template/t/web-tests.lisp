;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:app.tests)

(defun response-status (response) (first response))
(defun response-headers (response) (second response))
(defun response-body (response) (first (third response)))
(defun header-value (response key)
  (loop for rest on (response-headers response) by #'cddr
        when (string-equal (string key) (string (first rest))) return (second rest)))

(test home-page-renders-contract
  (let ((response (app.web::home-handler nil)))
    (is (= 200 (response-status response)))
    (is (search "Common Lisp Web App" (response-body response)))
    (is (search "/health" (response-body response)))
    (is (search "/version" (response-body response)))
    (is (string= "text/html; charset=utf-8" (header-value response :content-type)))
    (is (string= "DENY" (header-value response :x-frame-options)))))

(test operational-routes-are-plain-text
  (let ((health (app.web::health-handler nil))
        (version (app.web::version-handler nil)))
    (is (= 200 (response-status health)))
    (is (string= "ok\n" (response-body health)))
    (is (= 200 (response-status version)))
    (is (plusp (length (response-body version))))))
