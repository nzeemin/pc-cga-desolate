;
; Desolate for PC (8088, CGA) -- platform layer and main file.
; Port of desolcoda.asm from the ZX Spectrum version.
;
; Z80 -> 8088 register map used by all ported code:
;   A=AL  B=CH C=CL (BC=CX)  D=DH E=DL (DE=DX)  H=BH L=BL (HL=BX)  IX=SI
;   DI = scratch pointer (replaces (DE)/(BC) memory access), BP = spare
;   CF is the same as on the Z80; INC/DEC r16 DO change ZF on the 8088.
;
; Memory model: .COM style, CS=DS=ES=SS, origin 100h.
; The shadow screen is kept 1bpp as on the Spectrum (24 bytes per line, MSB = left pixel)
; and is expanded to CGA 2bpp by ShowShadowScreen.
;

  cpu 8086
  bits 16
  org 0x100

; Long conditional jumps (the 8086 has only short ones)
%macro jzl 1
  jnz %%s
  jmp %1
%%s:
%endmacro
%macro jnzl 1
  jz %%s
  jmp %1
%%s:
%endmacro
%macro jcl 1
  jnc %%s
  jmp %1
%%s:
%endmacro
%macro jncl 1
  jc %%s
  jmp %1
%%s:
%endmacro

; Set to 1 to run the platform test instead of the game
PLATFORM_TEST           EQU 0

; DEBUG: Esc/Tab = next room + weapon, E = ending, A = all items and door codes
DEBUG_NEXT_ROOM         EQU 0
CHEAT_SHOW_ROOM_NUMBER  EQU 0
CHEAT_ALL_ACCESS        EQU 0
CHEAT_ALL_INVENTORY     EQU 0
CHEAT_HAVE_WEAPON       EQU 0
CHEAT_HEALTH_999        EQU 0

; Screen layout, in CGA mode 4 pixels (x must be multiple of 4, y even)
AREA_X          EQU 48          ; themed area 224x144
AREA_Y          EQU 44
AREA_W          EQU 224
AREA_H          EQU 144
PLAY_X          EQU 64          ; game screen 192x128
PLAY_Y          EQU 52
SIGN_X          EQU 64          ; DESOLATE sign 192x30
SIGN_Y          EQU 6
SIGN_H          EQU 30
SIGN_SRC        EQU 8           ; first line of the menu title art that is copied

CGA_COLOR_REG   EQU 0x30        ; palette 1 (cyan/magenta/white), bright; see SetCgaColors

start:
  call InitPlatform
  call InitSign
  call ClearShadowScreen
  call ScreenThemeNite      ; titles are shown on the dark background

%if PLATFORM_TEST
  call PlatformTest
%else
  call LBA07  ; Show titles and go to Menu (never returns)
%endif
  jmp ExitProgram

;----------------------------------------------------------------------------
; Platform: init / exit
;----------------------------------------------------------------------------

InitPlatform:
  cld                       ; string ops go forward
  mov ax,0x0004             ; CGA mode 4, 320x200x2bpp
  int 0x10
  call ApplyPalette         ; palette 1, high intensity, black background
; Hook INT 9 keyboard
  xor ax,ax
  mov es,ax
  cli
  mov ax,[es:9*4]
  mov [OldInt9],ax
  mov ax,[es:9*4+2]
  mov [OldInt9+2],ax
  mov word [es:9*4],Int9Handler
  mov [es:9*4+2],cs
  sti
  push cs
  pop es
  ret

; AL = value for the CGA color select register (3D9h)
SetCgaColors:
  mov [CgaColors],al
  mov dx,0x3D9
  out dx,al
  ret
CgaColors: db CGA_COLOR_REG | 0x10

; Palettes: (color select register 3D9h, mode register 3D8h) pairs
;   0: cyan/magenta/white, bright; 1: the same, dim; 2: green/red/brown, bright; 3: the same, dim
; The game uses colors 0, 1 and 3 only (black, ink, white paper)
PaletteTable: db 0x30,0x0A, 0x20,0x0A, 0x10,0x0A, 0x00,0x0A
PaletteCount  EQU 4
PaletteNo:    db 0
PalHeld:      db 0

