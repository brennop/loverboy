(local ffi (require :ffi))

(local memory { })

(local {:rshift r-shift :lshift l-shift :band b-and :bnot b-not :bor b-or} bit)
(local down? (. love :keyboard :isDown))

(local cartridge-types {
       0x00 :rom
       0x01 :mbc1
       0x02 :mbc1 
       0x03 :mbc1
       0x11 :mbc3
       0x12 :mbc3
       0x13 :mbc3
       })

(fn memory.init [self rom]
    (tset self :rom rom)
    (tset self :data (ffi.new "uint8_t[?]" 0x10000))
    (tset self :banks (ffi.new "uint8_t[?]" 0x8000))
    (tset self :rom_bank 1)
    (tset self :ram_bank 0)
    (tset self :ram_enable false)
    (tset self :bank_mode :rom)
    (tset self :mapper (. cartridge-types (. rom 0x147)))

  ;; https://gbdev.io/pandocs/Power_Up_Sequence.html#hardware-registers
  (tset self :data 0xFF00 0xCF)
  (tset self :data 0xFF01 0x00)
  (tset self :data 0xFF02 0x7E)
  (tset self :data 0xFF04 0xAB)
  (tset self :data 0xFF05 0x00)
  (tset self :data 0xFF06 0x00)
  (tset self :data 0xFF07 0xF8)
  (tset self :data 0xFF0F 0xE1)
  (tset self :data 0xFF10 0x80)
  (tset self :data 0xFF11 0xBF)
  (tset self :data 0xFF12 0xF3)
  (tset self :data 0xFF13 0xFF)
  (tset self :data 0xFF14 0xBF)
  (tset self :data 0xFF16 0x3F)
  (tset self :data 0xFF17 0x00)
  (tset self :data 0xFF18 0xFF)
  (tset self :data 0xFF19 0xBF)
  (tset self :data 0xFF1A 0x7F)
  (tset self :data 0xFF1B 0xFF)
  (tset self :data 0xFF1C 0x9F)
  (tset self :data 0xFF1D 0xFF)
  (tset self :data 0xFF1E 0xBF)
  (tset self :data 0xFF20 0xFF)
  (tset self :data 0xFF21 0x00)
  (tset self :data 0xFF22 0x00)
  (tset self :data 0xFF23 0xBF)
  (tset self :data 0xFF24 0x77)
  (tset self :data 0xFF25 0xF3)
  (tset self :data 0xFF26 0xF1)
  (tset self :data 0xFF40 0x91)
  (tset self :data 0xFF41 0x85)
  (tset self :data 0xFF42 0x00)
  (tset self :data 0xFF43 0x00)
  (tset self :data 0xFF44 0x00)
  (tset self :data 0xFF45 0x00)
  (tset self :data 0xFF46 0xFF)
  (tset self :data 0xFF47 0xFC)
  (tset self :data 0xFF4A 0x00)
  (tset self :data 0xFF4B 0x00)
  (tset self :data 0xFF4D 0xFF)
  (tset self :data 0xFF4F 0xFF)
  (tset self :data 0xFF51 0xFF)
  (tset self :data 0xFF52 0xFF)
  (tset self :data 0xFF53 0xFF)
  (tset self :data 0xFF54 0xFF)
  (tset self :data 0xFF55 0xFF)
  (tset self :data 0xFF56 0xFF)
  (tset self :data 0xFF68 0xFF)
  (tset self :data 0xFF69 0xFF)
  (tset self :data 0xFF6A 0xFF)
  (tset self :data 0xFF6B 0xFF)
  (tset self :data 0xFF70 0xFF)
  (tset self :data 0xFFFF 0x00)
  )

(fn memory.get [self address]
  (let [range (r-shift address 12)]
    (if 
      (< range 4) 
        (. self :rom address)
      (< range 8) 
        (. self :rom (+ (- address 0x4000) (* self.rom_bank 0x4000)))
      (= address 0xff00)
        (: self :input)
      (. self :data address))))

(fn memory.set [self address value]
  (let [range (r-shift address 12)]
    (if 
      (= address 0xff46)
        (: self :dma value)
      (tset self :data address value))))

(fn memory.dma [self value]
  (let [source (l-shift value 8)]
    (for [i 0 0x9f]
      (tset self :data (+ 0xFE00 i) (. self :data (+ source i))))))

(fn memory.input [self]
  (let [joypad (-> (. self :data 0xff00) (b-not) (b-and 0x30))
        dpad (if (= 0x10 (b-and joypad 0x10))
                 (b-or (if (down? :right) 1 0) 
                       (if (down? :left) 2 0)
                       (if (down? :up) 4 0) 
                       (if (down? :down) 8 0))
                        0)
        keys (if (= 0x20 (b-and joypad 0x20))
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
