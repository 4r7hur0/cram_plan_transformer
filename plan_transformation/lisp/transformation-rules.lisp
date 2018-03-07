;;;
;;; Copyright (c) 2017, Arthur Niedzwiecki <niedzwiecki@uni-bremen.de>
;;;                     Gayane Kazhoyan <kazhoyan@cs.uni-bremen.de>
;;; All rights reserved.
;;;
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;;
;;;     * Redistributions of source code must retain the above copyright
;;;       notice, this list of conditions and the following disclaimer.
;;;     * Redistributions in binary form must reproduce the above copyright
;;;       notice, this list of conditions and the following disclaimer in the
;;;       documentation and/or other materials provided with the distribution.
;;;     * Neither the name of the Intelligent Autonomous Systems Group/
;;;       Technische Universitaet Muenchen nor the names of its contributors
;;;       may be used to endorse or promote products derived from this software
;;;       without specific prior written permission.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.

(in-package :plt)

(defun check-rules (&optional (top-level-name :top-level))
  (let (;; (both-hands-rule-bindings)
        (stacking-rule-bindings)
        ;; (environment-rule-bindings)
        )
    (format T "Checking for applicable rules.~%")
    
    ;; (when (setf both-hands-rule-bindings
    ;;             (prolog '(task-transporting-siblings
    ;;                       :top-level ((demo-stacking)) ?path-1 ?path-2
    ;;                       ?fetch-desig ?deliver-desig)))
    ;;   (format T "Function ~a is applicable!~%" #'both-hands-transporting-rule)
    ;;   (both-hands-transporting-rule (cut:lazy-car both-hands-rule-bindings)
    ;;                                 top-level-name))
    (when (setf stacking-rule-bindings
                (prolog '(task-transporting-with-tray
                          :top-level ((demo-stacking)) 0.5
                          ?path-1 ?path-2
                          ?fetch-1 ?deliver-1
                          ?fetch-2 ?deliver-2)))
      (format T "Function ~a is applicable!~%" #'stacking-rule)
      (stacking-rule (cut:lazy-car stacking-rule-bindings)
                     top-level-name))))

(defun both-hands-transporting-rule (bindings &optional (top-level-name :top-level))
  (cut:with-vars-bound
      (?path-1 ?path-2 ?fetch-desig ?deliver-desig)
      bindings
    (cpl-impl::replace-task-code '(BOTH-HANDS-TRANSFORM-1)
                                 #'(lambda (&rest desig)
                                     (declare (ignore desig))
                                     (exe:perform ?fetch-desig))
                                 ?path-1
                                 (cpl-impl::get-top-level-task-tree top-level-name))
    (cpl-impl::replace-task-code '(BOTH-HANDS-TRANSFORM-2)
                                 #'(lambda (&rest desig)
                                     (exe:perform (car desig))
                                     (exe:perform ?deliver-desig))
                                 ?path-2
                                 (cpl-impl::get-top-level-task-tree top-level-name))))

(defun stacking-rule (bindings &optional (top-level-name :top-level))
  (cut:with-vars-bound
      (?path-1 ?path-2 ?fetch-1 ?deliver-1 ?fetch-2 ?deliver-2)
      bindings
      (let* ((tray-poses '(((1.34 0.0 1.0)
                            ;;(0 0 1 0)
                            (0 0 0.7071 0.7071))
                           ((1.34 0.1 0.96)
                            (0 0 1 0))
                           ((1.34 0.0 0.96)
                            (0 0 1 0))))
             (tray-action (tray-transporting-action)))
        
        (labels ((change-loc-to-tray (action-desig)
                   (let ((?tray-pose (cl-transforms-stamped:pose->pose-stamped
                                      "map" 0.0
                                      (btr:ensure-pose (pop tray-poses))))
                         (?desig-cpy (desig:description (desig:copy-designator action-desig))))
                     (setf ?desig-cpy (remove (assoc :arm ?desig-cpy)
                                       (remove (assoc :target ?desig-cpy) ?desig-cpy)))
                     (push `(:target ,(desig:a location
                                               (pose ?tray-pose))) ?desig-cpy)
                     (push `(:target :left) ?desig-cpy)
                     (desig:make-designator :action ?desig-cpy)))
                 (btr-obj (name)
                   (btr:object btr:*current-bullet-world* name)))

          (let* ((deliver-1 (change-loc-to-tray ?deliver-1))
                 (deliver-2 (change-loc-to-tray ?deliver-2))
                 (name-1 (desig:desig-prop-value
                          (desig:desig-prop-value ?deliver-1 :object) :name))
                 (name-2 (desig:desig-prop-value
                          (desig:desig-prop-value ?deliver-2 :object) :name)))

            (flet ((trans-fun (&rest desig)
                     (declare (ignore desig))
                     (exe:perform ?fetch-1)
                     (exe:perform deliver-1)
                     (btr::attach-item name-1 (btr-obj :tray-1))
                     (exe:perform ?fetch-2)
                     (exe:perform deliver-2)
                     (btr::attach-item name-2 (btr-obj :tray-1))
                     (exe:perform tray-action)
                     (btr::detach-all-items (btr-obj :tray-1))))

              (cpl-impl::replace-task-code '(STACKING-TRANSFORM-1)
                                           #'trans-fun
                                           ?path-1
                                           (cpl-impl::get-top-level-task-tree top-level-name))

              (cpl-impl::replace-task-code '(STACKING-TRANSFORM-2)
                                           #'(lambda (&rest desig)
                                               (declare (ignore desig)))
                                           ?path-2
                                           (cpl-impl::get-top-level-task-tree top-level-name))))))))