NextPalette:
  push ax
  mov al,[PaletteNo]
  inc al
  cmp al,PaletteCount
  jb NextPalette_1
  xor al,al
NextPalette_1:
  mov [PaletteNo],al
  call ApplyPalette
  pop ax
  ret

; Set the palette PaletteNo. Preserves all registers
ApplyPalette:
  push ax
  push bx
  push dx
  mov al,[PaletteNo]
  xor ah,ah
  shl ax,1
  mov bx,PaletteTable
  add bx,ax
  mov al,[bx+1]
  mov dx,0x3D8
  out dx,al                 ; mode register
  mov al,[bx]
  call SetCgaColors
  pop dx
  pop bx
  pop ax
  ret
SetBorderColor_map: db 0,1,4,5,2,3,14,15   ; Spectrum color -> CGA color

; AL = Spectrum border color 0..7 (0 black, 1 blue, 2 red, 3 magenta, 4 green, 5 cyan, 6 yellow, 7 white)
; Sets the CGA border/background color (CGA numbering differs from the Spectrum one)
SetBorderColor:
  push dx
  push bx
  and al,0x07
  xor ah,ah
  mov bx,SetBorderColor_map
  add bx,ax
  mov al,[bx]
  pop bx
  or al,[CgaColors]
  mov dx,0x3D9
  out dx,al
  pop dx
  ret

ExitProgram:
; Unhook INT 9
  xor ax,ax
  mov es,ax
  cli
  mov ax,[OldInt9]
  mov [es:9*4],ax
  mov ax,[OldInt9+2]
  mov [es:9*4+2],ax
  sti
  push cs
  pop es
  mov ax,0x0003             ; text mode
  int 0x10
%ifdef NODOS
  mov si,ExitMessage        ; no DOS to return to (floppy test image): message and stop
ExitProgram_1:
  lodsb
  or al,al
  jz ExitProgram_2
  mov ah,0x0E
  mov bx,0x0007
  int 0x10
  jmp ExitProgram_1
ExitProgram_2:
  cli
  hlt
  jmp ExitProgram_2
ExitMessage: db "Program ended.",13,10,0
%else
  mov ax,0x4C00             ; DOS terminate
  int 0x21
%endif

OldInt9:  dw 0,0

;----------------------------------------------------------------------------
; Keyboard
;----------------------------------------------------------------------------

; INT 9 handler: keeps KeyState[scancode] = 1 while the key is down
Int9Handler:
  push ax
  push bx
  push ds
  mov ax,cs
  mov ds,ax
  in al,0x60
  cmp al,0xE0               ; ignore prefix bytes (E0/E1)
  jae .ack
  mov bl,al
  and bl,0x7F
  xor bh,bh
  test al,0x80              ; break code?
  mov al,1
  jz .set
  xor al,al
.set:
  mov [KeyState+bx],al
  or [KeyLatch+bx],al       ; remember the press until ReadKeyboard reads it (short taps between polls)
.ack:
  in al,0x61                ; acknowledge keyboard (XT)
  mov ah,al
  or al,0x80
  out 0x61,al
  mov al,ah
  out 0x61,al
  mov al,0x20               ; EOI
  out 0x20,al
  pop ds
  pop bx
  pop ax
  iret

SoundLookShoot_pitch EQU 1193   ; 1193182 / 1193 = 1000 Hz

; Sound for "Look" or "Shoot" action: short beep on the PC speaker
SoundLookShoot:
  push ax
  push cx
  mov al,0xB6               ; PIT channel 2, square wave
  out 0x43,al
  mov ax,SoundLookShoot_pitch
  out 0x42,al
  mov al,ah
  out 0x42,al
  in al,0x61
  or al,3                   ; speaker on
  out 0x61,al
  mov cx,2                  ; duration in frames
SoundLookShoot_1:
  call WaitVSync
  loop SoundLookShoot_1
  in al,0x61
  and al,0xFC               ; speaker off
  out 0x61,al
  pop cx
  pop ax
  ret

; Wait for the start of the next vertical retrace
WaitVSync:
  push ax
  push dx
  mov dx,0x3DA
WaitVSync_1:
  in al,dx
  test al,8
  jnz WaitVSync_1           ; wait for the end of a current retrace
