;; testing data.*

;; data.* depends on quite a few modules, so we run this after
;; tests of extension modules are done.

(use gauche.test)
(test-start "data.* modules")

(test-section "data.random")
(use data.random)
(test-module 'data.random)

;; depends on data.random
(test-section "data.heap")
(use data.heap)
(test-module 'data.heap)

(use srfi-1)
(use srfi-27)
(use gauche.sequence)
(use util.match)

(let ((rs (make-random-source)))
  (define (do-test data comparator) ; data must be sorted
    (define len (length data))
    (define heap (make-binary-heap :storage (make-vector len)
                                   :comparator comparator))
    (let1 input (shuffle data rs)
      (test* (format "heap(~s) insertion ~s" len input)
             (map-with-index (^[i e] (list i e #t #t)) input)
             (let ([zmin #f]
                   [zmax #f])
               (map-with-index
                (^[i e]
                  (begin
                    (binary-heap-push! heap e)
                    (binary-heap-check heap)
                    (when (or (not zmin)
                              (< (comparator-compare comparator e zmin) 0))
                      (set! zmin e))
                    (when (or (not zmax)
                              (> (comparator-compare comparator e zmax) 0))
                      (set! zmax e))
                    (list i e
                          (equal? (binary-heap-find-min heap) zmin)
                          (equal? (binary-heap-find-max heap) zmax))))
                input))))
    (let1 hp1 (binary-heap-copy heap)
      (test* (format "heap(~s) clear" len) #t
             (begin
               (binary-heap-clear! hp1)
               (binary-heap-empty? hp1))))
    (let1 hp1 (binary-heap-copy heap)
      (test* (format "heap(~s) deletion from min" len)
             data
             (map-in-order (^_ (begin0 (binary-heap-pop-min! hp1)
                                 (binary-heap-check hp1)))
                           (iota len))))
    (let1 hp1 (binary-heap-copy heap)
      (test* (format "heap(~s) deletion from max" len)
             (reverse data)
             (map-in-order (^_ (begin0 (binary-heap-pop-max! hp1)
                                 (binary-heap-check hp1)))
                           (iota len))))
    (let1 hp1 (binary-heap-copy heap)
      (test* (format "heap(~s) deletion mixed" len)
             (map list
                  (take data (quotient len 2))
                  (take (reverse data) (quotient len 2)))
             (map-in-order (^_ (let* ([x (binary-heap-pop-min! hp1)]
                                      [y (binary-heap-pop-max! hp1)])
                                 (binary-heap-check hp1)
                                 (list x y)))
                           (iota (quotient len 2)))))
    )
  
  (do-test (iota 15) default-comparator)
  (do-test (iota 253) default-comparator)
  (do-test (reverse (iota 33))
           (make-comparator number? #t (^[a b] (- (compare a b))) #f))
  (do-test '(#\a #\b #\c #\d #\e) default-comparator)
  )

(let ((rs (make-random-source)))
  (define (suck-all heap)
    (do ([r '() (cons (binary-heap-pop-min! heap) r)])
        [(binary-heap-empty? heap) (reverse r)]
      ))
  (define (do-heapify lis builder comparator)
    (test* (format "heapify ~s" lis)
           lis
           (let* ([src  (builder (shuffle lis rs))]
                  [heap (build-binary-heap src :comparator comparator)])
             (binary-heap-check heap)
             (suck-all heap))))
  (define (do-scan lis pred item)
    (test* (format "find, remove, delete ~s" lis)
           (list (boolean (find pred lis))
                 (remove pred lis)
                 (delete item lis))
           (let ([heap (build-binary-heap (list->vector (shuffle lis rs)))])
             (list (if-let1 r (binary-heap-find heap pred)
                     (pred r)
                     #f)
                   (let1 h (binary-heap-copy heap)
                     (binary-heap-remove! h pred)
                     (binary-heap-check h)
                     (suck-all h))
                   (let1 h (binary-heap-copy heap)
                     (binary-heap-delete! h item)
                     (binary-heap-check h)
                     (suck-all h))))))

  (do-heapify '() list->vector default-comparator)
  (do-heapify '(1) list->vector default-comparator)
  (do-heapify (iota 33) list->vector default-comparator)
  (do-heapify '("a" "aa" "b" "bb" "c" "cc" "d" "dd") list->vector
              string-comparator)

  (do-scan '() odd? 1)
  (do-scan (iota 23) odd? 5)
  (do-scan (iota 42) (^n (< (modulo n 3) 2)) 91)
  )

(let ()
  (define (test-swap source actions)
    ;; actions : ((min|max item expected-result expected-min expected-max) ...)
    (let1 hp (build-binary-heap source)
      (dolist [action actions]
        (match-let1 (minmax item xresult xmin xmax) action
          (test* (format "swap ~s ~s ~s" source minmax item)
                 (list xresult xmin xmax)
                 (let1 r ((ecase minmax
                            [(min) binary-heap-swap-min!]
                            [(max) binary-heap-swap-max!])
                          hp item)
                   (list r
                         (binary-heap-find-min hp)
                         (binary-heap-find-max hp))))))))

  (test-swap (vector 1 3 5 7 9 11 13 15 17)
             '((min 4 1 3 17)
               (min 2 3 2 17)
               (max 16 17 2 16)
               (max 1 16 1 15)
               (min 20 1 2 20)
               (min 10 2 4 20)))
  (test-swap (vector 1)
             '((min 2 1 2 2)
               (max 1 2 1 1)
               (min 0 1 0 0)))
  (test-swap (vector 3 1)
             '((min 4 1 3 4)
               (max 5 4 3 5)
               (min 6 3 5 6)
               (max 0 6 0 5)))
  (test-swap (vector 4 2 5)
             '((max 3 5 2 4)
               (max 1 4 1 3)
               (max 1 3 1 2)
               (max 1 2 1 1)
               (max 1 1 1 1)))
  )

;; trie
(test-section "data.trie")
(use data.trie)
(test-module 'data.trie)
(use gauche.uvector)
(use srfi-1)
(use srfi-13)

(let* ((strs '("kana" "kanaono" "kanawai" "kanawai koa"
               "kanawai mele" "kane" "Kane" "kane make" "kane makua"
               "ku" "kua" "kua`aina" "kua`ana"
               "liliko`i" "lilinoe" "lili`u" "lilo" "maoli" ""))
       (lists (map string->list strs))
       (vecs  (map list->vector lists))
       (uvecs (map string->u8vector strs)))

  ;; string trie tests
  (let1 t1 (make-trie)
    (test* "trie: constructor" '(#t 0)
           (list (trie? t1) (trie-num-entries t1)))
    (test* "trie: exists?" #f (trie-exists? t1 "kane"))

    (test* "trie: put!" 1
           (begin (trie-put! t1 "lilo" 4)
                  (trie-num-entries t1)))
    (test* "trie: get" 4
           (trie-get t1 "lilo"))
    (test* "trie: get (error)" (test-error)
           (trie-get t1 "LILO"))
    (test* "trie: get (fallback)" 'foo
           (trie-get t1 "LILO" 'foo))

    (test* "trie: put! more" (length strs)
           (begin (for-each (lambda (s)
                              (trie-put! t1 s (string-length s)))
                            strs)
                  (trie-num-entries t1)))
    (test* "trie: get more" #t
           (every (lambda (s)
                    (= (trie-get t1 s) (string-length s)))
                  strs))
    (test* "trie: exists? more" #t
           (every (cut trie-exists? t1 <>) strs))
    (test* "trie: longest match" '(("kana" . 4)
                                   ("kana" . 4)
                                   ("kanawai" . 7)
                                   ("" . 0))
           (map (^k (trie-longest-match t1 k #f))
                '("kana" "kanaoka" "kanawai pele" "mahalo")))
    (test* "trie: common-prefix" '(19 12 8 4 4 3)
           (map (^p (length (trie-common-prefix t1 p)))
                '("" "k" "ka" "ku" "li" "lili")))
    (test* "trie: common-prefix" '(("kua" . 3)
                                   ("kua`aina" . 8)
                                   ("kua`ana" . 7))
           (trie-common-prefix t1 "kua")
           (cut lset= equal? <> <>))
    (test* "trie: common-prefix-keys" '("kua" "kua`aina" "kua`ana")
           (trie-common-prefix-keys t1 "kua")
           (cut lset= equal? <> <>))
    (test* "trie: common-prefix-values" '(3 8 7)
           (trie-common-prefix-values t1 "kua")
           (cut lset= = <> <>))
    (test* "trie: common-prefix-fold" 18
           (trie-common-prefix-fold t1 "kua"
                                    (lambda (k v s) (+ v s))
                                    0))
    (test* "trie: common-prefix-map" '("KUA" "KUA`AINA" "KUA`ANA")
           (trie-common-prefix-map t1 "kua"
                                   (lambda (k v) (string-upcase k)))
           (cut lset= equal? <> <>))
    (test* "trie: common-prefix-for-each" '("KUA" "KUA`AINA" "KUA`ANA")
           (let1 p '()
             (trie-common-prefix-for-each t1 "kua"
                                          (lambda (k v)
                                            (push! p (string-upcase k))))
             p)
           (cut lset= equal? <> <>))
    (test* "trie: trie-fold" (fold (lambda (k s) (+ (string-length k) s))
                                      0 strs)
           (trie-fold t1 (lambda (k v s) (+ v s)) 0))
    (test* "trie: trie-map" (fold (lambda (k s) (+ (string-length k) s))
                                     0 strs)
           (apply + (trie-map t1 (lambda (k v) v))))
    (test* "trie: trie-for-each"
           (fold (lambda (k s) (+ (string-length k) s))
                 0 strs)
           (let1 c 0 (trie-for-each t1 (lambda (k v) (inc! c v))) c))
    (test* "trie: trie->list"
           (map (^s (cons s (string-length s))) strs)
           (trie->list t1)
           (cut lset= equal? <> <>))
    (test* "trie: trie-keys"
           strs
           (trie-keys t1)
           (cut lset= equal? <> <>))
    (test* "trie: trie-values"
           (map string-length strs)
           (trie-values t1)
           (cut lset= equal? <> <>))
    (test* "trie: trie-update!" 16
           (begin (trie-update! t1 "liliko`i" (cut + <> 8))
                  (trie-get t1 "liliko`i")))
    (test* "trie: trie-update! (nonexistent)" (test-error)
           (trie-update! t1 "humuhumu" (cut + <> 8)))
    (test* "trie: trie-update! (nonexistent)" 16
           (begin (trie-update! t1 "humuhumu" (cut + <> 8) 8)
                  (trie-get t1 "humuhumu")))
    (test* "trie: delete!" '(19 #f)
           (begin (trie-delete! t1 "humuhumu")
                  (list (trie-num-entries t1)
                        (trie-get t1 "humuhumu" #f))))
    (test* "trie: delete! (nonexistent)" '(19 #f)
           (begin (trie-delete! t1 "HUMUHUMU")
                  (list (trie-num-entries t1)
                        (trie-get t1 "HUMUHUMU" #f))))
    (test* "trie: delete! (everything)" 0
           (begin (for-each (cut trie-delete! t1 <>) strs)
                  (trie-num-entries t1)))
    )
  ;; trie and trie-with-keys
  (let1 t2 (trie '() '("foo" . 0) '("foof" . 1) '("far" . 2))
    (test* "trie: trie" '(("foo" . 0) ("foof" . 1) ("far" . 2))
           (trie->list t2)
           (cut lset= equal? <> <>)))
  (let1 t3 (trie-with-keys '() "foo" "foof" "far")
    (test* "trie: trie-with-keys"
           '(("foo" . "foo") ("foof" . "foof") ("far" . "far"))
           (trie->list t3)
           (cut lset= equal? <> <>)))

  ;; heterogeneous tries
  (let1 t4 (make-trie)
    (for-each (cut for-each
                   (lambda (seq)
                     (trie-put! t4 seq (class-of seq)))
                   <>)
              (list strs lists vecs uvecs))
    (test* "trie(hetero): put!" (* 4 (length strs))
           (trie-num-entries t4))
    (test* "trie(hetero): get" <vector> (trie-get t4 '#()))
    (test* "trie(hetero): get" <u8vector> (trie-get t4 '#u8()))
    (test* "trie(hetero): get" <pair> (trie-get t4 '(#\k #\u)))

    (test* "trie(hetero): delete!" <string>
           (begin (trie-delete! t4 '()) (trie-get t4 "")))
    (test* "trie(hetero): delete!" (* 3 (length strs))
           (begin (for-each (cut trie-delete! t4 <>) lists)
                  (trie-num-entries t4)))
    )

  ;; customizing tables
  (let1 t5 (make-trie list
                      (cut assoc-ref <> <> #f char-ci=?)
                      (lambda (t k v)
                        (if v
                          (assoc-set! t k v char-ci=?)
                          (alist-delete! k t char-ci=?)))
                      (lambda (t f s) (fold f s t)))
    (test* "trie(custom): put!" (- (length strs) 1)
           (begin
             (for-each (^s (trie-put! t5 s (string-length s))) strs)
             (trie-num-entries t5)))
    (test* "trie(custom): get" 99
           (begin
             (trie-put! t5 "LILIKO`I" 99)
             (trie-get t5 "liliko`i")))
    )

  ;; collection api
  (let1 t6 #f
    (test* "trie(collection): builder" (length strs)
           (begin
             (set! t6 (coerce-to <trie> (map (cut cons <> #t) strs)))
             (and (trie? t6) (size-of t6))))
    (test* "trie(collection): iterator" strs
           (let1 p '()
             (call-with-iterator t6
                                 (lambda (end next)
                                   (until (end)
                                     (push! p (car (next))))))
             p)
           (cut lset= equal? <> <>))
    (test* "trie(collection): coerce to list" (map (cut cons <> #t) strs)
           (coerce-to <list> t6)
           (cut lset= equal? <> <>))
    (test* "trie(collection): coerce to vector"
           (map (cut cons <> #t) strs)
           (vector->list (coerce-to <vector> t6))
           (cut lset= equal? <> <>))
    (test* "trie(collection): coerce to hashtable" #t
           (let1 h (coerce-to <hash-table> t6)
             (every (cut hash-table-get h <>) strs)))
    )
  )

  

(test-end)
