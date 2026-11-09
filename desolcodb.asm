;
; Desolate for PC (8088, CGA) -- game code.
; Port of desolcodb.asm from the ZX Spectrum version, translated in stages.
; Register map: see the header of desolcoda.asm (A=AL, BC=CX, DE=DX, HL=BX, IX=SI).
;
; Ported so far:
;   Stage 1: tile and sprite blitters (L9E5F, L9EAD, L9EDE), ReflectByte
;   Stage 2: titles, main menu, Info, Credits, text output
;   Stage 3: New Game, story screens, popups
;   Stage 4: main game loop, room display, player, movement, health, look/shoot switch
;   Stage 5: aliens, shooting, damage, look/shoot key
;   Stage 6a: look action - doors, door lock, dead bodies, items, weapon
;   Stage 6b: Inventory, using items, terminals, the ending (Pod flight, statistics)
; Not ported yet (kept out of the build): main game loop L9DDD, L9E51 (original lines 1-60),
;   and everything after ReflectByte / ClearShadowScreen (ClearShadowScreen lives in desolcoda.asm)
;

; Put tile on the screen (NOT aligned to 8px column), 16x16 -> 16x16 on shadow screen
; Uses XOR operation so it is revertable.
;   BL = row; AL = X coord; CH = height; SI = tile address
L9E5F:
  xor bh,bh
  mov di,bx
  shl bx,1                  ; now BX = L * 2
  add bx,di                 ; now BX = L * 3
  shl bx,1
  shl bx,1
  shl bx,1                  ; now BX = L * 24
  mov cl,al
  and cl,0x07               ; CL = offset within 8px column
  shr al,1
  shr al,1
  shr al,1                  ; AL = number of 8px column
  xor ah,ah
  add bx,ax                 ; now BX = offset on the shadow screen
  add bx,ShadowScreen       ; BX = address in the shadow screen
L9E8D:                      ; loop by CH - by rows
  push cx
  mov ah,[si+0x01]          ; Z80: B
  mov dh,[si+0x00]          ; Z80: D
  xor dl,dl                 ; Z80: E
  mov al,cl
  or al,al                  ; shift = 0?
  jz L9E9D                  ; yes => skip all shift ops
L9E96:
  shr ah,1
  rcr dh,1
  rcr dl,1
  dec al
  jnz L9E96
L9E9D:
  xor [bx],dh               ; put byte on the screen
  inc bx
  xor [bx],dl               ; put byte on the screen
  xor [bx],ah               ; put byte on the screen
  add bx,24-1               ; to the next line
  inc si
  inc si
  pop cx
  dec ch
  jnz L9E8D                 ; continue loop by rows
  ret

; Put background tile on the screen, 16x16 -> 16x16 on shadow screen, no mask
;   BL = row; DL = tile column 0..11; SI = tile address
L9EAD:
  mov al,dl
  shl al,1
  shl al,1
  shl al,1
  shl al,1
  mov [L86D7],al            ; penCol
  mov al,bl                 ; penRow
  mov ch,8                  ; 8 row pairs
  call GetScreenAddr        ; now BX = screen addr
  mov di,bx                 ; now DI = shadow screen address, SI = tile address
L9EAD_1:
; Draw 1st line
  movsw                     ; copy 2 bytes
  add di,24-2               ; to the 2nd line
; Draw 2nd line
  movsw                     ; copy 2 bytes
  add di,24-2               ; to the next line
; Continue the loop
  dec ch
  jnz L9EAD_1
  ret

; Draw sprite
;   DX = sprite address; BH = column; BL = row
;   AL = bits 0..5 - sub-sprite ; bit7=1 - reflect horz (was: bit6=1 - reflect vert)
L9EDE:
  push bx
  push ax
  and al,0x3F
  xor ah,ah
  mov cl,6
  shl ax,cl                 ; now AX = sprite number * 64
  add ax,dx                 ; now AX = source sprite address
  mov si,ax
  mov di,L9FAF              ; DI = buffer address
  mov cx,64
  rep movsb
  pop ax
  test al,0x80
  jz L9EDE_nr
  call L9EDE_HR             ; Reflect sprite horizontally
L9EDE_nr:
  mov si,L9FAF
  pop bx
  mov al,bh                 ; column
  xor bh,bh
  mov cx,bx                 ; get row
  add bx,cx
  add bx,cx                 ; now BX = row * 3
  shl bx,1
  shl bx,1
  shl bx,1                  ; now BX = row * 24
  mov cl,al                 ; CX = column (CH is 0 as row < 256)
  add bx,cx                 ; now BX = offset on the shadow screen
  add bx,ShadowScreen
  mov ch,8                  ; 8 line pairs
  jmp DrawTileMasked_1      ; same loop as for the masked tile
; Horizontal reflection
L9EDE_HR:
  push ax
  mov si,L9FAF
  mov ch,16
L9EDE_HR_1:
; Exchange bytes 0 <-> 2
  mov al,[si+0x00]
  mov cl,[si+0x02]
  call ReflectByte
  mov [si+0x02],al
  mov al,cl
  call ReflectByte
  mov [si+0x00],al
; Exchange bytes 1 <-> 3
  mov al,[si+0x01]
  mov cl,[si+0x03]
  call ReflectByte
  mov [si+0x03],al
  mov al,cl
  call ReflectByte
  mov [si+0x01],al
  add si,4
  dec ch
  jnz L9EDE_HR_1
  pop ax
  ret
;
L9FAF:                      ; Sprite buffer
  times 64 db 0
;
; Reflect byte bits of AL; preserves CX
ReflectByte:
  push cx
  mov cl,8
ReflectByte_1:
  shl al,1                  ; bit 7 to carry
  rcr ch,1                  ; ... and to the result, from the top
  dec cl
  jnz ReflectByte_1
  mov al,ch
  pop cx
  ret

; Copy shadow screen to the CGA screen
;
L9FEA EQU ShowShadowScreen

;----------------------------------------------------------------------------
; Stage 2: titles, main menu, Info (controls), Credits, text output
;   (original labels kept; not-yet-ported menu targets are stubs)
;----------------------------------------------------------------------------

; Scan keyboard
; Returns key in AL; Z=0 for key, Z=1 for no key. Preserves everything but AX.
LA0F1:
  jmp ReadKeyboard

; Delay by LDC59.
; Spectrum: ~F*F/250 ms (busy loop). Here: the same time in 60 Hz frames, rounded.
;   frames = (3 * F*F + 6250) / 12500; F=0 means 256. Preserves all registers.
LB2D0:
  push ax
  push bx
  push cx
  push dx
  mov al,[LDC59]            ; get delay factor
  xor ah,ah
  or al,al
  jnz LB2D0_1
  mov ah,1                  ; 0 => 256
LB2D0_1:
  mul ax                    ; DX:AX = F*F
  mov bx,dx
  mov cx,ax                 ; BX:CX = F*F
  add ax,cx
  adc dx,bx
  add ax,cx
  adc dx,bx                 ; DX:AX = 3 * F*F
  add ax,6250
  adc dx,0
  mov cx,12500
  div cx                    ; AX = frames
  mov cx,ax
  jcxz LB2D0_3
LB2D0_2:
  call WaitVSync
  loop LB2D0_2
LB2D0_3:
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; Wait for Escape key
LADA1:
  call LA0F1                ; Scan keyboard
  cmp al,0x07               ; Escape key?
  jne LADA1
  ret

; Get address from table
;   AL = Element number
;   BX = Table address
; Returns BX = address from the table
LADFF:
  xor ah,ah
  shl ax,1
  add bx,ax
  mov bx,[bx]
  ret

; Decode 96 bytes of the screen to LDBF5
;   BX = decode from
LADEE:
  mov cx,0x0060             ; decode 96 bytes
; Decode the room/screen to LDBF5
;   BX = decode from; CX = tile count to decode
;   Returns: BX = LDBF5
LADF5:
  mov dx,LDBF5              ; Decode to
  call LB9F1                ; Decode the room/screen
  mov bx,LDBF5
  ret

; Decode the block from RLE sequence
;   BX = address decode from (usually encoded room/screen)
;   DX = address decode to
;   CX = number of bytes to decode
LB9F1:
  mov si,bx
  mov di,dx
LB9F1_1:
  mov al,[si]
  cmp al,0xFF               ; repeater?
  je LB9FB
  movsb
  dec cx
LB9F8:
  jcxz LB9F1_ret            ; Z80: RET PO (BC = 0)
  jmp LB9F1_1
LB9F1_ret:
  ret
LB9FB:
  inc si
  mov al,[si]               ; repeat count
  inc si
  mov ah,[si]               ; value to repeat
  inc si
LB9FF:
  mov [di],ah
  inc di
  dec cx
  dec al
  jnz LB9FF
  jmp LB9F8

; Display 96 tiles on the screen
;   BX = Address where the 96 tiles are placed
LA88F:
  xor dx,dx                 ; DH = row in pixels, DL = column in tiles
LA892:
  push bx
  push dx
  mov bl,[bx]               ; get tile number
  mov al,bl
  or al,al                  ; empty tile?
  jz LA8B0                  ; yes => skip it
  cmp al,0x47               ; menu background tile?
  jne LA892_1
  call LBC29                ; yes => add phase to L
LA892_1:
  xor bh,bh
  mov cl,5
  shl bx,cl                 ; now BX = tile number * 32
  add bx,Tileset1
  mov si,bx
  mov bl,dh                 ; row
  call L9EAD                ; Put background tile on the screen
LA8B0:
  pop dx
  pop bx
  inc bx
  inc dl                    ; next column
  cmp dl,0x0C               ; was last column?
  jne LA892                 ; no => continue loop by columns
  mov dl,0x00
  add dh,0x10               ; next tile row
  cmp dh,0x80               ; was last tile row?
  jne LA892                 ; no => continue loop by tile rows
  ret

; Display screen from tiles with Tileset2
;   BX = Screen in tiles, usually LDBF5
LB177:
  xor cx,cx                 ; CH = row, CL = column, in pixels
LB177_0:
  push bx
  push cx
  mov al,[bx]
  mov bl,al
  dec al
  jz LB177_1                ; tile 1 is empty
  xor bh,bh
  mov cl,6
  shl bx,cl                 ; * 64
  add bx,Tileset2
  mov si,bx
  mov bp,sp
  mov cx,[bp]               ; restore CX = coordinates (CL was used above)
  mov bl,ch                 ; penRow
  mov dl,cl                 ; penCol
  call DrawTileMasked
LB177_1:
  pop cx
  pop bx
  inc bx
  add cl,16
  cmp cl,12*16
  jne LB177_0
  xor cl,cl
  add ch,16
  cmp ch,16*8
  jne LB177_0
  ret

; Add menu background phase 0..7 to L
LBC29:
  mov al,[LDC55]            ; get Menu background phase
  add al,bl
  mov bl,al
  ret

; Delay x40
LBA81:
  call LBC34                ; Delay x20
; Delay x20
LBC34:
  mov ch,0x14               ; x20
LBC36:
  call LB2D0                ; Delay
  dec ch
  jnz LBC36
  ret

; Clear shadow screen and copy to the screen
LBC7D:
  call ClearShadowScreen
  jmp ShowShadowScreen      ; Copy shadow screen to the screen

; Set zero penRow/penCol
ClearPenRowCol:
LBC84:
  xor bx,bx                 ; Left-top corner
  mov [L86D7],bx            ; Set penRow/penCol
  ret

; Generate random access code
;   BX = 4-byte buffer address
LBC6B:
  mov ch,0x04
LBC6D:
  push cx
  push bx
  call GetRandom11          ; Generate random number 0..10
  add al,0x1A               ; tile number for '0'
  pop bx
  mov [bx],al
  inc bx
  pop cx
  dec ch
  jnz LBC6D                 ; continue the loop
  ret

; Draw string on the screen
;   BX = String address
LBEDE:
  mov al,[bx]
  inc bx
  or al,al
  jz LBEDE_ret
  cmp al,0x7C               ; '|' - line end ?
  je LBF1B                  ; yes => process line end
  push bx
  call DrawChar
  mov al,[LDC85]            ; get Delay and copy screen flag
  or al,al
  jz LBEF9_1                ; Skip delay and copy screen
  call LB2D0                ; Delay
  call ShowShadowScreen     ; Copy shadow screen to the screen
LBEF9_1:
  pop bx
  jmp LBEDE
LBF1B:                      ; Line end
  push cx
  mov al,[L86D8]            ; Get penRow
  mov cl,al
  mov al,[LDCF4]            ; Line interval for text
  add al,cl
  mov [L86D8],al            ; Set penRow
  mov al,[LDCF3]            ; Get left margin size for text
  mov [L86D7],al            ; Set penCol
  pop cx
  jmp LBEDE
LBEDE_ret:
  ret

; Show titles and show Menu
LBA07:
  mov al,0x44
  mov [LDC59],al            ; set delay factor
  mov [LDC85],al            ; Use delay and copy screen in LBEDE
  mov bx,0x3A1E
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE09D              ; "MaxCoderz Presents"
  call LBEDE                ; Show message char-by-char
  call LBA81                ; Delay x40
  call LBC7D                ; Clear shadow screen and copy to the screen
  call LBC34                ; Delay x20
  mov bx,0x3A2E
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE09F              ; "a tr1p1ea game"
  call LBEDE                ; Show message char-by-char
  call LBA81                ; Delay x40
  call LBC7D                ; Clear shadow screen and copy to the screen
  call LBC34                ; Delay x20
  xor al,al
  mov [LDC85],al            ; Skip delay and copy screen in LBEDE
  call ScreenThemeLite      ; switching to the light theme on Main Menu
  jmp LBA3D                 ; Return to Menu

MenuFromGame:
  mov al,0x3A+12            ; "Continue" menu item
  mov [LDB8F],al            ; set Menu Y pos
;
; Return to Menu
;
LBA3D:
  mov al,[LDC55]            ; get Menu background phase
  inc al
  and al,0x07
  mov [LDC55],al            ; set Menu background phase
  mov bx,LF515              ; Main menu screen moving background, 96 tiles
  call LA88F                ; Display 96 tiles on the screen
  mov bx,LF4B5              ; Main menu screen
  call LB177                ; Display screen from tiles with Tileset 2
  mov cl,0x0B               ; left triangle X pos
  mov si,Tileset3           ; Tile arrow right
  call LBA88                ; Draw menu item selection triangle
  mov cl,0x4D               ; right triangle X pos
  mov si,Tileset3+32        ; Tile arrow left
  call LBA88                ; Draw menu item selection triangle
  call ShowShadowScreen     ; Copy shadow screen to the screen
  call LA0F1                ; Scan keyboard
  cmp al,0x05               ; look/shoot key
  jzl LBA93                 ;   select menu item
  cmp al,0x09               ; Enter key
  jzl LBA93                 ;   select menu item
  cmp al,0x04               ; Up key
  jzl LBBCC
  cmp al,0x01               ; Down key
  jzl LBBDC
  inc byte [GetRandomByte_seed] ; Change random seed
  jmp LBA3D                 ; Return to main Menu