WaitVSync_2:
  in al,dx
  test al,8
  jz WaitVSync_2
  pop dx
  pop ax
  ret

; Wait for any key
WaitAnyKey:
  call ReadKeyboard
  or al,al
  jnz WaitAnyKey            ; Wait for unpress
WaitAnyKey_1:
  call ReadKeyboard
  or al,al
  jz WaitAnyKey_1           ; Wait for press
  ret

; Wait until no key pressed - to put after ReadKeyboard calls to prevent double-reads of the same key
WaitKeyUp:
  call ReadKeyboard
  or al,al
  jnz WaitKeyUp             ; Wait for unpress
  ret

; Returns: AL=key code, $00 no key; Z=0 for key, Z=1 for no key
; Key codes: Down=$01, Left=$02, Right=$03, Up=$04, Look/shoot=$05
;            Inventory=$06, Escape=$07, Switch look/shoot=$08, Enter=$09, Menu=$0F
ReadKeyboard:
  push bx
  cmp byte [KeyState+0x19],0  ; P: change palette (once per key press)
  je ReadKeyboard_p0
  cmp byte [PalHeld],0
  jne ReadKeyboard_p1
  mov byte [PalHeld],1
  call NextPalette
  jmp short ReadKeyboard_p1
ReadKeyboard_p0:
  mov byte [PalHeld],0
ReadKeyboard_p1:
  mov bx,ReadKeyboard_map
ReadKeyboard_1:
  mov al,[bx]               ; scancode
  or al,al
  jz ReadKeyboard_none      ; end of the table
  push bx
  mov bl,al
  xor bh,bh
  mov al,[KeyState+bx]      ; key is down now ...
  or al,[KeyLatch+bx]       ; ... or was pressed since the last read
  mov byte [KeyLatch+bx],0  ; the press is consumed
  pop bx
  or al,al
  jne ReadKeyboard_2
  add bx,2
  jmp ReadKeyboard_1
ReadKeyboard_2:
  mov al,[bx+1]             ; game key code
  or al,al
  pop bx
  ret
ReadKeyboard_none:
  xor al,al
  pop bx
  ret

; Mapping (scancode, game key code):
;   cursor keys - arrows; Space - look/shoot; Enter; Esc/Tab - escape;
;   I - inventory; S - switch look/shoot mode; M - menu
; Cursor keys on the XT keyboard are the numpad ones (48 50 4B 4D), on AT E0 prefix is ignored.
ReadKeyboard_map:
  db 0x48,0x04              ; Up
  db 0x50,0x01              ; Down
  db 0x4B,0x02              ; Left
  db 0x4D,0x03              ; Right
  db 0x39,0x05              ; Space
  db 0x1C,0x09              ; Enter
  db 0x01,0x07              ; Esc
  db 0x0F,0x07              ; Tab
  db 0x17,0x06              ; I
  db 0x1F,0x08              ; S
  db 0x32,0x0F              ; M
%if DEBUG_NEXT_ROOM
  db 0x12,0x0A              ; DEBUG: E = ending
  db 0x1E,0x0B              ; DEBUG: A = all items and access codes
%endif
  db 0

;----------------------------------------------------------------------------
; Shadow screen helpers
;----------------------------------------------------------------------------

; Compare HL and DE
CpHLDE:
  cmp bx,dx
  ret

; Get shadow screen address using penCol in L86D7
;   AL = row 0..137
;   (L86D7) = penCol 0..191
; Returns BX = address; AL = penCol / 8
GetScreenAddr:
  xor ah,ah
  mov bx,ax
  shl bx,1                  ; row * 2
  add bx,ax                 ; row * 3
  shl bx,1
  shl bx,1
  shl bx,1                  ; row * 24
  mov al,[L86D7]            ; get penCol
  shr al,1
  shr al,1
  shr al,1                  ; now AL = 8px column
  xor ah,ah
  add bx,ax                 ; now BX = line address + column (shadow screen offset)
  add bx,ShadowScreen
  ret

; Draw tile with mask 16x8 -> 16x16 on shadow screen - for Tileset2 tiles
;   BL = penRow; DL = penCol; SI = tile address
DrawTileMasked:
  mov al,dl
  mov [L86D7],al            ; penCol
  mov al,bl                 ; penRow
  mov ch,8                  ; 8 row pairs
  call GetScreenAddr        ; now BX = screen addr
