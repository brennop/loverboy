(fn mask? [value mask]
  `(= (b-and ,value ,mask) ,mask))

;; uint8 arith

(fn +u8 [a b]
  `(b-and (+ ,a ,b) 255))

{: mask? : +u8}
