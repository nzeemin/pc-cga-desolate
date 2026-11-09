; Boot sector: loads SECTORS sectors (from sector 2 on) to 1000:0100 and runs them
; like a .COM would (CS=DS=ES=SS=1000h). No DOS needed; BIOS services stay available.
  cpu 8086
  bits 16
  org 0x7C00

  cli
  xor ax,ax
  mov ds,ax
  mov ss,ax
  mov sp,0x7C00
  sti
  mov [drive],dl
  mov ax,0x1000
  mov es,ax
  mov bx,0x0100
  mov cx,0x0002         ; cylinder 0, sector 2
  xor dh,dh             ; head 0
  mov word [cnt],SECTORS
next:
  mov ax,0x0201         ; read 1 sector
  mov dl,[drive]
  int 0x13
  jc fail
  add bx,512
  inc cl
  cmp cl,10             ; 9 sectors/track
  jb same
  mov cl,1
  inc dh
  cmp dh,2              ; 2 heads
  jb same
  xor dh,dh
  inc ch
same:
  dec word [cnt]
  jnz next
  mov ax,0x1000
  mov ds,ax
  mov es,ax
  cli
  mov ss,ax
  mov sp,0xFFFE
  sti
  jmp 0x1000:0x0100
fail:
  mov ax,0x0E21         ; '!' and halt
  int 0x10
  jmp $
drive: db 0
cnt:   dw 0
  times 510-($-$$) db 0
  dw 0xAA55