DrawTileMasked_1:
; Draw 1st line
  mov al,[si]               ; get mask
  and al,[bx]
  or al,[si+1]
  mov [bx],al               ; write 1st byte
  inc bx
  mov al,[si+2]             ; get mask
  and al,[bx]
  or al,[si+3]
  mov [bx],al               ; write 2nd byte
  add bx,24-1               ; to the 2nd line
; Draw 2nd line
  mov al,[si+4]             ; get mask
  and al,[bx]
  or al,[si+5]
  mov [bx],al               ; write 1st byte
  inc bx
  mov al,[si+6]             ; get mask
  and al,[bx]
  or al,[si+7]
  mov [bx],al               ; write 2nd byte
  add bx,24-1               ; to the next line
  add si,8
  dec ch
  jnz DrawTileMasked_1
  ret

; Draw string on shadow screen using FontProto
;   BX = string addr
DrawString:
  mov al,[bx]
  inc bx
  or al,al
  jz DrawString_ret
  call DrawChar
  jmp DrawString
DrawString_ret:
  ret

; Draw decimal number BX in 5 digits
DrawNumber5:
  mov cx,-10000
  call DrawNumber_1
  mov cx,-1000
  call DrawNumber_1
; Draw decimal number BX in 3 digits
DrawNumber3:
  mov cx,-100
  call DrawNumber_1
  mov cl,-10
  call DrawNumber_1
  mov cl,-1
DrawNumber_1:
  mov al,'0'-1
DrawNumber_2:
  inc al
  add bx,cx
  jc DrawNumber_2
  sub bx,cx
;
; Draw character on the screen using FontProto
;   AL = character to show: $00-$1F space with A width; $20 space
; Preserves BX, CX
DrawChar:
  push bx
  push cx
  cmp al,0x20               ; $00-$1F ?
  jb DrawChar_00            ; yes => set char width and process like space char
  jne DrawChar_0            ; not space char => jump
  mov al,3                  ; space char gap size
DrawChar_00:
  mov [DrawChar_width],al
  jmp DrawChar_fin
DrawChar_0:
  cmp al,0x27               ; char less than apostroph?
  jae DrawChar_1
  add al,0x3A               ; for '!', quotes, '#' '$' '%' '&'
  jmp short DrawChar_2
DrawChar_1:
  cmp al,0x2A               ; char less than '*'?
  jae DrawChar_2
  add al,0x15               ; for apostroph, '(' ')' chars
DrawChar_2:
  sub al,0x2C               ; font starts from ','
  xor ah,ah
  mov di,ax                 ; DI = a
  shl ax,1                  ; a * 2
  shl ax,1                  ; a * 4
  add ax,di                 ; a * 5
  shl ax,1                  ; a * 10
  add ax,di                 ; a * 11
  add ax,FontProto
  mov di,ax                 ; now DI = symbol addr
  mov al,[L86D8]            ; get penRow
  mov [DrawChar_row],al
  mov al,[di]               ; get flag/width byte
  inc di
  test al,0x80              ; lowered symbol?
  jz DrawChar_3
  inc byte [DrawChar_row]   ; start on the next line
DrawChar_3:
  and al,0x0F               ; keep width 1..8
  add al,2                  ; gap 2px after the symbol
  mov [DrawChar_width],al
  mov al,[DrawChar_row]
  call GetScreenAddr
  push bx                   ; store addr on the screen
  push di                   ; store symbol data addr
  mov al,[L86D7]            ; get penCol
  and al,7                  ; shift 0..7
  inc al
  mov cl,al
  mov ch,10                 ; 10 lines
DrawChar_4:                 ; loop by lines
  push cx                   ; save counter
  mov al,[di]
  inc di
DrawChar_5:                 ; loop for shift
  dec cl
  jz DrawChar_6
  shr al,1                  ; shift right
  jmp DrawChar_5
