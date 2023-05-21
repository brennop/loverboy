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

    (when (>= (. self :div) 256)
      (tset self :div 0)
      (memory:set 0xFF04 (+ div 1)))

    (when (mask? attrs 0x4)
      (tset self :tima (+ (. self :tima) cycles))
      (let [freq (b-and attrs 0x3)
            clock (. freqs (+ freq 1))]
        (when (>= (. self :tima) clock)
          (tset self :tima 0)
          (memory:set 0xFF05 (+u8 tima 1))
          (when (= tima 0xFF)
            (memory:set 0xFF05 tma)
            (cpu:interrupt :timer)))))))

timers