; Draw menu item selection triangle
LBA88:
  mov al,[LDB8F]            ; get Menu Y pos
  mov bl,al                 ; BL = Y coord
  mov al,cl                 ; AL = X coord
  mov ch,10                 ; CH = tile height
  jmp L9E5F                 ; Draw tile by XOR operation

; Select on Menu item
LBA93:
  call SoundLookShoot
  mov al,[LDB8F]            ; get Menu Y pos
  cmp al,0x3A
  jzl LBAB2                 ; New menu item
  cmp al,0x46
  jzl LBB82                 ; Continue menu item
  cmp al,0x52
  jzl LBBEC                 ; Info menu item
  cmp al,0x5E
  jzl LBF64                 ; Credits menu item
  cmp al,0x6A
  jzl L9E51                 ; Quit menu item
  jmp LBA3D                 ; Return to main Menu

; Menu up step
LBB92:
  mov al,[LDB73]
  or al,al                  ; do we have the game to continue?
  jnz LBBA4
  mov al,[LDB8F]            ; get Menu Y pos
  add al,-24                ; up two steps
  mov [LDB8F],al            ; set Menu Y pos
  jmp LBA3D                 ; Return to main Menu
LBBA4:
  mov al,[LDB8F]            ; get Menu Y pos
  add al,-12                ; up one step
  mov [LDB8F],al            ; set Menu Y pos
  jmp LBA3D                 ; Return to main Menu
LBBAF:
  mov al,[LDB73]
  or al,al                  ; do we have the game to continue?
  jnz LBBC1
  mov al,[LDB8F]            ; get Menu Y pos
  add al,24                 ; down two steps
  mov [LDB8F],al            ; set Menu Y pos
  jmp LBA3D                 ; Return to main Menu
; Menu down step
LBBC1:
  mov al,[LDB8F]            ; get Menu Y pos
  add al,12                 ; down one step
  mov [LDB8F],al            ; set Menu Y pos
  jmp LBA3D                 ; Return to main Menu
; Menu up key pressed
LBBCC:
  mov al,[LDB8F]            ; get Menu Y pos
  cmp al,0x3A               ; "New Game" selected?
  jzl LBA3D                 ; yes => continue
  cmp al,0x52               ; "Info" selected?
  je LBB92
  jmp LBBA4
; Menu down key pressed
LBBDC:
  mov al,[LDB8F]            ; get Menu Y pos
  cmp al,0x6A               ; "Quit" selected?
  jzl LBA3D
  cmp al,0x3A               ; "New Game" selected?
  je LBBAF
  jmp LBBC1

; Quit menu item selected: leave the program (back to DOS)
L9E51:
  jmp ExitProgram

; Info menu item, show Controls
LBBEC:
  mov bx,LF329              ; Encoded screen for Inventory/Info popup
  call LADEE                ; Decode 96 bytes of the screen to LDBF5
  call LB177                ; Display screen from tiles with Tileset 2
  mov al,10
  mov [LDCF3],al            ; Left margin size for text
  mov al,14
  mov [LDCF4],al            ; Line interval for text
  mov bx,0x163C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0A5              ; "- Controls -"
  call DrawString           ; Show message
  mov bx,0x240A
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0A7              ; "Arrows: Move ..." controls text
  call LBEDE                ; Show message char-by-char
  call ShowShadowScreen     ; Copy shadow screen to the screen
  call LADA1                ; Wait for Escape key
  jmp LBA3D                 ; Return to Menu

; Set variables for Credits
LBF54:
  xor al,al
  mov [LDD57],al            ; clear Credits line number
  mov [LDD56],al            ; clear Credits counter within one line
  mov [LDC85],al            ; Skip delay and copy screen in LBEDE
  mov al,0x96
  mov [LDC59],al            ; set delay factor
  ret

; Credits menu item selected
LBF64:
  call WaitKeyUp            ; (PC) do not exit at once on the held select key
  call LBC7D                ; Clear and show shadow screen
  call ScreenThemeNite      ; switching to dark theme for Credits
  call LBF54                ; Set variables for Credits
  jmp LBF81                 ; Credits screen text scrolls up

; The End
LBF6F:
  call LBC7D                ; Clear and show shadow screen
  call ScreenThemeNite      ; switching to dark theme for End and Credits
  call LBF54                ; Set variables for Credits
  mov bx,0x2E46
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE11F              ; "The End"
  call LBEDE                ; Show message char-by-char
; Credits screen text scrolls up
LBF81:
  mov al,126                ; To draw new strings on the very bottom
  mov [L86D8],al            ; Set penRow
LBF686:
  jmp LBF6F_4
LBF6F_2:
  call ShowShadowScreen     ; Copy shadow screen to the screen
LBF6F_3:
  call LA0F1                ; Scan keyboard
  jnzl Credits_exit         ; any key pressed => Return to main Menu
  call LBFD5                ; Scroll shadow screen up one line
LBF6F_4:
  mov al,[LDD56]
  inc al                    ; increase counter within the line
  mov [LDD56],al
  cmp al,12                 ; last line of the current string?
  je Credits_5              ; yes => jump
  call LB2D0                ; Delay
  jmp LBF6F_2               ; continue the Credits loop
Credits_5:
  xor al,al
  mov [LDD56],al            ; clear counter within the line
  mov al,[LDD57]
  xor ah,ah
  mov bx,LDDF2              ; Table of left margins for Credits strings
  add bx,ax
  mov al,[bx]               ; now AL = left margin for the string
  mov [L86D7],al            ; Set penCol
  mov al,[LDD57]            ; get Credits line number
  mov bx,LDD58              ; Table of Credits strings
  call LADFF                ; Get address from table by index AL
  call DrawString           ; Draw string on shadow screen without any delays
  mov al,[LDD57]
  inc al                    ; increase the Credits line counter
  mov [LDD57],al
  cmp al,0x49
  jne LBF6F_3
  call LBA81                ; Delay x40 - added to have a pause after the last line
Credits_exit:
  call LBC7D                ; Clear and show shadow screen
  call ScreenThemeLite      ; switching to light theme for Main Menu
  jmp LBA3D                 ; Return to main Menu
; Scroll shadow screen up 1px
LBFD5:
  mov di,ShadowScreen
  mov si,ShadowScreen+24
  mov cx,137*24
  rep movsb
  ret

;----------------------------------------------------------------------------
; Stage 3: New Game, story screens, popups, player variables
;----------------------------------------------------------------------------

; Show small message popup. Preserves CX, DX.
LAB28:
  push cx
  push dx
  mov bx,LEB27              ; Decode from: Small message popup
  call LADEE                ; Decode 96 bytes of the screen to LDBF5
  call LB177                ; Display screen from tiles with Tileset2
  pop dx
  pop cx
  ret

LB925:
  mov al,14
  mov [LDCF3],al            ; Left margin size for text
  mov al,14
  mov [LDCF4],al            ; Line interval for text
  ret

; Clear player variables
;   AL = room number and direction
LB9D6:
  mov [LDB79],al            ; set the room number
  mov [LDB75],al            ; Direction/orientation
  mov al,0x06
  mov [LDB76],al            ; set X tile coord = 6
  mov al,0x30
  mov [LDB77],al            ; set Y pixel coord = 48
  mov al,0x03
  mov [LDB78],al            ; set Y tile coord = 3
  mov al,0x64
  mov [LDB7A],al            ; set Health = 100
  ret

; New menu item selected
LBAB2:
  mov al,[LDB73]
  or al,al                  ; do we have current game?
  jzl LBADE                 ; no => New Game
  call LB925
  call LAB28                ; Show small message popup
  mov bx,0x580E
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0A3              ; "OverWrite Current Game? Enter - Yes :: M - No"
  call LBEDE                ; Show message char-by-char
  call ShowShadowScreen     ; Copy shadow screen to the screen
LBACE:
  call LA0F1                ; Scan keyboard
  cmp al,0x0F               ; Menu button?
  jzl LBA3D                 ; yes => return to Menu
  cmp al,0x09               ; Enter?
  je LBADE                  ; yes => New Game
  jmp LBACE                 ; wait some more

; New Game
LBADE:
  xor al,al
  mov [LDCF7],al            ; clear Weapon slot
  mov [LDB7D],al            ; set look/shoot switch value = Look
  mov [LDBC7],al            ; clear Items Found count
  call LB9D6                ; Clear player variables
  xor ax,ax
  mov [LDBC3],ax            ; clear Player deaths count
  mov [LDBC5],ax            ; clear Aliens Killed count
  mov di,LDB9C              ; Inventory table address
  mov cx,0x22               ; 34 bytes
  rep stosb
  mov di,LDC5B              ; Inventory list
  mov cx,0x22               ; 34 bytes
  rep stosb
  mov di,LDB90
  mov cx,0x09               ; 9 variables to clear
  rep stosb
  mov di,LDCA2              ; Table with Access code slots
  mov cx,0x48               ; 72 bytes
  rep stosb
  mov di,DoorLockLevelEntered+1
  mov cx,4                  ; Clear 4 flags
  rep stosb
  mov bx,LDC96              ; level 2 access code buffer
  call LBC6B                ; Generate random code
  mov bx,LDC9A              ; level 3 access code buffer
  call LBC6B                ; Generate random code
  mov bx,LDC9E              ; level 4 access code buffer
  call LBC6B                ; Generate random code
  call LBC7D                ; Clear shadow screen and copy to the screen
  call ScreenThemeNite      ; switching to dark theme for story mode
  mov al,0x44
  mov [LDC59],al            ; set delay factor
  mov [LDC85],al            ; Use delay and copy screen in LBEDE
  mov al,14
  mov [LDCF4],al            ; set Line interval for text
  xor al,al
  mov [LDCF3],al            ; clear Left margin size for text
  mov bx,0x3A14
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE115              ; "In the Distant Future . . ."
  call LBEDE                ; Show message char-by-char
  call LBA81                ; Delay x40
  call LBC7D                ; Clear shadow screen and copy to the screen
  call LBA81                ; Delay x40
  call LBC84                ; Set zero penRow/penCol
  mov bx,SE117              ; "'The Desolate' Space Cruiser leaves orbit. ...
  call LBEDE                ; Show message char-by-char
  mov bx,0x72B6
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0B9              ; String with arrow down sign
  call LBEDE                ; Show message char-by-char
  call WaitAnyKey           ; Wait for any (was: Wait for Down key)
  call ClearShadowScreen
  call LBC84                ; Set zero penRow/penCol
  mov bx,SE119              ; "The ship sustains heavy damage. ...
  call LBEDE                ; Show message char-by-char
  call WaitAnyKey           ; Wait for any key (was: Wait for MODE key)
;
; Game start
;
LBB7E:
  xor al,al
  mov [LDC85],al            ; Skip delay and copy screen in LBEDE
; Continue menu item selected
LBB82:
  call LBC7D                ; Clear shadow screen and copy to the screen
  call ScreenThemeLite      ; switching to light theme opening the game screen
  mov al,0x01
  mov [LDB73],al
  mov al,0xFF
  mov [LDC59],al            ; set delay factor
  call LB2D0                ; Delay
  jmp L9DDD                 ; go to the main game loop

;----------------------------------------------------------------------------
; Stage 4: main game loop, room display, player, movement, health, look/shoot switch
;----------------------------------------------------------------------------

; Game main loop
;
L9DDD:
  mov al,[LDB7A]            ; Get Health
  or al,al
  jzl LB9A2                 ; zero => Player is dead
;
  xor al,al                 ; black
  call SetBorderColor       ; set border color
;
  call LADE5                ; Decode current room to LDBF5; BX = LDBF5
  call LA88F                ; Display 96 tiles on the screen
  call LB96B                ; Display Health
  call LB8EA                ; Show look/shoot selection indicator
  call LB76B                ; Process shoot
  call LB551                ; Process Alien in the room
  call LA0F1                ; Scan keyboard
  cmp al,0x0F               ; Menu key?
  jzl MenuFromGame          ;   Return to main Menu
  cmp al,0x04               ; Up key?
  jzl LA99B
  cmp al,0x01               ; Down key?
  jzl LA966
  cmp al,0x02               ; Left key?
  jzl LA9EB
  cmp al,0x03               ; Right key?
  jzl LAA1A
  jmp LA8C6                 ; Draw the Player, then go to the Ending of main game loop
;
; Ending of main game loop
L9E19:
  call LB653                ; Draw Alien
  call LA0F1G               ; Scan keyboard (Enter = look/shoot key)
  cmp al,0x05               ; Look/shoot key?
  jzl LAAAF                 ;   Look / Shoot
  cmp al,0x08               ; Switch key?
  jzl LB930                 ;   Look / Shoot Mode
  cmp al,0x06               ; Inventory key?
  jzl LB0A2                 ;   Open the Inventory
%if DEBUG_NEXT_ROOM
  cmp al,0x07               ; DEBUG: Esc/Tab = next room, and give the weapon
  jzl DebugNextRoom
  cmp al,0x0A               ; DEBUG: E = jump to the ending
  jzl LBD85
  cmp al,0x0B               ; DEBUG: A = all items and access codes
  jzl DebugAll
%endif
; Show the screen, continue the game main loop
L9E2E:
  call ShowShadowScreen     ; Copy shadow screen to the screen
  jmp L9DDD                 ; continue main game loop

; Show screen and wait for Escape key
LAD8C:
  call ShowShadowScreen     ; Copy shadow screen to the screen
LAD8F:
  call LA0F1                ; Scan keyboard
  cmp al,0x07               ; Escape key?
  jne LAD8F
  jmp L9E2E                 ; Show the screen, continue the game main loop

; Decode current room to LDBF5
;   Returns: BX = LDBF5
LADE5:
  mov al,[LDB79]            ; Get the room number
  mov bx,LDE97              ; List of encoded room addresses
  call LADFF                ; now BX = encoded room address
  jmp LADEE                 ; Decode 96 bytes to LDBF5

; Decode current room description to LDBF5
;   Returns: BX = LDBF5
LAE09:
  mov al,[LDB79]            ; Get room number
  mov bx,LDF27              ; Table of adresses for room descriptions
  call LADFF                ; Get address from table by index AL
  mov cx,0x0031             ; decode 49 bytes
  jmp LADF5                 ; Decode the room/screen to LDBF5

; Draw the Player
LA8C6:
  xor al,al
  mov [LDD54],al            ; clear animation phase
;
; Draw Player tiles
LA8CD:
  mov cl,0x00
  mov al,[LDD55]            ; get shooting flag
  or al,al                  ; shooting animation?
  jz LA8DF                  ; no => jump
  mov bx,LDE87              ; Table with Player's tile numbers
  mov al,[LDB75]            ; Direction/orientation
  add al,al
  add al,al                 ; now AL = Direction * 4
  jmp short LA8E9
LA8DF:                      ; Shooting animation
  mov bx,LDE47              ; Table with Player's tile numbers
  mov al,[LDB75]            ; Direction/orientation
  add al,al
  add al,al
  add al,al
  add al,al                 ; now AL = Direction * 16
LA8E9:
  mov dl,al
  xor dh,dh
  add bx,dx
  mov al,[LDD54]            ; get animation phase
  add al,al
  add al,al                 ; now AL = phase * 4
  mov dl,al
  xor dh,dh
  add bx,dx
  mov ch,0x04               ; 4 tiles