DrawChar_6:
  or [bx],al                ; put on the screen
  mov al,[DrawChar_row]
  inc al
  mov [DrawChar_row],al
  call GetScreenAddr
  pop cx                    ; restore counter and shift
  dec ch
  jnz DrawChar_4
  pop di                    ; restore symbol data addr
  pop bx                    ; restore addr on the screen
  mov al,[L86D7]            ; get penCol
  and al,7                  ; shift 0..7
  mov ah,al
  mov al,[DrawChar_width]
  add al,ah
  cmp al,8                  ; shift + width < 8 ?
  jb DrawChar_fin           ; yes => no need for 2nd pass
; Second pass
  mov al,[L86D7]            ; get penCol
  and al,7                  ; shift 1..7
  sub al,8
  neg al                    ; al = 8 - shift; result is 1..7
  inc al
  mov cl,al
  mov al,[DrawChar_row]
  add al,-10
  mov [DrawChar_row],al
  inc bx
  mov ch,10                 ; 10 lines
DrawChar_8:                 ; loop by lines
  push cx                   ; save counter
  mov al,[di]
  inc di
DrawChar_9:                 ; loop for shift
  dec cl
  jz DrawChar_A
  shl al,1                  ; shift left
  jmp DrawChar_9
DrawChar_A:
  or [bx],al                ; put on the screen
  mov al,[DrawChar_row]
  inc al
  mov [DrawChar_row],al
  call GetScreenAddr
  inc bx
  pop cx                    ; restore counter
  dec ch
  jnz DrawChar_8
; All done, finalizing
DrawChar_fin:
  mov al,[DrawChar_width]
  add [L86D7],al            ; updating penCol
  pop cx
  pop bx
  ret
DrawChar_width:   db 0      ; Saved symbol width
DrawChar_row:     db 0      ; Saved current row number

;----------------------------------------------------------------------------
; Themes and screen output
;----------------------------------------------------------------------------

; Theme colors: 2-bit CGA colors (palette 1: 0=bg, 1=cyan, 2=magenta, 3=white)
Theme_ink:        db 1
Theme_paper:      db 0

ScreenThemeNite:            ; dark/story mode: cyan on black
  mov ax,0x0001             ; ink=cyan, paper=black
  jmp short ScreenTheme_0
ScreenThemeLite:            ; light/game mode: black on white
  mov ax,0x0300             ; ink=black, paper=white
ScreenTheme_0:
  mov [Theme_ink],al
  mov [Theme_paper],ah
  call BuildExpandTable
; Fill the themed area on the CGA screen with paper color
  push es
  mov ax,0xB800
  mov es,ax
  mov al,[Theme_paper]
  mov ah,al
  shl al,1
  shl al,1
  or al,ah
  mov ah,al
  shl al,1
  shl al,1
  shl al,1
  shl al,1
  or al,ah                  ; AL = paper in all 4 pixels
  mov ah,al
  mov bx,AREA_Y
  mov dx,AREA_H
ScreenTheme_1:
  call CgaLineAddr          ; DI = address of line BX
  add di,AREA_X/4
  mov cx,AREA_W/8
  rep stosw
  inc bx
  dec dx
  jnz ScreenTheme_1
  pop es
  ret

; BX = line 0..199; returns DI = CGA address of the line start
CgaLineAddr:
  mov di,bx
  shr di,1
  mov cx,di
  shl di,1
  shl di,1
  add di,cx                 ; *5
  shl di,1
  shl di,1
  shl di,1
  shl di,1                  ; *80
  test bl,1
  jz CgaLineAddr_1
  add di,0x2000             ; odd lines bank
CgaLineAddr_1:
  ret

; Build ExpandTable: 256 words, each is a shadow screen byte expanded to 8 CGA pixels
BuildExpandTable:
  mov di,ExpandTable
  mov al,[Theme_ink]
  mov ah,[Theme_paper]
; Build a 256-word table at DI for ink color AL and paper color AH
BuildExpandTableTo:
  push es
  push cs
  pop es
  mov [BET_ink],al
  mov [BET_paper],ah
  xor dx,dx                 ; DL = source byte
BuildExpandTable_1:
  mov al,dl
  mov cx,8
  xor bx,bx
BuildExpandTable_2:
  shl bx,1
  shl bx,1
  shl al,1                  ; next pixel to carry
  jc BuildExpandTable_ink
  or bl,[BET_paper]
  jmp short BuildExpandTable_n
BuildExpandTable_ink:
  or bl,[BET_ink]
