;;;
;;; libcmp.scm - compare and sort
;;;
;;;   Copyright (c) 2000-2014  Shiro Kawai  <shiro@acm.org>
;;;
;;;   Redistribution and use in source and binary forms, with or without
;;;   modification, are permitted provided that the following conditions
;;;   are met:
;;;
;;;   1. Redistributions of source code must retain the above copyright
;;;      notice, this list of conditions and the following disclaimer.
;;;
;;;   2. Redistributions in binary form must reproduce the above copyright
;;;      notice, this list of conditions and the following disclaimer in the
;;;      documentation and/or other materials provided with the distribution.
;;;
;;;   3. Neither the name of the authors nor the names of its contributors
;;;      may be used to endorse or promote products derived from this
;;;      software without specific prior written permission.
;;;
;;;   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;;;   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;;;   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;;;   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;;;   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;;;   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
;;;   TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
;;;   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
;;;   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;;   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;;   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;;

(select-module gauche.internal)

;;;
;;; Comparator (a la srfi-114)
;;;

(select-module gauche.internal)
(define (default-type-test _) #t)

(define-cproc %make-comparator (type-test equality-test comparison-proc hash
                                name no-compare::<boolean> no-hash::<boolean>
                                any-type::<boolean>)
  (let* ([flags::u_long (logior (?: no-compare SCM_COMPARATOR_NO_ORDER 0)
                                (?: no-hash SCM_COMPARATOR_NO_HASH 0)
                                (?: any-type SCM_COMPARATOR_ANY_TYPE 0))])
    (result
     (Scm_MakeComparator type-test equality-test comparison-proc hash
                         name flags))))

(define-in-module gauche (make-comparator type-test equality-test
                                          comparison-proc hash
                                          :optional (name #f))
  (rec self  ; referred by error proc
    ;; We use <bottom> for applicability check except type-test, since
    ;; those procs are only required to handle objects that passes type-test.
    (let ([type (cond [(eq? type-test #t) default-type-test]
                      [(applicable? type-test <top>) type-test]
                      [else (error "make-comparator needs a one-argument procedure or #t as type-test, but got:" type-test)])]
          [eq   (cond
                 [(eq? equality-test #t)
                  (if (applicable? comparison-proc <bottom> <bottom>)
                    (^[a b] (= (comparison-proc a b) 0))
                    (error "make-comparator needs a procedure as comparison-proc if equality-test is #t, but got:" comparison-proc))]
                 [(applicable? equality-test <bottom> <bottom>) equality-test]
                 [else (error "make-comparator needs a procedure or #t as equality-test, but got:" equality-test)])]
          [cmp  (cond [(eq? comparison-proc #f)
                       (^[a b] (errorf "can't compare objects by ~s: ~s vs ~s" self a b))]
                      [(applicable? comparison-proc <bottom> <bottom>)
                       comparison-proc]
                      [else (error "make-comparator needs a procedure or #f as comparison-proc, but got:" comparison-proc)])]
          [hsh  (cond [(eq? hash #f)
                       (^[a] (errorf "~s doesn't have a hash function"))]
                      [(applicable? hash <bottom>) hash]
                      [else (error "make-comparator needs a procedure or #f as hash, but got:" hash)])])
      (%make-comparator type eq cmp hsh name
                        (not comparison-proc) (not hash)
                        (eq? type default-type-test)))))
    

(select-module gauche)
(define-cproc comparator? (obj) ::<boolean> SCM_COMPARATORP)
(define-cproc comparator-comparison-procedure? (c::<comparator>) ::<boolean>
  (result (not (logand (-> c flags) SCM_COMPARATOR_NO_ORDER))))
(define-cproc comparator-hash-function? (c::<comparator>) ::<boolean>
  (result (not (logand (-> c flags) SCM_COMPARATOR_NO_HASH))))

(define-cproc comparator-type-test-procedure (c::<comparator>) :constant
  (result (-> c typeFn)))
(define-cproc comparator-equality-predicate (c::<comparator>) :constant
  (result (-> c eqFn)))
(define-cproc comparator-comparison-procedure (c::<comparator>) :constant
  (result (-> c compareFn)))
(define-cproc comparator-hash-function (c::<comparator>) :constant
  (result (-> c hashFn)))

;; We implement these in C for performance.
;; TODO: We might be able to do shortcut in comparator-equal? by recognizing
;; the equality predicate to be eq? or eqv?.
(define-cproc comparator-test-type (c::<comparator> obj) :constant
  (if (logand (-> c flags) SCM_COMPARATOR_ANY_TYPE)
    (result SCM_TRUE)
    (result (Scm_VMApply1 (-> c typeFn) obj))))

(inline-stub
 (define-cfn comparator-check-type-cc (result data::void**) :static
   (when (SCM_FALSEP result)
     (let* ([c   (SCM_OBJ (aref data 0))]
            [obj (SCM_OBJ (aref data 1))])
       (Scm_Error "Comparator %S cannot accept object %S" c obj)))
   (return SCM_TRUE))
 )

(define-cproc comparator-check-type (c::<comparator> obj) :constant
  (if (logand (-> c flags) SCM_COMPARATOR_ANY_TYPE)
    (result SCM_TRUE)
    (let* ([data::(.array void* (2))])
      (set! (aref data 0) c)
      (set! (aref data 1) obj)
      (Scm_VMPushCC comparator-check-type-cc data 2)
      (result (Scm_VMApply1 (-> c typeFn) obj)))))

(define-cproc comparator-equal? (c::<comparator> a b) :constant
  (result (Scm_VMApply2 (-> c eqFn) a b)))

(define-cproc comparator-compare (c::<comparator> a b) :constant
  (result (Scm_VMApply2 (-> c compareFn) a b)))

(define-cproc comparator-hash (c::<comparator> x) :constant
  (result (Scm_VMApply1 (-> c hashFn) x)))

;;;
;;; Generic comparison
;;;

(select-module gauche)
;; returns -1, 0 or 1
(define-cproc compare (x y) ::<fixnum> Scm_Compare)

;; eq-compare has two properties:
;;  Gives a total order to every Scheme object (within a single run of process)
;;  Returns 0 iff (eq? x y) => #t
(define-cproc eq-compare (x y) ::<fixnum>
  (if (SCM_EQ x y)
    (result 0)
    (result (?: (< (SCM_WORD x) (SCM_WORD y)) -1 1))))

;;;
;;; Sorting
;;;

;; The public API for sorting is in lib/gauche/sortutil.scm and
;; will be autoloaded.  We provide a C-implemented low-level routines.
(select-module gauche.internal)

(define-cproc %sort (seq)
  (cond [(SCM_VECTORP seq)
         (let* ([r (Scm_VectorCopy (SCM_VECTOR seq) 0 -1 SCM_UNDEFINED)])
           (Scm_SortArray (SCM_VECTOR_ELEMENTS r) (SCM_VECTOR_SIZE r) '#f)
           (result r))]
        [(>= (Scm_Length seq) 0) (result (Scm_SortList seq '#f))]
        [else (SCM_TYPE_ERROR seq "proper list or vector")
              (result SCM_UNDEFINED)]))

(define-cproc %sort! (seq)
  (cond [(SCM_VECTORP seq)
         (Scm_SortArray (SCM_VECTOR_ELEMENTS seq) (SCM_VECTOR_SIZE seq) '#f)
         (result seq)]
        [(>= (Scm_Length seq) 0) (result (Scm_SortListX seq '#f))]
        [else (SCM_TYPE_ERROR seq "proper list or vector")
              (result SCM_UNDEFINED)]))