LA8F8:                      ; loop by CH
  push bx
  mov bl,[bx]               ; get sprite number
  mov bh,bl
  xor bl,bl
  shr bx,1
  shr bx,1                  ; BX = sprite number * 64
  add bx,Sprites
  mov dx,bx                 ; DX = tile address
  call LA92E
  push cx
  call LA956                ; if looking left - set CL bit7=1 to reflect tile horizontal
  mov al,cl                 ; use CL as draw flags
  call L9EDE                ; Draw tile DX at column BH row BL
  pop cx
  pop bx
  inc bx
  dec ch
  jnz LA8F8                 ; continue loop by tiles
  mov al,[LDD54]            ; get animation phase 0..3
  cmp al,0x03               ; was last phase?
  je LA927                  ; yes => jump
  inc al                    ; next phase
  mov [LDD54],al            ; set animation phase
  xor al,al
  mov [LDD55],al            ; clear shooting flag for player's animation
  jmp L9E19                 ; Go to ending of main game loop
LA927:
  xor al,al
  mov [LDD54],al            ; clear animation phase
  jmp L9E19                 ; Go to ending of main game loop

; Calculate position for tile number CL (after increment): BH = column, BL = row
LA92E:
  inc cl
  mov al,[LDB76]            ; get X coord in tiles
  add al,al                 ; now coord in 8px columns
  mov bh,al
  mov al,[LDB77]            ; get Y coord in lines
  sub al,16
  mov bl,al
  mov al,cl
  cmp al,0x01
  je LA92E_ret
  cmp al,0x02
  jne LA94C
LA941:
  mov al,[LDB75]            ; Direction/orientation
  cmp al,0x02               ; left?
  je LA94A
  inc bh                    ; right
  inc bh
  ret
LA94A:
  dec bh                    ; left
  dec bh
  ret
LA94C:
  mov al,16
  add al,bl
  mov bl,al
  mov al,cl
  cmp al,0x04
  je LA941
LA92E_ret:
  ret

LA956:
  mov cl,0x00
  mov al,[LDB75]            ; Direction/orientation
  or al,al                  ; down?
  jz LA956_ret
  cmp al,0x01               ; up?
  je LA956_ret
  cmp al,0x03               ; right?
  je LA956_ret
  mov cl,0x80               ; looking left => reflect the tile horizontal
LA956_ret:
  ret

; Move Down
LA966:
  mov al,[LDB75]            ; Direction/orientation
  or al,al                  ; down?
  jz LA97C
  mov al,[LDB7D]            ; Get look/shoot switch value
  cmp al,0x01               ; shoot mode?
  jne LA97C
  xor al,al                 ; down
  mov [LDB75],al            ; set Direction/orientation
  jmp LA8C6                 ; Proceed to Draw the Player
LA97C:
  xor al,al                 ; down
  mov [LDB75],al            ; set Direction/orientation
  call LAA60                ; get byte from the room after movement
  cmp al,0x01               ; free block?
  jnzl LA8CD
  mov al,[LDB77]            ; get Y pixel coord
  push ax
  add al,16                 ; Down one tile
  mov [LDB77],al            ; set Y pixel coord
  mov al,[LDB78]            ; get Y tile coord
  push ax
  inc al                    ; down one tile
  mov [LDB78],al            ; set Y tile coord
  jmp short LA9D1

; Move Up
LA99B:
  mov al,[LDB75]            ; Direction/orientation
  cmp al,0x01               ; up?
  je LA9B3
  mov al,[LDB7D]            ; Get look/shoot switch value
  cmp al,0x01               ; shoot mode?
  jne LA9B3
  mov al,0x01               ; up
  mov [LDB75],al            ; Direction/orientation
  jmp LA8C6                 ; Proceed to Draw the Player
LA9B3:
  mov al,0x01               ; up
  mov [LDB75],al            ; Direction/orientation
  call LAA60                ; get byte from the room after movement
  cmp al,0x01
  jnzl LA8CD
  mov al,[LDB77]            ; get Y pixel coord
  push ax
  add al,-16                ; Up one tile
  mov [LDB77],al            ; set Y pixel coord
  mov al,[LDB78]            ; get Y tile coord
  push ax
  dec al                    ; up one tile
  mov [LDB78],al            ; set Y tile coord
; Moved down or up, check for Alien
LA9D1:
  mov al,[LDB84]            ; Alien still alive?
  or al,al
  jz LA9E6                  ; dead => jump
  call LB72E                ; Get value at offset $2F in the room description
  or al,al                  ; do we have the alien?
  jz LA9E6                  ; we don't have it => jump
; We have an alien in the room
  call LB74C
  or al,al                  ; Alien in the same cell as Player?
  jzl LB07B                 ; yes => Decrease Health by 4, restore Y coord
LA9E6:
  pop ax
  pop ax
  jmp LA8CD

; Move Left
LA9EB:
  mov al,[LDB75]            ; Direction/orientation
  cmp al,0x02               ; looking left already?
  je LAA03                  ; yes => jump
  mov al,[LDB7D]            ; Get look/shoot switch value
  cmp al,0x01               ; shoot mode?
  jne LAA03                 ; no => jump
  mov al,0x02               ; left
  mov [LDB75],al            ; set Direction/orientation
  jmp LA8C6                 ; Proceed to Draw the Player
LAA03:
  mov al,0x02               ; left
  mov [LDB75],al            ; set Direction/orientation
  call LAA60                ; get byte from the room after movement
  cmp al,0x01
  jnzl LA8CD
  mov al,[LDB76]            ; get X coord in tiles
  push ax
  dec al                    ; one tile left
  mov [LDB76],al            ; set X coord in tiles
  jmp short LAA47           ; go to Alien check

; Move Right
LAA1A:
  mov al,[LDB75]            ; Direction/orientation
  cmp al,0x03               ; right?
  je LAA32
  mov al,[LDB7D]            ; Get look/shoot switch value
  cmp al,0x01               ; shoot mode?
  jne LAA32                 ; no => jump
  mov al,0x03               ; right
  mov [LDB75],al            ; Direction/orientation
  jmp LA8C6                 ; Proceed to Draw the Player
LAA32:
  mov al,0x03               ; right
  mov [LDB75],al            ; Direction/orientation
  call LAA60                ; get byte from the room after movement
  cmp al,0x01
  jnzl LA8CD
  mov al,[LDB76]            ; get X coord in tiles
  push ax
  inc al                    ; one tile right
  mov [LDB76],al            ; set X coord in tiles
; Moved left or right, check for Alien
LAA47:
  mov al,[LDB84]            ; Alien still alive?
  or al,al
  jz LAA5C                  ; dead => skip
  call LB72E                ; Get value at offset $2F in the room description
  or al,al                  ; do we have the alien?
  jz LAA5C                  ; we don't have it => jump
; We have an alien in the room
  call LB74C
  or al,al                  ; Alien in the same cell as Player?
  jzl LB08D                 ; yes => Decrease Health by 4, restore X coord
LAA5C:
  pop ax
  jmp LA8CD

; Get byte from the room at position after the movement
;   AL = byte from the room
LAA60:
  call LADE5                ; Decode current room to LDBF5; BX = LDBF5
  mov al,[LDB76]            ; get X coord in tiles
  mov dl,al
  call LAA7D                ; For direction left - dec DL, right - inc DL
  xor dh,dh
  add bx,dx
  mov dl,12                 ; Line width in tiles
  mov al,[LDB78]            ; Get Y tile coord
  mov ch,al
  call LAA8D                ; For direction up - dec CH, down - inc CH
LAA78:
  add bx,dx
  dec ch
  jnz LAA78
  mov al,[bx]               ; get byte from the room
  ret

; For direction left - dec DL, right - inc DL
LAA7D:
  mov al,[LDB75]            ; Direction/orientation
  or al,al                  ; down?
  jz LAA7D_ret
  cmp al,0x01               ; up?
  je LAA7D_ret
  cmp al,0x02               ; left?
  jne LAA8B
  dec dl                    ; going left 1 tile
  ret
LAA8B:
  inc dl                    ; going right 1 tile
LAA7D_ret:
  ret

; For direction up - dec CH, down - inc CH
LAA8D:
  mov al,[LDB75]            ; Direction/orientation
  cmp al,0x02               ; left
  je LAA8D_ret
  cmp al,0x03               ; right?
  je LAA8D_ret
  or al,al                  ; down?
  jnz LAA9B
  inc ch                    ; going down 1 tile
  ret
LAA9B:
  dec ch                    ; going up 1 tile
LAA8D_ret:
  ret

; Get room offset in tiles for X = LDB76, Y = LDB78
;   Returns the room offset in AL and LDC56
LAA9D:
  mov dl,12                 ; Line width in tiles
  mov al,[LDB78]            ; get Y tile coord
  mov ch,al
  mov al,[LDB76]            ; get X tile coord
LAAA8:
  add al,dl                 ; add al,12
  dec ch
  jnz LAAA8
  mov [LDC56],al            ; (LDC56) = Y * 12 + X
  ret

; Display Health
LB96B:
%if CHEAT_SHOW_ROOM_NUMBER = 1
;DEBUG: Show room number at the bottom-left
  mov bx,0x7610
  mov [L86D7],bx            ; Set penRow/penCol
  mov al,[LDB79]            ; Get the room number
  mov bl,al
  xor bh,bh
  call DrawNumber3
%endif
  mov bx,0x012C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,[LDB7A]            ; get Health value
  jmp DrawNumber3           ; Show 3-digit decimal number BX

; Show look/shoot selection indicator
;
LB8EA:
  mov al,[LDB7D]            ; Get look/shoot switch value
  or al,al                  ; look mode?
  jz LB902                  ; yes => jump
  call LB913
  mov al,0x8C
  call L9E5F                ; Draw tile by XOR operation
  call LB91C
  mov al,0xA0
  jmp L9E5F                 ; Draw tile by XOR operation
LB902:
  call LB913
  mov al,0x76
  call L9E5F                ; Draw tile by XOR operation
  call LB91C
  mov al,0x8A
  jmp L9E5F                 ; Draw tile by XOR operation
LB913:
  mov si,Tileset3+20        ; Small triange pointing right
  mov ch,6                  ; Tile height
  mov bl,0x04               ; Y pos
  ret
LB91C:
  mov si,Tileset3+32+20     ; Small triange pointing left
  mov ch,6                  ; Tile height
  mov bl,0x04               ; Y pos
  ret

; Switch Look / Shoot mode
LB930:
  mov al,[LDCF7]            ; Weapon slot
  or al,al
  jnz LB94C
; Don't have a weapon
  call LB925
  call LAB28                ; Show small message popup
  mov bx,0x582C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0D3              ; "You dont have a Weapon to equip!"
  call LBEDE                ; Show message char-by-char
  jmp LAD8C                 ; Show screen and wait for Escape key
LB94C:
  mov al,[LDB7D]            ; Get look/shoot switch value
  cmp al,0x01               ; shoot mode?
  je LB95C                  ; yes => jump
  mov al,0x01
  mov [LDB7D],al            ; set look/shoot switch = Shoot
  jmp short LB960
LB95C:
  xor al,al
  mov [LDB7D],al            ; set look/shoot switch value = Look
LB960:
  mov al,0x96
  mov [LDC59],al            ; set delay factor
  call LB2D0                ; Delay
  jmp L9E2E                 ; Show the screen, continue the game main loop

; Player is dead, Health 0
;
LB9A2:
  call ClearShadowScreen
  mov al,0x32
  mov [LDCF3],al            ; Left margin size for text
  mov al,14
  mov [LDCF4],al            ; Line interval for text
  call LAB28                ; Show small message popup
  mov bx,0x580E
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0BD              ; "The Desolate has claimed your life too . . ."
  call LBEDE                ; Show message char-by-char
  xor al,al
  call LB9D6                ; Clear player variables
  mov bx,[LDBC3]            ; get Player deaths count
  inc bx
  mov [LDBC3],bx            ; set Player deaths count
LB9C9:
  call ShowShadowScreen     ; Copy shadow screen to the screen
  call LA0F1                ; Scan keyboard
  cmp al,0x07               ; Escape key? TODO: any key
  jzl L9E19                 ; yes => Go to ending of main game loop
  jmp LB9C9                 ; continue the waiting loop

;----------------------------------------------------------------------------
; Stage 5: Aliens, shooting, damage, look/shoot key
;----------------------------------------------------------------------------

; Look / Shoot key pressed
LAAAF:
  call SoundLookShoot
  mov al,[LDB7D]            ; Get look/shoot switch value
  cmp al,0x01               ; shoot mode?
  jzl LB758                 ; yes => Shooting
; Look action
  xor al,al
  mov [LDC88],al            ; clear current offset
  call LAA9D                ; Get room offset in tiles for X = LDB76, Y = LDB78
  call LAE09                ; Decode current room description to LDBF5
LAAC1:
  mov al,[bx]
  mov cl,al
  mov al,[LDC56]            ; get offset in the room
  sub al,cl
  jz LAADD                  ; found the action point for the current position
  mov al,[LDC88]            ; get current offset
  cmp al,0x31
  je LAADA                  ; => Show the screen, continue the game main loop
  inc al
  mov [LDC88],al            ; set current offset
  inc bx
  jmp LAAC1
; Show the screen, continue the game main loop
LAADA:
  jmp L9E2E                 ; Show the screen, continue the game main loop
; Found the action point for the current position in the room description
LAADD:
  mov al,[LDC88]            ; get current offset in the room description
  or al,al
  jzl LAB3F
  cmp al,0x01
  jzl LAB3F
  cmp al,0x03
  jzl LABA4
  cmp al,0x04
  jzl LABA4
  cmp al,0x19
  jzl LABBE
  cmp al,0x1A
  jzl LABBE
  cmp al,0x21
  jzl LAC05
  cmp al,0x22
  jzl LAC05
  cmp al,0x06
  jzl LAC54
  cmp al,0x07
  jzl LAC54
  cmp al,0x0B
  jzl LACE3
  cmp al,0x0C
  jzl LACE3
  cmp al,0x0F
  jzl LBC8B
  cmp al,0x10
  jzl LBC8B
  jmp L9E2E                 ; Show the screen, continue the game main loop

; Fire key pressed in Shoot mode
LB758:
  mov al,[LDB8C]            ; get shooting flag
  cmp al,0x01               ; still in prev shooting?
  je LB768                  ; yes => jump
  mov al,0x01
  mov [LDB8D],al            ; set shooting process flag
  mov [LDD55],al            ; set shooting flag for player's animation
LB768:
  jmp L9E2E                 ; Show the screen, continue the game main loop

; Process shoot within the game main loop
;
LB76B:
  mov al,[LDB8D]            ; get shooting process flag
  or al,al                  ; in the process?
  jzl LB84A                 ; no => jump
  mov al,[LDB8C]
  cmp al,0x01
  je LB797
  mov al,0x01
  mov [LDB8D],al            ; set shooting process flag
  mov al,[LDB75]            ; get player Direction/orientation
  mov [LDB8B],al            ; set bullet Direction/orientation
  mov al,[LDB76]            ; get player X coord in tiles
  mov [LDB88],al            ; set bullet X coord in tiles
  mov al,[LDB77]            ; get player Y coord/line on the screen
  mov [LDB89],al            ; set bullet Y coord/line on the screen
  mov al,[LDB78]            ; get player Y coord in tiles
  mov [LDB8A],al            ; set bullet Y coord in tiles