BuildExpandTable_n:
  loop BuildExpandTable_2
  xchg bl,bh                ; first 4 pixels go to the first byte
  mov [di],bx
  add di,2
  inc dl
  jnz BuildExpandTable_1
  pop es
  ret
BET_ink:   db 0
BET_paper: db 0

; Copy shadow screen 24*128=3072 bytes to the CGA screen, expanding 1bpp to 2bpp
ShowShadowScreen:
  push ax
  push bx
  push cx
  push dx
  push si
  push di
  push bp
  push es
  mov ax,0xB800
  mov es,ax
  mov si,ShadowScreen
  mov bx,PLAY_Y
  call CgaLineAddr
  add di,PLAY_X/4
  mov bp,128                ; lines
  call BlitLines
  mov si,SignBuffer         ; DESOLATE sign above the game screen
  mov bx,SIGN_Y
  call CgaLineAddr
  add di,SIGN_X/4
  mov bp,SIGN_H
  call BlitSign
  pop es
  pop bp
  pop di
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; Copy BP lines of 24 shadow bytes at SI to the CGA screen at ES:DI, expanding 1bpp to 2bpp
; DI must be the address of a line start; lines go on in the interlaced order
BlitLines:
  mov dx,di                 ; DX = start of current line
  xor bh,bh
BlitLines_1:
  mov cx,24
BlitLines_2:
  lodsb
  xor ah,ah
  mov bx,ax
  shl bx,1
  mov ax,[ExpandTable+bx]
  stosw
  loop BlitLines_2
  mov di,dx
  test dh,0x20
  jnz BlitLines_odd
  add di,0x2000             ; even => next is odd line
  jmp short BlitLines_3
BlitLines_odd:
  add di,80-0x2000          ; odd => next even line
BlitLines_3:
  mov dx,di
  dec bp
  jnz BlitLines_1
  ret

; Same as BlitLines, but with the fixed white-on-black SignTable
BlitSign:
  mov dx,di
  xor bh,bh
BlitSign_1:
  mov cx,24
BlitSign_2:
  lodsb
  xor ah,ah
  mov bx,ax
  shl bx,1
  mov ax,[SignTable+bx]
  stosw
  loop BlitSign_2
  mov di,dx
  test dh,0x20
  jnz BlitSign_odd
  add di,0x2000
  jmp short BlitSign_3
BlitSign_odd:
  add di,80-0x2000
BlitSign_3:
  mov dx,di
  dec bp
  jnz BlitSign_1
  ret

; Make the DESOLATE sign, like CopyTitleSign in the Vector port: draw the first three tile rows of the
; main menu screen (LF4B5) on the cleared shadow screen, keep SIGN_H lines from line SIGN_SRC in SignBuffer
; (the top and the bottom rules plus the lettering). ShowShadowScreen draws it above the game screen on
; every screen, white on black whatever the theme, so it is never erased.
InitSign:
  mov di,SignTable
  mov al,3                  ; set pixels = color 3 (white), others = color 0 (black)
  xor ah,ah
  call BuildExpandTableTo
  call ClearShadowScreen
  mov bx,LF4B5              ; main menu screen, 12 tiles per row
  xor cx,cx                 ; CH = row, CL = column, in pixels
InitSign_1:
  push bx
  push cx
  mov al,[bx]
  mov bl,al
  dec al
  jz InitSign_2             ; tile 1 is empty
  mov bh,bl
  xor bl,bl
  shr bx,1
  shr bx,1                  ; BX = tile number * 64
  add bx,Tileset2
  mov si,bx
  mov bl,ch                 ; penRow
  mov dl,cl                 ; penCol
  call DrawTileMasked
InitSign_2:
  pop cx
  pop bx
  inc bx
  add cl,16
  cmp cl,12*16
  jne InitSign_1
  xor cl,cl
  add ch,16
  cmp ch,48                 ; 3 tile rows
  jne InitSign_1
  mov si,ShadowScreen+24*SIGN_SRC
  mov di,SignBuffer
  mov cx,24*SIGN_H/2
  rep movsw
  call ClearShadowScreen
  ret

