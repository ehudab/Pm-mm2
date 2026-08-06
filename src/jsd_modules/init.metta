(exec (jsd 101 start-jsd)
    (, (INPUT DB $db-name)
       (INPUT PATTERN ($pattern $support))
       ((count-db $db-name -> db-size) $src-of-count $sink-of-count)
       ((count-conjuncts $pattern -> num-of-conjuncts) $src-of-cnj $sink-of-cnj))
    (O
        (+ (exec (jsd 102 count-db) $src-of-count $sink-of-count))
        (+ (exec (jsd 103 count-conjuncts) $src-of-cnj $sink-of-cnj))
        (pure
            (indexed-pattern $indexed-copy)
            $indexed-copy
            (vars_to_indices
                (cdr-atom (' $pattern))))))


(exec (jsd 105 partitions-of)
    (, (indexed-pattern $indexed-pattern))
    (O
        (pure
            (partitions-of $indexed-pattern $indexed-partition)
            $indexed-partition
            (partitions (' $indexed-pattern)))))


(exec (jsd 106 extract-partiton)
    (, (partitions-of $indexed-pattern $indexed-partition)
       (exec (jsd 106 extract-partiton) $src $sink))
    (O
        (pure
            (partition $car)
            $car
            (car-atom (' $indexed-partition)))
        (pure
            (partitions-of $indexed-pattern $cdr)
            $cdr
            (cdr-atom (' $indexed-partition)))
        (- (partitions-of $indexed-pattern $indexed-partition))
        (+ (exec (jsd 106 extract-partiton) $src $sink))))

;; Copy partitions before expanding them into blocks.
(exec (jsd 107 copy-partition)
    (, (partition $partition))
    (, (copy-of-partition $partition $partition)))

(exec (jsd 108 extract-blocks)
    (, (copy-of-partition $partition $partition-copy)
       (exec (jsd 108 extract-blocks) $src $sink))
    (O
        (pure
            (block $partition $block)
            $block
            (car-atom (' $partition-copy)))
        (pure
            (copy-of-partition $partition $cdr)
            $cdr
            (cdr-atom (' $partition-copy)))
        (- (copy-of-partition $partition $partition-copy))
        (+ (exec (jsd 108 extract-blocks) $src $sink))))