LB797:
  mov al,[LDB8B]            ; get Bullet Direction/orientation
  or al,al                  ; down?
  jz LB7AD
  cmp al,0x01               ; up?
  je LB7C7
  cmp al,0x02               ; left?
  je LB7E1
  cmp al,0x03               ; right?
  je LB7F3
; Bullet down
LB7AD:
  call LB87C                ; Move the Bullet
  cmp al,0x01               ; Empty cell?
  jnzl LB8D6
  mov al,[LDB89]            ; get Bullet Y coord/line on the screen
  add al,16                 ; down 16 rows
  mov [LDB89],al            ; set Bullet Y coord/line on the screen
  mov al,[LDB8A]            ; get Bullet Y coord in tiles
  inc al                    ; down one tile
  mov [LDB8A],al            ; set Bullet Y coord in tiles
  jmp short LB805
; Bullet up
LB7C7:
  call LB87C                ; Move the Bullet
  cmp al,0x01               ; Empty cell?
  jnzl LB8D6
  mov al,[LDB89]            ; get Bullet Y coord/line on the screen
  add al,-16                ; up 16 rows
  mov [LDB89],al            ; set Bullet Y coord/line on the screen
  mov al,[LDB8A]            ; get Bullet Y coord in tiles
  dec al                    ; up one tile
  mov [LDB8A],al            ; set Bullet Y coord in tiles
  jmp short LB805
; Bullet left
LB7E1:
  call LB87C                ; Move the Bullet
  cmp al,0x01               ; Empty cell?
  jnzl LB8D6
  mov al,[LDB88]            ; get bullet X coord in tiles
  dec al                    ; left one tile
  mov [LDB88],al            ; set bullet X coord in tiles
  jmp short LB805
; Bullet right
LB7F3:
  call LB87C                ; Move the Bullet
  cmp al,0x01               ; Empty cell?
  jnzl LB8D6
  mov al,[LDB88]            ; get bullet X coord in tiles
  inc al                    ; right one tile
  mov [LDB88],al            ; set bullet X coord in tiles
; Bullet moving
LB805:
  mov al,[LDB8D]            ; get shooting process flag
  or al,al                  ; in the process?
  jz LB84A                  ; no => jump
  mov al,[LDB88]            ; get bullet X coord in tiles
  add al,al                 ; tile coord -> column number
  mov bh,al
  mov al,[LDB89]            ; get Bullet Y coord/line on the screen
  mov bl,al
  call LB84F                ; Get Bullet sprite address in DX
  xor al,al                 ; draw flags
  call L9EDE                ; Draw sprite DX at column BH row BL
  mov al,0x01
  mov [LDB8C],al
  mov al,[LDB81]            ; get Alien type
  cmp al,0x02               ; the big one?
  je LB82B                  ; yes => jump to Check if the Bullet hit the Alien
  jmp LB64B                 ; Check Is the Bullet hit the Alien, process the hit
;
LB82B:
  call LB8CA                ; Is the Bullet hit the Alien?
  or al,al
  jnz LB82B_ret             ; no => return
; Bullet hit the Alien, the big one
  xor al,al
  mov [LDB8D],al            ; clear shooting process flag
  mov [LDB88],al            ; clear Bullet X coord in tiles
  mov [LDB89],al            ; clear Bullet Y coord/line on the screen
  mov al,[LDB85]            ; get Alien health
  dec al                    ; Alien injured
  mov [LDB85],al            ; set Alien health
  or al,al                  ; zero Health?
  jnz LB82B_ret
  call LB71F                ; yes => Killed the alien
LB82B_ret:
  ret
;
LB84A:
  xor al,al
  mov [LDB8C],al            ; clear shooting flag
  ret

; Get Bullet tile address and draw flags
;   Returns: DX = tile address; AL = draw flags
LB84F:
  mov al,[LDB8B]            ; get Bullet Direction/orientation
  or al,al                  ; down?
  jz LB865
  cmp al,0x01               ; up?
  je LB86A
  cmp al,0x02               ; left?
  je LB870
  cmp al,0x03               ; right?
  je LB876
LB865:                      ; Bullet goes down
  mov dx,Sprites+0x1D*64    ; Bullet vert sprite
  ret
LB86A:                      ; Bullet goes up
  mov dx,Sprites+0x1E*64    ; Bullet vert sprite
  ret
LB870:                      ; Bullet goes left
  mov dx,Sprites+0x1F*64    ; Bullet horz sprite
  ret
LB876:                      ; Bullet goes right
  mov dx,Sprites+0x20*64    ; Bullet horz sprite
  ret

; Move the Bullet
; Returns: AL = room cell value for the new bullet position
LB87C:
  call LADE5                ; Decode current room to LDBF5
  mov al,[LDB88]            ; get Bullet X coord in tiles
  mov dl,al
  call LB89B                ; For Bullet direction left: dec DL, right: inc DL
  xor dh,dh
  add bx,dx
  mov dl,12                 ; Line width in tiles
  mov al,[LDB8A]            ; get Bullet Y coord in tiles
  mov ch,al
  call LB8AB                ; For Bullet direction up: dec CH, down: inc CH
LB896:
  add bx,dx
  dec ch
  jnz LB896
  mov al,[bx]               ; get value for the room cell
  ret

; For Bullet direction left: dec DL, right: inc DL
LB89B:
  mov al,[LDB8B]            ; get Bullet Direction/orientation
  or al,al
  jz LB89B_ret
  cmp al,0x01
  je LB89B_ret
  cmp al,0x02               ; left?
  jne LB8A9
  dec dl                    ; one left
  ret
LB8A9:
  inc dl                    ; one right
LB89B_ret:
  ret

; For Bullet direction up: dec CH, down: inc CH
LB8AB:
  mov al,[LDB8B]            ; get Bullet Direction/orientation
  cmp al,0x02
  je LB8AB_ret
  cmp al,0x03
  je LB8AB_ret
  or al,al                  ; down?
  jnz LB8B9
  inc ch                    ; one down
  ret
LB8B9:
  dec ch                    ; one up
LB8AB_ret:
  ret

; Get AL = Bullet position within the room
LB8BB:
  mov cl,12                 ; Line width in tiles
  mov al,[LDB8A]            ; get Bullet Y coord in tiles
  mov ch,al
  mov al,[LDB88]            ; get Bullet X coord in tiles
LB8C6:
  add al,cl
  dec ch
  jnz LB8C6
  ret                       ; now AL = Bullet Y coord * 12 + Bullet X coord

; Is the Bullet hit the Alien?
LB8CA:
  call LB6ED                ; Get AL = Alien position within the room
  call LB8BB                ; Get AL = Bullet position within the room
  mov cl,al
  mov al,[LDB87]            ; get Alien position within the room
  sub al,cl
  ret

; Bullet hit something
LB8D6:
  call LB8DC                ; Clear all Bullet variables
  jmp LB805

; Clear all Bullet variables
LB8DC:
  xor al,al
  mov [LDB8D],al            ; clear shooting process mark
  mov [LDB88],al            ; clear Bullet X coord in tiles
  mov [LDB89],al            ; clear Bullet Y coord/line on the screen
  mov [LDB8A],al            ; clear Bullet Y coord in tiles
  ret

; Decrease Health by 4, restore Y coord
LB07B:
  mov ch,0x02
LB07D:
  call LB994                ; Decrease Health
  dec ch
  jnz LB07D
  pop ax
  mov [LDB78],al            ; set Y tile coord
  pop ax
  mov [LDB77],al            ; set Y pixel coord
  jmp LA8CD

; Decrease Health by 4, restore X coord
LB08D:
  mov ch,0x02
LB08F:
  call LB994                ; Decrease Health
  dec ch
  jnz LB08F
  pop ax                    ; Restore old X coord
  mov [LDB76],al            ; set X coord
  jmp LA8CD

; Decrease Health
LB994:
  mov al,[LDB7A]            ; get Health
  sub al,0x02               ; Health = Health minus 2
  jnc LB994_1
  xor al,al
LB994_1:
  mov [LDB7A],al            ; set Health
; Set border to red as an indication of the injury
  mov al,2                  ; red
  jmp SetBorderColor        ; set border color

; Process alien in the room
LB551:
  call LB72E                ; Get value at offset $2F in the room description
  or al,al                  ; do we have the alien?
  jz LB551_ret              ; we don't have it => return
; We have an alien in the room description
  mov al,[LDB82]
  or al,al                  ; do we have it already in the room?
  jnz LB57B                 ; yes => jump
  dec bx                    ; now BX = RoomDesc + $2E
  mov al,[bx]
  mov [LDB81],al            ; set Alien type
  dec bx                    ; now BX = RoomDesc + $2D
  mov al,[bx]
  mov [LDB80],al            ; set Alien Y tile coord
  dec bx                    ; now BX = RoomDesc + $2C
  mov al,[bx]
  add al,al
  mov [LDB7F],al            ; set Alien Y coord
  dec bx                    ; now BX = RoomDesc + $2B
  mov al,[bx]
  mov [LDB7E],al            ; set Alien X coord
  mov al,0x03
  mov [LDB85],al            ; set alien health = 3
  mov al,0x01
  mov [LDB84],al            ; set Alien alive flag
LB57B:
  mov al,[LDB84]            ; Alien still alive?
  or al,al
  jzl LB622                 ; dead => jump
  call GetRandom8           ; Generate random number 0..7
  or al,al
  jz LB59D                  ; Alien down
  cmp al,0x02
  jzl LB5C3                 ; Alien up
  cmp al,0x04
  jzl LB5E9                 ; Alien left
  cmp al,0x06
  jzl LB607                 ; Alien right
  jmp LB622
LB551_ret:
  ret

; Alien goes down
LB59D:
  xor al,al
  mov [LDB86],al            ; set Alien direction/orientation = down
  call LB713
  or al,al
  jzl LB737                 ; => Player injured by Alien moving to him
  call LB6B0
  cmp al,0x01
  jnzl LB622
  mov al,[LDB7F]            ; get Alien Y coord
  add al,16                 ; down one tile
  mov [LDB7F],al            ; set Alien Y coord
  mov al,[LDB80]            ; get Alien Y tile coord
  inc al                    ; down one tile
  mov [LDB80],al            ; set Alien Y tile coord
  jmp LB622

; Alien goes up
LB5C3:
  mov al,0x01
  mov [LDB86],al            ; set Alien direction/orientation = up
  call LB713
  or al,al
  jzl LB737                 ; => Player injured by Alien moving to him
  call LB6B0
  cmp al,0x01
  jnzl LB622
  mov al,[LDB7F]            ; get Alien Y coord
  add al,-16                ; up one tile
  mov [LDB7F],al            ; set Alien Y coord
  mov al,[LDB80]            ; get Alien Y tile coord
  dec al                    ; up one tile
  mov [LDB80],al            ; set Alien Y tile coord
  jmp LB622
LB5E9:
  mov al,0x02
  mov [LDB86],al            ; set Alien direction/orientation = left
  call LB713
  or al,al
  jzl LB737                 ; => Player injured by Alien moving to him
  call LB6B0
  cmp al,0x01
  jnzl LB622
  mov al,[LDB7E]            ; get Alien X coord
  dec al                    ; left one tile
  mov [LDB7E],al            ; set Alien X coord
  jmp LB622
LB607:
  mov al,0x03
  mov [LDB86],al            ; set Alien direction/orientation = right
  call LB713
  or al,al
  jzl LB737                 ; => Player injured by Alien moving to him
  call LB6B0
  cmp al,0x01
  jnz LB622
  mov al,[LDB7E]            ; get Alien X coord
  inc al                    ; right one tile
  mov [LDB7E],al            ; set Alien X coord
;
LB622:
  mov al,[LDB7E]            ; get Alien X coord
  add al,al                 ; tile X cord -> 8px column number
  mov bh,al                 ; column
  mov al,[LDB7F]            ; get Alien Y coord
  mov bl,al                 ; row
  xor al,al                 ; clear draw flags
  call LB67B                ; Get alien sprite address in DX
  call L9EDE                ; Draw sprite DX at column BH row BL
  mov al,0x01
  mov [LDB82],al            ; mark that we already have an Alien in the room
  mov al,[LDB83]            ; get Alien sprite phase
  inc al                    ; next phase
  cmp al,0x01
  je LB622_1
  call LB676                ; => Clear Alien tile phase
LB622_1:
  mov [LDB83],al            ; set Alien sprite phase
  mov al,[LDB81]            ; get Alien type
  cmp al,0x02               ; the big one?
  jzl LB82B                 ; yes => jump to Check if the Bullet hit the Alien
LB64B:
  call LB8CA                ; Is the Bullet hit the Alien?
  or al,al
  jnz LB64B_ret
  call LB71F                ; Bullet hit the alien => Killed the Alien
LB64B_ret:
  ret

; Draw Alien (the big one: head)
LB653:
  mov al,[LDB84]            ; Alien still alive?
  or al,al
  jz LB653_ret              ; dead => return
  call LB72E                ; Get value at offset $2F in the room description
  or al,al                  ; do we have the alien?
  jz LB653_ret              ; we don't have it => return
; We have an alien in the room description
  mov al,[LDB81]            ; get Alien type
  cmp al,0x02
  jne LB653_ret
; Draw alien type 2
  mov al,[LDB7E]            ; get Alien X coord
  add al,al                 ; tile X cord -> 8px column number
  mov bh,al
  mov al,[LDB7F]            ; get Alien Y coord
  add al,-16                ; one tile up
  mov bl,al
  xor al,al                 ; clear draw flags
  call LB69D                ; Get alien head sprite address
  jmp L9EDE                 ; Draw sprite DX at column BH row BL, and return
LB653_ret:
  ret

; Clear Alien tile phase
LB676:
  xor al,al
  mov [LDB83],al            ; clear Alien tile phase
  ret

; Get alien sprite address
; Returns DX = tile address, AL = draw flags
LB67B:
  mov al,[LDB84]            ; Alien still alive?
  or al,al
  jnz LB685
  mov dx,Sprites+0x18*64    ; Alien dead sprite
  ret
LB685:
  mov al,[LDB81]            ; get Alien type
  cmp al,0x02
  je LB698
  mov dx,Sprites+0x17*64    ; Small Alien sprite
  mov al,[LDB83]            ; get Alien sprite phase
  or al,al
  jz LB685_ret              ; phase 0 => return
  mov dx,Sprites+0x21*64    ; Small Alien sprite, reflected vertically
  xor al,al                 ; draw flags
LB685_ret:
  ret
LB698:                      ; Alien type 2
  mov dx,Sprites+0x1A*64    ; big Alien body sprite
  jmp short LB6A0
; Get alien head sprite address
LB69D:
  mov dx,Sprites+0x19*64    ; big Alien head sprite
LB6A0:
  mov al,[LDB83]            ; get Alien sprite phase
  or al,al
  jz LB6A0_ret
  add dx,0x0020*4           ; switch to other sprite
  xor al,al                 ; draw flags