; Clear shadow screen
; 128+10 lines, 24 8px columns; 24 * 138 = 3312 bytes
ClearShadowScreen:
  push ax
  push cx
  push di
  mov di,ShadowScreen
  mov cx,3312/2
  xor ax,ax
  rep stosw
  pop di
  pop cx
  pop ax
  ret

; Clear block on the shadow screen
;   BX=row/col (BH=row, BL=col), DX=rows/cols (DH=rows, DL=cols)
;   columns are 8px wide; row=1..128, row=0..127; col=0..23, cols=1..24
ClearScreenBlock:
  push cx
  mov al,bl                 ; column
  mov cl,bh                 ; row
  xor ch,ch
  mov bl,bh                 ; row
  xor bh,bh
  shl bx,1                  ; now BX = row * 2
  add bx,cx                 ; now BX = row * 3
  shl bx,1
  shl bx,1
  shl bx,1                  ; now BX = row * 24
  mov cl,al
  add bx,cx                 ; now BX = row * 24 + col
  add bx,ShadowScreen       ; now BX = start address
  xor al,al
ClearScreenBlock_1:         ; loop by rows
  push bx
  mov ch,dl                 ; cols
ClearScreenBlock_2:         ; loop by columns
  mov [bx],al
  inc bx
  dec ch
  jnz ClearScreenBlock_2
  pop bx
  add bx,24                 ; next line
  dec dh                    ; rows
  jnz ClearScreenBlock_1
  pop cx
  ret

;----------------------------------------------------------------------------
; Random
;----------------------------------------------------------------------------

; 8-bit random number generator; PIT channel 0 counter replaces the Z80 R register
GetRandomByte:
  mov bx,[GetRandomByte_seed]
  xor al,al
  out 0x43,al               ; latch channel 0 counter
  in al,0x40
  mov ah,al
  in al,0x40                ; high byte, discarded
  mov al,ah
  mov dh,al
  mov dl,al                 ; DX = A,A
  add bx,dx
  xor al,bl
  add al,al
  xor al,bh
  mov bl,al
  mov [GetRandomByte_seed],bx
  ret
GetRandomByte_seed: dw 12345
;
; Get random number 0..7
GetRandom8:
  call GetRandomByte
  and al,7
  ret
;
; Get random number 0..10 for door access codes
; value 10 is for '-' char and we made its probability lower by 1/3
GetRandom11:
  call GetRandomByte
  and al,0x1F               ; 0..31
GetRandom11_1:
  cmp al,11                 ; less than 11?
  jb GetRandom11_ret        ; yes => return 0..10
  sub al,11                 ; 0..20, then 0..9
  jmp GetRandom11_1
GetRandom11_ret:
  ret

;----------------------------------------------------------------------------
; Platform test (PLATFORM_TEST): themes, text, numbers, tiles, keys, beep
;----------------------------------------------------------------------------
%if PLATFORM_TEST
PlatformTest:
  call ScreenThemeNite
PlatformTest_loop:
  call ClearShadowScreen
  mov byte [L86D7],8
  mov byte [L86D8],8
  mov bx,PT_Str1
  call DrawString
  mov byte [L86D7],8
  mov byte [L86D8],24
  mov bx,PT_Str2
  call DrawString
  call ReadKeyboard
  mov [PT_key],al
  mov byte [L86D7],8
  mov byte [L86D8],40
  mov bx,PT_Str3
  call DrawString
  mov bl,[PT_key]
  xor bh,bh
  call DrawNumber3
  mov byte [L86D7],8
  mov byte [L86D8],56
  mov bx,PT_Str4
  call DrawString
  mov byte [L86D7],8
  mov byte [L86D8],68
  mov bx,PT_Str5
  call DrawString
; Masked tiles from Tileset2
  mov si,Tileset2+64*20
  mov bl,100
  mov dl,16
  call DrawTileMasked
  mov si,Tileset2+64*21
  mov bl,100
  mov dl,32
  call DrawTileMasked
  mov si,Tileset2+64*22
  mov bl,108
  mov dl,48
  call DrawTileMasked
  call ShowShadowScreen
  mov al,[PT_key]
  cmp al,9                  ; Enter => stage 1 test
  jne PT_noenter
  call Stage1Test
  call WaitKeyUp
