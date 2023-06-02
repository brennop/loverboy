(import-macros {: mask? : +u8} :macros)

(local {:rshift r-shift :lshift l-shift :band b-and :bnot b-not :bor b-or} bit)

(local cpu (require :cpu))
(local memory (require :memory))

(local timers {:div 0 :tima 0})

(local freqs [1024 16 64 256])

(fn timers.step [self cycles]
  (let [div   (memory:get 0xFF04)
        tima  (memory:get 0xFF05)
        tma   (memory:get 0xFF06)
        attrs (memory:get 0xFF07)]
    (tset self :div (+ (. self :div) cycles))

    (while (>= (. self :div) 256)
      (tset self :div (- (. self :div) 256))
      (memory:set 0xFF04 (+ (memory:get 0xff04) 1)))

    (when (mask? attrs 0x4)
      (tset self :tima (+ (. self :tima) cycles))
      (let [index (b-and attrs 0x3)
            freq (. freqs (+ index 1))]
        (while (>= (. self :tima) freq)
          (tset self :tima (- (. self :tima) freq))
          (memory:set 0xFF05 (+u8 (memory:get 0xff05) 1))
          (when (= (memory:get 0xff05) 0x00)
            (memory:set 0xFF05 tma)
            (cpu:interrupt :timer)))))))

timers