LB6A0_ret:
  ret

; Get the room cell at the Alien's next position
LB6B0:
  call LADE5                ; Decode current room to LDBF5
  mov al,[LDB7E]            ; get Alien X coord
  mov dl,al
  call LB6CD                ; left/right
  xor dh,dh
  add bx,dx
  mov dl,12                 ; Line width in tiles
  xor dh,dh
  mov al,[LDB80]            ; get Alien Y tile coord
  mov ch,al
  call LB6DD                ; up/down
  jmp LAA78

LB6CD:
  mov al,[LDB86]            ; get Alien direction/orientation
  or al,al
  jz LB6CD_ret
  cmp al,0x01
  je LB6CD_ret
  cmp al,0x02               ; left?
  jne LB6DB
  dec dl                    ; one left
  ret
LB6DB:
  inc dl                    ; one right
LB6CD_ret:
  ret

LB6DD:
  mov al,[LDB86]            ; get Alien direction/orientation
  cmp al,0x02
  je LB6DD_ret
  cmp al,0x03
  je LB6DD_ret
  or al,al                  ; down?
  jnz LB6EB
  inc ch                    ; one down
  ret
LB6EB:
  dec ch                    ; one up
LB6DD_ret:
  ret

; Get AL = Alien position within the room
LB6ED:
  call LB6FA                ; Get CH=Alien Y tile coord, CL=12 line width
  mov al,[LDB7E]            ; get Alien X coord
LB6F3:
  add al,cl
  dec ch
  jnz LB6F3
  mov [LDB87],al            ; AL = Alien Y tile coord * 12 + Alien X coord
  ret
; Get CH=Alien Y tile coord, CL=12 line width
LB6FA:
  mov cl,12                 ; Line width in tiles
  mov al,[LDB80]            ; get Alien Y tile coord
  mov ch,al
  ret

LB703:
  call LB6FA                ; Get CH=Alien Y tile coord, CL=12 line width
  call LB6DD                ; up/down
  mov al,[LDB7E]            ; get Alien X coord
  mov dl,al
  call LB6CD                ; left/right
  mov al,dl
  jmp LB6F3

LB713:
  call LAA9D                ; Get room offset in tiles for X = LDB76, Y = LDB78
  call LB703
  mov cl,al
  mov al,[LDC56]            ; get offset in the room
  sub al,cl
  ret
; Killed the alien
LB71F:
  xor al,al
  mov [LDB84],al            ; set Alien not alive
  call LB8DC                ; Clear all Bullet variables
  mov bx,[LDBC5]            ; get Enemies Killed count
  inc bx                    ; one more killed
  mov [LDBC5],bx            ; set Enemies Killed count
  ret

; Get value at offset $2F in the room description
;   Returns: AL = value; BX = address of the value
LB72E:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x002F             ; offset in the room description
  add bx,dx
  mov al,[bx]
  ret

; Player injured by Alien moving to him
LB737:
  xor al,al
  mov [LDB8D],al            ; clear shooting process mark
  call LB994                ; Decrease Health
  mov al,[LDB81]            ; get Alien type
  cmp al,0x02               ; big one?
  jnzl LB622
  call LB994                ; Decrease Health
  jmp LB622

LB74C:
  call LAA9D                ; Get room offset in tiles for X = LDB76, Y = LDB78
  call LB6ED                ; Get AL = Alien position within the room
  mov cl,al
  mov al,[LDC56]            ; get offset in the room
  sub al,cl
  ret

;----------------------------------------------------------------------------
; Stage 6a: look action - doors, door lock, dead bodies, items, weapon
;----------------------------------------------------------------------------

; Scan keyboard for the game screens: Enter works as the look/shoot key (code 5)
LA0F1G:
  call ReadKeyboard
  cmp al,0x09
  jne LA0F1G_1
  mov al,0x05
LA0F1G_1:
  or al,al
  ret

; Found action point at room description offset $00..$01
LAB3F:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x0002             ; offset in the room description
  call LAC4C                ; Compare byte at (BX+DX) with Direction/orientation LDB75
  jnzl LAADA                ; => Show the screen, continue the game main loop
  mov al,[LDB79]            ; Get room number
  cmp al,0x1B               ; room #27?
  jne LAB7A                 ; no => jump
; Room #27
  mov al,[LDCF7]            ; Weapon slot
  or al,al                  ; do we have it?
  jnz LAB7A                 ; have weapon => jump
  mov al,22
  mov [LDCF3],al            ; Left margin size for text
  mov al,14
  mov [LDCF4],al            ; Line interval for text
  call LAB28                ; Show small message popup
  call LAB73                ; Set penRow/penCol for small message popup
  mov bx,SE0D5              ; "It is not wise to proceed without a weapon."
  call LBEDE                ; Show message char-by-char
  jmp LAD8C                 ; Show screen and wait for Escape key

; Set penRow/penCol for small message popup
LAB73:
  mov bx,0x5810
  mov [L86D7],bx            ; Set penRow/penCol
  ret

LAB7A:
  mov al,0x01
  mov [LDC8A],al            ; Direction to other room = down
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x001C             ; offset in the room description - access level
LAB85:
  add bx,dx
  mov al,[bx]
  mov [LDC8C],al            ; Set Access code level
  mov dx,0x0007
  add bx,dx                 ; BX = $1C+$07=$23 - offset for room number
  mov al,[bx]
  mov [LDC86],al            ; store new room number
  mov dx,0x0004
  add bx,dx                 ; BX = $1C+$07+$04=$27 - offset for Access code slot
  mov al,[bx]
  mov [LDC8B],al            ; set Access code slot number
  mov al,[LDC8C]            ; Get Access code level
  or al,al                  ; Level 0?
  jzl LB00E                 ; yes => Going to the next room
  jmp LAE23                 ; Check access and show Door Lock

; Found action point at room description offset $03..$04
LABA4:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x0005             ; offset in the room description - direction
  call LAC4C                ; Compare byte at (BX+DX) with Direction/orientation LDB75
  jnzl LAADA                ; => Show the screen, continue the game main loop
  mov al,0x02
  mov [LDC8A],al            ; Direction to other room = up
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x001D             ; offset in the room description
  jmp LAB85

; Found action point at room description offset $19..$1A
LABBE:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x001B             ; offset in the room description - direction byte
  call LAC4C                ; Compare byte at (BX+DX) with Direction/orientation LDB75
  jnzl LAADA                ; => Show the screen, continue the game main loop
  mov al,[LDB79]            ; Get the room number
  cmp al,0x21               ; room #33?
  jne LABF7
; Room #33
  mov dx,0x0004
  call LB531                ; Get value (LDB90+DX)
  jnz LABF7
  mov al,16
  mov [LDCF3],al            ; Left margin size for text
  mov al,14
  mov [LDCF4],al            ; Line interval for text
  call LAB28                ; Show small message popup
  mov bx,0x580C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0D7              ; "You cant enter that sector Life-Support is offline."
  call LBEDE                ; Show message char-by-char
  jmp LAD8C                 ; Show screen and wait for Escape key
LABF7:
  mov al,0x03
  mov [LDC8A],al            ; Direction to other room = left
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x001E             ; offset in the room description
  jmp LAB85

; Found action point at room description offset $21..$22 (possibly an error, should be $20-$21)
LAC05:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x0022             ; offset in the room description
  call LAC4C                ; Compare byte at (BX+DX) with Direction/orientation LDB75
  jnzl LAADA                ; => Show the screen, continue the game main loop
  mov al,[LDB79]            ; Get the room number
  cmp al,0x45               ; room #69?
  jne LAC3E                 ; no => jump
; Room #69
  mov dx,0x0005
  call LB531                ; Get value (LDB90+DX)
  jnz LAC3E
  mov al,12
  mov [LDCF3],al            ; Left margin size for text
  mov al,14
  mov [LDCF4],al            ; Line interval for text
  call LAB28                ; Show small message popup
  mov bx,0x5814
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0D9              ; "You cant enter until the AirLock is re-pressurised"
  call LBEDE                ; Show message char-by-char
  jmp LAD8C                 ; Show screen and wait for Escape key
LAC3E:
  mov al,0x04
  mov [LDC8A],al            ; Direction to other room = right
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x001F             ; offset in the room description
  jmp LAB85

; Compare byte at (BX+DX) with Direction/orientation LDB75
LAC4C:
  add bx,dx
  mov al,[bx]
  mov cl,al
  mov al,[LDB75]            ; Direction/orientation
  sub al,cl
  ret

; Found action point at room description offset $06..$07
LAC54:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x0008             ; offset in the room description
  add bx,dx
  mov al,[bx]
  mov cl,al
  mov al,[LDB75]            ; Direction/orientation
  sub al,cl
  jnzl LAADA                ; => Show the screen, continue the game main loop
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x000A             ; offset in the room description
  add bx,dx
  mov al,[bx]
  mov [LDC89],al            ; set as current item
  call LAE09                ; Decode current room description to LDBF5 (again?)
  mov dx,0x0009             ; offset in the room description
  add bx,dx
  mov al,[bx]
  cmp al,0x01
  je LAC97
; Found dead body, no items on it
  call LAB28                ; Show small message popup
  call LAB73                ; Set penRow/penCol for small message popup
  mov bx,SE0C3              ; "Another Dead Person"
  call LBEDE                ; Show message char-by-char
  mov bx,0x6612
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0C5              ; "Search Reveals Nothing"
  call LBEDE                ; Show message char-by-char
  jmp LAD8C                 ; Show screen and wait for Escape key
; Found dead body with some item on it
LAC97:
  call LAD4F                ; Get inventory item flag for item number in LDC89
  cmp al,0x01               ; do we have it already?
  jzl LAADA                 ; have it => Show the screen, continue the game main loop
  mov al,[LDB79]            ; Get the room number
  or al,al                  ; room #0 ?
  je LACC5                  ; yes => Small message popup "OMG! This Person Is DEAD! What Happened Here!?!"
  call LAB28                ; Show small message popup
  call LAB73                ; Set penRow/penCol for small message popup
  mov bx,SE0C7              ; " This Person is Dead . . ."
  call LBEDE                ; Show message char-by-char
  call LACB8                ; Show arrow sign as prompt to continue
  jmp LAD00

; Show arrow sign in bottom-right corner, as a prompt to continue
LACB8:
  mov bx,0x66B0
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0B9              ; String with arrow down sign
  jmp LBEDE                 ; Show message char-by-char

; Small message popup "OMG! This Person Is DEAD! What Happened Here!?!"
LACC5:
  call LAB28                ; Show small message popup
  call LAB73                ; Set penRow/penCol for small message popup
  mov bx,SE0BF              ; "OMG! This Person Is DEAD!"
  call LBEDE                ; Show message char-by-char
  mov bx,0x6612
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0C1              ; "What Happened Here!?!"
  call LBEDE                ; Show message char-by-char
  call LACB8                ; Show arrow sign as prompt to continue
  jmp short LAD00

; Found action point at room description offset $0B..$0C
LACE3:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x000D             ; offset in the room description
  add bx,dx
  mov al,[bx]
  mov cl,al
  mov al,[LDB75]            ; Direction/orientation
  sub al,cl
  jnzl LAADA                ; => Show the screen, continue the game main loop
  jmp LAD5B

; Show screen, wait for any key, show small message popup
LACF6:
  call ShowShadowScreen     ; Copy shadow screen to the screen
  call WaitAnyKey           ; was: waiting for Down key
  jmp LAB28                 ; Show small message popup

; Get item found on the dead body
LAD00:
  call LACF6                ; Show screen, wait for any key, show small message popup
  mov bx,0x5816
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0C9              ; "They Seem To Be Holding"
  call LBEDE                ; Show message char-by-char
  mov bx,0x663E
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0CB              ; "Something"
  call LBEDE                ; Show message char-by-char
  mov al,[LDBC7]            ; get Items Found count
  inc al
  mov [LDBC7],al            ; set Items Found count
LAD22:
  call LACB8                ; Show arrow sign in bottom-right corner
  call LACF6                ; Show screen, wait for any key, show small message popup
  mov bx,0x5830
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0CF              ; "You Picked Up A"
  call LBEDE                ; Show message char-by-char
  mov bx,0x6612
  mov [L86D7],bx            ; Set penRow/penCol
  call LAE19                ; Get inventory item description string
  call LBEDE                ; Show message char-by-char
  mov al,[LDC89]            ; get the current item number
  xor ah,ah
  mov bx,LDB9C              ; Inventory table address
  add bx,ax                 ; BX = item address in my Inventory
  mov byte [bx],0x01        ; Mark that we have the item now
  jmp LAD8C                 ; Show screen and wait for Escape key

; Get inventory item flag for item number in LDC89
LAD4F:
  mov al,[LDC89]            ; get current item number
  xor ah,ah
  mov bx,LDB9C              ; Inventory table address
  add bx,ax                 ; BX = item address in my Inventory
  mov al,[bx]               ; AL = item flag: $00 = not having, $01 = have it
  ret

LAD5B:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x000E             ; offset in the room description
  add bx,dx
  mov al,[bx]
  mov [LDC89],al            ; set as current item
  cmp al,0x23               ; weapon?
  jzl LADA9                 ; yes => pick it up
  call LAD4F                ; Get inventory item flag for item number in LDC89
  cmp al,0x01               ; do we have it?
  jzl LAADA                 ; yes => Show the screen, continue the game main loop
  call LAB28                ; Show small message popup
  mov bx,0x5816
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0CD              ; " Hey Whats This . . . ?"
  call LBEDE                ; Show message char-by-char
  mov al,[LDBC7]            ; get Items Found count
  inc al
  mov [LDBC7],al            ; set Items Found count
  jmp LAD22

; We found the weapon
LADA9:
  mov al,[LDCF7]            ; Weapon slot
  or al,al                  ; do we have it already?
  jnzl LAADA                ; yes => Show the screen, continue the game main loop
; Picking up the weapon
  call LAB28                ; Show small message popup
  mov al,0x01
  mov [LDCF7],al            ; We've got the weapon
  mov bx,0x581C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0CD              ; "Hey Whats This  .  .  . ?"
  call LBEDE                ; Show message char-by-char
  call LACB8                ; Show arrow sign in bottom-right corner
  call LACF6                ; Show screen, wait for any key, show small message popup
  mov bx,0x5830
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0CF              ; "You Picked Up A"
  call LBEDE                ; Show message char-by-char
  mov bx,0x662C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0B7              ; "Ion Phaser"
  call LBEDE                ; Show message char-by-char
  jmp LAD8C                 ; Show screen and wait for Escape key

; Inventory item to item description string
LAE19:
  mov al,[LDC89]            ; get current item number
  mov bx,LDFB7
  jmp LADFF                 ; Get address from table by index AL, and return

; Get value (LDB90+DX)
LB531:
  mov bx,LDB90
  add bx,dx
  mov al,[bx]
  or al,al
  ret

; Door Lock: Preparing to draw string with prompt/result
LB09B:
  mov bx,0x3401             ; line 52 col 1
  mov dx,0x0C0C             ; 12 rows, 12 cols
  call ClearScreenBlock
  mov bx,0x340C
  mov [L86D7],bx            ; set penRow/penCol
  ret