PT_noenter:
  mov al,[PT_key]
  cmp al,5                  ; fire => beep
  jne PT_nofire
  call SoundLookShoot
PT_nofire:
  mov al,[PT_key]
  cmp al,8                  ; switch => toggle theme
  jne PT_noswitch
  cmp byte [Theme_paper],0
  je PT_tolite
  call ScreenThemeNite
  jmp short PT_waitup
PT_tolite:
  call ScreenThemeLite
PT_waitup:
  call WaitKeyUp
PT_noswitch:
  cmp byte [PT_key],7       ; Escape => exit
  jne PlatformTest_loop
  ret
PT_key:  db 0

; Stage 1 test: Tileset1 tiles (L9EAD), sprites (L9EDE) plain and reflected, XOR tile (L9E5F)
; Esc/Enter returns.
Stage1Test:
  call ScreenThemeLite
  call ClearShadowScreen
  mov byte [S1_n],0
S1_tiles:                   ; 2 rows of 12 Tileset1 tiles
  mov al,[S1_n]
  mov ah,0
  mov cl,5
  shl ax,cl                 ; * 32 bytes per tile
  add ax,Tileset1+32*40
  mov si,ax
  mov al,[S1_n]
  mov bl,0
  cmp al,12
  jb S1_t1
  sub al,12
  mov bl,16
S1_t1:
  mov dl,al
  push dx
  call L9EAD
  pop dx
  inc byte [S1_n]
  cmp byte [S1_n],24
  jb S1_tiles
  mov byte [S1_n],0
S1_sprites:                 ; 12 sprites normal (row 36) and reflected (row 52)
  mov bh,[S1_n]
  shl bh,1                  ; column in bytes, 2 per sprite
  mov bl,36
  mov al,[S1_n]
  mov dx,Sprites
  push bx
  call L9EDE
  pop bx
  mov bl,52
  mov al,[S1_n]
  or al,0x80
  mov dx,Sprites
  call L9EDE
  inc byte [S1_n]
  cmp byte [S1_n],12
  jb S1_sprites
; XOR tile: shifts 0..7 across the screen, drawn on row 72; second row drawn twice (must vanish)
  mov byte [S1_n],0
S1_xor:
  mov al,[S1_n]
  mov ah,0
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1                  ; x = n * 16 + ... shift grows because n*16 + n
  add al,[S1_n]
  mov si,Tileset1+32*60
  mov bl,76
  mov ch,16
  call L9E5F
  mov al,[S1_n]
  mov ah,0
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  add al,[S1_n]
  mov si,Tileset1+32*60
  mov bl,100
  mov ch,16
  push ax
  call L9E5F
  pop ax
  mov si,Tileset1+32*60
  mov bl,100
  mov ch,16
  call L9E5F                ; second draw: erases the first one
  inc byte [S1_n]
  cmp byte [S1_n],8
  jb S1_xor
  mov byte [L86D7],8
  mov byte [L86D8],114
  mov bx,S1_Str
  call DrawString
  call ShowShadowScreen
  call WaitAnyKey
  call ScreenThemeNite
  ret
S1_n:   db 0
S1_Str: db "TILES SPRITES XOR GAP=OK",0
PT_Str1: db "DESOLATE ON PC 8088 CGA",0
PT_Str2: db "ARROWS SPACE I S M TAB ESC",0
PT_Str3: db "KEY CODE ",0
PT_Str4: db "S THEME, SPACE BEEP",0
PT_Str5: db "ENTER: STAGE 1 TEST",0
%endif

;----------------------------------------------------------------------------

DesolateStrsBeg:
%include "desolstrs.asm"

DesolateFontBeg:
%include "desolfont.asm"

DesolateDataBeg:
%include "desoldata.asm"

;----------------------------------------------------------------------------
DesolateCodeBeg:
%include "desolcodb.asm"
DesolateCodeEnd:

;----------------------------------------------------------------------------
; Uninitialized data, not stored in the .COM file
section .bss
; Shadow screen, 192 x 140 pixels
;   12*2*(64*2+12) = 3360 bytes
ShadowScreen:   resb 3360
ExpandTable:    resw 256
SignBuffer:     resb 24*SIGN_H
SignTable:      resw 256
KeyState:       resb 128
KeyLatch:       resb 128
