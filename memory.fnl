(import-macros {: mask?} :macros)

(local ffi (require :ffi))
(local boot (require :boot))

(local {:rshift r-shift :lshift l-shift :band b-and :bnot b-not :bor b-or} bit)
(local down? (. love :keyboard :isDown))

(local memory {:data nil
               :banks nil
               :rom-bank 1
               :ram-bank 0
               :ram-enable false
               :bank-mode :rom })

(local cartridge-types {0x00 :rom
                        0x01 :mbc1
                        0x02 :mbc1
                        0x03 :mbc1
                        0x11 :mbc3
                        0x12 :mbc3
                        0x13 :mbc3})

(fn memory.init [self rom]
    (tset self :rom rom)
    (tset self :mapper (. cartridge-types (. rom 0x147)))
    (tset self :data (ffi.new "uint8_t[?]" 0x10000))
    (tset self :banks (ffi.new "uint8_t[?]" 0x8000))
    (each [key value (pairs boot)]
      (tset self key value)))

(fn memory.get [self address]
  (let [range (r-shift address 12)]
    (if (< range 0x04) 
          (. self :rom address)
        (< range 0x08) 
          (. self :rom (+ (- address 0x4000) (* self.rom-bank 0x4000)))
        (< range 0x0A)
          (. self :data address)
        (< range 0x0C)
          (match self.mapper
            "rom" (. self :rom address)
            (where (or :mbc1 :mbc3) (. self :ram_enable))
            (. self :rom (+ (- address 0xA000) (* self.ram-bank 0x2000)))
            _ 0xff)
        (= address 0xff00)
          (: self :input)
        (. self :data address))))

(fn memory.set [self address value]
  (let [range (r-shift address 12)]
    (if (< range 0x02)
          (tset self :ram-enable (mask? value 0x0A))
        (< range 0x04)
          (match self.mapper
            :mbc1 (tset self :rom-bank (b-or 
                                         (b-and value 0x1F) 
                                         (b-and self.rom-bank 0x60)))
            :mbc3 (tset self :rom-bank (b-and value 0x7F))
            _ nil)
        (< range 0x06)
          (let [bank (b-and value 0x03)]
            (match (values self.mapper self.bank-mode)
              (:mbc1 :rom) (tset self :rom-bank (b-or (l-shift bank 5) (b-and self.rom-bank 0x1F)))
              (:mbc1 :ram) (tset self :ram-bank bank)
              :mbc3 (tset self :ram-bank value)))
        (< range 0x08)
          (match self.mapper
            :mbc1 (if (mask? value 0x01) 
                       (tset self :bank-mode :ram)
                       (do
                         (tset self :bank-mode :rom)
                         (tset self :ram-bank 0))))
        (< range 0x0A)
          (tset self.data address value)
        (< range 0x0C)
          (match self.mapper
            :mbc1 (tset self :banks (+ (* self.ram-bank 0x2000) (- address 0xA000)) value)
            :mbc3 (tset self :banks (+ (* self.ram-bank 0x2000) (- address 0xA000)) value))
        (= address 0xff46)
          (: self :dma value)
      (tset self.data address value))))

(fn memory.dma [self value]
  (let [source (l-shift value 8)]
    (for [i 0 0x9f]
      (tset self.data (+ 0xFE00 i) (. self :data (+ source i))))))

(fn memory.input [self]
  (let [joypad (-> (. self :data 0xff00) (b-not) (b-and 0x30))
        dpad (if (mask? joypad 0x10)
                   (b-or (if (down? :right) 1 0) 
                         (if (down? :left) 2 0)
                         (if (down? :up) 4 0) 
                         (if (down? :down) 8 0))
                   0)
        keys (if (mask? joypad 0x20)
                   (b-or (if (down? :z) 1 0) 
                         (if (down? :x) 2 0)
                         (if (down? :backspace) 4 0) 
                         (if (down? :return) 8 0))
                   0)]
    (-> (b-or dpad keys)
        (b-not)
        (b-and 0x3F)
        (b-or 0xC0))))

memory