; Check access and show Door Lock
;   LDC8B - Access code slot number
LAE23:
  mov al,0x28
  mov [LDC59],al            ; set delay factor
  mov al,[LDC8B]            ; get Access code slot number
  xor ah,ah
  mov bx,LDCA2              ; Table with Access code slots
  add bx,ax
  mov al,[bx]               ; get value from the slot
  cmp al,0x01               ; code was entered already?
  jzl LB00E                 ; yes => Going to the next room
; Need to enter the code for the slot
  mov ch,0x04               ; 4 symbols in the code
  mov bx,LDC8D              ; Buffer for entering access code
LAE3D:
  mov byte [bx],0x00
  inc bx
  dec ch
  jnz LAE3D
  mov bx,LF468              ; Encoded screen: Door Lock panel popup
  call LADEE                ; Decode 96 bytes of the screen to DBF5
  call LB177                ; Display screen from tiles with Tileset2
  mov al,10
  mov [LDCF3],al            ; Left margin size for text
  mov al,12
  mov [LDCF4],al            ; Line interval for text
  call LB09B                ; Preparing to draw string with the prompt
  mov bx,SE0DD              ; "Door Locked"
  call LBEDE                ; Show message char-by-char
  mov bx,0x440A
  mov [L86D7],bx            ; Set penRow/penCol
  call LAFFE                ; Get "Access code level N required" string by access level in DC8C
  call LBEDE                ; Show message BX char-by-char
  mov al,0x25
  mov [LDC82],al            ; set current item number - "Enter" sign
  mov al,0xA0
  mov [LDC83],al            ; set X pos
  mov al,0x60
  mov [LDC84],al            ; set Y pos
  mov al,0x06
  mov [LDC57],al            ; set Door Lock pos
; Check if the access code was entered before for this level
  call DoorLockGetEnteredFlagAddr
  mov al,[bx]               ; get "access code was entered for this level" flag
  or al,al
  jz LAE80                  ; the code wasn't entered => enter the code as usual
; Access code was entered for this level before, so pre-fill the code
  call LAFEC                ; LDC8C access code level -> BX = address from LE015 table
  mov si,bx
  mov di,LDC8D              ; buffer for entering the code, 4 tile numbers
  movsw
  movsw
  mov al,0x02
  mov [LDC57],al            ; set Door Lock pos
  call DoorLockDisplayCode  ; show the pre-filled code
; Door Lock loop starts here
LAE80:
  mov si,Tileset3+15*32     ; Selection box tile
  mov ch,16                 ; CH = height
  mov al,[LDC84]            ; get Y pos
  mov bl,al
  mov al,[LDC83]            ; get X pos
  call L9E5F                ; Draw tile by XOR operation
  call ShowShadowScreen     ; Copy shadow screen to the screen
; Delay and wait for key in Door Lock
LAE99:
  mov ch,0x0C               ; x12
LAE9B:
  call LB2D0                ; Delay by LDC59
  dec ch
  jnz LAE9B
; Door Lock scan keyboard and process key pressed
  call LA0F1G               ; Scan keyboard
  cmp al,0x05               ; Select key
  je LAEBA
  cmp al,0x01               ; Down key?
  jzl DoorLock_KeyDown
  cmp al,0x02               ; Left key?
  jzl LAF70                 ;   Move left
  cmp al,0x03               ; Right key?
  jzl LAF86                 ;   Move right
  cmp al,0x04               ; Up key?
  jzl DoorLock_KeyUp
  cmp al,0x07               ; Escape key?
  jne LAE99                 ;   no => continue the key waiting loop
  jmp L9E2E                 ; Exit Door Lock - Show the screen, continue the game main loop
; Door Lock Select key pressed
LAEBA:
  call SoundLookShoot
  call WaitKeyUp            ; Wait until no key pressed to prevent double-reads of the same key
  mov al,[LDC82]            ; get current selection
  cmp al,0x25               ; "Enter" sign?
  jzl LAF14                 ; yes => Code entered, need to check it
  mov al,[LDC57]            ; get Door Lock pos
  dec al
  cmp al,0x01
  jzl LAE99                 ; Return to Delay and wait for key in Door Lock
  mov [LDC57],al            ; set Door Lock pos
; Move entered code digits higher
  mov ch,0x03
  mov bx,LDC8D              ; Buffer for entering access code
  inc bx
LAED4:
  push bx
  mov al,[bx]
  dec bx
  mov [bx],al
  pop bx
  inc bx
  dec ch
  jnz LAED4
  mov bx,LDC8D+3            ; Buffer for entering access code +3
  mov al,[LDC82]            ; get current selection
  mov [bx],al               ; put in the buffer
; Show four tiles with the entered code
  call DoorLockDisplayCode
  call ShowShadowScreen     ; Copy shadow screen to the screen
  jmp LAE99                 ; Return to Delay and wait for key in Door Lock

; Show four tiles with the entered code
DoorLockDisplayCode:
  mov bx,LDC8D              ; Buffer for entering access code
  mov cl,4
LAEEF:
  push bx
  mov bl,[bx]               ; get tile number
  mov bh,bl
  xor bl,bl
  shr bx,1
  shr bx,1                  ; now BX = tile number * 64
  add bx,Tileset2
  push cx
  mov si,bx                 ; now SI = tile address
  mov al,cl
  add al,al
  add al,al
  add al,al
  mov dl,al
  mov bl,16
  call DrawTileMasked       ; Draw tile SI at column DL row BL
  pop cx
  pop bx
  inc bx
  inc cl
  inc cl
  mov al,cl
  cmp al,12
  jne LAEEF
  ret

; Access code entered, need to check
LAF14:
  mov al,[LDC57]            ; get Door Lock pos
  dec al
  cmp al,0x01
  je LAF2C                  ; => validate the code
; Invalid Code
LAF1D:
  call LB09B                ; Preparing to draw string with the result
  mov bx,SE0DF              ; "INVALID CODE"
  call DrawString           ; Show message
  call ShowShadowScreen     ; Copy shadow screen to the screen
  jmp LAE99                 ; Return to Delay and wait for key in Door Lock
; Validate the code entered
LAF2C:
  mov ch,0x04
  mov dx,LDC8D              ; Buffer for entering access code
  call LAFEC                ; LDC8C access code level -> BX = address from LE015 table
LAF34:
  mov di,dx
  mov al,[di]
  mov cl,al
  mov al,[bx]
  sub al,cl
  jnz LAF1D                 ; -> Invalid Code
  inc dx
  inc bx
  dec ch
  jnz LAF34
  call LB09B                ; Preparing to draw string with the result
  mov bx,SE0E1              ; "Accepted!"
  call DrawString           ; Show message
  call ShowShadowScreen     ; Copy shadow screen to the screen
  mov al,[LDC8B]            ; get Access code slot number
  xor ah,ah
  mov bx,LDCA2              ; Table with Access code slots
  add bx,ax
  mov byte [bx],0x01        ; Mark code here was accepted
; Remember that we already entered access code for this level
  call DoorLockGetEnteredFlagAddr
  mov byte [bx],0x01        ; set the flag
  call LBA81                ; Delay x40 - added to have a pause after the Accepted message
  jmp LB00E                 ; Going to the next room

DoorLock_KeyUp:
  mov al,[LDC84]            ; get Y pos
  cmp al,0x30               ; top row already?
  jzl LAE99                 ; yes => Return to Delay and wait for key in Door Lock
; Move selection up
  call LAFD2                ; Draw selection box by XOR
  mov al,[LDC84]            ; get Y pos
  add al,-16                ;   one tile up
  mov [LDC84],al            ; set Y pos
  mov al,[LDC82]            ; get Inventory current
  add al,-3
  mov [LDC82],al            ; set Inventory current
  jmp LAE80                 ; continue the Door Lock loop
DoorLock_KeyDown:
  mov al,[LDC84]            ; get Y pos
  cmp al,0x60               ; bottom row already?
  jzl LAE99                 ; yes => Return to Delay and wait for key in Door Lock
; Move selection down
  call LAFD2                ; Draw selection box by XOR
  mov al,[LDC84]            ; get Y pos
  add al,16                 ;   one tile down
  mov [LDC84],al            ; set Y pos
  mov al,[LDC82]            ; get Inventory current
  add al,3
  mov [LDC82],al            ; set Inventory current
  jmp LAE80                 ; continue the Door Lock loop
; Move selection right
LAF5A:
  call LAFD2                ; Draw selection box by XOR
  mov al,[LDC82]            ; get Inventory current
  inc al                    ;   right
  mov [LDC82],al            ; set Inventory current
  ret
; Move selection left
LAF65:
  call LAFD2                ; Draw selection box by XOR
  mov al,[LDC82]            ; get Inventory current
  dec al                    ;   left
  mov [LDC82],al            ; set Inventory current
  ret
; Door Lock - key Left
LAF70:
  mov al,[LDC83]            ; get X pos
  cmp al,0x80
  je LAF9C                  ; => Move prev row
  call LAF65                ; Move selection Left
  mov al,[LDC83]            ; get X pos
  add al,-16
  mov [LDC83],al            ; set X pos
  jmp LAE80                 ; continue the Door Lock loop
; Door Lock - key Right
LAF86:
  mov al,[LDC83]            ; get X pos
  cmp al,0xA0
  je LAFB7                  ; => Move next row
  call LAF5A                ; Move selection Right
  mov al,[LDC83]            ; get X pos
  add al,16
  mov [LDC83],al            ; set X pos
  jmp LAE80                 ; continue the Door Lock loop
; Move prev row
LAF9C:
  mov al,[LDC84]            ; get Y pos
  cmp al,0x30
  jzl LAE99                 ; Return to Delay and wait for key in Door Lock
  call LAF65                ; Move selection Left
  mov al,0xA0
  mov [LDC83],al            ; set X pos
  mov al,[LDC84]            ; get Y pos
  add al,-16
  mov [LDC84],al            ; set Y pos
  jmp LAE80                 ; continue the Door Lock loop
; Move next row
LAFB7:
  mov al,[LDC84]            ; get Y pos
  cmp al,0x60
  jzl LAE99                 ; Return to Delay and wait for key in Door Lock
  call LAF5A                ; Move selection Right
  mov al,0x80
  mov [LDC83],al            ; set X pos
  mov al,[LDC84]            ; get Y pos
  add al,16
  mov [LDC84],al            ; set Y pos
  jmp LAE80                 ; continue the Door Lock loop

; Draw selection box by XOR
LAFD2:
  mov si,Tileset3+15*32     ; Gray square to use as selection box
  mov ch,16
  mov al,[LDC84]            ; get Y pos
  mov bl,al
  mov al,[LDC83]            ; get X pos
  call L9E5F                ; Draw tile by XOR operation
  jmp ShowShadowScreen

; LDC8C access code level -> address from LE015 table
LAFEC:
  mov al,[LDC8C]            ; Get Access code level 0..4
  mov bx,LE015              ; Table of addresses
  jmp LADFF

; LDC8C access code level -> message address from LE01F table
LAFFE:
  mov al,[LDC8C]            ; Get Access code level 0..4
  mov bx,LE01F              ; Access code messages table
  jmp LADFF

; LDC8C access code level -> "access code was entered for this level before" flag address
; Returns: BX = address
DoorLockGetEnteredFlagAddr:
  mov al,[LDC8C]            ; get Access code level 0..4
  xor ah,ah
  mov bx,DoorLockLevelEntered
  add bx,ax
  ret

; Going to the next room
LB00E:
  xor al,al
  mov [LDB82],al            ; mark we don't have an alien in the room
  mov al,0x40
  mov [LDC59],al            ; set delay factor
  mov al,[LDC8A]            ; get Direction to other room
  cmp al,0x01               ; down?
  je LB03E
  cmp al,0x02               ; up?
  je LB04F
  cmp al,0x03               ; left?
  je LB061
  cmp al,0x04               ; right?
  je LB06E
LB02E:
  mov ch,0x08               ; x8
LB030:
  call LB2D0                ; Delay
  dec ch
  jnz LB030
  mov al,[LDC86]            ; get new room number
  mov [LDB79],al            ; set the room number
  jmp L9E2E                 ; Show the screen, continue the game main loop
; Going to the next room - down
LB03E:
  mov al,0x30
  mov [LDB77],al            ; set Y pixel coord
  xor al,al                 ; down
  mov [LDB75],al            ; Direction/orientation
  mov al,0x03
  mov [LDB78],al            ; set Y tile coord = 3
  jmp LB02E
; Going to the next room - up
LB04F:
  mov al,0x60
  mov [LDB77],al            ; set Y pixel coord
  mov al,0x01               ; up
  mov [LDB75],al            ; Direction/orientation
  mov al,0x06
  mov [LDB78],al            ; set Y tile coord = 6
  jmp LB02E
LB061:
  mov al,0x0A
  mov [LDB76],al            ; set X tile coord = 10
  mov al,0x02               ; left
  mov [LDB75],al            ; Direction/orientation
  jmp LB02E
; Going to the next room - right
LB06E:
  mov al,0x01
  mov [LDB76],al            ; set X tile coord = 1
  mov al,0x03               ; right
  mov [LDB75],al            ; Direction/orientation
  jmp LB02E

;----------------------------------------------------------------------------
; Stage 6b: Inventory, using items, terminals, the ending
;----------------------------------------------------------------------------

; Open the Inventory pop-up
;
LB0A2:
  mov bx,LF329              ; Encoded screen for Inventory/Info popup
  call LADEE                ; Decode 96 bytes of the screen to LDBF5
  call LB177                ; Display screen from tiles with Tileset 2
  mov al,22
  mov [LDCF3],al            ; Left margin size for text
  mov al,12
  mov [LDCF4],al            ; Line interval for text
  xor al,al
  mov [LDCF5],al            ; Data cartridge reader slot??
  mov [LDC59],al            ; set delay factor
  mov [LDC5A],al            ; clear Inventory items count
  mov [LDCF8],al
  mov al,16
  mov [LDC83],al            ; set X pos
  mov al,0x24
  mov [LDC84],al            ; set Y pos
  mov bx,0x1630
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0BB              ; "- INVENTORY -"
  call DrawString
; Draw intentory items
  mov bx,LDB9C              ; Inventory table address
  mov ch,0x1D               ; 29 items
LB0E0:                      ; loop by CH
  push bx
  mov al,[bx]               ; get item
  cmp al,0x01               ; do we have the item
  jne LB0E0_1
  call LB12A                ; yes => put in the list and draw
LB0E0_1:
  pop bx
  inc bx                    ; next item in the Inventory
  dec ch
  jnz LB0E0                 ; continue loop
; Draw empty slots
  mov al,[LDC5A]            ; get Inventory items count
  mov cl,al
  mov al,0x1E               ; 30 placeholders
  sub al,cl
  mov cl,al                 ; CL = count of empty slots
