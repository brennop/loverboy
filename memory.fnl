(import-macros {: mask?} :macros)

(local ffi (require :ffi))
(local boot (require :boot))

(local {:rshift r-shift :lshift l-shift :band b-and :bnot b-not :bor b-or} bit)
(local max (. math :max))
(local down? (. love :keyboard :isDown))

(local memory {:data nil
               :banks nil
               :rom-bank 1
               :ram-bank 0
               :rom-banks 0
               :ram-banks 0
               :ram-enable false
               :bank-mode :rom })

(local cartridge-types {0x00 :rom
                        0x01 :mbc1
                        0x02 :mbc1
                        0x03 :mbc1
                        0x11 :mbc3
                        0x12 :mbc3
                        0x13 :mbc3})

(local ram-banks {0x00 0
                  0x02 1
                  0x03 4
                  0x04 16
                  0x05 8})

(fn memory.init [self rom]
    (tset self :rom rom)
    (tset self :mapper (. cartridge-types (. rom 0x147)))
    (tset self :rom-banks (l-shift 1 (+ (. rom 0x148) 1)))
    (tset self :ram-banks (. ram-banks (. rom 0x149)))
    (tset self :data (ffi.new "uint8_t[?]" 0x10000))
    (tset self :banks (ffi.new "uint8_t[?]" 0x8000))
    (each [key value (pairs boot)]
      (tset self :data key value)))

(fn memory.get [self address]
  (let [range (r-shift address 12)]
    (if (< range 0x04) 
          (. self :rom address)
        (< range 0x08) 
          (. self :rom (b-or 
                         (l-shift (b-and self.rom-bank (- self.rom-banks 1)) 14)
                         (b-and address 0x3FFF)))
        (< range 0x0A)
          (. self :data address)
        (< range 0x0C)
          (if self.ram-enable
              (let [addr (b-and address 0x1FFF)]
                (match (values self.bank-mode (< self.ram-bank self.ram-banks))
                  (:ram true) (. self :banks (b-or (l-shift self.ram-bank 13) addr))
                  (_ _) (. self :banks addr)))
              0xff)
        (= address 0xff00)
          (: self :input)
        (. self :data address))))

(fn memory.set [self address value]
  (let [range (r-shift address 12)]
    (if (< range 0x02)
          (tset self :ram-enable (= (b-and value 0x0F) 0x0A))
        (< range 0x04)
          (match self.mapper
            :mbc1 (tset self :rom-bank (max 1 (b-and value 0x1F)))
            :mbc3 (tset self :rom-bank (b-and value 0x7F))
            _ nil)
        (< range 0x06)
          (match (. self :mapper)
            :mbc1 (tset self :ram-bank (b-and value 0x03))
            :mbc3 (tset self :ram-bank value))
        (< range 0x08)
          (match self.mapper
            :mbc1 (if (mask? value 0x01) 
                       (tset self :bank-mode :ram)
                       (tset self :bank-mode :rom)))
        (< range 0x0A)
          (tset self.data address value)
        (< range 0x0C)
          (if self.ram-enable
            (let [addr (if (and (= self.bank-mode :ram) (< self.ram-bank self.ram-banks))
                           (b-or (l-shift self.ram-bank 13) (b-and address 0x1FFF))
                           (b-and address 0x1FFF))]
              (tset self :banks addr value)))
        (= address 0xff46)
          (: self :dma value))
      (tset self.data address value)))

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