(defun environment-rule (bindings &optional (top-level-name :top-level))
  (let* ((last-action (pop bindings))
         (bindings (reverse bindings))
         (first-action (pop bindings)))
    (flet ((close-nothing (&rest desig) 
             (declare (ignore desig))
             (setf pr2-proj-reasoning::*allow-pick-up-kitchen-collision* NIL))
           (open-nothing (navigation-action) 
             (exe:perform navigation-action)
             (setf pr2-proj-reasoning::*allow-pick-up-kitchen-collision* T)))

    (destructuring-bind (x y closing-path) first-action
      (declare (ignore x y))
      (cpl-impl::replace-task-code '(CONTAINER-FIRST-CLOSING-TRANSFORM)
                                   #'close-nothing
                                   closing-path
                                   (cpl-impl::get-top-level-task-tree top-level-name)))

    (destructuring-bind (navigation-action opening-path x) last-action
      (declare (ignore x))
      (cpl-impl::replace-task-code '(CONTAINER-LAST-OPENING-TRANSFORM)
                                   #'(lambda (&rest desig)
                                       (declare (ignore desig))
                                       (open-nothing navigation-action))
                                   opening-path
                                   (cpl-impl::get-top-level-task-tree top-level-name)))

    (loop for (navigation-action opening-path closing-path) in bindings
          do (cpl-impl::replace-task-code `(,(intern (format nil "CONTAINER-ACCESS-TRANSFORM-~a" 1)))
                                 #'close-nothing
                                 closing-path
                                 (cpl-impl::get-top-level-task-tree top-level-name))
             (cpl-impl::replace-task-code `(,(intern (format nil "CONTAINER-CLOSE-TRANSFORM-~a" 1)))
                                 #'(lambda (&rest desig)
                                     (declare (ignore desig))
                                     (open-nothing navigation-action))
                                 opening-path
                                 (cpl-impl::get-top-level-task-tree top-level-name))))))

;; (defun environment-rule (&optional (top-level-name :top-level))
;;   (let* ((matching-pairs (tasks-with-nearby-location top-level-name :transporting-from-container))
;;          (tasks (mapcar (alexandria:rcurry #'alexandria:assoc-value '?task) (car matching-pairs)))
;;          (paths (mapcar #'cpl:task-tree-node-path tasks))
;;          (first-closing-path (cpl:task-tree-node-path
;;                               (alexandria:assoc-value
;;                                (cut:lazy-car
;;                                 (prolog:prolog `(task-specific-action ,top-level-name
;;                                                                       ,(car (last paths))
;;                                                                       :closing-container
;;                                                                       ?task ?_))) '?task)))
;;          (last-opening (cut:lazy-car
;;                         (prolog:prolog `(task-specific-action ,top-level-name
;;                                                               ,(car paths)
;;                                                               :accessing-container
;;                                                               ?task ?desig))))
;;          (last-opening-path (cpl:task-tree-node-path (alexandria:assoc-value last-opening '?task)))
;;          (last-opening-action (alexandria:assoc-value last-opening '?desig))
;;          (?opening-location (desig:desig-prop-value last-opening-action :location)))
    

;;     ;; dont close the door, just enable collisions
;;     (cpl-impl::replace-task-code '(CONTAINER-FIRST-CLOSING-TRANSFORM)
;;                                  #'(lambda (&rest desig)
;;                                      (declare (ignore desig))
;;                                      (setf pr2-proj-reasoning::*allow-pick-up-kitchen-collision* NIL))
;;                                  first-closing-path
;;                                  (cpl-impl::get-top-level-task-tree top-level-name))

;;     ;; dont open, just navigate and disable collisions
;;     (cpl-impl::replace-task-code '(CONTAINER-LAST-OPENING-TRANSFORM)
;;                                  #'(lambda (&rest desig)
;;                                      (declare (ignore desig))
;;                                      (exe:perform
;;                                       (desig:an action
;;                                                 (type navigating)
;;                                                 (location ?opening-location)))
;;                                      (setf pr2-proj-reasoning::*allow-pick-up-kitchen-collision* T))
;;                                  last-opening-path
;;                                  (cpl-impl::get-top-level-task-tree top-level-name))

;;    first-closing-path ))