LB0F3:
  push cx
  mov si,Tileset3+14*32     ; Tile gray dot in the center - placeholder
  call LB15D                ; Draw tile by XOR then go to next position
  pop cx
  mov al,cl
  or al,al                  ; last item?
  jz LB119                  ; yes, exit the loop
  dec cl
  mov bx,LDC5B              ; Inventory list
  mov al,[LDC5A]            ; get Inventory items count
  xor ah,ah
  add bx,ax                 ; BX = addr of the empty slot
  mov al,0x63               ; empty slot marker
  mov [bx],al
  mov al,[LDC5A]            ; get Inventory items count
  inc al                    ; increase Inventory items count
  mov [LDC5A],al
  jmp LB0F3                 ; continue the loop
LB119:
  jmp LB1AA                 ; go to Inventory screen loop

; Inventory - move (X,Y) to the next row
LB11C:
  mov al,16
  mov [LDC83],al            ; set X pos
  mov al,[LDC84]            ; get Y pos
  add al,20                 ; 20 lines lower
  mov [LDC84],al            ; set Y pos
  ret

LB12A:
  push cx
  mov cl,ch
  mov al,0x1D               ; 29 items
  sub al,cl
  push ax
  call LB529                ; Convert Inventory item number to icon number
  xor ah,ah
  mov bx,ax
  mov cl,5
  shl bx,cl                 ; BX = icon * 32
  add bx,Tileset3+2*32      ; Inventory items, 12 tiles
  mov si,bx
  call LB15D                ; Draw tile by XOR then go to next position
  mov bx,LDC5B              ; Inventory items
  mov al,[LDC5A]            ; get Inventory items count
  xor ah,ah
  add bx,ax
  pop ax
  mov [bx],al
  or al,al
  jnz LB12A_1
  call LB301                ; => mark we've got Data cartridge reader
LB12A_1:
  mov al,[LDC5A]            ; get Inventory items count
  inc al                    ; increase Inventory items count
  mov [LDC5A],al
  pop cx
  ret

; Inventory - Draw tile by XOR using X = (LDC83), Y = (LDC84),
; then go to next position
LB15D:
  mov al,[LDC84]            ; get Y pos for Inventory
  mov bl,al                 ; BL = row
  mov al,[LDC83]            ; AL = X pos for Inventory
  mov ch,16
  call L9E5F                ; Draw tile by XOR operation
  mov al,[LDC83]            ; get X pos
  add al,16                 ;   increase X
  mov [LDC83],al            ; set X pos
  cmp al,176
  jne LB15D_ret
  call LB11C
LB15D_ret:
  ret

; Clear the bottom area in the Inventory popup
ClearInventoryMesage:
  push bx
  mov bx,0x5C01             ; at row 92 col 1
  mov dx,0x1A16             ; 24 rows, 22 cols
  call ClearScreenBlock
  pop bx
  ret

; Inventory screen loop
LB1AA:
  xor al,al
  mov [LDC82],al            ; clear Inventory current
  mov al,16
  mov [LDC83],al            ; set X pos
  mov al,0x24
  mov [LDC84],al            ; set Y pos
  call LB2AF                ; Prepare item description string
LB1BB:                      ; Inventory loop starts here
  call ClearInventoryMesage
  call DrawString           ; draw Inventory item description
  call LB295                ; draw Inventory selection square
  mov al,0x44
  mov [LDC59],al            ; set delay factor
  call LB2D0                ; delay, to make Inventory selection more usable
; Inventory item selection loop
LB1C1:
  call LA0F1G               ; Scan keyboard (Enter = look/shoot key)
  cmp al,0x07               ; Escape key? (close any popups)
  jzl L9DDD                 ;   yes => return to the game main loop
  cmp al,0x05               ; Look/shoot key?
  jzl LB307
  cmp al,0x01               ; Down key?
  jzl Inventory_KeyDown
  cmp al,0x02               ; Left key?
  jzl LB1FE
  cmp al,0x03               ; Right key?
  jzl LB214
  cmp al,0x04               ; Up key?
  jzl Inventory_KeyUp
  jmp LB1C1                 ; continue the loop
LB1DB:
  call LB2DE                ; Print string LDCF9
  jmp LB2AF                 ; Prepare item description string
LB1E2:
  call LB295                ; Draw Inventory selection square
  mov al,[LDC82]            ; get Inventory current
  dec al                    ; left
  mov [LDC82],al            ; set Inventory current
  jmp LB1DB                 ; Print string LDCF9 and Prepare item description string
LB1F0:
  call LB295                ; Draw Inventory selection square
  mov al,[LDC82]            ; get Inventory current
  inc al                    ; right
  mov [LDC82],al            ; set Inventory current
  jmp LB1DB                 ; Print string LDCF9 and Prepare item description string
; Inventory Down key pressed
Inventory_KeyDown:
  call LB295                ; Draw Inventory selection square
  mov al,[LDC84]            ; get Y pos
  cmp al,0x4C               ; last row?
  je Inventory_KeyDown_1
  add al,20
  mov [LDC84],al            ; set Y pos
  mov al,[LDC82]            ; get Inventory current
  add al,10
  mov [LDC82],al            ; set Inventory current
Inventory_KeyDown_1:
  call LB1DB                ; Print string LDCF9 and Prepare item description string
  jmp LB1BB                 ; continue Inventory loop
; Inventory Up key pressed
Inventory_KeyUp:
  call LB295                ; Draw Inventory selection square
  mov al,[LDC84]            ; get Y pos
  cmp al,0x24               ; first row?
  je Inventory_KeyUp_1
  add al,-20
  mov [LDC84],al            ; set Y pos
  mov al,[LDC82]            ; get Inventory current
  add al,-10
  mov [LDC82],al            ; set Inventory current
Inventory_KeyUp_1:
  call LB1DB                ; Print string LDCF9 and Prepare item description string
  jmp LB1BB                 ; continue Inventory loop
; Inventory Left key pressed
LB1FE:                      ; Left key pressed
  mov al,[LDC83]            ; get X pos
  cmp al,16
  jzl LB25F
  call LB1E2                ; Draw square and move left
  mov al,[LDC83]            ; get X pos
  add al,-16
  mov [LDC83],al            ; set X pos
  jmp LB1BB                 ; continue Inventory loop
; Inventory Right key pressed
LB214:                      ; Right key pressed
  mov al,[LDC83]            ; get X pos
  cmp al,0xA0
  je LB22A
  call LB1F0                ; Draw square and move right
  mov al,[LDC83]            ; get X pos
  add al,16
  mov [LDC83],al            ; set X pos
  jmp LB1BB                 ; continue Inventory loop
LB22A:
  mov al,[LDC84]            ; get Y pos
  cmp al,0x4C               ; last row?
  je LB245
  call LB1F0                ; Draw square and move right
  mov al,[LDC84]            ; get Y pos
  add al,20
  mov [LDC84],al            ; set Y pos
  mov al,16
  mov [LDC83],al            ; set X pos
  jmp LB1BB                 ; continue Inventory loop
; Inventory - Put selection on the 1st item
LB245:                      ; Last row
  call LB295                ; Draw Inventory selection square
  mov al,16
  mov [LDC83],al            ; set X pos
  mov al,0x24               ; top row
  mov [LDC84],al            ; set Y pos
  xor al,al
  mov [LDC82],al            ; clear Inventory current
  call LB2DE                ; Print string LDCF9
  call LB2AF                ; Prepare item description string
  jmp LB1BB                 ; continue Inventory loop
LB25F:
  mov al,[LDC84]            ; get Y pos
  cmp al,0x24
  je LB27A
  call LB1E2                ; Draw square and move left
  mov al,[LDC84]            ; get Y pos
  add al,-20
  mov [LDC84],al            ; set Y pos
  mov al,0xA0
  mov [LDC83],al            ; set X pos
  jmp LB1BB                 ; continue Inventory loop
LB27A:
  call LB295                ; Draw Inventory selection square
  mov al,0xA0
  mov [LDC83],al            ; set X pos
  mov al,0x4C
  mov [LDC84],al            ; get Y pos
  mov al,0x1D
  mov [LDC82],al            ; set Inventory current
  call LB2DE                ; Print string LDCF9
  call LB2AF                ; Prepare item description string
  jmp LB1BB                 ; continue Inventory loop
; Draw Inventory selection square
LB295:
  mov si,Tileset3+15*32
  mov ch,16
  mov al,[LDC84]            ; get Y pos
  mov bl,al
  mov al,[LDC83]            ; get X pos
  call L9E5F                ; Draw tile by XOR operation
  jmp ShowShadowScreen

; Prepare item description string
;   Returns: BX = item description string
LB2AF:
  mov bx,0x6812
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,LDC5B              ; Inventory list
  mov al,[LDC82]            ; get Inventory current
  xor ah,ah
  add bx,ax
  mov al,[bx]
  cmp al,0x63               ; empty slot?
  je LB2CC
  mov [LDC89],al            ; set as current item
  jmp LAE19                 ; Inventory item to item description string
LB2CC:
  mov bx,SE0DB              ; "---- N o  I t e m ----"
  ret

; Print string LDCF9
LB2DE:
  mov al,[LDCF2]
  cmp al,0x01
  jne LB2EC
  mov bx,0x5C0A
  call LB2F7
LB2EC:
  mov bx,0x680A
  call LB2F7
  xor al,al
  mov [LDCF2],al
  ret
LB2F7:
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,LDCF9
  jmp DrawString

; We've got Data cartridge reader
LB301:
  mov al,0x01
  mov [LDCF5],al            ; Data cartridge reader slot
  ret

; Inventory Look/shoot key pressed
LB307:
  call SoundLookShoot
  call WaitKeyUp
  call ClearInventoryMesage
  mov bx,LDC5B              ; Inventory list
  mov al,[LDC82]            ; get Inventory current
  xor ah,ah
  add bx,ax                 ; BX = addr of current item in the list
  mov al,[bx]               ; get item
  cmp al,0x63               ; empty slot?
  jzl LB1C1
  mov [LDC89],al            ; set as current item
  or al,al                  ; $00 - Data cartridge reader?
  jz LB33F
  cmp al,0x13               ; Power Drill?
  jzl LB3F4
  cmp al,0x14               ; Life Support Data Disk?
  jzl LB44A
  cmp al,0x15               ; Air-Lock Tool?
  jzl LB487
  cmp al,0x16               ; Box of Power Cells?
  jzl LB4C4
  cmp al,0x19               ; Rubik's Cube?
  jzl LB501
  sub al,0x11               ; Data cartridge?
  jcl LB3AF
  jmp LB3E8                 ; smth other

; Data cartridge reader (or data cartridge) selected in the Inventory
LB33F:
  mov al,0x44
  mov [LDC59],al            ; set delay factor
  mov [LDC85],al            ; Use delay and copy screen in LBEDE
  mov bx,LF42F              ; Encoded screen for Data cartridge reader
  call LADEE                ; Decode 96 bytes of the screen to DBF5
  call LB177                ; Display screen from tiles with Tileset 2
  mov al,[LDCF8]
  cmp al,0x01               ; was cartridge selected?
  je LB36C                  ; yes => jump
  mov al,0x21
  mov [LDCF3],al            ; Left margin size for text
  mov bx,0x2C16
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE09B              ; "No Data Cartridge Selected"
  jmp short LB373
LB36C:
  mov bx,0x1416
  mov [L86D7],bx            ; Set penRow/penCol
  mov al,0x16
  mov [LDCF3],al            ; Left margin size for text
  pop bx                    ; restore the message address
LB373:
  call LBEDE                ; Show message char-by-char
  mov al,[LDC89]            ; get current item number
  cmp al,0x02
  jne LB373_1
  call LB39A                ; Draw level 2 access code
LB373_1:
  mov al,[LDC89]
  cmp al,0x03
  jne LB373_2
  call LB3A1                ; Draw level 3 access code
LB373_2:
  mov al,[LDC89]
  cmp al,0x04
  jne LB373_3
  call LB3A8                ; Draw level 4 access code
LB373_3:
  call ShowShadowScreen     ; Copy shadow screen to the screen
LB38B:
  call LA0F1                ; Scan keyboard
  cmp al,0x07               ; Escape key?
  jne LB38B
  xor al,al
  mov [LDC85],al            ; Skip delay and copy screen in LBEDE
  jmp L9DDD                 ; return to the main game loop
LB39A:
  mov bx,LDC96              ; Get code address - level 2 access code buffer
  jmp LBC3C
LB3A1:
  mov bx,LDC9A              ; Get code address - level 3 access code buffer
  jmp LBC3C
LB3A8:
  mov bx,LDC9E              ; Get code address - level 4 access code buffer
  jmp LBC3C

; Data cartridge selected in the Inventory
LB3AF:
  mov al,[LDCF5]            ; Data cartridge reader
  or al,al                  ; do we have the reader?
  jz LB3C8                  ; no => jump
  mov al,[LDC89]            ; get current item number
  mov bx,LDFF3              ; Table address for data cartridge messages
  call LADFF                ; Get address from table by index AL
  push bx                   ; store the message address
  mov al,0x01
  mov [LDCF8],al            ; mark that cartridge was selected
  jmp LB33F                 ; => go like the Data cartridge reader selected
LB3C8:                      ; We don't have data cartridge reader
  call LB2DE                ; Print string LDCF9
  mov bx,0x5C18
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0E3              ; "You Need A Data Cartridge Reader"
  call LB513                ; Show message
  jmp LB1C1

LB3DA:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x0011             ; offset in the room description
  add bx,dx
  mov al,[bx]
  mov cl,al
  mov al,[LDB75]            ; Direction/orientation
  sub al,cl
  ret

; Something other selected in the Inventory
LB3E8:
  call LB51F
  mov bx,SE129              ; "You dont seem to be able to use this item here"
  call LB513                ; Show message
  jmp LB1C1

; Power drill selected in the Inventory
LB3F4:
  call LB3DA
  jnzl LB3E8
  call LB538                ; Get value at $13 offset in the room description
  cmp al,0x01               ; is it Generator in the room?
  jnzl LB3E8
  mov bx,LDB90+1
  mov al,[bx]
  or al,al                  ; Generator working?
  jnz LB42E                 ; yes => jump
  call LB541                ; Get value at $0F offset in the room description
  sub al,cl                 ; compare current offset in the room with the value
  jz LB41C                  ; equal => jump
  inc bx
  mov al,[bx]
  mov cl,al
  mov al,[LDC56]            ; get offset in the room
  sub al,cl
  jnzl LB3E8
; Using Power Drill in the proper spot
LB41C:
  call LB51F
  mov bx,SE137              ; "You use the Power Drill to Repair the Generator"
  call LB513                ; Show message
  mov bx,LDB90+1
  mov byte [bx],0x01        ; mark the Generator is working now
  jmp LB1C1

LB42E:
  mov al,10
  mov [LDCF3],al            ; Left margin size for text
  mov al,12
  mov [LDCF4],al            ; Line interval for text
  call LB2DE                ; Print string LDCF9
  mov bx,0x5E0A
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE12D              ; "It doesnt look like you can do anything else here"
  call LB513                ; Show message
  jmp LB1C1

; Life Support Data Disk selected in the Inventory
LB44A:
  call LB3DA
  jnzl LB3E8
  call LB538                ; Get value at $13 offset in the room description
  cmp al,0x04
  jnzl LB3E8
  mov dx,0x0004
  call LB531                ; Get value (LDB90+DX)
  jnz LB42E
  call LB541                ; Get value at $0F offset in the room description
  sub al,cl                 ; compare current offset in the room with the value
  jz LB472                  ; equal => jump
  inc bx
  mov al,[bx]
  mov cl,al
  mov al,[LDC56]            ; get offset in the room
  sub al,cl
  jnzl LB3E8
