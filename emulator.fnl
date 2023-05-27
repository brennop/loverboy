(local ffi (require :ffi))

(local cpu (require :cpu))
(local graphics (require :graphics))
(local memory (require :memory))
(local timers (require :timers))

;; TODO: we may not need init instructions
(local instructions (require :instructions))

(local emulator {:rom nil})

(fn load-rom [filename]
  (with-open [file (io.open filename "rb")]
    (let [size (: file :seek :end)
          buffer (ffi.new "uint8_t[?]" size)]
      (: file :seek :set)
      (for [i 0 (- size 1)]
        (tset buffer i (: (: file :read 1) :byte)))
      buffer)))

(fn emulator.init [self filename]
  (tset self :rom (load-rom filename))
  (: memory :init (. self :rom))
  (: cpu :init memory)
  (: graphics :init)
  (: instructions :init cpu memory)
  (tset self :image (love.graphics.newImage (. graphics :framebuffer))))

(fn emulator.recur [self cycles]
  (if (< cycles 70224)
      (self:recur
        (+ cycles (doto (: cpu :step)
              (timers:step)
              (graphics:step))))))

(fn emulator.step [self]
  (self:recur 0)
  (self.image:replacePixels (. graphics :framebuffer)))

(fn emulator.draw [self]
  (love.graphics.draw self.image 0 0 0 2 2)
  ;; draw a rectangle for fps
  (love.graphics.setColor 0 0 0)
  (love.graphics.rectangle "fill" 0 0 60 20)
  (love.graphics.setColor 1 1 1)
  (love.graphics.print (string.format "FPS: %d" (love.timer.getFPS)) 0 0))

emulator