; Using Life Support Data Disk in the proper spot
LB472:
  call LB51F
  mov bx,SE139              ; "Life-Support System has been fully restored"
  call LB513                ; Show message
  mov bx,LDB90+4            ; BX = Life-Support System
  mov byte [bx],0x01        ; mark that Life-Support System is working
  jmp LB1C1

; Air-Lock Tool selected in the Inventory
LB487:
  call LB3DA
  jnzl LB3E8
  call LB538                ; Get value at $13 offset in the room description
  cmp al,0x05
  jnzl LB3E8
  mov dx,0x0005
  call LB531                ; Get value (LDB90+DX)
  jnzl LB42E
  call LB541                ; Get value at $0F offset in the room description
  sub al,cl                 ; compare current offset in the room with the value
  jz LB4AF                  ; equal => jump
  inc bx
  mov al,[bx]
  mov cl,al
  mov al,[LDC56]            ; get offset in the room
  sub al,cl
  jnzl LB3E8
; Using Air-Lock Tool in the proper spot
LB4AF:
  call LB51F
  mov bx,SE13B              ; "The Evacuation Deck has been re-pressurised"
  call LB513                ; Show message
  mov bx,LDB90+5
  mov byte [bx],0x01        ; mark that the Evacuation Deck re-pressurised
  jmp LB1C1

; Box of Power Cells selected in the Inventory
LB4C4:
  call LB3DA
  jnzl LB3E8
  call LB538                ; Get value at $13 offset in the room description
  cmp al,0x06
  jnzl LB3E8
  mov dx,0x0006
  call LB531                ; Get value (LDB90+DX)
  jnzl LB42E
  call LB541                ; Get value at $0F offset in the room description
  sub al,cl                 ; compare current offset in the room with the value
  jz LB4EC                  ; equal => jump
  inc bx
  mov al,[bx]
  mov cl,al
  mov al,[LDC56]            ; get offset in the room
  sub al,cl
  jnzl LB3E8
; Using Box of Power Cells in the proper spot
LB4EC:
  call LB51F
  mov bx,SE13D              ; "You Insert a Power Cell. Guidance System Online"
  call LB513                ; Show message
  mov bx,LDB90+6
  mov byte [bx],0x01        ; mark we have Guidance System working
  jmp LB1C1

; Rubik's Cube selected in the Inventory
LB501:
  call LB2DE                ; Print string LDCF9
  mov bx,0x5E14
  mov [L86D7],bx
  mov bx,SE12B              ; "You dont have any time to play with this now"
  call LB513                ; Show message
  jmp LB1C1

; Show message BX and show the screen
LB513:
  call LBEDE                ; Show message char-by-char
  call ShowShadowScreen     ; Copy shadow screen to the screen
  mov al,0x01
  mov [LDCF2],al
  ret

LB51F:
  call LB2DE                ; Print string LDCF9
  mov bx,0x5E12
  mov [L86D7],bx
  ret

; Convert Inventory item number to icon number
LB529:
  or al,al
  jz LB529_ret              ; 0 = Data cartridge reader
  sub al,0x11
  jnc LB529_ret
  mov al,0x01               ; Data cartridge
LB529_ret:
  ret

; Get value at $13 offset in the room description
LB538:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x0013             ; offset in the room description
  add bx,dx
  mov al,[bx]
  ret

; Get value at $0F offset in the room description
;   Returns: CL = value from the offset; AL = LDC56 = offset in the room; BX = address of the value
LB541:
  call LAA9D                ; Get room offset in tiles for X = LDB76, Y = LDB78
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x000F             ; offset in the room description
  add bx,dx
  mov al,[bx]
  mov cl,al
  mov al,[LDC56]            ; get offset in the room
  ret

; Draw access code, 4 chars
;   BX = access code buffer address
LBC3C:
  mov dx,0x5038
  mov [L86D7],dx            ; penRow/penCol
  mov ch,0x04
LBC45:
  push cx
  push bx
  mov al,[bx]
  cmp al,0x24               ; tile number for '-' sign
  je LBC64
  add al,0x30-0x1A          ; from tile number to '0'..'9' char
LBC53:
  call DrawChar
  pop bx
  inc bx
  pop cx
  dec ch
  jnz LBC45
  ret
LBC64:
  mov al,0x2D               ; '-'
  jmp LBC53

; Found action point at room description offset $0F..$10
LBC8B:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x0011             ; offset in the room description
  add bx,dx
  mov al,[bx]
  mov cl,al
  mov al,[LDB75]            ; Direction/orientation
  sub al,cl
  jnzl LAADA
  call LAB28                ; Show small message popup
  mov al,10
  mov [LDCF3],al            ; Left margin size for text
  mov al,14
  mov [LDCF4],al            ; Line interval for text
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x0013             ; offset in the room description
  add bx,dx
  mov al,[bx]
  mov [LDC87],al            ; store RoomDesc[$13] value
  mov dl,al
  xor dh,dh
  mov bx,LDB90
  add bx,dx
  mov al,[bx]
  or al,al                  ; do we have it working?
  jz LBCD5
  mov bx,SE12D              ; " It doesnt look like you can do anything else here"
; Show the message, show screen, wait for key, continue game main loop
LBCC5:
  call LBD69                ; Set penRow/penCol = $580A
  call LBEDE                ; Show message char-by-char
  call ShowShadowScreen     ; Copy shadow screen to the screen
LBCCB:
  call LA0F1                ; Scan keyboard
  cmp al,0x07               ; Escape key?
  jne LBCCB                 ; no => wait some more
  jmp L9E2E                 ; Show the screen, continue the game main loop

LBCD5:
  mov al,[LDC87]            ; get RoomDesc[$13] value - important object in the room
  cmp al,0x01               ; the Generator
  je LBCF6
  cmp al,0x02               ; the Workstation
  je LBCFF
  cmp al,0x04               ; Life-Support System
  jzl LBD4E
  cmp al,0x05               ; Evacuation Deck re-pressure
  jzl LBD57
  cmp al,0x06               ; Guidance System
  jzl LBD60
  cmp al,0x07               ; the Pod
  jzl LBD70
; RoomDesc[$13] == $01 - the Generator
LBCF6:
  mov bx,SE12F              ; "This Generator is damaged All of the panels are loose"
  jmp LBCC5                 ; Show the message/screen, wait for key, continue game main loop
; RoomDesc[$13] == $02 - the Workstation
LBCFF:
  mov bx,LDB90+1
  mov al,[bx]
  or al,al                  ; Generator working?
  jnz LBD11                 ; yes => jump
  mov bx,SE131              ; "This Workstation doesnt seem to have any power...?"
  jmp LBCC5                 ; Show the message/screen, wait for key, continue game main loop
LBD11:
  call LAE09                ; Decode current room description to LDBF5
  mov dx,0x0030             ; offset in the room description
  add bx,dx
  mov al,[bx]
  mov [LDC89],al            ; set the current item
  call LBD69                ; Set penRow/penCol = $580A
  mov bx,SE133              ; "The Workstation has now successfully booted up"
  call LBEDE                ; Show message char-by-char
  call ShowShadowScreen     ; Copy shadow screen to the screen
  call LAB28                ; Show small message popup
LBD2B:
  call WaitAnyKey           ; was: waiting for Down key
  mov bx,LDB90+2
  mov byte [bx],0x01        ; mark Workstation is used
  mov al,[LDC89]            ; get the current item number
  xor ah,ah
  mov bx,LDB9C              ; Inventory items
  add bx,ax
  mov byte [bx],0x01        ; mark that we have the item now
  mov bx,SE135              ; "The Workstation Ejected A Data Cartridge 2"
  jmp LBCC5                 ; Show the message/screen, wait for key, continue game main loop
; RoomDesc[$13] == $04 - Life-Support System
LBD4E:
  mov bx,SE13F              ; "The Life Support System needs Re-Configuring"
  jmp LBCC5                 ; Show the message/screen, wait for key, continue game main loop
; RoomDesc[$13] == $05 - Evacuation Deck re-pressurised
LBD57:
  mov bx,SE141              ; "AirLock Control & Re-Pressurisation Station"
  jmp LBCC5                 ; Show the message/screen, wait for key, continue game main loop
; RoomDesc[$13] == $06 - Guidance System
LBD60:
  mov bx,SE143              ; "This MainFrame is missing a Power Cell"
  jmp LBCC5                 ; Show the message/screen, wait for key, continue game main loop
; Set penRow/penCol = $580A
LBD69:
  push bx
  mov bx,0x580A
  mov [L86D7],bx            ; Set penRow/penCol
  pop bx
  ret
; RoomDesc[$13] == $07 - Pod
LBD70:
  mov bx,LDB90+6            ; BX = address of Guidance System mark
  mov al,[bx]               ; mark Guidance System working now
  or al,al                  ; does it work?
  jnz LBD85                 ; yes => Flying away on the Pod
  mov bx,SE145              ; "This Pod cant naviagate. Guidance System is offline"
  jmp LBCC5                 ; Show the message/screen, wait for key, continue game main loop

; Flying away on the Pod
LBD85:
  mov al,0x44
  mov [LDC59],al            ; set delay factor
  mov [LDC85],al            ; Use delay and copy screen in LBEDE
  xor al,al
  mov [LDCF3],al            ; Left margin size for text
  mov [LDBF4],al            ; clear counter of achievements
  mov al,14
  mov [LDCF4],al            ; Line interval for text
; Showing end-of-story screen
  call LBC7D                ; Clear and show shadow screen
  call ScreenThemeNite      ; switch to dark theme for story mode
  call ClearPenRowCol
  mov bx,SE11B              ; "The onboard guidance system picks up a ...
  call LBEDE                ; Show message char-by-char
  call WaitAnyKey           ; was: Wait for MODE key
; Showing statistics screen
  mov al,0x06
  mov [LDCF3],al            ; Left margin size for text
  call ClearShadowScreen
  mov bx,0x0C0C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0A1              ; "Items Found (/24): Enemies Killed: PlayerDeaths: Awards:
  call LBEDE                ; Show message char-by-char
  call LBC34                ; Delay x20
  mov dx,0x0C8C
  mov al,[LDBC7]            ; get Items Found count
  mov bl,al
  xor bh,bh
  call LB97D                ; Draw 5-digit number BX at row/col DX, and show the screen
  call LBC34                ; Delay x20
  mov dx,0x1A8C
  mov bx,[LDBC5]            ; get Enemies Killed count
  call LB97D                ; Draw 5-digit number BX at row/col DX, and show the screen
  call LBC34                ; Delay x20
  mov dx,0x288C
  mov bx,[LDBC3]            ; get Player Deaths count
  call LB97D                ; Draw 5-digit number BX at row/col DX, and show the screen
  call LBC34                ; Delay x20
  mov al,[LDBC7]            ; get Items Found count
  sub al,0x14               ; 20 or more?
  jc LBE06                  ; no => jump
  mov bx,0x520C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0AD              ; "Sherlock Holmes" (achievement)
  call LBEDE                ; Show message char-by-char
  mov al,[LDBF4]
  inc al                    ; increase counter of achievements
  mov [LDBF4],al
  jmp short LBE12
LBE06:
  mov bx,0x520C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0AB              ; "Sir Miss-A-Lot" (achievement)
  call LBEDE                ; Show message char-by-char
LBE12:
  mov dx,0x0032             ; 50
  mov bx,[LDBC5]            ; get Enemies Killed count
  call CpHLDE               ; Compare BX and DX
  jc LBE32                  ; less 50? => jump
  mov bx,0x600C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0B1              ; "Terminator" (achievement)
  call LBEDE                ; Show message char-by-char
  mov al,[LDBF4]
  inc al                    ; increase counter of achievements
  mov [LDBF4],al
  jmp short LBE3E
LBE32:
  mov bx,0x600C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0AF              ; "Running Scared"
  call LBEDE                ; Show message char-by-char
LBE3E:
  mov dx,0x0000
  mov bx,[LDBC3]            ; get Player deaths count
  call CpHLDE               ; Compare BX and DX
  jne LBE5E
  mov bx,0x6E0C
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0B5              ; "Survivor" (achievement)
  call LBEDE                ; Show message char-by-char
  mov al,[LDBF4]
  inc al                    ; increase counter of achievements
  mov [LDBF4],al
  jmp short LBE6A
LBE5E:
  mov bx,0x6E0C             ; Player deaths > 0
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0B3              ; "Over & Over Again" (achievement)
  call LBEDE                ; Show message char-by-char
LBE6A:
  call WaitAnyKey           ; was: Wait for MODE key
  call ClearShadowScreen
  mov al,[LDBF4]            ; get counter of achievements
  cmp al,0x03               ; do we have all three of them?
  jne LBE8A                 ; no => skip extended ending
; Extended ending
  xor al,al
  mov [LDCF3],al            ; clear Left margin size for text
  call ClearPenRowCol
  mov bx,SE11D              ; "System Alert triggered: ..."
  call LBEDE                ; Show message char-by-char
  jmp short LBE9B
LBE8A:
  mov al,30
  mov [LDCF3],al            ; Left margin size for text
  mov bx,0x3414
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE0A9              ; "Earn 3 Good Awards for an Extended Ending!"
  call LBEDE                ; Show message char-by-char
LBE9B:
  call WaitAnyKey           ; was: Wait for MODE key
  call ClearShadowScreen
  mov bx,0x2E46
  mov [L86D7],bx            ; Set penRow/penCol
  mov bx,SE11F              ; "The End"
  call LBEDE                ; Show message char-by-char
  call LBC34                ; Delay x20
  jmp LBF6F                 ; The End

; Draw 5-digit number BX at row/col DX, and show the screen
LB97D:
  mov [L86D7],dx            ; set penRow/penCol
  call DrawNumber5
  jmp ShowShadowScreen      ; Copy shadow screen to the screen

%if DEBUG_NEXT_ROOM
; DEBUG (until doors are ported): go to the next room, have the weapon
DebugNextRoom:
  mov al,[LDB79]
  inc al
  cmp al,72
  jb DebugNextRoom_1
  xor al,al
DebugNextRoom_1:
  mov [LDB79],al
  mov byte [LDCF7],1
  xor al,al
  mov [LDB82],al            ; no alien in the new room yet
  call WaitKeyUp
  jmp L9E2E
%endif

%if DEBUG_NEXT_ROOM
DebugAll:
  mov di,LDB9C
  mov cx,0x1D
  mov al,1
  rep stosb
  xor al,al                 ; unused slots: $11, $12, $1A..$1C
  mov [LDB9C+0x11],al
  mov [LDB9C+0x12],al
  mov [LDB9C+0x1A],al
  mov [LDB9C+0x1B],al
  mov [LDB9C+0x1C],al
  mov al,1
  mov di,LDCA2
  mov cx,0x48
  rep stosb
  mov byte [LDCF7],1
  call WaitKeyUp
  jmp L9E2E
%endif
