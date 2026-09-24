; **** (RE)START & INTERRUPT SERVICE ROUTINES ****

; Start the space invaders game. When the ROM is loaded into the 8080's memory, the code
; begins at 0x0000. It is roughly followed by initialization values for game variables at
; 0x1B00 and then game constants at 0x1C00. However, there is some mixing between the three.
; There are three major control flow pathways.
;         1. start (entry point: 0x0000) -> init -> splash loop or game loop 
;         2. midscreen interrupt service routine (0x0008) -> MIDSCREEN ISR game processing
;         3. VBLANK interrupt service routine (0x0010) -> VBLANK ISR game processing
; Midscreen happens at the rough midpoint of screen refresh and VBLANK happens at the end. 
; In the original machine, the latter two are triggered by interrupts coming from the monitor.

.start                                                      ; INPOINT VECTOR 0x00 (normal game start)
     0x0000: 00          |   NOP
     0x0001: 00          |   NOP
     0x0002: 00          |   NOP
     0x0003: C3 [D4 18]  |   JMP 0x18D4                     ; jump to init
     0x0006: 00          |   NOP
     0x0007: 00          |   NOP

; name: midscreenISR
; This is the entry point for the interrupt service routine vector at MIDSCREEN
; Here we push registers to the stack and then jump for further processing to
; 0x008C, which is the midsreen interrupt processing gateway

.midscreenISR                                               ; MIDSCREEN interrupt vector
     0x0008: F5          |   PUSH PSW
     0x0009: C5          |   PUSH B
     0x000a: D5          |   PUSH D
     0x000b: E5          |   PUSH H
     0x000c: C3 [8C 00]  |   JMP 0x008C                     ; midscreen processing gateway
     0x000f: 00          |   NOP

; name: vblankISR
; This is the entry point for the interrupt service routine vector at VBLANK.
; Here we push registers to the stack, 
; set ram variable 0x2072 (which indicates the ISR we are in) to VBLANK (0x80)
; decrement loop control for game-loop or splash-loop timed pauses (0x20C0)
; and call a handler for the arcade machine's "_TILT" command
; we then fall into the handler for the machine's "_COIN" command

.vblankISR                                                       ; VBLANK interrupt vector
     0x0010: F5          |   PUSH PSW
     0x0011: C5          |   PUSH B
     0x0012: D5          |   PUSH D
     0x0013: E5          |   PUSH H
     0x0014: 3E [80]     |   MVI A, 0x80
     0x0016: 32 [72 20]  |   STA 0x2072                          ; set screenDrawStatus to VBLANK
     0x0019: 21 [C0 20]  |   LXI H, 0x20C0 
     0x001c: 35          |   DCR M                               ; decrement pauseLoopControl
     0x001d: CD [CD 17]  |   CAL 0x17CD                          ; handle _TILT
                                                                 ;    tilt exits to splash/demo
                                                                 ;    returns if no tilt

; ****************** VBLANK INTERRUPT SERVICE ROUTINE PROCEDURES *********************

; -------------------------------------------------------------------------
;
; **** VBLANK ISR PROCEDURES ***
;
;   0x0020: _COIN signal and credit service routines
;   0x003F: VBLANK game processing gateway
;   0x0050: check credit, exit ISR to wait-to-start loop
;   0x006F: game/demo/splash processing
;   0x0082: restore registers and return from ISR (shared with MIDSCREEN ISR)
;   NOTE: procedures for _TILT handling during VBLANK can be found at 0x17CD
;
; -------------------------------------------------------------------------

; name: coinTriggerCheck [VBLANK ISR]
; This checks bit 0 of input port 1 to see if a coin has been inserted (coin slot opened)
; if so, we call a function that will trigger credit processing in a future ISR, once
; the coin slot has closed

.coinTriggerCheck
     0x0020: DB [01]     |   IN 0x01                             ; check INPUT PORT 1 for _COIN signal
     0x0022: 0F          |   RRC
     0x0023: DA [67 00]  |   JC 0x0067                           ; if _COIN set, triggerCredit

; name: creditTriggeredCheck [VBLANK ISR]
; We reach this point only if the _COIN signal is off, which means the credit door is closed.
; once the coin door has been opened at least once, the RAM variable at 0x20EA ("isCreditTriggered")
; will be set. However, credit servicing during the VBLANK ISR does not register a new credit until
; the credit door is also closed once again. (I assume this is to prevent 1 coin from triggering
; multiple credits)
; Here is where we handle the second half of that, once the door is closed

.creditTriggeredCheck [VBLANK ISR]
     0x0026: 3A [EA 20]  |   LDA 0x20EA                          ; otherwise, check isCreditTriggered
     0x0029: A7          |   ANA A
     0x002a: CA [42 00]  |   JZ 0x0042                           ; if isCreditTriggered clear,
                                                                 ;    ... coin door not yet opened
                                                                 ;    ... skip to VBLANK gateway

; name: incrementCreditBalance
; the "coin door" has been opened and then closed again, so it's time to register credit.
; We only allow credit up to 99 though, because we are limited to two digits of binary-coded decimal

.incrementCreditBalance [VBLANK ISR]
     0x002d: 3A [EB 20]  |   LDA 0x20EB                          ; check creditbalance
     0x0030: FE [99]     |   CPI 0x99                            ;    ... if it's 99,
     0x0032: CA [3E 00]  |   JZ 0x003E                           ;    ... exit coin control
     0x0035: C6 [01]     |   ADI 0x01                            ; otherwise use binary-coded decimal
     0x0037: 27          |   DAA                                 ;    math to add 1
     0x0038: 32 [EB 20]  |   STA 0x20EB                          ;    ... and update creditBalance
     0x003b: CD [47 19]  |   CAL 0x1947                          ; display creditBalance

; name: exitCreditService [VBLANK ISR]
; Clears A for storage in the 'coin door opened' RAM variable, 0x20EA

.exitCreditService
     0x003e: AF          |   XRA A

; name: storeCreditStatus [VBLANK ISR]
; Used to update the RAM variable that indicates if the coin door has been opened.
; If a coin is inserted, this is actually called twice, once at 0069 in triggerCredit,
; then again here.
; After, we fall into the VBLANK ISR processing gateway

.storeCreditStatus                                               ; can reach from VBLANK
     0x003f: 32 [EA 20]  |   STA 0x20EA

; name: vblankISRGateway [VBLANK ISR]
; this is the primary control flow checkpoint for VBLANK. We check two key variables: 
; ** 0x20E9: ISR processing lock 
;              - 0: locked. We exit without further processing
;              - 1: unlocked. We proceed.
; ** 0x20EF: Mode toggle
;              - 0: demo mode, including splash screens and wait-for-start
;              - 1: game mode

.vblankISRGateway                                                ; can reach from VBLANK
     0x0042: 3A [E9 20]  |   LDA 0x20E9
     0x0045: A7          |   ANA A                               ; if ISRStatus is clear
     0x0046: CA [82 00]  |   JZ 0x0082                           ;    ... return from ISR
     0x0049: 3A [EF 20]  |   LDA 0x20EF                          ; otherwise:
     0x004c: A7          |   ANA A                               ;    gameStatus?
     0x004d: C2 [6F 00]  |   JNZ 0x006F                          ;    ... 1: start game processing

; name: checkCreditBalance [VBLANK ISR]
; If there is sufficient credit (at least one coin has been inserted), but we are not in a game,
; the VBLANK ISR will direct us into the wait-for-start loop

.checkCreditBalance
     0x0050: 3A [EB 20]  |   LDA 0x20EB
     0x0053: A7          |   ANA A                               ; if credit balance is nonzero
     0x0054: C2 [5D 00]  |   JNZ 0x005D                          ;    ... enter wait-for-start loop
     0x0057: CD [BF 0A]  |   CAL 0x0ABF                          ; otherwise, process splash screens
     0x005a: C3 [82 00]  |   JMP 0x0082                          ;    ... and return from ISR

; name: waitToStart [VBLANK ISR]
; Here the ISR determines if we are already in wait-to-start. If we are, it returns us to where we were.
; Otherwise, it directs us to the top of the wait-to-start loop, and exits VBLANK there.

.waitToStart
     0x005d: 3A [93 20]  |   LDA 0x2093                          ; check if we're already
     0x0060: A7          |   ANA A                               ; waiting to start?
     0x0061: C2 [82 00]  |   JNZ 0x0082                          ;    ... if yes: return from ISR
     0x0064: C3 [65 07]  |   JMP 0x0765                          ; otherwise, exit VBLANK and enter wait loop

; name: triggerCredit [VBLANK ISR]
; We set the RAM variable indicating that the coin gateway has been opened

.triggerCredit
     0x0067: 3E [01]     |   MVI A, 0x01                         ; set isCreditTriggered to 1
     0x0069: 32 [EA 20]  |   STA 0x20EA                          ; ... and store credit status
     0x006c: C3 [3F 00]  |   JMP 0x003F                          ; store again, fall into VBLANK gateway

; name: gameProcessing_vblank [VBLANK ISR]
; This is where VBLANK launches into the meat of ISR game processing. Note that during splash, ISR 
; jumps in here right below the sound output trigger if 0x20C1 indicates we're in the demo.
; We then return from ISR

.gameProcessing_vblank
     0x006f: CD [40 17]  |   CAL 0x1740                          ; handler for invader sound sequence
                                                                 ; skip for splash/demo

._splashDemoInpoint                                              ; rejoin here for splash/demo
     0x0072: 3A [32 20]  |   LDA 0x2032
     0x0075: 32 [80 20]  |   STA 0x2080                          ; sync shot timer
     0x0078: CD [00 01]  |   CAL 0x0100                          ; end explosion timer / draw current invader
     0x007b: CD [48 02]  |   CAL 0x0248                          ; game processing: parse structures
     0x007e: CD [13 09]  |   CAL 0x0913                          ; set flag when it's UFO time
     0x0081: 00          |   NOP

; name: returnFromISR [MIDSCREEN/VBLANK INTERRUPT EXIT POINT]
; restore the stack by popping registers saved during ISR, enable interrupts & return

.returnFromISR
     0x0082: E1          |   POP H                               ; restore registers
     0x0083: D1          |   POP D
     0x0084: C1          |   POP B
     0x0085: F1          |   POP PSW
     0x0086: FB          |   EI                                  ; enable interrupts
     0x0087: C9          |   RET                                 ; return to where we were before interrupt

.__not_accessed__     
     0x0088: 00 [00 00]  |   NOP
     0x0089: 00 [00 00]  |   NOP
     0x008a: 00 [00 AF]  |   NOP
     0x008b: 00 [AF 32]  |   NOP

; ************************* MIDSCREEN INTERRUPT SERVICE ROUTINE *************************

; -------------------------------------------------------------------------
;
; **** MIDSCREEN ISR PROCEDURES ***
;
;   0x008C: MIDSCREEN game processing gateway
;   0x00A5: MIDSCREEN demo/game processing (no non-demo splash)
;   ** NOTE: 0x0082 exit-from-ISR routine is above and shared with VBLANK ISR
;
; -------------------------------------------------------------------------

; name: midscreenISRGateway [MIDSCREEN ISR]
; This is the primary control-flow checkpoint for MIDSCREEN. 
; We clear the RAM variable at 0x2072 (which sets which ISR we're in), indicating MIDSCREEN
; Then we check the following:
; ** 0x20E9: ISR processing lock 
;              - 0: locked. We exit without further processing
;              - 1: unlocked. We proceed.
; ** 0x20EF: Mode toggle
;              - 0: demo mode, including splash screens and wait-for-start
;              - 1: game mode

.midscreenISRGateway
     0x008c: AF          |   XRA A
     0x008d: 32 [72 20]  |   STA 0x2072                          ; set screenDrawStatus to MIDSCREEN
     0x0090: 3A [E9 20]  |   LDA 0x20E9                          ; check ISRStatus..
     0x0093: A7          |   ANA A                               ;    ... is it clear?
     0x0094: CA [82 00]  |   JZ 0x0082                           ;    return from ISR
     0x0097: 3A [EF 20]  |   LDA 0x20EF                          ; otherwise... gameStatus?
     0x009a: A7          |   ANA A                               ;    ... nonzero...
     0x009b: C2 [A5 00]  |   JNZ 0x00A5                          ;    ... start game processing

; name: midscreenSplashGateway [MIDSCREEN ISR]
; We reach this if we're in demo mode during midscreen ISR. Here we return unless we're
; actually processing the demo, rather than a sprite animation

._midscreenSplashGateway                                         ; reach this from midscreen
     0x009e: 3A [C1 20]  |   LDA 0x20C1                          ; where are we in splash sequence?
     0x00a1: 0F          |   RRC                                 ;    .. LSB not set?
     0x00a2: D2 [82 00]  |   JNC 0x0082                          ; return from ISR

; name: gameProcessing_MIDSCREEN [MIDSCREEN ISR]
; In game mode, parses the following game structures: player shot, alien shot 1, alien shot 2,
; alien shot 3/UFO
; Then gets coordinates for next "current alien", populating 0x200B/0x200C with Y & X
; Then jumps to exit ISR and return to where were were in previous loop

.gameProcessing_MIDSCREEN
     0x00a5: 21 [20 20]  |   LXI H, 0x2020                       ; point H at 2nd game object
     0x00a8: CD [4B 02]  |   CAL 0x024B                          ; call parseStructsLoop
     0x00ab: CD [41 01]  |   CAL 0x0141                          ; move to next alien & flag for drawing
     0x00ae: C3 [82 00]  |   JMP 0x0082                          ; return from ISR

; ********************************* INITIALIZE ALIENS ***************************************

; --------------------------------------------------------------------------------
;
; **** INITIALIZE ALIENS ***
;
;    NOTE: we reach this non-ISR procedure as part of launching a 
;          new game or round for one or two players
;
;    0x00B1: set coordinates and direction for the origin alien
;
; -------------------------------------------------------------------------

; name: initializeAliens [PRE-GAME-LOOP]
; called while loading data for a player in order to start or restore a game. This sets the data for 
; the origin alien, the first current alien, the direction aliens are going horizontally, and the
; horizontal offset they are using.

.initializeAliens
     0x00b1: CD [86 08]  |   CAL 0x0886                          ; get pointer to "origin alien" in lower left
     0x00b4: E5          |   PUSH H                              ; save coordinates on stack
     0x00b5: 7E          |   MOV A, M                            
     0x00b6: 23          |   INX H 
     0x00b7: 66          |   MOV H, M                            ; MSB in H
     0x00b8: 6F          |   MOV L, A                            ; LSB in L --> coordinates in HL
     0x00b9: 22 [09 20]  |   SHLD 0x2009                         ; save "origin alien" at 0x2009
     0x00bc: 22 [0B 20]  |   SHLD 0x200B                         ; initialize "current alien" at 0x200B
     0x00bf: E1          |   POP H                               ; restore coordinates
     0x00c0: 2B          |   DCX H                               ; decrease HL to xxFB (in current player data)
     0x00c1: 7E          |   MOV A, M                            ; put in A
     0x00c2: FE [03]     |   CPI 0x03                            ; if it's 3...
     0x00c4: C2 [C8 00]  |   JNZ 0x00C8
     0x00c7: 3D          |   DCR A                               ; .... decrement and store in 0x2008
     0x00c8: 32 [08 20]  |   STA 0x2008                          ; otherwise just store directly in 0x2008
     0x00cb: FE [FE]     |   CPI 0xFE                            ; if it's not -2, movement is to the right
     0x00cd: 3E [00]     |   MVI A, 0x00                         ;
     0x00cf: C2 [D3 00]  |   JNZ 0x00D3                          ; ... set A to 0
     0x00d2: 3C          |   INR A                               ; ... else 1
     0x00d3: 32 [0D 20]  |   STA 0x200D                          ; Store A in 0x200D
     0x00d6: C9          |   RET                                 ; ... and return

; name: initializeInvaderMovement [PRE-GAME LOOP]
; Here we initialize invaders by starting them (in both players' data segments) moving to the right
; we then jump into removing player 2's on-screen score if there is only 1 player.

.initializeInvaderMovement
     0x00d7: 3E [02]     |   MVI A, 0x02
     0x00d9: 32 [FB 21]  |   STA 0x21FB                          ; start invaders moving 2 to right (player 1)
     0x00dc: 32 [FB 22]  |   STA 0x22FB                          ; start invaders moving 2 to right (player 2)
     0x00df: C3 [E4 08]  |   JMP 0x08E4                          ; remove player 2 score if only 1 player

.__not_accessed__
     0x00e2: 00          |   NOP
     0x00e3: 00          |   NOP
     0x00e4: 00          |   NOP
     0x00e5: 00          |   NOP
     0x00e6: 00          |   NOP
     0x00e7: 00          |   NOP
     0x00e8: 00          |   NOP
     0x00e9: 00          |   NOP
     0x00ea: 00          |   NOP
     0x00eb: 00          |   NOP
     0x00ec: 00          |   NOP
     0x00ed: 00          |   NOP
     0x00ee: 00          |   NOP
     0x00ef: 00          |   NOP
     0x00f0: 00          |   NOP
     0x00f1: 00          |   NOP
     0x00f2: 00          |   NOP
     0x00f3: 00          |   NOP
     0x00f4: 00          |   NOP
     0x00f5: 00          |   NOP
     0x00f6: 00          |   NOP
     0x00f7: 00          |   NOP
     0x00f8: 00          |   NOP
     0x00f9: 00          |   NOP
     0x00fa: 00          |   NOP
     0x00fb: 00          |   NOP
     0x00fc: 00          |   NOP
     0x00fd: 00          |   NOP
     0x00fe: 00          |   NOP
     0x00ff: 00          |   NOP

; ********************************* DRAW CURRENT INVADER ***************************************

; ----------------------------------------------------------------
;
;    NOTE: we reach this as part of VBLANK ISR game processing.
;          the "current invader" is advanced during MIDSCREEN,
;          where that invader's coordinates are also advanced.
;          However, these procedures are where the invader is actually
;          drawn (during VBLANK)
;
;    0x0100 - draw current invader
;
;    NOTE: the RAM flag at 0x2000 coordinates with MIDSCREEN advance-alien procedure
;
; ----------------------------------------------------------------

; name: updateInvader [VBLANK ISR]
; this is called during game/demo processing in the VBLANK ISR sequence when game processing 
; is allowed.
; Here we begin by checking to see if the current invader has been hit. 
; If so, we process its explosion.
; otherwise, we move on and fall into getInvaderData for the current alien

.updateInvader
     0x0100: 21 [02 20]  |   LXI H, 0x2002                       ; 0x2002: has player shot hit something?
     0x0103: 7E          |   MOV A, M
     0x0104: A7          |   ANA A
     0x0105: C2 [38 15]  |   JNZ 0x1538                          ; ... if yes: process explosion, return
                                                                 ; this either counts down or
                                                                 ; clears explosion sprite & resets flags

; name: _checkInvaderStatus [VBLANK ISR]
; Here we check the current invader's status. If it's dead, we don't draw it. Otherwise,
; we are going to draw it.

._checkInvaderStatus
     0x0108: E5          |   PUSH H                              ; otherwise,
     0x0109: 3A [06 20]  |   LDA 0x2006                          ; grab index for current alien
     0x010c: 6F          |   MOV L, A                            ; ... and put it in L
     0x010d: 3A [67 20]  |   LDA 0x2067                          ; get invader data for correct player
     0x0110: 67          |   MOV H, A                            ; ... and put it in H
     0x0111: 7E          |   MOV A, M                            ; A <- the current alien's status
     0x0112: A7          |   ANA A
     0x0113: E1          |   POP H
     0x0114: CA [36 01]  |   JZ 0x0136                           ; if the alien is dead, don't draw

; name _getInvaderSprite [VBLANK ISR]
; Information about the row the invader is located in has previously been stored in 0x2004. 
; Here we use that information to get an offset to the appropriate alien sprite.
;    * rows 0 & 1 are at 0x1C00
;    * rows 2 & 3 are at 0x1C10
;    * row 4 is at 0x1C20
;    This pointer value is stored in DE and we continue.

._getInvaderSprite
     0x0117: 23          |   INX H
     0x0118: 23          |   INX H
     0x0119: 7E          |   MOV A, M                            ; 0x2004: current alien row
     0x011a: 23          |   INX H
     0x011b: 46          |   MOV B, M                            ; 0x2005: alien's animation state
     0x011c: E6 [FE]     |   ANI 0xFE                            ; convert row to  sprite offset
     0x011e: 07          |   RLC                                 ;    * rows 0 & 1 -> no offset
     0x011f: 07          |   RLC                                 ;    * rows 2 & 3 -> 0x16 offset
     0x0120: 07          |   RLC                                 ;    * row 4 -> 0x32 offset
     0x0121: 5F          |   MOV E, A
     0x0122: 16 [00]     |   MVI D, 0x00
     0x0124: 21 [00 1C]  |   LXI H, 0x1C00                       ; point to sprite data area
     0x0127: 19          |   DAD D                               ;    by adding offset
     0x0128: EB          |   XCHG                                ; put pointer to sprite in DE (0x1c00 + offset)

; name: _drawInvader [VBLANK ISR]
; check to see if we need to toggle the sprite forward to second state by polling RAM variable
; at 0x2005. Provide unshifted coordinates and size, then call the procedure that shifts and
; then draws the sprite in question. Afterward, return.

._drawInvader
     0x0129: 78          |   MOV A, B                            ; when 0x2005 flag is nonzero
     0x012a: A7          |   ANA A
     0x012b: C4 [3B 01]  |   CNZ 0x013B                          ; ... toggle sprite to second state
     0x012e: 2A [0B 20]  |   LHLD 0x200B                         ; put sprite's unshifted position in HL
     0x0131: 06 [10]     |   MVI B, 0x10                         ; set size of sprite
     0x0133: CD [D3 15]  |   CAL 0x15D3                          ; shift position & draw sprite (overwrite)
     0x0136: AF          |   XRA A
     0x0137: 32 [00 20]  |   STA 0x2000                          ; 0x2000: clear draw alien lock
     0x013a: C9          |   RET                                 ; and return

; name: _toggleSprite [VBLANK ISR]
; When this is called, we add 0x30 to the sprite pointer, which corresponds to the 
; second-state sprite for the same invader. That pointer is stored in DE once again and returned.

._toggleSprite
     0x013b: 21 [30 00]  |   LXI H, 0x0030 
     0x013e: 19          |   DAD D
     0x013f: EB          |   XCHG
     0x0140: C9          |   RET

; ***************************** ADVANCE INVADER POINTERS ************************************

; -------------------------------------------------------
;
; ** NOTE: We reach this as part of the MIDSCREEN ISR game processing
;          (after processing the game structures is complete)
;
;    0x0141 - point to next active alien position in alien metadata array
;         - loop control: prevents infinite loop when all aliens are gone
;         - boundary check: if aliens are low, exits ISR via "invaders win" routine
;         - when end of array reached: loop & call routines to move origin alien
;
;    NOTE: the RAM flag at 0x2000 coordinates with VBLANK draw-alien procedure
;
; -------------------------------------------------------

; name: moveToNextAlien [MIDSCREEN ISR]
; after parsing the game structure, we move pointers to the next invader in the array.
; at the end, the "current invader" index is reset to 0 and we advance in the invader's 
; sprite sequence.
; To prevent infinite looping when all aliens are dead, allInvadersDrawn returns up two 
; levels from the call at 0x157, returning to gameProcessing_MIDSCREEN, which then returns
; from ISR.

.moveToNextAlien 
     0x0141: 3A [68 20]  |   LDA 0x2068                          ; is player
     0x0144: A7          |   ANA A                               ; ... dying?
     0x0145: C8          |   RZ                                  ; return if so.
     0x0146: 3A [00 20]  |   LDA 0x2000                          ; otherwise, are we still drawing?
     0x0149: A7          |   ANA A                               ; ... if we are,
     0x014a: C0          |   RNZ                                 ; ... return
     0x014b: 3A [67 20]  |   LDA 0x2067                          ; put MSB to player's data area in H
     0x014e: 67          |   MOV H, A
     0x014f: 3A [06 20]  |   LDA 0x2006                          ; get index/address of current alien
     0x0152: 16 [02]     |   MVI D, 0x02                         ; put 0x02 in D to prevent infinite looping
     0x0154: 3C          |   INR A                               ; add 1 to alien index
     0x0155: FE [37]     |   CPI 0x37                            ; have we finished all 55?
     0x0157: CC [A1 01]  |   CZ 0x01A1                           ; .... if so, wrap to 0, toggle animation state
                                                                 ; .... move alien coords by change_x and change_y
                                                                 ; .... and reset change_x
     0x015a: 6F          |   MOV L, A                            ; point HL at next alien
     0x015b: 46          |   MOV B, M                            ; ... is the value in memory...
     0x015c: 05          |   DCR B                               ;    ... zero?
     0x015d: C2 [54 01]  |   JNZ 0x0154                          ; if it is, loop: skip this alien
     0x0160: 32 [06 20]  |   STA 0x2006                          ; store the new current alien index
     0x0163: CD [7A 01]  |   CAL 0x017A                          ; puts alien Y in L, X in C, row in D
     0x0166: 61          |   MOV H, C
     0x0167: 22 [0B 20]  |   SHLD 0x200B                         ; store this aliens coords in 200B(L), 200C(X)
     0x016a: 7D          |   MOV A, L                            
     0x016b: FE [28]     |   CPI 0x28                            ; is 0x28 greater than Y?
     0x016d: DA [71 19]  |   JC 0x1971                           ; if so alien is very low. Invaders win!
     0x0170: 7A          |   MOV A, D                            ; ... otherwise,
     0x0171: 32 [04 20]  |   STA 0x2004                          ; put alien's row in 0x2004
     0x0174: 3E [01]     |   MVI A, 0x01
     0x0176: 32 [00 20]  |   STA 0x2000                          ; flag that drawing has begun
     0x0179: C9          |   RET                                 ; ... and return

; name: getInvaderCoords [MIDSCREEN ISR, PROCESS ALIEN SHOT SUBROUTINE (BOTH ISR)]
; We take the invader's row and column numbers, and multiply each by 0x10. We add each to the
; origin alien's coordinates to get the current alien's x-y coordinates.
; note that these are encoded coordinates and must be converted to actual screen addresses.
; puts Y into L and X into C
; This is used by both the 'load current invader' subroutine (above) and the process alien shot
; subroutine (it is used to spawn explosion sprite)

.getInvaderCoordinates                                      ; puts Y-coord in L, X-coord in C, row in D
     0x017a: 16 [00]     |   MVI D, 0x00                    ; start with row 0
     0x017c: 7D          |   MOV A, L                       ; index of current alien
     0x017d: 21 [09 20]  |   LXI H, 0x2009                  ; put current alien's y-coordinate
     0x0180: 46          |   MOV B, M                       ; ... in B
     0x0181: 23          |   INX H                          ; put current alien's x-coordinate
     0x0182: 4E          |   MOV C, M                       ; ... in C

; name: _getInvaderY
; gets current alien's Y-coordinate and puts it in B

._getInvaderY
     0x0183: FE [0B]     |   CPI 0x0B                       ; is 11 greater than alien's index?
     0x0185: FA [94 01]  |   JM 0x0194                      ; ... yes, Y is right. Get X below
     0x0188: DE [0B]     |   SBI 0x0B                       ; otherwise, subract 11 from index
     0x018a: 5F          |   MOV E, A                       ; ... and save it
     0x018b: 78          |   MOV A, B                       ; add 0x10 to y-coordinate (up a row)
     0x018c: C6 [10]     |   ADI 0x10
     0x018e: 47          |   MOV B, A                       ; ... and put back in B
     0x018f: 7B          |   MOV A, E                       ; restore index to accumulator
     0x0190: 14          |   INR D                          ; increase row number
     0x0191: C3 [83 01]  |   JMP 0x0183                     ; ... and jump until we're done

; name: _getInvaderX
; gest current alien's X-coordinate and puts it in C. Y-coordinate now in L

._getInvaderX
     0x0194: 68          |   MOV L, B                       ; move Y-coordinate into L
     0x0195: A7          |   ANA A                          ; are we in the column (A is 0)?
     0x0196: C8          |   RZ                             ; ... if so, return
     0x0197: 5F          |   MOV E, A                       ; otherwise... we've got more to advance
     0x0198: 79          |   MOV A, C
     0x0199: C6 [10]     |   ADI 0x10                       ; add 0x10 to x-coordinate
     0x019b: 4F          |   MOV C, A                       ; and store in C
     0x019c: 7B          |   MOV A, E                       ;
     0x019d: 3D          |   DCR A                          ; subtract from index
     0x019e: C3 [95 01]  |   JMP 0x0195                     ; jump until no more to subtract, then return

; name: allInvadersDrawn
; This is housekeeping functionality for when we get to the end of the array of aliens.
; This: have we already reached the array's end once? That means the whole array is empty.
; we pop the return address of the stack, which allows us to return twice,
; returning back from moveToNextAlien without setting flag to draw.

._allInvadersDrawn
     0x01a1: 15          |   DCR D                               ; decrement D. is it zero?
     0x01a2: CA [CD 01]  |   JZ 0x01CD                           ; pop H and return (2 callframes)
     0x01a5: 21 [06 20]  |   LXI H, 0x2006                       ; otherwise grab current alien index
     0x01a8: 36 [00]     |   MVI M, 0x00                         ; and wrap it back around to 0
     0x01aa: 23          |   INX H                               ; point to 0x2007
     0x01ab: 4E          |   MOV C, M                            ; put current value in C
     0x01ac: 36 [00]     |   MVI M, 0x00                         ; and reset 0x2007 in memory to 0
     0x01ae: CD [D9 01]  |   CAL 0x01D9                          ; alien's coords now in: 0x2009 (Y), 0x200A (X)
     0x01b1: 21 [05 20]  |   LXI H, 0x2005                       ; grab and...
     0x01b4: 7E          |   MOV A, M
     0x01b5: 3C          |   INR A                               ; ... toggle Alien's animation state
     0x01b6: E6 [01]     |   ANI 0x01                            ; we only care about bit 0
     0x01b8: 77          |   MOV M, A                            ; put back in memory at 0x2005
     0x01b9: AF          |   XRA A
     0x01ba: 21 [67 20]  |   LXI H, 0x2067 
     0x01bd: 66          |   MOV H, M                            ; put player specific data MSB in H
     0x01be: C9          |   RET                                 ; return

.__not_accessed__
     0x01bf: 00          |   NOP

; *********************** START ROUND PROCEDURES (A) *********************

; ----------------------------------------------------------------
;
;    NOTE: these are not necessarily listed in order called
;
;    0x01C0 - reset player 1's invaders
;    0x01CF - draws horizontal line across the bottom of game area
;
;
; -----------------------------------------------------------------

; name: resetInvadersP1 [START NEW GAME/ROUND/DEMO SUBROUTINES]
; Insert 1's for all 55 (0x37) invaders in player 1's data. Returns them all to "active" status on
; the screen for a new game round or demo round. As a reminder, 5 rows of 11 invaders = 55 total

.resetInvadersP1

     0x01c0: 21 [00 21]  |   LXI H, 0x2100                       ; refers to player 1's data 
     0x01c3: 06 [37]     |   MVI B, 0x37
     0x01c5: 36 [01]     |   MVI M, 0x01                         ; put 1 in memory for all 55
     0x01c7: 23          |   INX H
     0x01c8: 05          |   DCR B
     0x01c9: C2 [C5 01]  |   JNZ 0x01C5
     0x01cc: C9          |   RET

.utilityPopH
     0x01cd: E1 [C9 3E]  |   POP H
     0x01ce: C9 [3E 01]  |   RET

; name: drawBottomLine [START GAME/ROUND/DEMO SUBROUTINES]
; This is an init function for drawHorizontalLine, which draws a single-byte-tall sprite repeatedly
; (B) times horizontally across the screen. Here we set the bottom bit only an draw a thin line 0xE0 (224) times
; 224 is the entire width of the screen

.drawBottomLine                                                ; draw 1 px line across bottom of screen
     0x01cf: 3E [01]     |   MVI A, 0x01
     0x01d1: 06 [E0]     |   MVI B, 0xE0                         ; put E0 in B (length)
     0x01d3: 21 [02 24]  |   LXI H, 0x2402                       ; starting coordinates (lower left)
     0x01d6: C3 [CC 14]  |   JMP 0x14CC                          ; draws horizontal line across screen

; *********************** ISR UTILITY: ADD INVADER OFFSETS ******************************

; ----------------------------------------------------------------
;
;    NOTE: This is called during midscreen when the origin invader is advanced 
;          and during splash animation processing must move a sprite in VBLANK
;
;    0x01D9 - add invader offsets
;
; -----------------------------------------------------------------

; name: addInvaderOffsets [MIDSCREEN ISR (load current invader), VBLANK (splash animation)]
; this is a utility function related to the sprite position/offset data structure
; that moves a sprite by changing its position in the x and y direction.
; This is a 4 byte structure containing data as follows:
;         1: desired offset in y direction
;         2: desired offset in x direction
;         3: current y position
;         4: current x position
; When we get here, the y-direction offset should already be loaded in C
; HL should point at the memory location where C was stored
; We calculate y-coord += y-offset and x-coord += x-offset, then return. 
; This is used by both the game and the splash animations.

.addInvaderOffsets
     0x01d9: 23          |   INX H                          ; value already in C (in game: 0x2007)
     0x01da: 46          |   MOV B, M                       ; load second value in B (0x2008)
     0x01db: 23          |   INX H
     0x01dc: 79          |   MOV A, C
     0x01dd: 86          |   ADD M                          ; add C to third value (Y)
     0x01de: 77          |   MOV M, A                       ; and store 
     0x01df: 23          |   INX H
     0x01e0: 78          |   MOV A, B                       
     0x01e1: 86          |   ADD M                          ; add B to fourth value (X)
     0x01e2: 77          |   MOV M, A                       ; and store.
     0x01e3: C9          |   RET                            ; ... and return

; *********************** RAM SET/RESET UTILITIES  ******************************

; ----------------------------------------------
;
;    NOTE: These are used in several locations to reset game buffer RAM by
;          copying sections from ROM or player specific RAM buffers
;
;    0x01E4 - limited game data buffer RAM reset (0x2000 - 0x20BF)
;    0x01E6 - initial ROM-to-RAM copy of full game buffer area (0x2000 - 0x20FF)
;    0x01EF - initialize player 1 bunker buffer
;    0x01F5 - initialize player 2b bunker buffer
;    0x0209 - save data from game bunker buffer to player 1 bunker buffer
;    0x020E - save data from game bunker buffer to player 2 bunker buffer
;    0x0213 - restore data from player 2 bunker buffer to game buffer
;    0x021A - restore data from player 1 bunker buffer to game buffer
;    
;    overall, game buffer RAM is located at 0x2000 - 0x20FF
;    game buffers are initialized by ROM at 0x1B00 - 0x1BFF
;    a few RAM structures are not pre-iniitalized 
;    (although ROM values are still copied at game init)
;
;    player-specific buffers, including alien array and bunker data are located:
;         - 0x2100-0x21FF (player 1)
;         - 0x2200-0x22FF (player 2)
;
; -----------------------------------------------

; name: limitedRamReset [NEW GAME / GAME RESET SUBROUTINES]
; Setup the range of RAM we want reset from ROM here. This will be 0x2000 - 0x20C0 only

.limitedRamReset 
     0x01e4: 06 [C0]     |   MVI B, 0xC0

; procedure: setupInitRomToRamCopy [PROGRAM INIT]
; sets the parameters to copy memory between 1B00-xxxx to 2000-xxxx (B controls length)
; This code sets parameters, then jumps to the actual copying and returns

.setupInitRomToRamCopy
     0x01e6: 11 [00 1B]  |   LXI D, 0x1B00 
     0x01e9: 21 [00 20]  |   LXI H, 0x2000 
     0x01ec: C3 [32 1A]  |   JMP 0x1A32                     ; copies data from ROM into RAM.
                                                            ; returns

; name: setupBunkers_player1
; This is a gateway into the resetBufferNewBunkers function at 0x01F8 for player 1. It points HL
; at 0x2142, which is the start of Player 1's data buffer for the bunkers.
; data on the bunkers is saved to this buffer and restored when the player returns for another life.
; In a 2-player game, the players switch off before the round is finished.

.setupBunkers_player1
     0x01ef: 21 [42 21]  |   LXI H, 0x2142                       ; point HL at 2142
     0x01f2: C3 [F8 01]  |   JMP 0x01F8

; name: setupBunkers_player2
; This is a gateway into the resetBufferNewBunkers function at 0x01F8 for player 2.

.setupBunkers_player2
     0x01f5: 21 [42 22]  |   LXI H, 0x2242                       ; point HL at 2242

; name: resetBufferNewBunkers
; draws the data for four bunkers (without spaces) into the buffer memory for a given player (pointer in HL)
; the buffer should take a total of B0 = 2C x 4 bytes

.resetBufferNewBunkers
     0x01f8: 0E [04]     |   MVI C, 0x04                         ; four bunkers
     0x01fa: 11 [20 1D]  |   LXI D, 0x1D20                       ; bunker sprite in ROM
     0x01fd: D5          |   PUSH D
     0x01fe: 06 [2C]     |   MVI B, 0x2C                         ; bunker art is 44 bytes long
     0x0200: CD [32 1A]  |   CAL 0x1A32                          ; ROM to RAM copy DE to HL (B bytes)
     0x0203: D1          |   POP D
     0x0204: 0D          |   DCR C
     0x0205: C2 [FD 01]  |   JNZ 0x01FD                          ; loop until we've done 4
     0x0208: C9          |   RET

.playerOne_saveBunkersToBuffer
     0x0209: 3E [01]     |   MVI A, 0x01                         ; sets 0x2081 to 1 (onscreen -> buffer)
     0x020b: C3 [1B 02]  |   JMP 0x021B                          ; and DE to 0x2142 (player 1)

.playerTwo_saveBunkersToBuffer
     0x020e: 3E [01]     |   MVI A, 0x01                         ; sets 0x2081 to 1 (onscreen -> buffer)
     0x0210: C3 [14 02]  |   JMP 0x0214                          ; and DE to 0x2242 (player 2)

.playerTwo_restoreBunkersFromBuffer
     0x0213: AF          |   XRA A
     0x0214: 11 [42 22]  |   LXI D, 0x2242 
     0x0217: C3 [1E 02]  |   JMP 0x021E

; name: playerOne_restoreBunkersFromBuffer
; restores "live" game bunkers on screen from player 1's buffer. This code initializes _saveRestoreBunker.
; Here we set parameters A to 0 (buffer -> screen memory) and DE to 0x2142 (player 1's buffer)

.playerOne_restoreBunkersFromBuffer
     0x021a: AF          |   XRA A
     0x021b: 11 [42 21]  |   LXI D, 0x2142 

; name: _saveRestoreBunkers
; Moves data from player's bunker buffer to screen memory or vice versa.
; A determines the direction (0: buffer -> screen memory, 1: screen memory -> buffer)
; DE holds a pointer to the player's buffer

._saveRestoreBunkers
     0x021e: 32 [81 20]  |   STA 0x2081                          ; stores parameter in bunker direction toggle
     0x0221: 01 [02 16]  |   LXI B, 0x1602                       ; size of sprite: 2 bytes high x 0x16 wide
     0x0224: 21 [06 28]  |   LXI H, 0x2806                       ; onscreen memory space for bunkers
     0x0227: 3E [04]     |   MVI A, 0x04
     0x0229: F5          |   PUSH PSW                            ; handle a buffer
     0x022a: C5          |   PUSH B
     0x022b: 3A [81 20]  |   LDA 0x2081                          ; check direction
     0x022e: A7          |   ANA A
     0x022f: C2 [42 02]  |   JNZ 0x0242                          ; ... handle save to buffer
     0x0232: CD [69 1A]  |   CAL 0x1A69                          ; .updateBunkersFromBuffer    
     0x0235: C1          |   POP B
     0x0236: F1          |   POP PSW
     0x0237: 3D          |   DCR A                               ; are we done?
     0x0238: C8          |   RZ                                  ; ... if so, return
     0x0239: D5          |   PUSH D
     0x023a: 11 [E0 02]  |   LXI D, 0x02E0                       ; 23 x 0x40 = 0x2E0
     0x023d: 19          |   DAD D                               ; ... shift over 23 rows
     0x023e: D1          |   POP D
     0x023f: C3 [29 02]  |   JMP 0x0229                          ; and do it again

; name: saveSingleBunkerToBuffer
; wrapper function handling moving data for a single bunker from the screen to the buffer.
; the code at 0x147C does the bulk of the work here

.saveSingleBunkerToBuffer
     0x0242: CD [7C 14]  |   CAL 0x147C                          ; saveBunker
     0x0245: C3 [35 02]  |   JMP 0x0235                          ; back to logic for handling next bunker

; ************************ ISR GAME OBJECT PROCESSING ******************************

; -------------------------------------------------------------------
;
; **** ISR GAME OBJECT PROCESSING LOOP ****
;
;    0x0248 - setup game processing for VBLANK (starts at 0x2010, 
;             midscreen start set to 0x2020 above)
;    0x024B - game structure parsing loop (see notes below under parseStructsLoop)
;    0x0277 - 16-bit decrement helper for numbers stored in big-endian configuration
;             (the control counter at beginning of each game structure is stored in this manner)
;    0x0288 - 8-bit decrement helper
;
;    NOTE: Game object subroutines refer to data in game buffer RAM at locations 
;          in [brakets] below and are located as follows:
;
;         * 0x028E - player object [0x2010] subroutine (VBLANK only)
;         * 0x03BB - player shot object [0x2020] subroutine
;         * 0x0476 - alien shot 1 object [0x2030] ("skinny shot") subroutine
;         * 0x04B6 - alien shot 2 object [0x2040] ("uptack-T shot") subroutine
;         * 0x0682 - UFO OR alien shot 3 object [0x2050] ("zigzag shot") subroutine
;                    * zigzag shot logic is located at 0x050F
;                    * when called, this routine only processes one or the other
;                    * it switches when either shot or UFO is no longer active
;                    * as elsewhere, which object spawns depends on timers
;                    * if neither is active and timers coincide, UFO spawning takes precedence
;
;         * 0x0550 - process alien shot utility logic (used by all 3 alien shot objects)
;
; ---------------------------------------------------------------------

; name: setupParseStructsLoop_VBLANK [VBLANK ISR]
; this is the VBLANK entry point into parsing the game objects. Unlike midscreen, we start
; here with the player object at 0x2010. After checking timers/control variables, we
; indirectly jump into processors stored at bytes 3 & 4 of object's metadata.

.setupParseStructsLoop_VBLANK
     0x0248: 21 [10 20]  |   LXI H, 0x2010 

.parseStructsLoop
     ; this is an instruction jump table of data structures situated 16 bytes apart.
     ; These contain both metadata and data, but we are concerned here with metadata in the
     ; first five bytes: val0, val1, val2, val3, val4
     ;    ** val0 == 0xFF (-1) stops the loop
     ;    ** val 0/1 (16-bit counter) and 2 (8-bit counter) must all be 0 before we can access an instruction
     ;         -- if val0 or val1 is nonzero, decrement 16-bit number and jump forward to next data struct
     ;    ** val 3/4 are the address for an instruction in the game ROM
     ;    ** control loops through the array and indirectly executes
     ;    ** by moving vals 3/4 into the program counter

     ; TABLE (at initialization):     |  counters: 16-bit    8-bit  |  jump address   | data structure
     ;              ROM  / RAM           val0      val1      val2      val3/val4    
     ;
     ;              1B10 / 2010          0x00      0x80      0x00      0x028E           player
     ;              1B20 / 2020          0x00      0x00      0x00      0x03BB           player shot
     ;              1B30 / 2030          0x00      0x00      0x02      0x0476           invader shot 1 (skinny)
     ;              1B40 / 2040          0x00      0x00      0x00      0x04B6           invader shot 2 (uptack-T)
     ;              1B50 / 2050          0x00      0x00      0x00      0x0682           UFO + invader shot 3 (zigzag)
     ;              1B60 / 2060          0xFF                                           (stops parsing loop)
     ;
     ; ALIEN SHOT SPRITES REFERENCE
     ; 
     ; "skinny shot" (invader shot 1) sprites at 0x1CEE in ROM
     ;
     ;    . x .          . x .          . x .          x x .
     ;    . x .          . x .          . x .          . x x
     ;    . x .          . x x          . x .          . x .
     ;    . x .     ->   x x .     ->   . x .     ->   x x .
     ;    . x .          . x .          . x .          . x x
     ;    . x .          . x x          . x .          . x .
     ;    . x .          x . .          . x .          . x .
     ;    . . .          . . .          . . .          . . .
     ;
     ; "uptack-T" (invader shot 2) sprites at 0x1CE2 in ROM
     ;
     ;    . x .          . x .          . x .          x x x
     ;    . x .          . x .          . x .          . x .
     ;    . x .          . x .          x x x          . x .
     ;    . x .     ->   x x x     ->   . x .     ->   . x .
     ;    . x .          . x .          . x .          . x .
     ;    x x X          . x .          . x .          . x .
     ;    . . .          . . .          . . .          . . .
     ;    . . .          . . .          . . .          . . .
     ;
     ; "zigzag shot" (invader shot 3) sprites at 0x1CD0 in ROM
     ;
     ;    . x .          . . x          . x .          x . .
     ;    . . X          . x .          x . .          . x .
     ;    . x .          x . .          . x .          . . x
     ;    x . .     ->   . x .     ->   . . x     ->   . x . 
     ;    . x .          . . x          . x .          x . .
     ;    . . x          . x .          x . .          . x .
     ;    . x .          x . .          . x .          . . x
     ;    . . .          . . .          . . .          . . .

; name: _checkLoopControl [VBLANK, MIDSCREEN ISR]
; We begin loop control for our ISR game processing loop here, by first looking at
; val0 of the game data structure. If its value is 0xFF, we are finished here and return

._checkLoopControl 
     0x024b: 7E          |   MOV A, M
     0x024c: FE [FF]     |   CPI 0xFF                       ; if val0 == 0xFF:
     0x024e: C8          |   RZ                             ; ... return

; name: _conditionalSkip [VBLANK, MIDSCREEN ISR]
; Here we check val0 again. If it is equal to 0xFE, we skip forward 16 bytes to the next
; game data structure.

._conditionalSkip
     0x024f: FE [FE]     |   CPI 0xFE                       ; if val0 == 0xFE:
     0x0251: CA [81 02]  |   JZ 0x0281                      ; ... skip forward

; name: _check16BitCounter [VBLANK, MIDSCREEN ISR]
; Each of these game data structures contains two counters at the beginning. The first is
; 16 bits in size. When it's nonzero, we decrement it.

._check16BitCounter
     0x0254: 23          |   INX H                          ; otherwise,
     0x0255: 46          |   MOV B, M                       ;
     0x0256: 4F          |   MOV C, A                       ;
     0x0257: B0          |   ORA B                          ; if 16 bits in val0/val1 is nonzero:
     0x0258: 79          |   MOV A, C                       ;
     0x0259: C2 [77 02]  |   JNZ 0x0277                     ; ...decrement 16-bit counter & skip forward

; name: _check8Bitcounter
; if we reach here, the 16-bit counter is zero. If val2 is nonzero, 
; decrement the 8-bit counter and skip forward to next data structure

._check8Bitcounter
     0x025c: 23          |   INX H
     0x025d: 7E          |   MOV A, M                       ; if val2 is nonzero:
     0x025e: A7          |   ANA A
     0x025f: C2 [88 02]  |   JNZ 0x0288                     ; decrement 8-bit counter and skip forward

; name: _processStruct
; These are the "launch" instructions for processing the game data structure in question.
; Here we
;         1. push the next address on data structure into the stack
;         2. push the "jump address" we are jumping to for data structure processing onto stack
;         3. load the return address into HL then swap with stack. HL now holds jump address.
;         4. push our place in the data structure onto the stack again. So stack should hold:
;              ...
;              [pointer to MSB of jump address/val4] 
;              [return address (0x026F)]                      
;              [pointer to MSB of jump address/val4] -- STACK TOP
;         5. indirectly call current data structure's processing subroutine

._processStruct
     0x0262: 23          |   INX H                          ; if both counters are now zero:
     0x0263: 5E          |   MOV E, M                       ; ... put jump address LSB in E
     0x0264: 23          |   INX H
     0x0265: 56          |   MOV D, M                       ; ... put jump address MSB in D
     0x0266: E5          |   PUSH H                         ; save our place
     0x0267: EB          |   XCHG
     0x0268: E5          |   PUSH H                         ; and save jump address
     0x0269: 21 [6F 02]  |   LXI H, 0x026F 
     0x026c: E3          |   XTHL                           ; return address to stack, jump address in HL
     0x026d: D5          |   PUSH D                         ; ... save our place to stack again
     0x026e: E9          |   PCHL                           ; and move to jump address for current struct

; name: _advanceToNextStruct
; once we return from the indirect subroutine call, jump forward to next data structure

.advanceToNextStruct
     0x026f: E1          |   POP H                          ; adds 12 to advance to next
     0x0270: 11 [0C 00]  |   LXI D, 0x000C                  ; count of 16
     0x0273: 19          |   DAD D
     0x0274: C3 [4B 02]  |   JMP 0x024B                     ; back to the top of loop control

; name: _decrement16BitNum
; A helper function that allows us to properly decrement at 16-bit number, then skip forward
; by 16 bytes to the next game data structure. Note that A is the first byte and B is the 
; second, so for some reason this 16-bit number is stored in a big-endian arrangement.

._decrement16BitNum
     0x0277: 05          |   DCR B                          ; A is MSB, B is LSB
     0x0278: 04          |   INR B                          ; if B's not zero yet,
     0x0279: C2 [7D 02]  |   JNZ 0x027D                     ;   ... skip borrow
     0x027c: 3D          |   DCR A                          ; otherwise borrow from A
     0x027d: 05          |   DCR B                          ; decrement B
     0x027e: 70          |   MOV M, B                       ; and store both
     0x027f: 2B          |   DCX H
     0x0280: 77          |   MOV M, A                       ; ... digits back in memory
     0x0281: 11 [10 00]  |   LXI D, 0x0010                  ; skip jump 16 bytes to next struct 
     0x0284: 19          |   DAD D
     0x0285: C3 [4B 02]  |   JMP 0x024B                     ; return to beginning of loop

; name: _decrement8BitNum
; decrement the 8-bit counter and then realign to the beginning of data structure.
; Once realigned, jump forward.

._decrement8BitNum
     0x0288: 35          |   DCR M                          ; decrement
     0x0289: 2B          |   DCX H
     0x028a: 2B          |   DCX H                          ; realign to beginning
     0x028b: C3 [81 02]  |   JMP 0x0281                     ; skip to next

; ************************ ISR PLAYER OBJECT SUBROUTINE *****************************

; ------------------------------------------------
;
; **** PLAYER OBJECT SUBROUTINE ****
;
;    procedures are ordered as follows:
;         1. check player status
;         2. unhealthy: 
;              a. handle explosion (draw)
;              b. return or reset stack and exit ISR to 
;                 appropriate game procedure
;         3. healthy:
;              a. handle alien shot cooldown timer
;              b. load & execute movement when appropriate
;              c. draw player & return
;
;    0x028E - entry point: check if player has been shot
;    0x0296 - player explosion
;    0x02B6 - reset player data structure & either return
;             (game over for player, demo) or pop/exit ISR
;    0x02d0 - [CONT.] reset stack, exit ISR to game loop at appropriate location
;    0x02ed - [CONT.] ... more "appropriate location" logic
;    0x032C - update remaining player "lives"
;    0x0332 - wraps logic to save player 1's bunkers
;    0x033B - move player: indicate player alive, check if alien shots are locked
;    0x0346 - alien shot cooldown handling utility: re-enable alien shot
;             (goes through this when time hits 0, before movement)
;    0x034A - movement handler begins: game/demo mode switch
;    0x0355 - movement handler: demo mode (grabs demo movement instructions)
;    0x0363 - movement hanlder: game mode (polls for _LEFT or _RIGHT from player)
;    0x036F - draw player sprite utility
;    0x0381 - move player right utility
;    0x038E - move player left utility
;    0x039B - assign correct damaged player sprite
;    0x03B0 - alien shot cooldown handling utility: decrement timer 
;             (goes through this before movement)
;
; ------------------------------------------------

; name: processPlayer [PLAYER SUBROUTINE / VBLANK ISR]
; This is the subroutine called from the first structure in the game data structure
; processing loop. Unlike the other game structures, this one is only called during
; the VBLANK interrupt.
; Here we start by checking if the player has been shot. Then we either:
;         (1) fall into the player shot / explosion / reset handler
;         (2) jump ahead to the player movement handler

.processPlayer
     0x028e: E1          |   POP H                          ; this points HL at 0x2014                        
     0x028f: 23          |   INX H                          ; grab pointer to val5 (0x2015)
     0x0290: 7E          |   MOV A, M                       ; get player status
     0x0291: FE [FF]     |   CPI 0xFF                       ; has player been shot?
     0x0293: CA [3B 03]  |   JZ 0x033B                      ; no (0x2015 == 0xFF)... move player
                                                            ; otherwise fall into _playerShotHandler

; name: playerExplosion [PLAYER SUBROUTINE / VBLANK ISR]
; This handler runs when a player has been shot and that shot has been recorded in the 
; RAM status variable 0x2015. There is a 5-count timer, and this does nothing until zero is reached.
; at that point, we:
;         * clear 0x2068 - (player unhealthy) 
;         * clear 0x2069 - (prevent new alien shots)
;         * load 0x30 into 0x206A - (alien's shot cooldown timer)
;         * mark the explosion sprite complete by decreasing counter at 0x2017
;         * ... and draw explosion sprite

.playerExplosion
     0x0296: 23          |   INX H                          ; grab pointer to val6 (0x2016)
     0x0297: 35          |   DCR M                          ; decrement 5-tick timer
     0x0298: C0          |   RNZ                            ; .... is it 0? if not return
     0x0299: 47          |   MOV B, A                       ; otherwise, save player status in B
     0x029a: AF          |   XRA A
     0x029b: 32 [68 20]  |   STA 0x2068                     ; clear 0x2068: indicates player exploding
     0x029e: 32 [69 20]  |   STA 0x2069                     ; clear 0x2069: locks new alien shot
     0x02a1: 3E [30]     |   MVI A, 0x30
     0x02a3: 32 [6A 20]  |   STA 0x206A                     ; initialize alien shot cooldown timer
     0x02a6: 78          |   MOV A, B
     0x02a7: 36 [05]     |   MVI M, 0x05                    ; reset 5-tick timer at 0x2015
     0x02a9: 23          |   INX H                          ; pointer to explosing stage counter (0x2017)
     0x02aa: 35          |   DCR M                          ; decrease it
     0x02ab: C2 [9B 03]  |   JNZ 0x039B                     ; is it zero? if not, draw damaged sprite stage
     0x02ae: 2A [1A 20]  |   LHLD 0x201A                    ; if yes,
     0x02b1: 06 [10]     |   MVI B, 0x10
     0x02b3: CD [24 14]  |   CAL 0x1424                     ; ...erase sprite and continue

; name: resetPlayer [PLAYER SUBROUTINE / VBLANK ISR]
; This routine resets all 16 bytes of the player object data structure from ROM, turns off
; all port 3 audio (including player explosion), and checks if the invaders have reached the bottom.
; If they have, return from processing the player. Then it either returns (in demo mode), or exits
; VBLANK ISR to the game by resetting the stack.

.resetPlayer
     0x02b6: 21 [10 20]  |   LXI H, 0x2010                  ; point HL at beginning of struct in RAM
     0x02b9: 11 [10 1B]  |   LXI D, 0x1B10                  ; point DE at beginning of struct in ROM
     0x02bc: 06 [10]     |   MVI B, 0x10
     0x02be: CD [32 1A]  |   CAL 0x1A32                     ; reset player struct at 0x2010 from ROM
     0x02c1: 06 [00]     |   MVI B, 0x00                    ; set audio mask
     0x02c3: CD [DC 19]  |   CAL 0x19DC                     ; mask off all port 3 audio
     0x02c6: 3A [6D 20]  |   LDA 0x206D                     ; "invaders win" flag
     0x02c9: A7          |   ANA A                          ; did the invaders win / reach bottom?
     0x02ca: C0          |   RNZ                            ; ... if yes, return
     0x02cb: 3A [EF 20]  |   LDA 0x20EF                     ; are we in game mode?
     0x02ce: A7          |   ANA A                          ; ... if not...
     0x02cf: C8          |   RZ                             ; ... return

; name _exitToGame [PLAYER SUBROUTINE / VBLANK ISR EXIT POINT]
; After the player is reset, if we're in game mode, we exit from VBLANK ISR, reset the stack, and execute
; reset player logic, which checks where/how we need to re-enter the game loop. We:
;    1. turn off interrupt game processing
;    2. check if the player is out of lives.
;         a. if so -> game over
;         b. if not, 
;              i. re-enter game loop on this player 
;                 IF the other player is dead or this is one-player game
;              ii. switch players (see code at 0x2ED)
;    3. either way, we then continue to update the player's lives and re-enter gane loop 

._exitToGame
     0x02d0: 31 [00 24]  |   LXI SP, 0x2400                 ; otherwise, reset the stack
     0x02d3: FB          |   EI                             ; enable interrupts (exit point for VBLANK ISR)
     0x02d4: CD [D7 19]  |   CAL 0x19D7                     ; turn off interrupt game processing
     0x02d7: CD [2E 09]  |   CAL 0x092E                     ; get current lives: put the number of ships in A
     0x02da: A7          |   ANA A                          ; no ships?
     0x02db: CA [6D 16]  |   JZ 0x166D                      ; ... handle game over
     0x02de: CD [E7 18]  |   CAL 0x18E7                     ; get pointer to other player's status
     0x02e1: 7E          |   MOV A, M                       ; 
     0x02e2: A7          |   ANA A                          ; 
     0x02e3: CA [2C 03]  |   JZ 0x032C                      ; ... dead? draw ships, re-enter game loop
     0x02e6: 3A [CE 20]  |   LDA 0x20CE                     ; One player game?
     0x02e9: A7          |   ANA A                          ; 
     0x02ea: CA [2C 03]  |   JZ 0x032C                      ; ... draw ships, re-enter game loop

; name: switchPlayer [PLAYER SUBROUTINE / GAME LOOP RETURN (CONT)]
; called when switching between players during a multi-player game. It:
; * saves the "live" bunkers to appropriate buffer. 
; * stores the origin alien's coordinates to buffer
; * It then resets RAM between 2000 and 20C0
; * switches the current player (toggle between 0x21 and 0x22) at 0x2067
; * clears the player's movement cooldown timer (0x2011)
; * sends out 1 (player 2) or 0 (player 1) to OUTPUT PORT 5 bit 5 (flip visuals for cocktail table)
; * then increments the value (init invader audio) and stores in port 5 audio buffer
; * it clears the game area, writes appropriate number of player lives
; * and finally writees "PLAY PLAYER X" to screen

.switchPlayer
     0x02ed: 3A [67 20]  |   LDA 0x2067                     ; ... which current player?
     0x02f0: F5          |   PUSH PSW
     0x02f1: 0F          |   RRC
     0x02f2: DA [32 03]  |   JC 0x0332                      ; player 1... save bunkers to buffer
     0x02f5: CD [0E 02]  |   CAL 0x020E                     ; player 2... save bunkers to buffer
     0x02f8: CD [78 08]  |   CAL 0x0878                     ; DE: ref. invader coords, HL: xxFC (depends on player)
     0x02fb: 73          |   MOV M, E                       ; puts lower-left invader coord LSB at xxFC
     0x02fc: 23          |   INX H
     0x02fd: 72          |   MOV M, D                       ; puts lower-left invader coord MSB at xxFD
     0x02fe: 2B          |   DCX H
     0x02ff: 2B          |   DCX H
     0x0300: 70          |   MOV M, B                       ; saves aliens' x offset (in B) at xxFB
     0x0301: 00          |   NOP
     0x0302: CD [E4 01]  |   CAL 0x01E4                     ; resets 0xC0 bytes: RAM from ROM
     0x0305: F1          |   POP PSW
     0x0306: 0F          |   RRC                            ; check current player
     0x0307: 3E [21]     |   MVI A, 0x21
     0x0309: 06 [00]     |   MVI B, 0x00
     0x030b: D2 [12 03]  |   JNC 0x0312                     ; not player 1? jump
     0x030e: 06 [20]     |   MVI B, 0x20                    ; otherwise put 0x20 in B and 0x22 in A
     0x0310: 3E [22]     |   MVI A, 0x22
     0x0312: 32 [67 20]  |   STA 0x2067                     ; sets 0x2067 to **other** player
     0x0315: CD [B6 0A]  |   CAL 0x0AB6                     ; pause loop: 80 ticks
     0x0318: AF          |   XRA A
     0x0319: 32 [11 20]  |   STA 0x2011                     ; clear 0x2011
     0x031c: 78          |   MOV A, B                       ; set (player 2) or clear (player 1) bit 5 and...
     0x031d: D3 [05]     |   OUT 0x05                       ; ... send to OUTPUT PORT 5
     0x031f: 3C          |   INR A                          ; set bit 0 (1st position in invader audio sequence)
     0x0320: 32 [98 20]  |   STA 0x2098                     ; save in 0x2098 (port 5 audio buffer)
     0x0323: CD [D6 09]  |   CAL 0x09D6                     ; clear the game area
     0x0326: CD [7F 1A]  |   CAL 0x1A7F                     ; .writeRemaningPlayerLives
     0x0329: C3 [F9 07]  |   JMP 0x07F9                     ; print "PLAY PLAYER x" message 
                                                            ; (continues to game loop)

; name: updateRemainingLives [PLAYER SUBROUTINE / GAME LOOP RETURN (CONT)]
; Here we call the function that updates the player's remaining lives, redraws their sprites, and then
; returns to the main game loop. 

.updateRemainingLives
     0x032c: CD [7F 1A]  |   CAL 0x1A7F                     ; update and draw ships
     0x032f: C3 [17 08]  |   JMP 0x0817                     ; re-enter main game loop
                                                            ; at _restoreGameProcessing

; name: p1SaveBunkers [PLAYER SUBROUTINE / VBLANK ISR]
; Saves data about player 1's bunkers to the player-specific RAM buffer.

.p1SaveBunkers
     0x0332: CD [09 02]  |   CAL 0x0209                     ; save p1's bunkers to RAM data buffer
     0x0335: C3 [F8 02]  |   JMP 0x02F8                     ; continue switching to new player

.__not_accessed__
     0x0338: 00          |   NOP
     0x0339: 00          |   NOP
     0x033a: 00          |   NOP

; name: movePlayer [PLAYER SUBROUTINE / VBLANK ISR]
; We get here if the player is healthy (0x2015 == 0xFF) when game processing 
; indirectly calls the player subroutine on VBLANK.

.movePlayer
     0x033b: 21 [68 20]  |   LXI H, 0x2068                  ; reset 0x2068:
     0x033e: 36 [01]     |   MVI M, 0x01                    ;    ... the player is not exploding
     0x0340: 23          |   INX H                          ; HL <- 0x2069
     0x0341: 7E          |   MOV A, M 
     0x0342: A7          |   ANA A                          ; flags: alien shot still locked?
     0x0343: C3 [B0 03]  |   JMP 0x03B0                     ; move player / process alien shot cooldown

; name: endAlienShotCooldown [PLAYER SUBROUTINE / VBLANK ISR]
; this is called when the 0x30-count timer at 0x206A has finished (it's started when player begins exploding)
; Here is where we reset 0x2069 to re-enable new alien shots.

.endAlienShotCooldown
     0x0346: 00          |   NOP                            ; not sure why we jump in here
     0x0347: 2B          |   DCX H                          ; point HL back at 0x2069
     0x0348: 36 [01]     |   MVI M, 0x01                    ; unlock new alien shots
                                                            ; ... and fall into player movement handler

; name: handlePlayerMovement [PLAYER SUBROUTINE / VBLANK ISR]
; once we've handled an exploding player and decremented timer as needed, this is where we 
; handle the normal player movement by polling user's input (or processing demo command). 

.handlePlayerMovement
     0x034a: 3A [1B 20]  |   LDA 0x201B                         ; load X position
     0x034d: 47          |   MOV B, A                           ; and save in B
     0x034e: 3A [EF 20]  |   LDA 0x20EF                         ; are we in game mode? (01)
     0x0351: A7          |   ANA A
     0x0352: C2 [63 03]  |   JNZ 0x0363                         ; ... jump if so ...

; name: handleDemoMovement [PLAYER SUBROUTINE / VBLANK ISR]
; here we process movement according to the command sequence provided for the demo.

.handleDemoMovement
     0x0355: 3A [1D 20]  |   LDA 0x201D                         ; grab next demo movement command
     0x0358: 0F          |   RRC                                ; right?
     0x0359: DA [81 03]  |   JC 0x0381                          ; ... move right
     0x035c: 0F          |   RRC                                ; left?
     0x035d: DA [8E 03]  |   JC 0x038E                          ; ... move left
     0x0360: C3 [6F 03]  |   JMP 0x036F                         ; ... draw player and return

; name: pollPlayerMovement [PLAYER SUBROUTINE / VBLANK ISR]
; Check player controls to see whether player has depressed the command for right or left
; If both are pressed, right takes precedence

.pollPlayerMovement
     0x0363: CD [C0 17]  |   CAL 0x17C0                         ; read current player controls
     0x0366: 07          |   RLC
     0x0367: 07          |   RLC                                ; check for move right
     0x0368: DA [81 03]  |   JC 0x0381                          ; ... move right
     0x036b: 07          |   RLC                                ; otherwise check for move left
     0x036c: DA [8E 03]  |   JC 0x038E                          ; ... move left

; name: drawPlayer [PLAYER SUBROUTINE / VBLANK ISR]
; load the sprite coordinates from 0x2018 into HL, then put 5 byte data structure starting at
; 0x2018 into registers as follows:
;    * DE <- the address of the sprite to write
;    * HL <- screen coordinates
;    * B <- size of sprite to write (initialized at 0x10).
; When we write the player we don't need to shift because the player doesn't move vertically
; (so it can't move out of byte alignment)
; Finally, the player has been drawn. Clear 8-bit timer and return

.drawPlayer
     0x036f: 21 [18 20]  |   LXI H, 0x2018 
     0x0372: CD [3B 1A]  |   CAL 0x1A3B                          ; grab registers: E, D, L, H, B
     0x0375: CD [47 1A]  |   CAL 0x1A47                          ; convert HL: divide by 8 and add 2000
     0x0378: CD [39 14]  |   CAL 0x1439                          ; writeSpriteNoShift
     0x037b: 3E [00]     |   MVI A, 0x00
     0x037d: 32 [12 20]  |   STA 0x2012                          ; clear val2
     0x0380: C9          |   RET                                 ; standard end to player object subroutine

; name: movePlayerRight [PLAYER SUBROUTINE / VBLANK ISR]
; we reach here because the player has pressed the control to move the player right.
; This procedure checks to see if we are already at the rightmost maximum coordinate 0xD9.
; otherwise, adds 1 and stores as new player position

.movePlayerRight
     0x0381: 78          |   MOV A, B
     0x0382: FE [D9]     |   CPI 0xD9                           ; are we at position 0xD9?
     0x0384: CA [6F 03]  |   JZ 0x036F                          ; ... if so, no movement
     0x0387: 3C [32 1B]  |   INR A                              ; otherwise add 1 to player position
     0x0388: 32 [1B 20]  |   STA 0x201B                         ; and store back at 0x201B
     0x038b: C3 [6F 03]  |   JMP 0x036F                         ; ... draw player and return

; movePlayerLeft [PLAYER SUBROUTINE / VBLANK ISR]
; we reach here because the player has pressed control to move the player left.
; Here we check if the player is at 0x30. If not, movement left is allowed, removing
; 1 from the horizontal coordinate and re-storing it as player position

.moveplayerLeft
     0x038e: 78          |   MOV A, B                           ; are we at position 0x30?
     0x038f: FE [30]     |   CPI 0x30
     0x0391: CA [6F 03]  |   JZ 0x036F                          ; ... if so, no movement
     0x0394: 3D          |   DCR A                              ; otherwise, subtract 1 from player position
     0x0395: 32 [1B 20]  |   STA 0x201B                         ; and store back at 0x201B
     0x0398: C3 [6F 03]  |   JMP 0x036F                         ; ... draw player and return

; name: _assignDamagedPlayerSprite [PLAYER SUBROUTINE / VBLANK ISR]
; Here the player is unhealthy. This code toggles between 1 and 0 in 0x2015, which causes the address of
; the sprite in ROM in 0x2018 to toggle between 0x1C70 and 0x1C80
;
;    for reference: 0x1C70            ->   0x1C80
;    . . . . . . . . . x . . . . . .       . . x . . . . . . . . . x . . .
;    . . . . x . . . . . . . . . . .       x . . x x . . . . x . . . . . x
;    . . . . . . . x . x . . . . . .       . . . . . . x x . . . . x . . .
;    . . . . . . . . . x . . x . . .       . x . . . . . . . x . . . . . .
;    . . . . x . . x x . . . . . . .       x . . . x x . . x x . x . . x .
;    . . . x . . . x x . x . . . x .       . . x . . . x x x . . . . x . . 
;    . . x . . x x x x x x x x . . .       . . . . x x x x x x x x x . . .
;    x . x . x . x x x x x x x x . .       . x . . x x x x x x x . x x . .

._assignDamagedPlayerSprite
     0x039b: 3C          |   INR A                              ; toggle player status
     0x039c: E6 [01]     |   ANI 0x01                           ; between 1 and 0
     0x039e: 32 [15 20]  |   STA 0x2015                         ; store back at 0x2015
     0x03a1: 07          |   RLC
     0x03a2: 07          |   RLC
     0x03a3: 07          |   RLC
     0x03a4: 07          |   RLC                                ; multiply by 16
     0x03a5: 21 [70 1C]  |   LXI H, 0x1C70                      ; point at 0x1C70 (1st player damage sprite)
     0x03a8: 85          |   ADD L
     0X03a9: 6F          |   MOV L, A                           ; add 0x10 or 0x00
     0x03aa: 22 [18 20]  |   SHLD 0x2018                        ; put HL at 0x2018 (pointer to current sprite)
     0x03ad: C3 [6F 03]  |   JMP 0x036F                         ; draw player and return

; name: alienShotCooldown [PLAYER SUBROUTINE / VBLANK ISR]
; When the player explodes, a new alien shots are blocked from firing (0x2069 must be clear to accomplish this)
; flags here are already based on the current status of 0x2069, so we begin by jumping past this logic if
; 0x2069 is not clear (alien shots are still permitted.)
; Then we handle decrement of timer at 0x2017, before continuing to the player movement handler

.alienShotCooldown
     0x03b0: C2 [4A 03]  |   JNZ 0x034A                          ; if nonzero, skip this logic
     0x03b3: 23          |   INX H                               ; HL <- 0x206A
     0x03b4: 35          |   DCR M                               ; decrement 0x30-tick cooldown timer
     0x03b5: C2 [4A 03]  |   JNZ 0x034A                          ; ... *then* handle player movement
     0x03b8: C3 [46 03]  |   JMP 0x0346                          ; ... unless it's time to unlock new alien shots
                                                                 ; (this falls into the player movement handler)

; ************************** ISR PLAYER'S SHOT OBJECT SUBROUTINE *****************************

; ------------------------------------------------
;
; **** PLAYER'S SHOT OBJECT SUBROUTINE ****
;
;    procedures are ordered as follows:
;
;         1. task filter (returns if wrong half of screen for interrupt)
;         2. check 0x2025 (player shot status):
;              a. if 0, return
;              b. if 1, spawn new player shot
;              c. if 2, move shot & check for collision
;              d. if 3, move sprite coords to allow larger sprite
;                       point at explosion sprite, and draw
;              e. if 4 or 5, 
;                       if 5, return
;                       if 4, erase explosion sprite & reset player shot from ROM
;                             then handle UFO pseudorandomization (runs after explosion)
;
;    0x03BB - applies task filter, checks status and jumps to procedure
;    0x03d7 - explode player shot
;    0x03FA - spawn new player shot
;    0x040A - move player shot up by 0x04 in Y direction, check for collision
;    0x042A - handle invader hit (waits for explosion to finish and change status)
;    0x0430 - utility: loads shot structure data into registers
;    0x0436 - reset after shot: erase sprite and reload player's shot struct from RAM
;    0x0447 - [cont.] ... "randomize" UFO score: advance pointer to UFO score table
;    0x0456 - [cont.] ... "randomize" UFO direction: increment then dereference 
;                         pointer at 0x208F, which is somewhere between 0x0800 and 0x08FF
;                         Uses the least-significant bit of the machine instruction or 
;                         operand there to determine if UFO will enter screen-left or screen-right
;
; ------------------------------------------------

; name: processPlayerShot [PLAYER SHOT SUBROUTINE / ISR]
; Because this process runs in both interrupts, the first thing we do is apply a task filter
; so that objects are only handled during the appropriate interrupt (MIDSCREEN handles first half, 
; VBLANK handles second half). 
; We then check 0x2025 the shot status

.processPlayerShot
     0x03bb: 11 [2A 20]  |   LXI D, 0x202A                       ; DE: horizontal location of player shot 
     0x03be: CD [06 1A]  |   CAL 0x1A06                          ; task filter based on screen position
     0x03c1: E1          |   POP H                               ; pop H <- 0x2024
     0x03c2: D0          |   RNC                                 ; not time to update this? return
     0x03c3: 23          |   INX H                               ; otherwise, grab pointer to val5 (0x2025)
     0x03c4: 7E          |   MOV A, M
     0x03c5: A7          |   ANA A                               ; is it 0? (no shot)
     0x03c6: C8          |   RZ                                  ; ... if so, return
     0x03c7: FE [01]     |   CPI 0x01                            ; is it 1? (new shot fired)
     0x03c9: CA [FA 03]  |   JZ 0x03FA                           ; ... spawn new player shot
     0x03cc: FE [02]     |   CPI 0x02                            ; is it 2? (shot is present & traveling)
     0x03ce: CA [0A 04]  |   JZ 0x040A                           ; ... move shot, check for collision
     0x03d1: 23          |   INX H                               ; grab pointer to 0x2026
     0x03d2: FE [03]     |   CPI 0x03                            ; ... is shot status 3? (hit, not alien)
     0x03d4: C2 [2A 04]  |   JNZ 0x042A                          ; nope! jump to 0x042A

; name: explodePlayerShot [PLAYER SHOT SUBROUTINE / ISR]
; this procedure is called when the shot status is 3, meaning it has hit something that is not one of
; the regular invaders. This is either a miss (shot hit a bunker, an alien shot, or reached the top) or
; the shot has hit a UFO. Either way, this handles the player's shot explosion sequence.
; The timer at 0x2026 is initialized to 0x10
;    * at 0x0F: write the 8-bit explosion sprite to a position that is 2 down and 3 left from shot coords
;    * then count down
;    * until we reach 0 and jump to finish the explosion

.explodePlayerShot
     0x03d7: 35          |   DCR M                               ; decrease byte at 0x2026
     0x03d8: CA [36 04]  |   JZ 0x0436                           ; when timer hits 0, explosion is over
     0x03db: 7E          |   MOV A, M                            ; otherwise, player's shot is exploding!
     0x03dc: FE [0F]     |   CPI 0x0F                            ; is it 0x0F (we show explosion at 0x0F)
     0x03de: C0          |   RNZ                                 ; no? ok great, return
     0x03df: E5          |   PUSH H                              ; store 0x2026 on stack
     0x03e0: CD [30 04]  |   CAL 0x0430                          ; loads registers from 0x2027
     0x03e3: CD [52 14]  |   CAL 0x1452                          ; eraseSprite
     0x03e6: E1          |   POP H                               ; restore H: 0x2026
     0x03e7: 23          |   INX H                               ; HL <- 0x2027
     0x03e8: 34          |   INR M                               ;    ... point at explosion sprite
     0x03e9: 23          |   INX H                                
     0x03ea: 23          |   INX H                               ; HL <- 0x2029                              
     0x03eb: 35          |   DCR M
     0x03ec: 35          |   DCR M                               ;    ... subtract 2 from 0x2029
     0x03ed: 23          |   INX H                               ; HL <- 0x202A
     0x03ee: 35          |   DCR M
     0x03ef: 35          |   DCR M
     0x03f0: 35          |   DCR M                               ;    ... subtract 3 from 0x202A
     0x03f1: 23          |   INX H                               ; and put 0x08 in 0x202B
     0x03f2: 36 [08]     |   MVI M, 0x08
     0x03f4: CD [30 04]  |   CAL 0x0430                          ; load new shot structure data
     0x03f7: C3 [00 14]  |   JMP 0x1400                          ; ... and draw a shifted sprite
                                                                 ; with transparent background

; name: spawnPlayerShot [PLAYER SHOT SUBROUTINE / ISR]
; This runs when a new shot is fired. Sets 0x2025 (player shot status) to 2 (traveling normally)
; draws the initial shot 0x08 right from the player position, centered over player sprite

.spawnPlayerShot
     0x03fa: 3C          |   INR A                               ; add 1 to shot status and store
     0x03fb: 77          |   MOV M, A
     0x03fc: 3A [1B 20]  |   LDA 0x201B                          ; loads player X coordinate
     0x03ff: C6 [08]     |   ADI 0x08                            ; add 8 to position (centers over sprite)
     0x0401: 32 [2A 20]  |   STA 0x202A                          ; save as shot x coordinate
     0x0404: CD [30 04]  |   CAL 0x0430                          ; load 5 shot structure bytes into reg's
     0x0407: C3 [00 14]  |   JMP 0x1400                          ; ... and draw a shifted sprite
                                                                 ; ... with transparent background

; name: movePlayerShot [PLAYER SHOT SUBROUTINE / ISR]
; this procedure moves the player's shot up 4 in the Y direction,
; then and checks to see if it hit something (triggered when drawing on a position already set).
; If there was a collision, 0x2061 and 0x2002 are both set.
; 0x2061: indicates collision
; 0x2002 - indicates player shot hit something.

.movePlayerShot
     0x040a: CD [30 04]  |   CAL 0x0430                         ; get shot structure data, return
     0x040d: D5          |   PUSH D                             ; ... and save on stack
     0x040e: E5          |   PUSH H
     0x040f: C5          |   PUSH B
     0x0410: CD [52 14]  |   CAL 0x1452                         ; eraseSprite
     0x0413: C1          |   POP B
     0x0414: E1          |   POP H
     0x0415: D1          |   POP D                              ; ... restore registers
     0x0416: 3A [2C 20]  |   LDA 0x202C                         ; load player shot Y offset at 0x202C
     0x0419: 85          |   ADD L                              ; add it to L
     0x041a: 6F          |   MOV L, A                           ; and store back in L
     0x041b: 32 [29 20]  |   STA 0x2029                         ; then also store it at 0x2029 (Y coord)
     0x041e: CD [91 14]  |   CAL 0x1491                         ; draws shot in new position, sets 2061 if collision
     0x0421: 3A [61 20]  |   LDA 0x2061                         ; ... check for collision
     0x0424: A7          |   ANA A                              ; ... if not...
     0x0425: C8          |   RZ                                 ; ... return.
     0x0426: 32 [02 20]  |   STA 0x2002                         ; otherwise, set 0x2002
     0x0429: C9          |   RET                                ; and return

; name: handleInvaderHit [PLAYER SHOT SUBROUTINE / ISR]
; An invader's explosion is largely handled by the routines that draw the "current invader"
; This routine is where we direct processing to reset player shot objects when the explosion is complete
; Note that the player shot doesn't actually explode when an invader is hit, the alien does

.handleInvaderHit
     0x042a: FE [05]     |   CPI 0x05                       ; ok, is shot status 5?
     0x042c: C8          |   RZ                             ; return if so
     0x042d: C3 [36 04]  |   JMP 0x0436                          ... otherwise go to 0436 for status 4

; name: getShotStructureData [PLAYER SHOT SUBROUTINE / ISR]
; loads 0x2027, 0x2028 into DE, 0x2029, 0x202A into HL, 0x202B into B, then returns

.getShotStructureData
     0x0430: 21 [27 20]  |   LXI H, 0x2027                  ; starting at val7... load 5b into registers
     0x0433: C3 [3B 1A]  |   JMP 0x1A3B                     ; E, D, L, H, B (init: 90, 1C, 28, 30, 01), return

; name: finishExplodingPlayerShot [PLAYER SHOT SUBROUTINE / ISR]
; * Erases the latest player sprite (whether it's an explosion sprite or not)
; * resets 7 bytes from 0x2025 to 0x202B from ROM (player shot explosion data)

.finishExplodingPlayerShot 
     0x0436: CD [30 04]  |   CAL 0x0430                     ; load 5 bytes at 0x2027 into registers: E,D,L,H,B
     0x0439: CD [52 14]  |   CAL 0x1452                     ; eraseSprite
     0x043c: 21 [25 20]  |   LXI H, 0x2025                  ; grab pointer to shot status
     0x043f: 11 [25 1B]  |   LXI D, 0x1B25                  ; and corresponding value in ROM
     0x0442: 06 [07]     |   MVI B, 0x07                    ; reset 7 bytes ROM -> RAM
     0x0444: CD [32 1A]  |   CAL 0x1A32                     ; ROM-to-RAM copy

; name: setUFOScore [PLAYER SHOT SUBROUTINE / ISR]
; This runs when an alien or player shot has finished exploding
; * Increments the pointer in 0x208D to get UFO points (loops between 0x1D54 and 1D63)

.setUFOScore
     0x0447: 2A [8D 20]  |   LHLD 0x208D                    ; point to HL value stored at 0x208D (init 0x1D54)
     0x044a: 2C          |   INR L                          ; but loop value 0x1d54-0x1d63:...
     0x044b: 7D          |   MOV A, L                       ;
     0x044c: FE [63]     |   CPI 0x63                       ; 
     0x044e: DA [53 04]  |   JC 0x0453                      ;    ... when it is greater than 0x63...
     0x0451: 2E [54]     |   MVI L, 0x54                    ;    ... reset it to 0x54
     0x0453: 22 [8D 20]  |   SHLD 0x208D                    ; otherwise, store increased value

; name: setupUFO [PLAYER SHOT SUBROUTINE / ISR]
; This runs every time a player shot finishes exploding.
; This code makes a pseudorandom choice between two directions for the UFO.
; The "randomization" comes from sequentially pointing at opcodes or operands starting at 0x0801 in the
; ROM (adding 1 to the ROM address each time)
; The code then dereferences this address and looks at the least significant bit, using it to load:
;    * 0: C & 0x208A: E0, B & 0x208C: FC (starting at right)
;    * 1: C & 0x208A: 29, B & 0x208C: 02 (starting at left)
;         0x208A is an encoded x screen coordinate for the UFO 
;         0x208C the second is the x-coordinate offset used for UFO movement
; note that there is apparently no boundary checking, and we're dereferencing ROM, which isn't terribly safe

.setupUFODirection
     0x0456: 2A [8F 20]  |   LHLD 0x208F                    ; increase 2-byte pointer at 0x208F (init: 0800)
     0x0459: 2C          |   INR L                          ; ... loops between 0x0800 and 0x08FF
     0x045a: 22 [8F 20]  |   SHLD 0x208F                    ; 
     0x045d: 3A [84 20]  |   LDA 0x2084                     ; load 0x2084 into A (saucer on screen)
     0x0460: A7          |   ANA A                          ;    ... is it nonzero?
     0x0461: C0          |   RNZ                            ;        if so, there's already a saucer. return
     0x0462: 7E          |   MOV A, M                       ; otherwise... dereference 2-byte pointer at 208F into A
     0x0463: E6 [01]     |   ANI 0x01                       ; (init: 0800) -> take least significant bit
     0x0465: 01 [29 02]  |   LXI B, 0x0229                  ; load 0x0229 into BC
     0x0468: C2 [6E 04]  |   JNZ 0x046E                     ;    ... if LSB is 0, do not
     0x046b: 01 [E0 FE]  |   LXI B, 0xFEE0                  ;    ... load 0xFE into B and 0xE0 into C 
     0x046e: 21 [8A 20]  |   LXI H, 0x208A                  ; but either way... point HL at 0x208A 
     0x0471: 71          |   MOV M, C                       ; put C into memory there             
     0x0472: 23          |   INX H
     0x0473: 23          |   INX H
     0x0474: 70          |   MOV M, B                       ; and put B into memory at 0x208C
     0x0475: C9          |   RET                            ; and return


; **************** ISR ALIEN SHOT 1 ("SKINNY SHOT") OBJECT SUBROUTINE ********************

; -----------------------------------------------------------------------------------
;
; **** ALIEN SHOT 1 ("SKINNY SHOT") OBJECT SUBROUTINE ****
;
;    0x0476 - 1. restart alien shot coordination cycle 
;             2. return if one-time skip at beginning of round after reset. 
;             3. load active alien shot game buffer from skinny shot game buffer
;             4. call process alien shot subroutine
;    0x04A1 - 5. after processing: check explosion timer
;                   a. if nonzero: save alien shot game buffer to skinny shot buffer
;                   b. if zero: reset the skinny shot game buffer from ROM & return
;
; -----------------------------------------------------------------------------------

; name: setupSkinnyShot
; Here we set up processing for the first of three alien shot structures.
; Firstly, the skinny shot sets the toggle at 0x2032 to 0x02, which will block its
; own processing.
; 0x2080 is set from 0x2032, coordinating between the three alien shot structures:
;    0x2032 = 0 / 0x2080 = 0 -- alien shot 1 goes (skinny)
;    0x2032 = 1 / 0x2080 = 1 -- alien shot 2 goes (uptack-T)
;    0x2032 = 2 / 0x2080 = 2 -- alien shot 3 goes (zigzag)
; Note that 0x2032 is initialized as 0x02 and reset from ROM in this procedure
; ** this means skinny shot only runs every 3rd interrupt
;    (when countdown reaches 0)
; ** We then check if 16-bit number in 0x2038/0x2039 is 0x0000. If it is, we
;    decrement it to 0xFFFF and return. Since it's initialized to 0000 this means
;    we skip one interrupt that would have otherwise been active each time it's reset
; We load 11 bytes starting at 0x2035 into the active alien shot structure
; and load running counters from other alien shot structs into 2070 and 2071
;
; we then call processAlienShot
;
; afterward, we check the explosion countdown and save the buffer if ongoing
; or reset the shot structure 0x2030-0x203F if the explosion has concluded

.setupSkinnyShot
     0x0476: E1          |   POP H                          ; this puts 0x2034 into HL
     0x0477: 3A [32 1B]  |   LDA 0x1B32                     ; loads 1B32 (initialized as 0x02)
     0x047a: 32 [32 20]  |   STA 0x2032                     ; restart alien shot coordination cycle
     0x047d: 2A [38 20]  |   LHLD 0x2038                    ; loads the 2-byte value at 2038
     0x0480: 7D          |   MOV A, L                       ; ... to check if this is the first time
     0x0481: B4          |   ORA H                          ; ... we've run this code after reset
     0x0482: C2 [8A 04]  |   JNZ 0x048A                     ; ... if so, 2 bytes at 2038 are 0000
     0x0485: 2B          |   DCX H                          ;         decrement to FFFF
     0x0486: 22 [38 20]  |   SHLD 0x2038                    ;
     0x0489: C9          |   RET                            ;    ... and return. Next time we'll be able to pass
     0x048a: 11 [35 20]  |   LXI D, 0x2035                  ; otherwise point DE to 0x2035
     0x048d: 3E [F9]     |   MVI A, 0xF9                    ; and F9 in A (will be upper limit to relevant sprites)
     0x048f: CD [50 05]  |   CAL 0x0550                     ; load 11 bytes 2035 -> 2073
     0x0492: 3A [46 20]  |   LDA 0x2046                     ; load most recent running time from shotStruct2
     0x0495: 32 [70 20]  |   STA 0x2070                     ; and store at 0x2070
     0x0498: 3A [56 20]  |   LDA 0x2056                     ; and most recent runnint time from shotStruct3
     0x049b: 32 [71 20]  |   STA 0x2071                     ; and store at 0x2071
     0x049e: CD [63 05]  |   CAL 0x0563                     ; call processAlienShot

._saveOrResetSkinny
     0x04a1: 3A [78 20]  |   LDA 0x2078                     ; load explosion countdown timer
     0x04a4: A7          |   ANA A                          ; ... if it's nonzero
     0x04a5: 21 [35 20]  |   LXI H, 0x2035                  ; ... point to structure's buffer at 0x2035
     0x04a8: C2 [5B 05]  |   JNZ 0x055B                     ; ... save 11 values and return
     0x04ab: 11 [30 1B]  |   LXI D, 0x1B30                  ; but if it's zero... 
     0x04ae: 21 [30 20]  |   LXI H, 0x2030
     0x04b1: 06 [10 C3]  |   MVI B, 0x10                    ; 
     0x04b3: C3 [32 1A]  |   JMP 0x1A32                     ; reset shot structure from ROM and return

; **************** ISR ALIEN SHOT 2 ("UPTACK-T SHOT") OBJECT SUBROUTINE ********************

; ----------------------------------------------------------
;
; **** ALIEN SHOT 2 ("UPTACK-T SHOT") OBJECT SUBROUTINE ****
;
;    0x04B6 - 1. check if 0x206E is set. Blocks/returns if one alien left.
;             2. Then check if it's time to process uptack (only when 0x2080 is 1)
;             3. if so, load the active alien shot game buffer from uptack shot game buffer
;             4. and call process alien shot subroutine.
;    0x04D9 - 5. after processing: 
;                   a. boundary check spawn table. Loop to beginning if needed.
;    0x04E7         b. check explosion counter
;                        i. if nonzero: save alien shot game buffer to uptack shot buffer (return)
;                        ii. if zero: reset the uptack shot game buffer from ROM (continue)
;    0x04FC - if there is only one invader left, set flag to block shot next time 
;    0x0508 - save place in the spawn column table to uptack shot buffer
;
;    *** see code further down ***
;    0x067E - utility: save place in spawn column table to alien shot buffer 
;                      (called by wrappers during uptack-T shot processing)
;
; ----------------------------------------------------------

; name: setupUptackTShot
; This is the subroutine jumped to by the second data structure in the game structures 
; processing loop. Here we see that this subroutine runs only when there is more than 1 
; alien left and only if the toggle at 0x2080 is set to 0x01. 
; Setup begins by reading the shot-specific data into the "live" alien shot data structure
; (placing 11 bytes at 2045 into 11 bytes at 2073)
; we then load data from running time counters in the other two alien shot structures into
; 2070 (shot struct 1) and 2071 (shot struct 3)
; and call processAlienShot

.setupUptackTShot
     0x04b6: E1          |   POP H                          ; point HL at 0x2044
     0x04b7: 3A [6E 20]  |   LDA 0x206E                     ; you can see below we set this when 0x2082 is 1
     0x04ba: A7          |   ANA A
     0x04bb: C0          |   RNZ                            ; ... return, block execution if only 1 alien remains
     0x04bc: 3A [80 20]  |   LDA 0x2080                     ; if 0x2080 is not 0x01, return
     0x04bf: FE [01]     |   CPI 0x01
     0x04c1: C0          |   RNZ
     0x04c2: 11 [45 20]  |   LXI D, 0x2045 
     0x04c5: 3E [ED]     |   MVI A, 0xED                    ; 0xED in A will be upper limit of relevant sprites
     0x04c7: CD [50 05]  |   CAL 0x0550                     ; load 11 bytes 2045 -> 2073
     0x04ca: 3A [36 20]  |   LDA 0x2036                     ; put most recent running time from shotStruct1
     0x04cd: 32 [70 20]  |   STA 0x2070                     ; into 0x2070
     0x04d0: 3A [56 20]  |   LDA 0x2056                     ; and most recent running time from shotStruct3 
     0x04d3: 32 [71 20]  |   STA 0x2071                     ; into 0x2071
     0x04d6: CD [63 05]  |   CAL 0x0563                     ; call processAlienShot

; name: _boundaryCheckSpawnTable
; This shot follows a table to determine which column of the invader grid it spawns in (it does not
; follow the player). Here we loop the pointer so it always remains within bounds of the table.
; (allowed: 1D00 - 1D0F)

._boundaryCheckSpawnTable
     0x04d9: 3A [76 20]  |   LDA 0x2076                     ; check pointer to invader column where shot will spawn
     0x04dc: FE [10]     |   CPI 0x10                       ; ... if it's out of bounds (0x00-0x0F permitted)
     0x04de: DA [E7 04]  |   JC 0x04E7                      ;     (full address is 1D00 - 1D0F)
     0x04e1: 3A [48 1B]  |   LDA 0x1B48                     ;
     0x04e4: 32 [76 20]  |   STA 0x2076                     ;    ... reset it to 0 and store back at 0x2076

; name: _saveOrResetUptack
; if the shot has exploded and the explosion counter has finished, we reset the shot structure from ROM.
; Otherwise we save data from the "live" alien shot data structure into the uptack-specific shot structure
; at 0x2045

._saveOrResetUptack
     0x04e7: 3A [78 20]  |   LDA 0x2078                     ; check 0x2078 (explosion status)
     0x04ea: A7          |   ANA A
     0x04eb: 21 [45 20]  |   LXI H, 0x2045 
     0x04ee: C2 [5B 05]  |   JNZ 0x055B                     ; if it's not 0, save shot structure
     0x04f1: 11 [40 1B]  |   LXI D, 0x1B40                  ; otherwise 
     0x04f4: 21 [40 20]  |   LXI H, 0x2040 
     0x04f7: 06 [10]     |   MVI B, 0x10
     0x04f9: CD [32 1A]  |   CAL 0x1A32                     ; reset shot structure from ROM 

; name: _flagOneInvaderLeft
; here we set 0x206E to block the uptack-T shot from firing if there is only one invader left.

._flagOneInvaderLeft
     0x04fc: 3A [82 20]  |   LDA 0x2082                     ; decrement byte at 2082
     0x04ff: 3D          |   DCR A                          ; is it 0?
     0x0500: C2 [08 05]  |   JNZ 0x0508                     ; ... if so...
     0x0503: 3E [01]     |   MVI A, 0x01                    ; store 0x01 at 0x206E
     0x0505: 32 [6E 20]  |   STA 0x206E                     ; ... which prevents processing until decremented

; name: _saveSpawnTablePlace
; This saves the shot structure's place in the new-shot-spawn-column table even if the structure has been
; reset from ROM, so the same few columns don't run over and over.

._saveSpawnTablePlace
     0x0508: 2A [76 20]  |   LHLD 0x2076                    ; load HL from 0x2076
     0x050b: C3 [7E 06]  |   JMP 0x067E                     ; saves HL to 2048, which will restore it for next run (returns)


; ***************** ISR UFO / ALIEN SHOT 3 ("ZIGZAG SHOT") OBJECT SUBROUTINE *********************

; ----------------------------------------------------------
;
; **** ALIEN SHOT 3 ("ZIGZAG SHOT") OBJECT SUBROUTINE ****
;
;    0x050f - 1. load the active alien shot game buffer from zigzag shot game buffer
;             2. and call process alien shot subroutine.
;    0x0526 - 3. after processing: 
;                   a. boundary check spawn table. Loop to beginning if needed.
;    0x0534         b. check explosion counter
;                        i. if nonzero: save alien shot game buffer to zigzag shot buffer (return)
;                        ii. if zero: reset the zigzag shot game buffer from ROM (continue)
;    0x0549 - save place in the spawn column table to zigzag shot buffer
;
; **** ENTRY POINT: UFO SUBROUTINE ***
;
;    0x0682 - entry point. continues active zigzag or UFO. Otherwise falls
;             into spawn-UFO routine
;    0x069E - spawn UFO. if correct time, starts a UFO from either left or right
;             otherwise jumps to zigzag shot handler
;    0x06AB - advance UFO. pass task filter for correct interrupt, then check if UFO is shot (jump). 
;             Otherwise, move UFO appropriately
;    0x06C7 - check location boundary. check if UFO has reached the edge. If so, erase
;    0x06D6 - UFO explosion controller. 
;                   1. at 0x1F: starts explosion. (0x074B)
;                   2. at 0x18: displays score (starts at 0x070C)
;                   3. at 0, turns off explosion sound and resets UFO data from ROM, (falls into 0x06F9)
;    0x06F9 - remove UFO sprite, turn off all UFO audio (returns)
;    0x070C - look up current pseudorandom UFO score, lookup message location to write
;    0x0715 - use score table look up location of score message sprites (numbers) in ROM
;    0x0728 - convert score amount and store as score amount to add, write score to screen (returns)
;    0x073C - utility: write UFO to memory (draw UFO)
;    0x0742 - load registers from UFO struct and convert screen coordinates
;    0x074B - begin UFO explosion - starts port 5 "UFO hit" audio, queues up sprite coordinates
;    0x075F - resets UFO struct from ROM (called during removeUFO)
;
; ----------------------------------------------------------

.__not_accessed__
     0x050e: E1 [11 55]  |   POP H                          ; fairly sure this is an artifact of code that
                                                            ; jumped directly here from game processing structure

; name: setupZigZagShot [PROCESS ZIGZAG SHOT SUBROUTINE / ISR]
; we get here from the 3rd alien shot structure jump if UFO processing has been ruled out or 
; if a shot is already active. (This particular processing jump is shared between the zigzag shot
; and the UFO at top of screen). Here we:
;    ** load the third alien shot structure from its specific RAM buffer into the "live" alien shot struct

.setupZigZagShot
     0x050f: 11 [55 20]  |   LXI D, 0x2055                  ; point at 3rd (jump 4) alien shot structure 
     0x0512: 3E [DB]     |   MVI A, 0xDB                    ; set A <- DB ; this will be the upper limit of sprites
     0x0514: CD [50 05]  |   CAL 0x0550                     ; load shot structure 2055 -> 2073
     0x0517: 3A [46 20]  |   LDA 0x2046                     ; load most recent running time from shotStruct2
     0x051a: 32 [70 20]  |   STA 0x2070                     ; and put t at 0x2070
     0x051d: 3A [36 20]  |   LDA 0x2036                     ; load most recent running time from shotStruct1
     0x0520: 32 [71 20]  |   STA 0x2071                     ; and put it in 0x2071
     0x0523: CD [63 05]  |   CAL 0x0563                     ; call processAlienShot

; name: _boundaryCheckSpawnTableZigzag [PROCESS ZIGZAG SHOT SUBROUTINE / ISR]
; This shot follows a table to determine which column of the invader grid it spawns in (it does not
; follow the player). Here we loop the pointer so it always remains within bounds of the table.
; (allowed: 1D06 - 1D14, inclusive)

._boundaryCheckSpawnTableZigzag
     0x0526: 3A [76 20]  |   LDA 0x2076                     ; check pointer to invader column where shot will spawn
     0x0529: FE [15]     |   CPI 0x15                       ; ... if it's out of bounds (06-14 are permitted)
     0x052b: DA [34 05]  |   JC 0x0534                      ;     (full address is 1D06 to 1D14)
     0x052e: 3A [58 1B]  |   LDA 0x1B58                     ;
     0x0531: 32 [76 20]  |   STA 0x2076                     ;    ... reset to 6 and store back in 0x2076

; name: _saveOrResetZigzag [PROCESS ZIGZAG SHOT SUBROUTINE / ISR]
; if the shot has exploded and the explosion counter has finished, we reset the shot structure from ROM.
; Otherwise we save data from the "live" alien shot data structure into the zigzag-specific shot structure
; at 0x2055

._saveOrResetZigzag
     0x0534: 3A [78 20]  |   LDA 0x2078                     ; check shot explosion countdown
     0x0537: A7          |   ANA A                               ; is it 0? 
     0x0538: 21 [55 20]  |   LXI H, 0x2055                  ; point HL at 2055
     0x053b: C2 [5B 05]  |   JNZ 0x055B                     ; if not, save the alien shot structure and return
     0x053e: 11 [50 1B]  |   LXI D, 0x1B50                  ; otherwise, point DE at 1B50
     0x0541: 21 [50 20]  |   LXI H, 0x2050                  ; and HL at 0x2050
     0x0544: 06 [10]     |   MVI B, 0x10                    ; length in bytes
     0x0546: CD [32 1A]  |   CAL 0x1A32                     ; ROM to RAM copy

; name: _saveSpawnTablePlaceZigzag [PROCESS ZIGZAG SHOT SUBROUTINE / ISR]
; This saves the shot structure's place in the new-shot-spawn-column table even if the structure has been
; reset from ROM, so the same few columns don't run over and over.

._saveSpawnTablePlaceZigzag
     0x0549: 2A [76 20]  |   LHLD 0x2076                    ; store 2076 at 2058 
     0x054c: 22 [58 20]  |   SHLD 0x2058                    ; to preserve position in rotation
     0x054f: C9          |   RET                            ; and return

; *************************** PROCESS ALIEN SHOT SUBROUTINE ******************************

; ----------------------------------------------------------
;
; **** PROCESS ALIEN SHOT SUBROUTINE ****
;
;    Note: this is called by all three alien shot objects.
;    It works with data in the active alien shot game buffer
;
;    0x0550 - utility: load active alien shot from shot-specific buffer
;    0x055B - utility: save active alien shot data to shot-specific buffer
;    0x0563 - entry point: process alien shot. Checks if shot is active
;    0x056C - inactive shot processing: check splash setting
;    0x0577 - check spawn-shot locks & timer as appropriate
;    0x0596 - get column where new shot will be spawned 
;    0x05A5 - checks if there's an alien in the column. If so, gets shot coordsinates
;    0x05B7 - activates new shot, increments counter, returns
;    0x05C1 - active shot actions: checks if shot exploding or falls into advance-sprite
;    0x05D1 - advance shot sprite: erases current, moves pointers to next shot sprite
;    0x05E5 - add sprite offset and draw shot
;    0x05F3 - check for hit. There may be a hit that only leads to explosion of shot itself, or
;             we set the "player hit" flag if the shot "hits" within thresholds
;    0x0612 - set shot exploding: the current alien shot is exploding
;    0x061B - get the invader column closest to the player (to generate tracking shot)
;    0x062F - utility: find closest live invader in player's column
;    0x0644 - handle alien shot blowing up
;    0x064E - draw the explosion sprite by calling draw-sprite utility
;    0x0667 - finish exploding
;    0x066C - utility: draw queued sprite
;    0x0675 - utility: erase queued sprite
;
; ----------------------------------------------------------


; name: loadAlienShotStruct [ALIEN SHOT UTLITY / ISR]
; This utility function moves data from data addressed in DE into the active alien shot buffer

.loadAlienShotStruct
     0x0550: 32 [7F 20]  |   STA 0x207F                     ; A -> upper limit of relevant sprites in ROM (LSB)
     0x0553: 21 [73 20]  |   LXI H, 0x2073 
     0x0556: 06 [0B]     |   MVI B, 0x0B                    ; start 0x0B (11) in B
     0x0558: C3 [32 1A]  |   JMP 0x1A32                     ; rom-to-ram copy 11 bytes from address in DE (returns)

; name: saveAlienShotStruct [ALIEN SHOT UTILITY / ISR]
; This utility procedure moves data from active alien shot buffer into buffer addressed by HL

.saveAlienShotStructure
     0x055b: 11 [73 20]  |   LXI D, 0x2073                  ; point to the struct at 2073
     0x055e: 06 [0B]     |   MVI B, 0x0B                    ; and move 11 bytes into address at HL
     0x0560: C3 [32 1A]  |   JMP 0x1A32                     ; ; rom-to-ram copy 11 bytes from address in DE (returns)

; name: processAlienShot [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; this is the workhorse subroutine for all three alien shots (it's called when each is active)
;    * We begin by checking whether the alien shot in question is active and directing accordingly

.processAlienShot
     0x0563: 21 [73 20]  |   LXI H, 0x2073                  ; load graphical memory pointer at 0x2073 
     0x0566: 7E          |   MOV A, M                       ; put byte there into A
     0x0567: E6 [80]     |   ANI 0x80                       ; bit 7: shot is active when set
     0x0569: C2 [C1 05]  |   JNZ 0x05C1                     ; if it's set... 0x05C1

; name _splashAnimationCheckpoint [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; if the processAlienShot subroutine is called and the shot in question is not active, we come here
; First, we check the permissions for splash processing. If we are processing the splash screen
; where the alien shoots the C, this skips forward to activate shot without the game/demo logic

._splashAnimationCheckpoint
     0x056c: 3A [C1 20]  |   LDA 0x20C1                     ; load A from 0x20C1 (splash index)
     0x056f: FE [04]     |   CPI 0x04                       ; 
     0x0571: 3A [69 20]  |   LDA 0x2069
     0x0574: CA [B7 05]  |   JZ 0x05B7                      ; ... if 0x20C1 is 4, skip until below
                                                            ;     (we are in splash animation)

; name: _checkSpawnShotLocks [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; Here we are checking whether to activate a new alien shot. BOTH other alien shots' counters
; must be either 0 OR above the wait threshold in order to spawn (other conditions return)
;    1. We start by looking at the lock on new alien shots (set with timer when player explodes). 
;       If it's locked, we return.
;    2. check the other alien shot struct's timers. If 2070 and 2071 are both clear, we can
;       continue on and get the shot's spawning coordinates.
;    3. if either 2070 or 2071 is set, but has not reached the interval-between-shots threshold,
;       we return. No new shots until both other shots are either 0 or have passed the interval.

._checkSpawnShotLocks
     0x0577: A7          |   ANA A                          ; is 0x2069 0? (locks new alien shots)
     0x0578: C8          |   RZ                             ; if so, return; we're done
     0x0579: 23          |   INX H                          ; otherwise, increment HL -> 0x2074
     0x057a: 36 [00]     |   MVI M, 0x00                    ; clear it
     0x057c: 3A [70 20]  |   LDA 0x2070                     ; is 2070 clear?
     0x057f: A7          |   ANA A
     0x0580: CA [89 05]  |   JZ 0x0589                      ; ... if so, jump to 0589
     0x0583: 47          |   MOV B, A                       ; ... otherwise check the new shot start timer
     0x0584: 3A [CF 20]  |   LDA 0x20CF                     ; ...     return if we're not there yet
     0x0587: B8          |   CMP B                          ; ...     (2070 is NOT greater than 20CF)
     0x0588: D0          |   RNC
     0x0589: 3A [71 20]  |   LDA 0x2071                     ; load 0x2071
     0x058c: A7          |   ANA A                          ; ... if it's clear...
     0x058d: CA [96 05]  |   JZ 0x0596                      ; ... jump to 0596
     0x0590: 47          |   MOV B, A                       ; ... otherwise, check the new shot start timer
     0x0591: 3A [CF 20]  |   LDA 0x20CF                     ; ...     return if we're not there yet 
     0x0594: B8          |   CMP B                          ; ...     (2071 is NOT greater than 20CF)
     0x0595: D0          |   RNC

; name: _getShotCoordinates [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; This retrieves and stores the column where we're going to spawn the first alien shot sprite
; There are two options. We differentiate using a toggle in 0x2075 set in the ROM for each shot struct.
;    1. 0x2075 is 0: shot location based on player position
;    2. 0x2075 is 1: shot location based on lookup of table in 2076
;         ** alien shot structure 2: lookup table is 1D00 - 1DFF
;         ** alien shot structure 3: lokupt table is 1D06 - 1D14

._getShotColumn
     0x0596: 23          |   INX H                          ; ok we're going to start an alien shot. 
     0x0597: 7E          |   MOV A, M                       ; check byte at 0x2075
     0x0598: A7          |   ANA A                          ; if the byte there is 0, shot tracks player
     0x0599: CA [1B 06]  |   JZ 0x061B                      ; ... jump to 061B (getTargetDistance)
     0x059c: 2A [76 20]  |   LHLD 0x2076                    ; otherwise lookup spawning coords LSB 
     0x059f: 4E          |   MOV C, M                       ; ... by dereferencing address stored at 0x2076
     0x05a0: 23          |   INX H                          ; Bump jump addres in 2076 to the next one. 
     0x05a1: 00          |   NOP
     0x05a2: 22 [76 20]  |   SHLD 0x2076                    ; and store HL back at 2 bytes at 2076

; name: _getSpawningCoordinates [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; gets the coordinates for an alien shot that's going to spawn such that it tracked the player.
; shot coordinates are stored at 0x207B

._getSpawningCoordinates
     0x05a5: CD [2F 06]  |   CAL 0x062F                     ; sets carry if alien found
     0x05a8: D0          |   RNC                            ; appropriate live alien not found so return.
     0x05a9: CD [7A 01]  |   CAL 0x017A                     ; calls getInvaderCoords procedure
                                                            ; use alien index in L to get coords 
                                                            ; L = Y coordinate, C = X coordinate    
     0x05ac: 79          |   MOV A, C                       ; add 7 to X coordinate
     0x05ad: C6 [07]     |   ADI 0x07                       ; 
     0x05af: 67          |   MOV H, A                       ; and put in H
     0x05b0: 7D          |   MOV A, L                       ; then put L in A
     0x05b1: D6 [0A]     |   SUI 0x0A                       ; subtract 10 (spawn below invader)
     0x05b3: 6F          |   MOV L, A                       ; and put back in L
     0x05b4: 22 [7B 20]  |   SHLD 0x207B                    ; store those updated coordinates at 207B

; name: _makeShotActive [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; This procedure comes after we have stored the updated coordinates for the alien shot in
; 0x207B (or we are in the splash animation where invader shoots a "C"). Here we mark the
; current shot being processed as "active" by setting bit 7 of 0x2073.

._makeShotActive
     0x05b7: 21 [73 20]  |   LXI H, 0x2073                   ; back to 2073 
     0x05ba: 7E          |   MOV A, M
     0x05bb: F6 [80]     |   ORI 0x80                       ; shot is now active
     0x05bd: 77          |   MOV M, A                       ; set most significant bit at address in 2073
     0x05be: 23          |   INX H
     0x05bf: 34          |   INR M                          ; and increment MSB at 0x2074
     0x05c0: C9          |   RET                            ; then return

; name: activeShotActions [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; we reach this procedure when we are processing an alien shot structure and the shot in question
; is already active.
; * first we check if we are in the correct interrupt routine (if not, return)
; * then we check if the alien shot is exploding (LSB of 0x2073 is set)

.activeShotActions
     0x05c1: 11 [7C 20]  |   LXI D, 0x207C                  ; point DE at 0x207C (x coordinate of player shot)
     0x05c4: CD [06 1A]  |   CAL 0x1A06                     ; task filter based on screen position (sets carry or not)
     0x05c7: D0          |   RNC                            ; not correct portion of screen, skip this
     0x05c8: 23          |   INX H                          ; HL -> back at 0x2073 (task filter points at 2072)
     0x05c9: 7E          |   MOV A, M
     0x05ca: E6 [01]     |   ANI 0x01                       ; is LSB set? jump [shot blowing up]
     0x05cc: C2 [44 06]  |   JNZ 0x0644
     0x05cf: 23          |   INX H                          ;
     0x05d0: 34          |   INR M                          ; increase byte at 0x2074 (alien shot running time)

; name _advanceShotSprite [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; Here we erase the previous sprite using values already held in the shot structure, then update
; the shot structure to point at the next sprite in the shot's animation sequence. These are 3 bytes apart.
; The address of the final sprite in animation sequence is held in 0x207F. We wrap by subtracting 0x12
; when we surpass it, to skip back to the first of four sprites. 

._advanceShotSprite
     0x05d1: CD [75 06]  |   CAL 0x0675                     ; eraseQueuedSprite_2079 (5 bytes at 2079)
     0x05d4: 3A [79 20]  |   LDA 0x2079                     ; load A from 2079 (LSB of shot sprite ROM pointer)
     0x05d7: C6 [03]     |   ADI 0x03                       ; add 3 to point at next sprite
     0x05d9: 21 [7F 20]  |   LXI H, 0x207F                  ; grab value from 207F (holds last sprite LSB)
     0x05dc: BE          |   CMP M                          ; ... compare new value to the byte at 0x207F?
     0x05dd: DA [E2 05]  |   JC 0x05E2                      ; ... if the new value is greater than (207F)
     0x05e0: D6 [0C]     |   SUI 0x0C                       ;        ... wrap around by subtracting 12
     0x05e2: 32 [79 20]  |   STA 0x2079                     ; then store new value at 2079

; name: _moveShot [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; Here we advance the shot's Y position in 0x207B by adding the horizontal offset stored in 207E
; Then we draw the shot by calling the drawQueuedSprite utility that pulls data from registers at 2079,
; then calls drawShot (which shifts and writes to screen, while checking for collisions)

._moveShot
     0x05e5: 3A [7B 20]  |   LDA 0x207B                     ; load 0x207B
     0x05e8: 47          |   MOV B, A                       ; store in B
     0x05e9: 3A [7E 20]  |   LDA 0x207E                     ; load 0x207E
     0x05ec: 80          |   ADD B                          ; A += B
     0x05ed: 32 [7B 20]  |   STA 0x207B                     ; and store at 0x207B
     0x05f0: CD [6C 06]  |   CAL 0x066C                     ; draw the shot, set 0x2061 if collision

; name: _checkForHit [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; This handler checks whether a shot needs to initiate an explosion (because something is hit or it's
; out of bounds)
; The primary purpose of the alien shot is to kill the player's gunship. This handles the
; parameters of that action by setting Y-coordinate thresholds. 
; The alien shot may:
;    * reach 0x15 whether or not there was collision (this is bottom, start shot explosion)
;    * not collide. Returns with no further action so long as 0x15 has not been reached.
;    * hit something above 0x27 encoded Y coordinate (shot explosion started)
;    * hit something between 0x1E and 0x27 (player explosion started, shot explosion started)
;    * hit something below 0x1E (shot explosion started)

._checkForHit     
     0x05f3: 3A [7B 20]  |   LDA 0x207B                     ; where is shot?
     0x05f6: FE [15]     |   CPI 0x15                       ;
     0x05f8: DA [12 06]  |   JC 0x0612                      ; hit the bottom... deactivate shot/start explosion
     0x05fb: 3A [61 20]  |   LDA 0x2061                     ; has shot collided with anything?
     0x05fe: A7          |   ANA A
     0x05ff: C8          |   RZ                             ; ... nope! return
     0x0600: 3A [7B 20]  |   LDA 0x207B                     ; ... yes but....
     0x0603: FE [1E]     |   CPI 0x1E                       ;    ... happened below player damage threshold
     0x0605: DA [12 06]  |   JC 0x0612                      ;    deactivate shot/start explosion (player ok)
     0x0608: FE [27]     |   CPI 0x27                       ; ... yes and....
     0x060a: 00          |   NOP                            ;    ... happened above player damage threshold
     0x060b: D2 [12 06]  |   JNC 0x0612                     ;    deactivate shot/start explosion (player ok)
     0x060e: 97          |   SUB A                          ; ... yes and was within player damage threshold
     0x060f: 32 [15 20]  |   STA 0x2015                     ;    ... set player hit

; name: _setShotExploding [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; Sets bit 0 of 0x2073 for the current shot to indicate that it is exploding.
; At this point, the shot remains active

._setShotExploding
     0x0612: 3A [73 20]  |   LDA 0x2073
     0x0615: F6 [01]     |   ORI 0x01                       ; set bit 0 (indicates shot exploding)
     0x0617: 32 [73 20]  |   STA 0x2073                     ; and store back in 0x2073
     0x061a: C9          |   RET                            ; return

; name: invaderColumnOfPlayer [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; Here we are finding the column number of invaders near the center of the player's sprite
; in order to properly generate an alien shot in the correct location
; We start by loading the player's X-coordinate, and adding 8 to center over the sprite
; We put the column in C and A and make sure it's no more than 0x0B (11d, which is how many
; invader columns there are). We then call findAlienColumn. If the answer is out of range
; we set to the last column (0x0B or decimal 11)

.invaderColumnOfPlayer 
     0x061b: 3A [1B 20]  |   LDA 0x201B                     ; load current player X coordinate
     0x061e: C6 [08]     |   ADI 0x08                       ;
     0x0620: 67          |   MOV H, A                       ; H = player X-coord + 8 (center of sprite)
     0x0621: CD [6F 15]  |   CAL 0x156F                     ; puts column in C
     0x0624: 79          |   MOV A, C
     0x0625: FE [0C]     |   CPI 0x0C                       ; boundary checking. column in grid of aliens?
     0x0627: DA [A5 05]  |   JC 0x05A5                      ; ... player within alien grid. jump
     0x062a: 0E [0B]     |   MVI C, 0x0B                    ; otherwise player outside grid. Set to max (0x0B)
     0x062c: C3 [A5 05]  |   JMP 0x05A5                     ; continue...

; name: liveInvaderLookup [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; we get here when we want to fire a new alien shot that tracks the player. We know the 
; alien grid column closest to the player (in C) but now we need to check whether there is 
; an alien alive within the player's column that can shoot at them.
; Here we loop through the aliens within that column. If we find a live one,
; we set carry and return, with the invader's index in L. Otherwise, return
; without carry set.

.liveInvaderLookup
     0x062f: 0D          |   DCR C                          ; decrement C
     0x0630: 3A [67 20]  |   LDA 0x2067                     ; load value in 2067 into A (player specific)
     0x0633: 67          |   MOV H, A                       ; put A in H
     0x0634: 69          |   MOV L, C                       ; put C in L
     0x0635: 16 [05]     |   MVI D, 0x05                    ; and 0x05 in D
     0x0637: 7E          |   MOV A, M                       ; byte from player specific + distance in 16s in A
     0x0638: A7          |   ANA A                          ; is it 0? ...set carry                          
     0x0639: 37          |   STC
     0x063a: C0          |   RNZ                            ;              ... and return
     0x063b: 7D          |   MOV A, L                       ; otherwise, put L in A
     0x063c: C6 [0B]     |   ADI 0x0B                       ; add 11
     0x063e: 6F          |   MOV L, A                       ; restore to L
     0x063f: 15          |   DCR D                          ; decrement D
     0x0640: C2 [37 06]  |   JNZ 0x0637                     ; loop until D is 0
     0x0643: C9          |   RET                            ; and return

; name: handleShotBlowingUp [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; we reach here if an alien shot is actively blowing up (bit 0 of 0x2073 is set)
; 0x2078 holds the explosion status countdown. It is initialized at 0x04 in all three
; alien shot structures when ROM is copied.
; Here we see that at 0x03, it replaces the shot sprite with a larger explosion sprite
; Then at 0x00 it erases the explosion sprite sprite and returns.
; At other values of 0x2078, the code returns without taking action.

.handleShotBlowingUp
     0x0644: 21 [78 20]  |   LXI H, 0x2078 
     0x0647: 35          |   DCR M
     0x0648: 7E          |   MOV A, M
     0x0649: FE [03]     |   CPI 0x03                       ; if byte at 0x2078 is not 3...
     0x064b: C2 [67 06]  |   JNZ 0x0667                     ;    ... either return (countdown in progress)
                                                            ; or erase sprite then return (countdown hit 0)

; name: _drawExplosionSprite [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; Removes shot sprite and draws explosion sprite when the countdown in 0x2078 reaches 3.

._drawExplosionSprite
     0x064e: CD [75 06]  |   CAL 0x0675                     ; otherwise, 2078 is 3. erase sprite
     0x0651: 21 [DC 1C]  |   LXI H, 0x1CDC                  ; ... then continue processing here ...
     0x0654: 22 [79 20]  |   SHLD 0x2079                    ; put 1CDC at 0x2079
     0x0657: 21 [7C 20]  |   LXI H, 0x207C                  ; point HL at 0x207C 
     0x065a: 35          |   DCR M                          ; ... and decrement it x2
     0x065b: 35          |   DCR M
     0x065c: 2B          |   DCX H                          ; point HL at 0x207B
     0x065d: 35          |   DCR M                          ; ... and decrement it x2
     0x065e: 35          |   DCR M
     0x065f: 3E [06]     |   MVI A, 0x06                    ; stores 6 at 207D 
     0x0661: 32 [7D 20]  |   STA 0x207D                     ; ... sets width of explosion sprite
     0x0664: C3 [6C 06]  |   JMP 0x066C                     ; draw queued sprite

; name: _finishExploding [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; Removes alien shot explosion sprite when countdown in 0x2078 reaches 0

._finishExploding                                            ; skip erase sprite if 0x2078 (in A) is nonzero but not 3
     0x0667: A7          |   ANA A
     0x0668: C0          |   RNZ
     0x0669: C3 [75 06]  |   JMP 0x0675

; name: drawQueuedSprite [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; used to draw any of the alien shots, once their sprites and coordinates have been updated.
; This calls drawShot, which sets 0x2061 if there is a collision (drawShot is also used for the player's shot)

.drawQueuedSprite_2079                                           ; use 5 bytes in memory at 2079 to draw a sprite (shot)
     0x066c: 21 [79 20]  |   LXI H, 0x2079 
     0x066f: CD [3B 1A]  |   CAL 0x1A3B                          ; retrieve registers from memory (E, D, L, H, B)
     0x0672: C3 [91 14]  |   JMP 0x1491                          ; draw shot

; name: eraseQueuedSprite_0279 [PROCESS ALIEN SHOT SUBROUTINE / ISR]
; This erases the alien shot sprite currently "live" in the data structure at 0x2079
; It's used when explosion is finished to erase the sprite a final time, and 
; when to remove an old shot sprite when moving down to a new position

.eraseQueuedSprite_2079                                         ; uses 5 bytes in memory at 2079 to erase a sprite
     0x0675: 21 [79 20]  |   LXI H, 0x2079                       ; point HL at 0x2079
     0x0678: CD [3B 1A]  |   CAL 0x1A3B                          ; retrieve registers from memory (E, D, L, H, B)
     0x067b: C3 [52 14]  |   JMP 0x1452                          ; jump to .eraseSprite (returns)


; --------------------------------------------------------
;
;  out of place: utility used in uptack-T shot processing
;
; --------------------------------------------------------

; name: Put2076InBuffer_uptack
; called during uptack-T shot processing as a wrapper. Not sure why it's down here.

.Put2076InBuffer_uptack
     0x067e: 22 [48 20]  |   SHLD 0x2048                   ; store HL at 0x2048 (sets 2076 for next jump3 load)
     0x0681: C9          |   RET

; ----------------------------------------------------------
;
; **** ALIEN SHOT 3 ("ZIGZAG SHOT") OBJECT SUBROUTINE ****
;
; ----------------------------------------------------------

.setupZigZagShotUFO
     0x0682: E1          |   POP H                          ; point HL to 0x2054
     0x0683: 3A [80 20]  |   LDA 0x2080                     ; 0x2080 must be 2, or this doesn't go
     0x0686: FE [02]     |   CPI 0x02
     0x0688: C0          |   RNZ
     0x0689: 21 [83 20]  |   LXI H, 0x2083                  ; load 0x2083 (start UFO flag) 
     0x068c: 7E          |   MOV A, M                       ; are we starting a UFO?
     0x068d: A7          |   ANA A                          ; if it's 0, jump to shot handler
     0x068e: CA [0F 05]  |   JZ 0x050F
     0x0691: 3A [56 20]  |   LDA 0x2056                     ; is this the first tick we've counted 
     0x0694: A7          |   ANA A                          ; ... in other words has shot already started?
     0x0695: C2 [0F 05]  |   JNZ 0x050F                     ; if the shot's already started, jump to shot handler
     0x0698: 23          |   INX H                          ; point at 0x2084 (is there a UFO on screen?)
     0x0699: 7E          |   MOV A, M                       ; is it 0?
     0x069a: A7          |   ANA A
     0x069b: C2 [AB 06]  |   JNZ 0x06AB                     ; no... a UFO is already on screen

; ************************************* UFO SUBROUTINE ********************************

; name: startUFO [ZIGZAG SHOT-UFO SUBROUTINE (JUMP STRUCTURE 4) / ISR]
; This routine starts a UFO by first checking that there are at least aliens on screen. If so, 
; we set 0x2084, indicating an active UFO is present, and then write the UFO to coordinates in the
; UFO data structure (the starting location and travel direction are set during setupUFO 
; in the player shot ISR subroutine). We then draw the UFO and fall into the advanceUFO routine

.startUFO
     0x069e: 3A [82 20]  |   LDA 0x2082                     ; is (2082) < 8?
     0x06a1: FE [08 DA]  |   CPI 0x08
     0x06a3: DA [0F 05]  |   JC 0x050F                      ; if so, jump to shot handler (skip saucer)
     0x06a6: 36 [01]     |   MVI M, 0x01                    ; otherwise, set 2084 to 1 (set saucer on screen)
     0x06a8: CD [3C 07]  |   CAL 0x073C                     ; writeUFOToMemory

; name: advanceUFO [UFO SUBROUTINE (JUMP STRUCTURE 4) / ISR]
; We check to make sure we're in the correct interrupt for screen location, then check to see if we are moving
; the sprite (once a UFO is hit -- flagged by 0x2085 -- it doesn't move.)

.advanceUFO
     0x06ab: 11 [8A 20]  |   LXI D, 0x208A                  ; load screen coordinates
     0x06ae: CD [06 1A]  |   CAL 0x1A06                     ; taskFilter: are we in correct interrupt?
     0x06b1: D0          |   RNC                            ; ... if not, return
     0x06b2: 21 [85 20]  |   LXI H, 0x2085                  ; otherwise, point HL at 2085
     0x06b5: 7E          |   MOV A, M                       ; is it clear?
     0x06b6: A7          |   ANA A
     0x06b7: C2 [D6 06]  |   JNZ 0x06D6                     ; if not, jump to 06D6 (ufoShot)
     0x06ba: 21 [8A 20]  |   LXI H, 0x208A                  ; otherwise, point HL at UFO X coordinate
     0x06bd: 7E          |   MOV A, M                       ;
     0x06be: 23          |   INX H                          ; point HL at 208C (UFO X offset)
     0x06bf: 23          |   INX H
     0x06c0: 86          |   ADD M                          ; and add the offset to MSB (x coord)
     0x06c1: 32 [8A 20]  |   STA 0x208A                     ; and store back in 208A
     0x06c4: CD [3C 07]  |   CAL 0x073C                     ; writeUFOToMemory

; name: _ufoBoundryCheck [UFO SUBROUTINE (JUMP STRUCTURE 4) / ISR]
; checks to make sure the UFO has not reached the edge of the screen. If not, returns. If it has, 
; jumps to the out-of-bounds handler.

._UFOBoudaryCheck
     0x06c7: 21 [8A 20]  |   LXI H, 0x208A 
     0x06ca: 7E          |   MOV A, M                       ; grab x coordinate
     0x06cb: FE [28]     |   CPI 0x28                       ; is it less than 0x28? (offscreen to left?)
     0x06cd: DA [F9 06]  |   JC 0x06F9                      ; ... jump to 06F9 (ufoOutOfBounds)
     0x06d0: FE [E1]     |   CPI 0xE1                       ; is it greater than 0xE1 (offscreen to right?)
     0x06d2: D2 [F9 06]  |   JNC 0x06F9                     ; ... jump to 06F9 (ufoOutOfBounds)
     0x06d5: C9          |   RET

; name: ufoShot [UFO SUBROUTINE / ISR]
; Turn off the running UFO sound. Turn off the UFO explosion sound at end of explosion
; times down the explosion from 0x20 (starts explosion at 0x1F, writes score at 0x18)

.ufoShot
     0x06d6: 06 [FE]     |   MVI B, 0xFE
     0x06d8: CD [DC 19]  |   CAL 0x19DC                     ; mask port 3 audio (turns off running UFO sound)
     0x06db: 23          |   INX H                          ; point HL at 0x2086 (time down the UFO explosion)
     0x06dc: 35          |   DCR M                          ; decrease
     0x06dd: 7E          |   MOV A, M
     0x06de: FE [1F]     |   CPI 0x1F                       ; is it 1F? (first time through - initialized at 0x20)
     0x06e0: CA [4B 07]  |   JZ 0x074B                      ; if so, jump to 074B, beginUFOExplosion (returns)
     0x06e3: FE [18]     |   CPI 0x18                       ; is it 0x18?
     0x06e5: CA [0C 07]  |   JZ 0x070C                      ; if so, jump to 070C, write ufo score (returns)
     0x06e8: A7          |   ANA A                          ; ... otherwise, is it 0?
     0x06e9: C0          |   RNZ                            ; ... nope, return
     0x06ea: 06 [EF]     |   MVI B, 0xEF                    ; handling 0 (timer finished):
     0x06ec: 21 [98 20]  |   LXI H, 0x2098                  ; point HL at 0x2098 (port 5 audio buffer)
     0x06ef: 7E          |   MOV A, M                       ; turn off bit 4
     0x06f0: A0          |   ANA B
     0x06f1: 77          |   MOV M, A                       ; .. and replace it            
     0x06f2: E6 [20]     |   ANI 0x20                       ; send bit 5 ONLY out to port 5 ; indicates player
     0x06f4: D3 [05]     |   OUT 0x05                       ; 
     0x06f6: 00          |   NOP                            ; falls into the removeUFO procedure, which
     0x06f7: 00          |   NOP                            ; removes the sprite and resets the data structure
     0x06f8: 00          |   NOP

; name: removeUFO [UFO SUBROUTINE / ISR]
; removes UFO from screen, resets UFO structure from ROM, and masks off UFO audio in Port 3
; returns from jump object subroutine

.removeUFOSprite
     0x06f9: CD [42 07]  |   CAL 0x0742                     ; sets up data for writing UFO to memory
     0x06fc: CD [CB 14]  |   CAL 0x14CB                     ; clear line of length (B) --- 0xEF (returns)
     0x06ff: 21 [83 20]  |   LXI H, 0x2083                  ; point HL at 2083
     0x0702: 06 [0A]     |   MVI B, 0x0A                    ; set B to 0x0A (10 bytes)
     0x0704: CD [5F 07]  |   CAL 0x075F                     ; 1B83 (rom) -> 2083 (ram). resets UFO struct
     0x0707: 06 [FE]     |   MVI B, 0xFE
     0x0709: C3 [DC 19]  |   JMP 0x19DC                     ; masks port 3 audio (bit 0 off), returns

name: ufoShotScore [UFO SUBROUTINE (JUMP STRUCTURE 4) / ISR]
; set 0x20F1 (time to add UFO score)
; 0x208D is the current pointer to the UFO score. It's moved during the player shot subroutine

.ufoShotScore
     0x070c: 3E [01]     |   MVI A, 0x01
     0x070e: 32 [F1 20]  |   STA 0x20F1                          ; set 0x01 at 0x20F1 (update score flag)
     0x0711: 2A [8D 20]  |   LHLD 0x208D                         ; load HL from 208D (pointer to score)
     0x0714: 46          |   MOV B, M                            ; move score table value into B


; name: _lookupMessageLocation [UFO SUBROUTINE (JUMP STRUCTURE 4) / ISR]
; Here we are using the score looked up in the pseudorandomizer table (which is either 5, 10, 15, or 30)
; to look up the LSB coordinate for where we will find the sprite sequence of numeric characters 
; to print the score to the screen (0x1Dxx)
; the first column (match with score) is at 0x1D50
; the second column, with the LSB values, is at 1D4C 
; the sprite messages the tables eventually reference are at:
;         ** 1D94 " 50"
;         ** 1D97 "100" 
;         ** 1D9A "150"
;         ** 1D9D "300"

._lookupMessageLocation
     0x0715: 0E [04]     |   MOV C, 0x04                         ; set C to 4
     0x0717: 21 [50 1D]  |   LXI H, 0x1D50                       ; point HL at 0x1D50 
     0x071a: 11 [4C 1D]  |   LXI D, 0x1D4C                       ; and DE at 1D4C
     0x071d: 1A          |   LDAX D                              ; load A from DE (starts with 1d4c -- init: 05)
     0x071e: B8          |   CMP B                               ; compare: does byte at DE == B?
     0x071f: CA [28 07]  |   JZ 0x0728                           ; ... if so jump
     0x0722: 23          |   INX H                               ; otherwise, increase HL
     0x0723: 13          |   INX D                               ; increase DE
     0x0724: 0D          |   DCR C                               ; decrement C
     0x0725: C2 [1D 07]  |   JNZ 0x071D                          ; if C's not 0 yet, loop

; name: _prepareScoreMessage [UFO SUBROUTINE (JUMP STRUCTURE 4) / ISR]
; After looking up the message location, we store the LSB into 0x2087 (we'll use this to write to screen)
; We then grab the score from B and put it into HL, where we shift it over 4 bits (x16). 
; Because the scores are BCD this is effectively multiplying by 10. (so 5 -> 50 and so on)

._prepareScoreMessage
     0x0728: 7E          |   MOV A, M                            ; move corresponding value from HL into A
     0x0729: 32 [87 20]  |   STA 0x2087                          ; and update as LSB of message location
                                                                 ; this will populate in DE
     0x072c: 26 [00]     |   MVI H, 0x00                         ; then clear H and put B in L
     0x072e: 68          |   MOV L, B
     0x072f: 29          |   DAD H                               ; x2
     0x0730: 29          |   DAD H                               ; x4
     0x0731: 29          |   DAD H                               ; x8
     0x0732: 29          |   DAD H                               ; x16 -> but BCD so simulates x10
     0x0733: 22 [F2 20]  |   SHLD 0x20F2                         ; store that value as score update amount (0x20F2)
     0x0736: CD [42 07]  |   CAL 0x0742                          ; grab UFO registers
     0x0739: C3 [F1 08]  |   JMP 0x08F1                          ; write score message to screen (and return)

; name: writeUfOToMemory [UFO SUBROUTINE / ISR]
; here we pull data from the UFO data structure at 0x2087 and read it into registers as follows:
; DE <- 0x2087, 2088 (sprite coordinates), HL <- 0x2089, 0x208A (screen coords), B <- 0x208B (sprite size)
; Decoding routine for screen coordinates is called as part of the setupUFOToRegisters procedure.

.writeUFOToMemory
     0x073c: CD [42 07]  |   CAL 0x0742                     ; call setupUFOToRegisters
     0x073f: C3 [39 14]  |   JMP 0x1439                     ; visual memory address now in HL. 
                                                            ; call writeSpriteNoShift

; name: UFOToRegisters [UFO SUBROUTINE / ISR]
; Here we dump the data in the UFO data structure into registers and jump to 0x1A47 to convert
; the screen coordinates in HL from encoded to memory addresses (returns)

.UFOToRegisters
     0x0742: 21 [87 20]  |   LXI H, 0x2087                  ; point HL at 2087
     0x0745: CD [3B 1A]  |   CAL 0x1A3B                     ; read 5 bytes into registers:  E, D, L, H, B 
     0x0748: C3 [47 1A]  |   JMP 0x1A47                     ; convert to screen coordinates (returns) 
                                                            ; changes encoded location to visual memory coordinates 

; name: beginUFOExplosion [UFO SUBROUTINE / ISR]
; called at the beginning of the 0x20-tick UFO explosion countdown, this writes an explosion sprite the screen
; and turns on port 5  
.beginUFOExplosion
     0x074b: 06 [10]     |   MVI B, 0x10
     0x074d: 21 [98 20]  |   LXI H, 0x2098                  ; turns on "UFO hit" bit in port 5 audio buffer
     0x0750: 7E          |   MOV A, M
     0x0751: B0          |   ORA B
     0x0752: 77          |   MOV M, A                       
     0x0753: CD [70 17]  |   CAL 0x1770                     ; turn off invaders' standard audio
     0x0756: 21 [7C 1D]  |   LXI H, 0x1D7C                  ; point HL at sprite for exploding saucer (step1)
     0x0759: 22 [87 20]  |   SHLD 0x2087                    ; store those coordinates at 2087 *current ufo sprite*
     0x075c: C3 [3C 07]  |   JMP 0x073C                     ; writeUFOToMemory (returns)

; name: resetUFOStruct [UFO SUBROUTINE / ISR]
; when a UFO is destroyed (either out of bounds or via explosion) this procedure is called and the 10-byte
; structure is reset from ROM (0x1B83 -> 0x2083) 

.resetUFOStruct                                             ; 1B83 (rom) -> 2083 (ram). resets UFO struct
     0x075f: 11 [83 1B]  |   LXI D, 0x1B83                  ; point DE at 1B83
     0x0762: C3 [32 1A]  |   JMP 0x1A32


; ************************* WAIT-FOR-START LOOP: INIT & SINGLE-PLAYER *****************************

; -----------------------------------------------------------------------
;
;    NOTE: wait-for-start functions are in two places
;          * umbrella and single-player procedures: 0x0765
;          * explicit multi-player procedures: 0x0857
;
;    This section of code is the umbrella and single-player procedures
;
;    0x0765: exit ISR (resets stack) / prints "PUSH"
;    0x077F: gateway: considers whether credit balance is greater than 1
;    0x078B: prints "ONLY 1PLAYER BUTTON" and checks for _START1PLAYER input
;    0x0798: single player start. Clears A & falls into game loop
;
; ------------------------------------------------------------------------

; name: waitToStartPrintPush [ISR EXIT POINT - VBLANK]
; this is the beginning of the "wait-to-start" loop. We are deposited here by the VBLANK interrupt once
; at least one credit has been registered. 
; Note that as we exit VBLANK, we do not pop registers. Instead, the stack is entirely reset.
; This enters a flag indicating the game is waiting to start, enables interrupts, and prints "PUSH".
; "wait-to-start" then begins polling inputs for a start signal

.waitToStartPrintPush
     0x0765: 3E [01]     |   MVI A, 0x01
     0x0767: 32 [93 20]  |   STA 0x2093                     ; stores 0x01 in 2093 (waiting to start flag)
     0x076a: 31 [00 24]  |   LXI SP, 0x2400                 ; resets the stack pointer
     0x076d: FB          |   EI                             ; enables interrupts
     0x076e: CD [79 19]  |   CAL 0x1979                     ; turns off game processing & displays credit
     0x0771: CD [D6 09]  |   CAL 0x09D6                     ; clear the game area
     0x0774: 21 [13 30]  |   LXI H, 0x3013 
     0x0777: 11 [F3 1F]  |   LXI D, 0x1FF3                  ; pointer to "PUSH"
     0x077a: 0E [04]     |   MVI C, 0x04
     0x077c: CD [F3 08]  |   CAL 0x08F3                     ; write message (no delay)

; name: _considerCreditPollStartLoop
; This gateway considers whether a player's credit balance is greater than 1. If so, moves to polling
; for either start button. If not, continues polling for 1-player start only

._considerCreditPollStartLoop
     0x077f: 3A [EB 20]  |   LDA 0x20EB                     ; load the credit balance
     0x0782: 3D          |   DCR A                          ; decrement by 1
     0x0783: 21 [10 28]  |   LXI H, 0x2810                  ; and point HL at 0x2810
     0x0786: 0E [14]     |   MVI C, 0x14                    ; length of message
     0x0788: C2 [57 08]  |   JNZ 0x0857                     ; jump if credit left is at least 2 -> .2creditPollStart

; name: oneCreditPollStart
; code prints the message "ONLY 1PLAYER BUTTON" and checks INPUT PORT 1 for bit 4, the single-player
; start button. If there's no signal, this loops. Otherwise, falls into single-player start.

.oneCreditPollStart
     0x078b: 11 [CF 1A]  |   LXI D, 0x1ACF                  ; load DE with pointer to "ONLY 1PLAYER BUTTON "
     0x078e: CD [F3 08]  |   CAL 0x08F3                     ; write to screen (no delay)
     0x0791: DB [01]     |   IN 0x01
     0x0793: E6 [04]     |   ANI 0x04                       ; check _START1PLAYER input
     0x0795: CA [7F 07]  |   JZ 0x077F                      ; return to top of _considerCreditPollStartLoop

; name: onePlayerStart
; sets B to 0x99 (-1, to subtract from credits) and A to 0 (1 player start)

.onePlayerStart
     0x0798: 06 [99]     |   MVI B, 0x99
     0x079a: AF [32 CE]  |   XRA A                          ; clear A (to set one player)

; ****************************** GAME PROCESSING *****************************

; ----------------------------------------------------------------------------
;
;    **** NON-ISR GAME PROCESSING ****
;
;    NOTE: non-ISR game processing is in two locations. Here and
;          beneath the 2-player wait-to-start procedures.
;          Those pick up again at 0x0872
;
;    0x079B - start new game procedure
;    0x0804 - draw boundary line. jump to restore current player's bunkers
;    0x080E - player 2: restore bunkers, draw boundary line again
;    0x0814 - wrapper: initialize alien arrays for both players to 1s
;    0x0817 - enable interrupt game processing and sound
;    0x081F - main game loop (see documentation below for more info)
;
; ------------------------------------------------------------------------------

; name: startNewGame
; This is the landing point to start a new game as we come out of the wait-for-start loop.
; First, we either set or clear the one-or-two-players flag at 0x20CE
; Then we subtract either 1 or 2 from the number of credits at 0x20EB (using BCD addition)
; We display the credit balance and player scores
; then we lock ISR processing in order to intialize the game field and game structures
; To initialize game we:
;    * switch into game mode
;    * set players 1 and 2 to "alive" at 0x20E7 and 0x20E8
;    * indicate neither player has yet received an extra life
;    * print the high scores
;    * initialize both bunker buffers 
;    * poll input for dipswitch settings and set lives for both players
;    * restore the global x-direction invader offset to 02
;    * remove the score for player 2 if we're in a single-player game
;    * set all invaders to "alive" for both players
;    * store 0x3878 (converts to 0x270F) to 0x21FC and 0x22FC. 
;      This is the origin alien's start for players 1 and 2
;    * reset RAM from FOM 0x2000 - 0X20C0 (game structures & variables)
;    * write number of lives and "ship" sprites indicating lives to video memory
;    * message 'PLAY PLAYER<1> or PLAY PLAYER<2>', blinking score
;    * clear the play area
;    * reset splash sequence processing control to 0

.startNewGame
     0x079b: 32 [CE 20]  |   STA 0x20CE                     ; set/clear one or two players flag
     0x079e: 3A [EB 20]  |   LDA 0x20EB                     ; load number of credits
     0x07a1: 80          |   ADD B                          ; BCD -1
     0x07a2: 27          |   DAA                            ; adjust for BCD
     0x07a3: 32 [EB 20]  |   STA 0x20EB                     ; store in memory
     0x07a6: CD [47 19]  |   CAL 0x1947                     ; display credit balance
     0x07a9: 21 [00 00]  |   LXI H, 0x0000 
     0x07ac: 22 [F8 20]  |   SHLD 0x20F8                    ; set player 1 score to '0000'
     0x07af: 22 [FC 20]  |   SHLD 0x20FC                    ; sets player 2 score to '0000'
     0x07b2: CD [25 19]  |   CAL 0x1925                     ; prints player 1 score
     0x07b5: CD [2B 19]  |   CAL 0x192B                     ; prints player 2 score
     0x07b8: CD [D7 19]  |   CAL 0x19D7                     ; turns off interrupt game processing
     0x07bb: 21 [01 01]  |   LXI H, 0x0101 
     0x07be: 7C          |   MOV A, H
     0x07bf: 32 [EF 20]  |   STA 0x20EF                     ; set game mode
     0x07c2: 22 [E7 20]  |   SHLD 0x20E7                    ; set 20E7 and 20E8 to 0x01 (p1, p2 are alive)
     0x07c5: 22 [E5 20]  |   SHLD 0x20E5                    ; set 20E5 and 20E6 to 0x01 (p1, p2 get extra ships)
     0x07c8: CD [56 19]  |   CAL 0x1956                     ; print high scores
     0x07cb: CD [EF 01]  |   CAL 0x01EF                     ; draw new bunkers in buffer (player 1)
     0x07ce: CD [F5 01]  |   CAL 0x01F5                     ; draw new bunkers in buffer (player 2)
     0x07d1: CD [D1 08]  |   CAL 0x08D1                     ; reset lives from input (puts in A)
     0x07d4: 32 [FF 21]  |   STA 0x21FF                     ; store lives for player 1
     0x07d7: 32 [FF 22]  |   STA 0x22FF                     ; store lives for player 2
     0x07da: CD [D7 00]  |   CAL 0x00D7                     ; invader X movement = 0x02, p2 score removed if 1 player
     0x07dd: AF          |   XRA A
     0x07de: 32 [FE 21]  |   STA 0x21FE                     ; player 1: no levels defeated yet
     0x07e1: 32 [FE 22]  |   STA 0x22FE                     ; player 2: no levels defeated yet
     0x07e4: CD [C0 01]  |   CAL 0x01C0                     ; reset player 1 invaders array to 1s
     0x07e7: CD [04 19]  |   CAL 0x1904                     ; reset player 2's invaders array to 1s
     0x07ea: 21 [78 38]  |   LXI H, 0x3878                  ; point HL to 0x3878
     0x07ed: 22 [FC 21]  |   SHLD 0x21FC                    ; store that address to 0x21FC (p1 origin alien coords)
     0x07f0: 22 [FC 22]  |   SHLD 0x22FC                    ; store the same address to 22FC (p2 origin alien coords)
     0x07f3: CD [E4 01]  |   CAL 0x01E4                     ; reset ram 2000 - 20C0 ONLY
     0x07f6: CD [7F 1A]  |   CAL 0x1A7F                     ; .writeRemainingPlayerLives
     0x07f9: CD [8D 08]  |   CAL 0x088D                     ; message: 'PLAY PLAYER<1>' or 'PLAY PLAYER<2>', blink score
     0x07fc: CD [D6 09]  |   CAL 0x09D6                     ; clear play area (ignore edges)
     0x07ff: 00          |   NOP
     0x0800: AF          |   XRA A
     0x0801: 32 [C1 20]  |   STA 0x20C1                     ; reset splash sequence to 0

; ************************* START ROUND: RESTORE PLAYER(S) FROM MEMORY ***************************

; name: gameLoopRestore
; Control function to restore the appropriate player's data for a fresh round. 
; This is the entry point for restoring a player's game field from their previous round

.gameLoopRestore
     0x0804: CD [CF 01]  |   CAL 0x01CF                     ; draw boundary line
     0x0807: 3A [67 20]  |   LDA 0x2067                     ; which player?
     0x080a: 0F          |   RRC
     0x080b: DA [72 08]  |   JC 0x0872                      ; ... jump to restore player 1's bunkers

; name: _restorePlayer2
; This reads data from player 2's bunker into "live" game bunker struct

._restorePlayer2
     0x080e: CD [13 02]  |   CAL 0x0213                     ; update player 2's bunkers from ram
     0x0811: CD [CF 01]  |   CAL 0x01CF                     ; draw boundary line

; name: _restorePlayer
; runs for either player. This initializes the aliens by storing coordinates for both the origin and
; current aliens, by resetting the offsets in X and Y directions.
; This also sets the horizontal direction RAM variable at 0x200D

._restorePlayer
     0x0814: CD [B1 00]  |   CAL 0x00B1                     ; both players: initialize aliens

; name: _restoreInterruptProcessing
; Here we re-enable game processing during interrupts (it was previously blocked as aliens were re-initialized)
; Then we turn the game sound back on by setting bit 5 (which enabled the amp)

._restoreInterruptProcessing
     0x0817: CD [D1 19]  |   CAL 0x19D1                     ; enable ISR game processing
     0x081a: 06 [20]     |   MVI B, 0x20
     0x081c: CD [FA 18]  |   CAL 0x18FA                     ; add bit 5 to port 3 audio (turns sound back on)

; name: mainGameLoop
; This is the primary processing loop when in game mode.
; handling unfolds in the following order:
;    1. starts a shot if "fire" command is depressed (requires cooldown between shots)
;    2. begin the alien explosion if one hit. Also update alien offsets
;    3. update the invader count
;    4. none left? jump to handler for end-of-round and loop to gameLoopRestore (above)
;    5. lookup (in table) and restore time between invader shots 
;    6. if it's time, award player an extra life (at 1500 or 1000 points)
;    7. increase speed of invaders' shots if there are fewer than 9
;    8. turn off the player shot audio (this won't make a difference if already off)
;    9. check the player's health. 
;         ** if they're dying, turn on the player death audio, then continue processing
;         ** both healthy and unhealthy: if time, switch invader audio & reset countdown
;                                        play UFO audio if one is present and not hit by shot
;    10. jump back to the top of the main game loop

.mainGameLoop
     0x081f: CD [18 16]  |   CAL 0x1618                     ; playerFireHandler
     0x0822: CD [0A 19]  |   CAL 0x190A                     ; start alien explosion if necessary, update offsets
     0x0825: CD [F3 15]  |   CAL 0x15F3                     ; 0x2082 <- invader count, 0x206B <- 0x01 if down to 1
     0x0828: CD [88 09]  |   CAL 0x0988                     ; update player score and write to screen
     0x082b: 3A [82 20]  |   LDA 0x2082                     ; A <- remaining alien count
     0x082e: A7          |   ANA A
     0x082f: CA [EF 09]  |   JZ 0x09EF                      ; ... player wins! (handles, loops to gameLoopRestore)
     0x0832: CD [0E 17]  |   CAL 0x170E                     ; lookup & initialize time between invader shots
     0x0835: CD [35 09]  |   CAL 0x0935                     ; if conditions are met, award player an extra life
     0x0838: CD [D8 08]  |   CAL 0x08D8                     ; increase distance invaders' shots travel if count < 9
     0x083b: CD [2C 17]  |   CAL 0x172C                     ; turn off player shot audio
     0x083e: CD [59 0A]  |   CAL 0x0A59                     ; zero flag set for healthy player
     0x0841: CA [49 08]  |   JZ 0x0849                      ; ... jump if player is healthy

._unhealthyPlayer
     0x0844: 06 [04]     |   MVI B, 0x04
     0x0846: CD [FA 18]  |   CAL 0x18FA                     ; turn on player death audio (bit 2 -> port3)

._healthyPlayer
     0x0849: CD [75 17]  |   CAL 0x1775                     ; port 5: changes invader audio when flag (2095) set
                                                            ;    & resets audio countdown control from table (2097)
                                                            ; always turns off port 3 audio when time reached (2099)
     0x084c: D3 [06 CD]  |   OUT 0x06                       ; no impact on game
     0x084e: CD [04 18]  |   CAL 0x1804                     ; send out UFO audio if one is on screen and not hit
     0x0851: C3 [1F 08]  |   JMP 0x081F                     ; repeat main game loop

.__not_accessed__
     0x0854: 00          |   NOP
     0x0855: 00          |   NOP
     0x0856: 00          |   NOP

; ************************* WAIT-FOR-START LOOP: MULTI-PLAYER *****************************

; -----------------------------------------------------------------------
;
;    NOTE: wait-for-start functions are in two places
;          * umbrella and single-player procedures: 0x0765
;          * explicit multi-player procedures: 0x0857
;
;    This section of code is the explicitly two-player procedures
;
;    0x0857: prints "1 OR 2 PLAYERS BUTTON" and checks for either 1-player
;            or 2-player start button input
;    0x086D: two player start. Sets A to 0x01 & jumps into game loop
;
; ------------------------------------------------------------------------


; name: twoCreditPollStart
; this is the more-than-one-credit option within the wait-to-start loop. Here we print the message
; "1 OR 2 PLAYERS BUTTON" and poll for both _START2PLAYER and _START1PLAYER, in that order.
; directs code to either two-player start, one-player start, or continues the wait-for-start loop.

.twoCreditPollStart
     0x0857: 11 [BA 1A]  |   LXI D, 0x1ABA                  ; load pointer to '1 OR 2 PLAYERS BUTTON'
     0x085a: CD [F3 08]  |   CAL 0x08F3                     ; write message (no delay)
     0x085d: 06 [98]     |   MVI B, 0x98                    ; subtract 2 credits
     0x085f: DB [01]     |   IN 0x01                        ; read player controls
     0x0861: 0F          |   RRC                            ; check bit 1: _START2PLAYER
     0x0862: 0F          |   RRC
     0x0863: DA [6D 08]  |   JC 0x086D                      ; if 2-player start button is pressed, 2-player start
     0x0866: 0F          |   RRC                            ; check bit 2: _START1PLAYER
     0x0867: DA [98 07]  |   JC 0x0798                      ; if 1-player start button is pressed, 1-player start
     0x086a: C3 [7F 07]  |   JMP 0x077F                     ; otherwise jump 

; name: twoPlayerStart
; We will set A with 0x01, indicating that this will be at two-player game when it is stored in
; the RAM variable 0x20CE (indicates one or two players)

.twoPlayerStart
     0x086d: 3E [01]     |   MVI A, 0x01                    ; load 1 into A (will designate 2 players)
     0x086f: C3 [9B 07]  |   JMP 0x079B                     ; startNewGame (falls into game loop)

; ************************* GAME PROCESSING CONT. *****************************

; ----------------------------------------------------------------------------
;
;    **** NON-ISR GAME PROCESSING ****
;
;    NOTE: non-ISR game processing is in two locations. It begins up above
;    at 0x079B and continues through the main game loop.
;    It picks up here for player 1 reset/restore and game procedures
;
;    0x0872 - player 1: restore bunkers
;
; ------------------------------------------------------------------------------

; name: restorePlayer1
; Player 1 is live. This restores bunker data from player 1's buffer to the "live" bunker
; data structure in game RAM

.restorePlayer1
     0x0872: CD [1A 02]  |   CAL 0x021A                          ; update player 1's bunkers from ram
     0x0875: C3 [14 08]  |   JMP 0x0814                          ; continue initializing new player

; *********************** MISCELLANEOUS PROCEDURES & UTILITIES ********************

; ---------------------------------------------------------------------------------
;
;    **** MISCELLANEOUS GAME PROCEDURES & UTILITIES ****
;
;    0x0878 - puts origin alien data into registers
;    0x0886 - gets origin alien starting coordinates in HL
;    0x088D - print message: "PLAY PLAYER<1>"
;    0x0898 - overwrite the number with '2', initialize loop control for blinking
;    0x08A9 - loop for blinking current player's score. Lasts about 2.75 seconds
;    0x08D1 - reset the current player's "lives" using dipswitch input
;    0x08d8 - if fewer than 9 invaders, increase invader shot speed to -5 per cycle
;    0x08E4 - remove the second player's score from screen if 1-player game
;    0x08F1 - setup: write UFO score message (sets length)
;    0x08F3 - utility: write message, no delay
;    0x08FF - write single character sprite
;    0x0913 - trigger UFO countdown (called right after game processing in VBLANK)
;    0x092E - get the current player's remaining number of lives in A
;    0x0935 - when it's time, award player an extra life/ship sprite
;
;    0x09D6 - clear the game area in video memory
;    0x09EF - handle player win (also handles last-second player death)
;    0x0A59 - check player's health (sets zero flag if healthy)
;    0x0A5F - handle invader death
;              * game mode: explosion sound, setup for score update, points HL at sprite
;              * demo mode: points HL at explosion sprite only
;
; ---------------------------------------------------------------------------------------------

; name: originAlienToRegisters
; Puts the origin alien's data into registers

.originAlienToRegisters                                          ; puts x offset in a
                                                                 ; HL: origin alien starting coordinate buffer 
                                                                 ; DE: current origin alien coords
     0x0878: 3A [08 20]  |   LDA 0x2008                          ; load accumulator from 2008 (current X offset)
     0x087b: 47          |   MOV B, A                            ; save it in B
     0x087c: 2A [09 20]  |   LHLD 0x2009                         ; origin alien coordinates to HL
     0x087f: EB          |   XCHG                                ; ... move them to DE
     0x0880: C3 [86 08]  |   JMP 0x0886                          ; HL is the player's origin alien starting position


.__not_accessed__                                                ; not clear why this is here
     0x0883: 00          |   NOP
     0x0884: 00          |   NOP
     0x0885: 00          |   NOP

.getOriginAlienPtr
     0x0886: 3A [67 20]  |   LDA 0x2067                          ; current player-specific data MSB
     0x0889: 67          |   MOV H, A                            ; put pointer to player's
     0x088a: 2E [FC]     |   MVI L, 0xFC                         ; "origin alien" starting coords at xxFC
     0x088c: C9          |   RET

; name: setupPlayPlayer1
; sets up the registers to write the 'PLAY PLAYER<1> message to hte screen.
; prints it

.printPlayPlayer1
     0x088d: 21 [11 2B]  |   LXI H, 0x2B11                       ; screen coordinates
     0x0890: 11 [70 1B]  |   LXI D, 0x1B70                       ; address of message: 'PLAY PLAYER<1>
     0x0893: 0E [0E]     |   MVI C, 0x0E
     0x0895: CD [F3 08]  |   CAL 0x08F3                          ; print message to screen

; name: _overwritePlayPlayer2
; After writing 'PLAY PLAYER<1>' we check the current player. 
; If player 2, overwrite "2" over the "1" in the message
; Then initialize counter for 0xB0 ticks (about 2.75 seconds)

._overwritePlayPlayer2
     0x0898: 3A [67 20]  |   LDA 0x2067                          ; load player data address page
     0x089b: 0F          |   RRC                                 ; player 1 would set carry
     0x089c: 3E [1C]     |   MVI A, 0x1C
     0x089e: 21 [11 37]  |   LXI H, 0x3711                       ; screen coordinates
     0x08a1: D4 [FF 08]  |   CNC 0x08FF                          ; no carry? write "2" over 1 on plaay message
     0x08a4: 3E [B0]     |   MVI A, 0xB0
     0x08a6: 32 [C0 20]  |   STA 0x20C0                          ; initialize 0xb0-tick waiting loop

; name: _blinkScoreLoop
; Blink the current player's score total for 2.75 seconds

._blinkScoreLoop
     0x08a9: 3A [C0 20]  |   LDA 0x20C0
     0x08ac: A7          |   ANA A                               ; are we at zero?
     0x08ad: C8          |   RZ                                  ; return when we are
     0x08ae: E6 [04]     |   ANI 0x04                            ; otherwise, limit to bit 4
     0x08b0: C2 [BC 08]  |   JNZ 0x08BC                          ; when countdown bit 2 is set: clearScore ('blink')
     0x08b3: CD [CA 09]  |   CAL 0x09CA                          ; point to the current player's score
     0x08b6: CD [31 19]  |   CAL 0x1931                          ; loads registers with score -> write score
     0x08b9: C3 [A9 08]  |   JMP 0x08A9                          ; loop until waiting loop finishes

._clearScore
     0x08bc: 06 [20]     |   MVI B, 0x20
     0x08be: 21 [1C 27]  |   LXI H, 0x271C                       ; screen coordinates
     0x08c1: 3A [67 20]  |   LDA 0x2067
     0x08c4: 0F          |   RRC                                 ; which player?
     0x08c5: DA [CB 08]  |   JC 0x08CB                           ; 1-> skip loading screen coordinates
     0x08c8: 21 [1C 39]  |   LXI H, 0x391C                       ; screen coordinates
     0x08cb: CD [CB 14]  |   CAL 0x14CB                          ; clears previous score (length: 0x20)
     0x08ce: C3 [A9 08]  |   JMP 0x08A9                          ; back to top of blink loop

; name: resetLivesFromInput
; polls input port 2 for configuration provided by the arcade machine's dip switches (bits 0 and 1)
; and resets the number of player lives accordingly. You can see here that the following apply:
;
;              * 00 = 3 lives
;              * 01 = 4 lives
;              * 10 = 5 lives
;              * 11 = 6 lives

.resetLivesFromInput                                             ; resets the number of player lives
     0x08d1: DB [02]     |   IN 0x02                             ; check bits 1 and 2 of INPUT PORT 2
     0x08d3: E6 [03]     |   ANI 0x03
     0x08d5: C6 [03]     |   ADI 0x03                            ; add 3
     0x08d7: C9          |   RET                                 ; return

; name: setInvaderShotMotion
; if there are fewer than 9 invaders left, set the downward motion for the aliens' shot per cycle to -5. 

.setInvaderShotMotion
     0x08d8: 3A [82 20]  |   LDA 0x2082                          ; load current invader count                         
     0x08db: FE [09]     |   CPI 0x09                            ; is it less than 9?
     0x08dd: D0          |   RNC                                 ; ... nope! return
     0x08de: 3E [FB]     |   MVI A, 0xFB                         ; otherwise... fewer invaders than 9
     0x08e0: 32 [7E 20]  |   STA 0x207E                          ; store 0xFB at 207E (-5)
     0x08e3: C9          |   RET                                 ; this is the invader shot advance per cycle

; name: removePlayer2Score [PRE GAME LOOP PROCESSING]
; here we visually remove the player 2 score from the screen if there is only one player 

.removePlayer2Score
     0x08e4: 3A [CE 20]  |   LDA 0x20CE                          ; load number of players (0 = 1, 1 = 2)
     0x08e7: A7          |   ANA A
     0x08e8: C0          |   RNZ                                 ; if two players, return
     0x08e9: 21 [1C 39]  |   LXI H, 0x391C                       ; screen coordinates for player 2 score
     0x08ec: 06 [20]     |   MVI B, 0x20
     0x08ee: C3 [CB 14]  |   JMP 0x14CB                          ; clears line of length 32

; name: setupUFOMessage [UFO SUBROUTINE / ISR]
; Here we are writing the score for the UFO to the screen. The appropriate screen coordinates
; have already been loaded into HL

.setupUFOMessage
     0x08f1: 0E [03]     |   MVI C, 0x03                         ; sets loop control for UFO message

; name: writeMessageNoDelay
; writes the characters to the screen at the address coordinates given by HL
; ** HL must hold the actual RAM memory address here, 2400 - 3FFF
; ** DE must hold the starting point of the encoded message character indices in ROM

.writeMessageNoDelay
     0x08f3: 1A          |   LDAX D                         ; get character location
     0x08f4: D5          |   PUSH D
     0x08f5: CD [FF 08]  |   CAL 0x08FF                     ; get pointer to sprite
     0x08f8: D1          |   POP D                          ; restore character location
     0x08f9: 13          |   INX D                          ; and handle next letter
     0x08fa: 0D          |   DCR C
     0x08fb: C2 [F3 08]  |   JNZ 0x08F3                     ; ... and loop until message is done
     0x08fe: C9          |   RET

; name: getPointerToSprite
; 8-byte sprites for letters, numbers, and a few other symbols are stored in ROM starting at
; 0x1E00. Each sprite has an index, starting at 0, that can code the message. This procedure
; retrieves the index from the address pointer to ROM in DE and looks it up in the table
; of character art. 
; ** HL must hold the address in video memory where the character should be written.
; ** DE must originally hold the pointer to the encoded character index in ROM
; ** mutates DE to hold a pointer to the actual pixel art
; then jumps to actually write the pixel art into video memory

.getPointerToSprite     
     0x08ff: 11 [00 1E]  |   LXI D, 0x1E00                  ; beginning of character art in ROM
     0x0902: E5          |   PUSH H
     0x0903: 26 [00]     |   MVI H, 0x00
     0x0905: 6F          |   MOV L, A
     0x0906: 29          |   DAD H                          ; *=2
     0x0907: 29          |   DAD H                          ; *=2
     0x0908: 29          |   DAD H                          ; *=2
     0x0909: 19          |   DAD D                          ; use as offset 0x1E00
     0x090a: EB          |   XCHG                           ; DE <- HL, HL <- DE
     0x090b: E1          |   POP H                          ; restore HL
     0x090c: 06 [08]     |   MVI B, 0x08
     0x090e: D3 [06]     |   OUT 0x06                       ; signal out to port 6. no game impact
     0x0910: C3 [39 14]  |   JMP 0x1439                     ; write sprite (no shift) (returns)

; name: triggerUFOCountdown [VBLANK ISR]
; If the invaders have dropped at least once from their original position, countdown processing begins.
; Every 0x600 game cycles (1536 decimal), we launch a new UFO across the top. When it's time,
; this code sets the flag at 0x2083 and resets the 2-byte countdown at 0x2091 

.triggerUFOCountdown
     0x0913: 3A [09 20]  |   LDA 0x2009                     ; load origin alien's Y coordinate
     0x0916: FE [78]     |   CPI 0x78                       ; is it less than 0x78 (where origin alien starts)?
     0x0918: D0          |   RNC                            ; no. invaders have not moved yet. return.
     0x0919: 2A [91 20]  |   LHLD 0x2091                    ; ok. Load 16-bit countdown timer
     0x091c: 7D          |   MOV A, L                       ;    ... if set, either digit blocks new UFO
     0x091d: B4          |   ORA H                          ; 
     0x091e: C2 [29 09]  |   JNZ 0x0929                     ; either of these nonzero? No UFO.

._startUFOFlag
     0x0921: 21 [00 06]  |   LXI H, 0x0600                  ; reset timer to 0x600
     0x0924: 3E [01]     |   MVI A, 0x01                    ; set the "trigger UFO" flag
     0x0926: 32 [83 20]  |   STA 0x2083                     ; ... at 0x2083

._countdownToUFO
     0x0929: 2B          |   DCX H                          ; decrement HL (UFO countdown timer)
     0x092a: 22 [91 20]  |   SHLD 0x2091
     0x092d: C9          |   RET                            ; and return

; name: getCurrentLifeCount
; Gets the current player's number of remaining lives from the variable at 0x21FF (player 1)
; or 0x22FF (player 2)

.getCurrentLifeCount                                             ; get current ships: put the number of ships in A
     0x092e: CD [11 16]  |   CAL 0x1611                          ; get pointer to current player's data in HL
     0x0931: 2E [FF]     |   MVI L, 0xFF                         ;
     0x0933: 7E          |   MOV A, M                            ; grab the byte at either 21FF (player1) or 22FF
     0x0934: C9          |   RET

; name: awardExtraLife
; when the player has a sufficient number of points, and if a life hasn't already been awarded,
; award the player an extra life. This is called during the main game loop
; there are two possible points thresholds, which can be toggled based on dipswitch input
; via input port 2

.awardExtraLife
     0x0935: CD [10 19]  |   CAL 0x1910                          ; returns HL = 20E7 if p1, 20E8 if p2
     0x0938: 2B          |   DCX H
     0x0939: 2B          |   DCX H                               ; p1: point at 20E5, p2: point at 20E6
     0x093a: 7E          |   MOV A, M
     0x093b: A7          |   ANA A                               ; is the value 0? 
     0x093c: C8          |   RZ                                  ; ... return if so (extra ship not enabled) 
     0x093d: 06 [15]     |   MVI B, 0x15                         ; 
     0x093f: DB [02]     |   IN 0x02                             ; if it's set, look at INPUT PORT 2
     0x0941: E6 [08]     |   ANI 0x08                            ; if bit 3 is clear: B = 0x15
     0x0943: CA [48 09]  |   JZ 0x0948                           ; 
     0x0946: 06 [10]     |   MVI B, 0x10                         ; otherwise, B=0x10
     0x0948: CD [CA 09]  |   CAL 0x09CA                          ; point to the player's score
     0x094b: 23          |   INX H                               ; get MSB.
     0x094c: 7E          |   MOV A, M                            ; is it greater than B? (either 10 or 15)
     0x094d: B8          |   CMP B
     0x094e: D8          |   RC                                  ; ... no, return. We haven't reached the threshold
     0x094f: CD [2E 09]  |   CAL 0x092E                          ; otherwise, get pointer to current ship count
     0x0952: 34          |   INR M                               ; ... and increase it by 1
     0x0953: 7E          |   MOV A, M
     0x0954: F5          |   PUSH PSW                            ; push the count to the stack
     0x0955: 21 [01 25]  |   LXI H, 0x2501                       ; get coords for sprite: start at 2501 and add 0x0200
     0x0958: 24          |   INR H
     0x0959: 24          |   INR H
     0x095a: 3D          |   DCR A                               ; subtract 1 from ship count
     0x095b: C2 [58 09]  |   JNZ 0x0958                          ; if not yet zero, loop, adding 0x20 to H each time
     0x095e: 06 [10]     |   MVI B, 0x10
     0x0960: 11 [60 1C]  |   LXI D, 0x1C60                       ; point DE to player's sprite
     0x0963: CD [39 14]  |   CAL 0x1439                          ; write sprite of new player "life" here                         
     0x0966: F1          |   POP PSW                             ; get the new ship count again
     0x0967: 3C          |   INR A                               ; increase it by 1
     0x0968: CD [8B 1A]  |   CAL 0x1A8B                          ; write BCD of remaining player lives
     0x096b: CD [10 19]  |   CAL 0x1910                          ; returns HL = 20E7 if p1, 20E8 if p2
     0x096e: 2B          |   DCX H
     0x096f: 2B          |   DCX H                               ; decrease to 20E5 or 20E6
     0x0970: 36 [00]     |   MVI M, 0x00                         ; ... and disable adding extra ship for player
     0x0972: 3E [FF]     |   MVI A, 0xFF
     0x0974: 32 [99 20]  |   STA 0x2099                          ; and put 0xFF at 0x2099 (hold sound timer)
     0x0977: 06 [10]     |   MVI B, 0x10                         ; set bit 4 in B
     0x0979: C3 [FA 18]  |   JMP 0x18FA                          ; sound out port 3 (2094 |= B --> out). New ship added!

; -------------------------------------------------------
;
; *** UPDATE PLAYER SCORE SUBROUTINE  ***
;
;    0x097C - get score for dying invader (look up in table by alien row)
;    0x0988 - update the player's score if flag at 0x20F1 indicates it's needed
;    0x09AD - write the player's 4-digit score to screen pointer in HL
;    0x09C5 - write single binary-coded decimal digit (in A) to screen (calls 0x08FF)
;    0x09CA - prints to the score data structure in RAM for current player
;
; --------------------------------------------------------

; name: alienRowToScore
; look up the shot alien's score in a table, based on its row in the grid. This is called
; during the handleInvaderDeath routine

.alienRowToScore                                                 ; look up correct points for alien (HL is pointer)
     0x097c: 21 [A0 1D]  |   LXI H, 0x1DA0                       ; point HL at 1DA0 (10)
     0x097f: FE [02]     |   CPI 0x02                            ; is A (alien row) less than 2?
     0x0981: D8          |   RC                                  ; return if so
     0x0982: 23          |   INX H                               ; otherwise point to 1DA1 (20)
     0x0983: FE [04]     |   CPI 0x04                            ; is alien row less than 4?
     0x0985: D8          |   RC                                  ; return if so
     0x0986: 23          |   INX H                               ; otherwise point to 1DA2 (30) for row 4
     0x0987: C9          |   RET                                 ; and return

; name: updateScore
; Here we update the player's score as needed, based on whether the "update score" flag was set at 0x20F1
; Use binary-coded decimal to add the value at 0x20F2 to the current player's score
; then jumps down to write the score to the screen

.updateScore
     0x0988: CD [CA 09]  |   CAL 0x09CA                          ; point to player's score
     0x098b: 3A [F1 20]  |   LDA 0x20F1                          ; load score update needed flag
     0x098e: A7          |   ANA A
     0x098f: C8          |   RZ                                  ; no score update? return
     0x0990: AF          |   XRA A                               ; 
     0x0991: 32 [F1 20]  |   STA 0x20F1                          ; otherwise clear the score needed flag
     0x0994: E5          |   PUSH H                              ; put the player's score pointer on the stack
     0x0995: 2A [F2 20]  |   LHLD 0x20F2                         ; and grab two bytes at 0x20F2
     0x0998: EB          |   XCHG                                ; ... put them in DE
     0x0999: E1          |   POP H                               ; ... and recover the score pointer
     0x099a: 7E          |   MOV A, M                            ; get the previous LSB of score
     0x099b: 83          |   ADD E                               ; add the new score
     0x099c: 27          |   DAA                                 ; (adjust for binary-coded decimal)
     0x099d: 77          |   MOV M, A                            ; and put it back in memory
     0x099e: 5F          |   MOV E, A                            ; as well as back into E
     0x099f: 23          |   INX H                               ; grab the byte after player's score
     0x09a0: 7E          |   MOV A, M                            ; get the previous MSB of score
     0x09a1: 8A          |   ADC D                               ; add with carry
     0x09a2: 27          |   DAA                                 ; (and adjust for binary coded decimal)
     0x09a3: 77          |   MOV M, A                            ; put back into memory
     0x09a4: 57          |   MOV D, A                            ; and into D
     0x09a5: 23          |   INX H                               ; to next memory location...
     0x09a6: 7E          |   MOV A, M                           
     0x09a7: 23          |   INX H                            
     0x09a8: 66          |   MOV H, M                            ; screen pointer MSB to H
     0x09a9: 6F          |   MOV L, A                            ; screen pointer LSB to L
     0x09aa: C3 [AD 09]  |   JMP 0x09AD                          ; jump to writeUpdatedScore

; name: writeUpdatedScore
; This writes the 4-digit binary-coded-decimal score in DE to the screen coordinates in HL
; ** HL should be loaded with screen coordinates
; ** DE should be loaded with actual score in binary coded decimal
; we first call 'displayBCDNums' for digit 1 and 1, then fall into the same 
; function for digits 3 and 4

.writeUpdatedScore
     0x09ad: 7A          |   MOV A, D                       ; put higher bytes in A
     0x09ae: CD [B2 09]  |   CAL 0x09B2                     ; displayBCDNums
     0x09b1: 7B          |   MOV A, E                       ; lower byte in A (and fall into displayBCDNums)

; name: _displayBCDNums
; writes sprites for the two BCD nums in A to the screen

._displayBCDNums
     0x09b2: D5          |   PUSH D                         ; push D on stack
     0x09b3: F5          |   PUSH PSW                       ; store A on stack
     0x09b4: 0F          |   RRC                            ; move upper nibble into lower nibble
     0x09b5: 0F          |   RRC
     0x09b6: 0F          |   RRC
     0x09b7: 0F          |   RRC
     0x09b8: E6          |   ANI 0x0F                       ; mask other part of byte
     0x09ba: CD [C5 09]  |   CAL 0x09C5                     ; write digit
     0x09bd: F1          |   POP PSW                        ; restore A
     0x09be: E6 [0F]     |   ANI 0x0F                       ; mask out all but original lower nibble
     0x09c0: CD [C5 09]  |   CAL 0x09C5                     ; write digit
     0x09c3: D1          |   POP D                          ; restore D
     0x09c4: C9          |   RET                            ; and return

; name: setupWriteBCDNum
; adds 0x1A to move pointer into the part of 8bit-square sprite array that holds symbols for
; binary digits 1-9. This can be used to print the score, or other decimal numeric values

.setupWriteBCDNum                                           ; add offset for numeric sprites 0-9
     0x09c5: C6 [1A]     |   ADI 0x1A
     0x09c7: C3 [FF 08]  |   JMP 0x08FF                     ; get pointer to sprite -> write sprite -> returns

; name: pointToPlayerScore
; point to the score data structure for current player

.pointToPlayerScore
     0x09ca: 3A [67 20]  |   LDA 0x2067                     ; which player?
     0x09cd: 0F          |   RRC
     0x09ce: 21 [F8 20]  |   LXI H, 0x20F8                  ; point HL at 0x20F8 (PLAYER 1 SCORE)
     0x09d1: D8          |   RC                             ; if player 1, return
     0x09d2: 21 [FC 20]  |   LXI H, 0x20FC                  ; player 2: point HL at 0x20FC (PLAYER 2 SCORE)
     0x09d5: C9          |   RET

; name: clearPlayArea
; clears video memory 2402-4000 except bottom 2 bytes (00, 01) and top 4 bytes
; (1C, 1D, 1E, 1F). Because we are comparing to "1C" the skip only happens at
; the top of the screen.

.clearPlayArea                                                   
     0x09d6: 21 [02 24]  |   LXI H, 0x2402                  ; load start coords
     0x09d9: 36 [00]     |   MVI M, 0x00                    
     0x09db: 23          |   INX H                          
     0x09dc: 7D          |   MOV A, L                       
     0x09dd: E6 [1F]     |   ANI 0x1F                       
     0x09df: FE [1C]     |   CPI 0x1C                       ; jump if A < 1C
     0x09e1: DA [E8 09]  |   JC 0x09E8
     0x09e4: 11 [06 00]  |   LXI D, 0x0006                  ; otherwise add 6
     0x09e7: 19          |   DAD D
     0x09e8: 7C          |   MOV A, H
     0x09e9: FE [40]     |   CPI 0x40                       ; A < 0x40?
     0x09eb: DA [D9 09]  |   JC 0x09D9                      ; loop if A < 40
     0x09ee: C9          |   RET

; name: handlePlayerWins
; This handler is called by the main game loop when all the invaders have been killed
; This method:
;    1. pauses for 30 ticks unless player dies
;    2. Then disables interrupt game processing
;    3. clears the game area
;    4. saves the player's data page on the stack
;    5. resets limited RAM from ROM (0x2000 to 0x20BF)
;    6. restores player's data page and re-saves it in RAM
;    7. increase byte at 0x__FE (current player's levels defeated)
;       value could increase from 1 to 8, then loops
;    8. look up starting x-coordinate for invaders based on levels won
;    9. put the starting origin alien coordinates in xxFC and xxFD
;    10. check player and reset bunker buffers / invaders for current player
;        (also for player 2 set port 5 bit 5 to flip cocktail table visuals)
;    11. jump into reset and rejoin game loop

.handlePlayerWins
     0x09ef: CD [3C 0A]  |   CAL 0x0A3C                          ; 30-tick pause unless player dies
                                                                 ;    ... player death triggers loop until ISR 
                                                                 ;    ... resets player health
     0x09f2: AF          |   XRA A
     0x09f3: 32 [E9 20]  |   STA 0x20E9                          ; disable ISR game processing
     0x09f6: CD [D6 09]  |   CAL 0x09D6                          ; clear the game area
     0x09f9: 3A [67 20]  |   LDA 0x2067                          ; A <- player data page
     0x09fc: F5          |   PUSH PSW                            ; ... save on stack
     0x09fd: CD [E4 01]  |   CAL 0x01E4                          ; reset ram 2000 - 20C0 ONLY
     0x0a00: F1          |   POP PSW                             ; restore A
     0x0a01: 32 [67 20]  |   STA 0x2067                          ; restore current player data page
     0x0a04: 3A [67 20]  |   LDA 0x2067
     0x0a07: 67          |   MOV H, A
     0x0a08: E5          |   PUSH H                              ; push player data page to stack
     0x0a09: 2E [FE]     |   MVI L, 0xFE                         ; put FE in L
     0x0a0b: 7E          |   MOV A, M                            ; and put xxFE byte into A
     0x0a0c: E6 [07]     |   ANI 0x07                            ; mask bottom 3 bits
     0x0a0e: 3C          |   INR A                               ; and increase by 1
     0x0a0f: 77          |   MOV M, A
     0x0a10: 21 [A2 1D]  |   LXI H, 0x1DA2                       ; point HL at 0x1DA2
     0x0a13: 23          |   INX H                               ; ... and increment forward by 1 for every level won
     0x0a14: 3D          |   DCR A                               ; ... lookup starting Y coordinate for invaders
     0x0a15: C2 [13 0A]  |   JNZ 0x0A13                          ; ... by looping 
     0x0a18: 7E          |   MOV A, M                            ; put the value in A
     0x0a19: E1          |   POP H
     0x0a1a: 2E [FC]     |   MVI L, 0xFC                         ; point HL to xxFC
     0x0a1c: 77          |   MOV M, A                            ; set origin alien position Y (1AD2 + levels_won)
     0x0a1d: 23          |   INX H
     0x0a1e: 36 [38]     |   MVI M, 0x38                         ; reset origin alien position X = 0x38
     0x0a20: 7C          |   MOV A, H                            ; and put player page into A
     0x0a21: 0F          |   RRC                                 ; ... and check which player.
     0x0a22: DA [33 0A]  |   JC 0x0A33                           ; ... ... handle player 1

._player2Reset
     0x0a25: 3E [21]     |   MVI A, 0x21                         ; 
     0x0a27: 32 [98 20]  |   STA 0x2098                          ; put 0x21 in port 5 audio buffer
     0x0a2a: CD [F5 01]  |   CAL 0x01F5                          ; reset bunkers in player 2's buffer
     0x0a2d: CD [04 19]  |   CAL 0x1904                          ; reset player 2's invaders array
     0x0a30: C3 [04 08]  |   JMP 0x0804

._player1Reset
     0x0a33: CD [EF 01]  |   CAL 0x01EF                          ; reset bunkers in player 1's buffer
     0x0a36: CD [C0 01]  |   CAL 0x01C0                          ; reset "live" invaders array to 1s
     0x0a39: C3 [04 08]  |   JMP 0x0804

; name: _pause30IfHealthy
; stops for 30-ticks (about 0.75 seconds) to allow ISR to process player that was hit
; before end of game.

._pause30IfHealthy
     0x0a3c: CD [59 0A]  |   CAL 0x0A59                          ; check player health (0 is healthy)
     0x0a3f: C2 [52 0A]  |   JNZ 0x0A52                          ; ... was player hit? jump (returns)
     0x0a42: 3E [30]     |   MVI A, 0x30                         ; otherwise... 
     0x0a44: 32 [C0 20]  |   STA 0x20C0                          
     0x0a47: 3A [C0 20]  |   LDA 0x20C0                          ; 30-tick pause...
     0x0a4a: A7          |   ANA A                               ; ... 0x20C0 decremented by ISR
     0x0a4b: C8          |   RZ                                  ; ... return when we're done
     0x0a4c: CD [59 0A]  |   CAL 0x0A59                          ; ... as long as player stays healthy
     0x0a4f: CA [47 0A]  |   JZ 0x0A47                           ; ... (player death breaks loop)

; name: _handlePlayerDeath
; if player has been killed during final seconds of round, this holds processing here
; until ISR has finished handling the death. This needs to be finished before we turn
; off ISR processing.

._handlePlayerDeath
     0x0a52: CD [59 0A]  |   CAL 0x0A59                               ; loop here while ISR
     0x0a55: C2 [52 0A]  |   JNZ 0x0A52                               ; ... handles player death
     0x0a58: C9          |   RET                                      ; ... and return

; name: checkPlayerHealth
; Looks at 0x2015 (player's health). This should be 0xFF when healthy and 0x00 when not healthy.
; If healthy: a zero flag will be set.

.checkPlayerHealth                                                    ; zero flag set for healthy player
     0x0a59: 3A [15 20]  |   LDA 0x2015                               ; check player status
     0x0a5c: FE [FF]     |   CPI 0xFF                                 ; against 0xFF (player not shot)
     0x0a5e: C9          |   RET                                      ; return

; name: handleInvaderDeath
;
; in game mode, this function handles the explosion sound, setting points to add, flagging
; that score should be updated, and pointing HL at the explosion sprite
;
; In demo mode, this simply points HL at the explosion sprite in variable 0x2062 and returns.

.handleInvaderDeath
     0x0a5f: 3A [EF 20]  |   LDA 0x20EF                               ; game mode (1) or splash (0)
     0x0a62: A7          |   ANA A                                    ;    if clear...
     0x0a63: CA [7C 0A]  |   JZ 0x0A7C                                ;    ... we are in the demo so skip ahead

._alienDeath_gameOnly
     0x0a66: 48          |   MOV C, B                                 ; hold B (row number)
     0x0a67: 06 [08]     |   MVI B, 0x08                              ; put 8 into B...
     0x0a69: CD [FA 18]  |   CAL 0x18FA                               ; ... and send out explosion sound
     0x0a6c: 41          |   MOV B, C                                 ; restore B
     0x0a6d: 78          |   MOV A, B
     0x0a6e: CD [7C 09]  |   CAL 0x097C                               ; HL now points to correct score
     0x0a71: 7E          |   MOV A, M                                 ; grab it
     0x0a72: 21 [F3 20]  |   LXI H, 0x20F3                            ; clear 0x20F3
     0x0a75: 36 [00]     |   MVI M, 0x00                              ; put 00 in 20F3
     0x0a77: 2B          |   DCX H                                    ; then get pointer to 20F2
     0x0a78: 77          |   MOV M, A                                 ; and set score update amount (0x20F2)
     0x0a79: 2B          |   DCX H                                    ; move pointer to 20F1
     0x0a7a: 36 [01]     |   MVI M, 0x01                              ; .... and set it to 0x01 (score update needed)

._alienDeath_bothModes                                                ; we pick up here for the demo
     0x0a7c: 21 [62 20]  |   LXI H, 0x2062                            ; point HL at 2062 (explosion sprite pointer)
     0x0a7f: C9          |   RET                                      ; and return

; ******************** SPLASH METHODS **************************

; ------------------------------------------------------------------------
;
; **** SPLASH METHODS ****
;
;    0x0A80 - busy-wait for ISR (until 0x20CB marks animation complete)
;    0x0A93 - write message with 7-interrupt delay between characters
;    0x0AAB - setup for ISR processing during "invader shoots C" animation
;             (sets game parsing entry to 0x2050, the zigzag shot/UFO object)
;    0x0AB1 - one second pause loop; controlled by variable that decrements
;             only during VBLANK ISR
;    0x0AB6 - two-second pause loop; controlled by variable that decrements
;             only during VBLANK ISR
;    0x0ABB - utility pop H / jump into VBLANK game processing
;    0x0ABF - splash processing gateway (VBLANK ISR)
;    0x0ACF - writes "SPACE INVADERS" message to splash screen
;    0x0AD7 - utility pause loop controlled by 0x20C0 in RAM. Used for the
;             one-second and two-second pauses above
;    0x0AE2 - loads the splash animation data structure from ROM address (in DE)
;    0x0AEA - top of the splash sequence loop. There are two "paths" through the 
;             loop controlled by a toggle. 
;    0x0B0B - high-level splash loop control. calls functions to print "PLAY
;             "SPACE INVADERS" and print the score-advance table, check toggle
;    0x0B1E - animation to replace upside-down Y 1: invader in from right
;    0x0B27 - animation to replace upside-down Y 2: invader drags wrong 'Y' out
;    0x0B33 - animation to replace upside-down Y 3: invader brings in right 'Y'
;    0x0B3F - remove invader and pause two seconds
;    0x0B4A - beginning of demo (calls function to clear game area)
;    0x0B4D - reset lives / player 1
;    0x0B5d - reset player 1's bunker buffer and aliens, clear game area again
;    0x0B69 - set 0x20C1 to 1 for demo processing, draw line across screen
;    0x0B71 - demo loop
;    0x0B89 - "INSERT COIN" splash screen with or without coin info
;              * 0x0BBD - coin info
;              * 0x0BC3 - no coin info
;    0x0BCE - animation where alien shoots extra "C" (0x189E handles shot animation)
;    0x0BDA - flip toggle & restart splash
;    0x0BE8 - write message: "PLAY" with normal 'Y'
;    0x0Bf1 - handles demo-time movement of invaders
;
; -------------------------------------------------------------------------

; name: busyWaitForISR
; This enters an infinite loop that is exited only when the splash animation flag 
; is set, which marks an animation sequence "complete"
; actual processing of the animation is completed by code that fires during
; interrupts.

.busyWaitForISR
     0x0a80: 3E [02]     |   MVI A, 0x02
     0x0a82: 32 [C1 20]  |   STA 0x20C1                          ; set splash index to 2
._waitUntilNonZero
     0x0a85: D3 [06]     |   OUT 0x06                            ; no game impact
     0x0a87: 3A [CB 20]  |   LDA 0x20CB                          ; load animation complete flag
     0x0a8a: A7          |   ANA A                               ; ... is it set?
     0x0a8b: CA [85 0A]  |   JZ 0x0A85                           ; ... loop until it is
     0x0a8e: AF          |   XRA A
     0x0a8f: 32 [C1 20]  |   STA 0x20C1                          ; clear animation processing type
     0x0a92: C9          |   RET                                 ; ... and return

; name: writeMessageWithDelay
; Writes a message to the screen at coordinates in HL. DE should point to the
; character sequence. This uses the pauseLoop to wait 6 interrupts between each
; character, creating a slight animation when the message appears.

.writeMessageWithDelay
     0x0a93: D5          |   PUSH D                              ; save D
     0x0a94: 1A          |   LDAX D                              ; load A from DE
     0x0a95: CD [FF 08]  |   CAL 0x08FF                          ; write single character to screen
     0x0a98: D1          |   POP D                               ; restore D
     0x0a99: 3E [07]     |   MVI A, 0x07                         ; put 0x07 into A
     0x0a9b: 32 [C0 20]  |   STA 0x20C0                          ; store it in 0x20C0 (loop control for delay)
     0x0a9e: 3A [C0 20]  |   LDA 0x20C0                          ; short delay loop while ISR
     0x0aa1: 3D          |   DCR A                               ; ... is A 1? (decrements 0x20C0 at VBLANK)
     0x0aa2: C2 [9E 0A]  |   JNZ 0x0A9E                          ; ... inner loop
     0x0aa5: 13          |   INX D
     0x0aa6: 0D          |   DCR C
     0x0aa7: C2 [93 0A]  |   JNZ 0x0A93                          ; outer loop: finish message
     0x0aaa: C9          |   RET

; name: splashShootC
; this is called for ISR processing of the zigzag shot during splash animation when the
; invader shoots an extra 'C' in 'CCOIN'

.splashShootC
     0x0aab: 21 [50 20]  |   LXI H, 0x2050                       ; start processing loop at zigzag shot
     0x0aae: C3 [4B 02]  |   JMP 0x024B                          ; jump to game processing

; name: oneSecondDelay
; initializes and then jumps to a 0x40-tick pause. The wait is an infinite loop that 
; works as intended only when interrupts are on, as the control variable at 0x20C0 
; is decremented during VBLANK. Assuming 60 (decimal) hz screen refresh, 
; 0x40 = 64d = approximately 1 second.

.oneSecondDelay
     0x0ab1: 3E [40]     |   MVI A, 0x40                    ; countdown happens during ISRs
     0x0ab3: C3 [D7 0A]  |   JMP 0x0AD7                     ; jump to wait loop. returns.

; name: twoSecondDelay
; initializes and then jumps to an 80-tick pause. The wait is an infinite loop that
; works as intended only when interrupts are on, as the control variable at 0x20C0
; is decremented during VBLANK. Assuming 60 (decimal) hz screen refresh, 
; 0x80 = 120d = approximately 2 seconds

.twoSecondDelay
     0x0ab6: 3E [80]     |   MVI A, 0x80                    ; countdown happens during ISRs (at VBLANK)
     0x0ab8: C3 [D7 0A]  |   JMP 0x0AD7                     ; jump to wait loop. returns when done

._utilityPopH
     0x0abb: E1          |   POP H
     0x0abc: C3 [72 00]  |   JMP 0x0072                     ; jump into vblank game processing

; **********************************************
;
;        * SPLASH SEQUENCE PROCESSING *
;
; **********************************************

; name: processSplash [VBLANK ISR]
; reroutes processing depending on the setting of the splash sequence variable (0x20C1)
;    ** 0 (clear) - set at the top of the splash loop. No ISR processing.
;    ** 1 (bit 0) - set for the game demo. The most ISR processing afforded to a splash module.
;    ** 2 (bit 1) - ISR processing to animate a sprite
;    ** 4 (bit 2) - ISR processing to animate an invader's shot (used to shoot extra 'C')

.processSplash
     0x0abf: 3A [C1 20]  |   LDA 0x20C1                          ; where are we in splash sequence?
     0x0ac2: 0F          |   RRC                                 ; 1? (game demo)               
     0x0ac3: DA [BB 0A]  |   JC 0x0ABB                           ; pop H & jump into VBLANK game processing
     0x0ac6: 0F          |   RRC                                 ; 2? (splash animation)
     0x0ac7: DA [68 18]  |   JC 0x1868                           ; ...move sprite
     0x0aca: 0F          |   RRC                                 ; 4? (splash animation involving alien shot)
     0x0acb: DA [AB 0A]  |   JC 0x0AAB                           ; ...into the parse structs loop at 0x2050
     0x0ace: C9          |   RET                                 ;    [zigzag shot]... and return

; name: writeMessage_spaceInvaders
; writes the message "SPACE INVADERS" to the screen. A pointer to the character sequence
; must already be in DE. This jumps to code that actually writes the sprites, including
; a slight 7-screen-refresh delay between characters.

.writeMessage_spaceInvaders
     0x0acf: 21 [14 2B]  |   LXI H, 0x2B14                       ; point HL to 2B14 in visual memory
     0x0ad2: 0E [0F]     |   MVI C, 0x0F                         ; set length of message
     0x0ad4: C3 [93 0A]  |   JMP 0x0A93                          ; writeMessageWithDelay

; name: pauseLoop
; An otherwise-infinite loop that is controlled when VBLANK decrements the variable
; value in 0x20C0. This occurs at the top of each VBLANK interrupt.
; the loop waits for the number of VBLANK interrupts in A (VBLANK runs at ~60hz)

.pauseLoop
     0x0ad7: 32 [C0 20]  |   STA 0x20C0                          ; update loop control from A
     0x0ada: 3A [C0 20]  |   LDA 0x20C0                          ; load loop control
     0x0add: A7          |   ANA A
     0x0ade: C2 [DA 0A]  |   JNZ 0x0ADA                          ; loop
     0x0ae1: C9          |   RET

; name: resetSplashObject
; Reloads the 12-byte "live" animation data buffer from a ROM address in DE

.resetSplashObject
     0x0ae2: 21 [C2 20]  |   LXI H, 0x20C2                       ; point HL at 0x20C2
     0x0ae5: 06 [0C]     |   MVI B, 0x0C                         ; 12 bytes
     0x0ae7: C3 [32 1A]  |   JMP 0x1A32                          ; romToRamCopy, returns

; name: startSplashSequence
; Top of the splash loop starts here. Both audio ports are silenced.
; This turns off audio, and switches between:
;     * (if 20EC splash toggle is 0) "PLAY (upside-down Y)" is printed
;     * (if 20EC splash toggle is nonzero) "PLAY (correct Y)" is printed
; this then either jumps or falls into code that prints " SPACE INVADERS" and continues
;    ** note that 0x20EC is initialized as 1, so no animations first time through

.startSplashSequence
     0x0aea: AF          |   XRA A
     0x0aeb: D3 [03]     |   OUT 0x03                            ; turn off port 3 audio
     0x0aed: D3 [05]     |   OUT 0x05                            ; turn off port 5 audio
     0x0aef: CD [82 19]  |   CAL 0x1982                          ; clear splash processing
     0x0af2: FB          |   EI                                  ; enable interrupts (init complete)
     0x0af3: CD [B1 0A]  |   CAL 0x0AB1                          ; pause one second
     0x0af6: 3A [EC 20]  |   LDA 0x20EC                          ; check splash toggle
     0x0af9: A7          |   ANA A                               ; 
     0x0afa: 21 [17 30]  |   LXI H, 0x3017                       ; load position in video memory
     0x0afd: 0E [04]     |   MVI C, 0x04                         ; message length
     0x0aff: C2 [E8 0B]  |   JNZ 0x0BE8                          ;    if 20EC == 1: "PLAY" 
     0x0b02: 11 [FA 1C]  |   LXI D, 0x1CFA                       ; else: "PLA [upside down y]"
     0x0b05: CD [93 0A]  |   CAL 0x0A93                          ; writeMessageWithDelay
     0x0b08: 11 [AF 1D]  |   LXI D, 0x1DAF                       ; start of "SPACE INVADERS"

; name: splashScreen_messageAndTable
; this picks up after "PLAY" with correct Y has been written and continues to write
; messages to the screen, including the remainder of "SPACE INVADERS" and the 
; 'score-advance' table

.splashScreen_messageAndTable
     0x0b0b: CD [CF 0A]  |   CAL 0x0ACF                          ; writeMessage_spaceInvaders
     0x0b0e: CD [B1 0A]  |   CAL 0x0AB1                          ; wait one second
     0x0b11: CD [15 18]  |   CAL 0x1815                          ; print the score advance table
     0x0b14: CD [B6 0A]  |   CAL 0x0AB6                          ; 80-tick wait loop
     0x0b17: 3A [EC 20]  |   LDA 0x20EC                          ; load 20EC
     0x0b1a: A7          |   ANA A                               ;    
     0x0b1b: C2 [4A 0B]  |   JNZ 0x0B4A                          ; ... if splash toggle is nonzero ...

; name: _splashAnimation_1A95
; This loads data for the first step of animation in which an alien replaces the upside-down Y
; this copies the 12 bytes at 0x1A95 and puts them into the animation struct in memory 
; starting at 20C2. The code sets 0x20C1 to 2, which turns on ISR processing sufficient to
; animate a sprite. 
; here we are moving an invader from 0x3F17 to 0x3317 in converted coordinates.
; encoded screen starting coords are: 0xFEB8. 
; encoded x-direction target is 0x9E (so 9EB8 final)
; x-direction step is FF (-1). y-direction step is: 00

._splashAnimation_1A95
     0x0b1e: 11 [95 1A]  |   LXI D, 0x1A95                       ; DE <- 1a95
     0x0b21: CD [E2 0A]  |   CAL 0x0AE2                          ; reset splash sequence (12d bytes romToRamCopy at 20C2)
     0x0b24: CD [80 0A]  |   CAL 0x0A80                          ; set 0x20C1 to 2 and loop for ISR animation

; name: _splashAnimation_1BB0
; This loads the data for movement of invader dragging wrong-"Y" to the right edge
; converted screen coordinates are 0x3317 -> 0x3F17

._splashAnimation_1BB0
     0x0b27: 11 [B0 1B]  |   LXI D, 0x1BB0                       ; DE <- 1BB0
     0x0b2a: CD [E2 0A]  |   CAL 0x0AE2                          ; reset splash sequence (12d bytes romToRamCopy at 20C2)
     0x0b2d: CD [80 0A]  |   CAL 0x0A80                          ; set 0x20C1 to 2 and loop for ISR animation
     0x0b30: CD [B1 0A]  |   CAL 0x0AB1                          ; one second pause

; name: _splashAnimation_1FC9
; this loads data for the invader with the correct "Y" from the right edge
; to the middle of the screen

._splashAnimation_1FC9
     0x0b33: 11 [C9 1F]  |   LXI D, 0x1FC9                       ; point DE at 1FC9
     0x0b36: CD [E2 0A]  |   CAL 0x0AE2                          ; reset splash sequence (12d bytes romToRamCopy at 20C2)
     0x0b39: CD [80 0A]  |   CAL 0x0A80                          ; set 0x20C1 to 2 and loop for ISR animation
     0x0b3c: CD [B1 0A]  |   CAL 0x0AB1                          ; one second pause

; name: _removeSplashInvader
; this animation removes the invader who has now successfully replaced the "Y"

._removeSplashInvader
     0x0b3f: 21 [B7 33]  |   LXI H, 0x33B7                       ; points to screen coordinates
     0x0b42: 06 [0A]     |   MVI B, 0x0A
     0x0b44: CD [CB 14]  |   CAL 0x14CB                          ; clear a single byte high x 0x0A long
     0x0b47: CD [B6 0A]  |   CAL 0x0AB6                          ; two-second delay

; name: splashDemo
; this launches the game demo portion of the splash sequence.

.splashDemo     
     0x0b4a: CD [D6 09]  |   CAL 0x09D6                     ; clear the game area

; name: resetLivesPlayer1
; This checks to see if a player has run out of "lives." If the player hasn't, it calls 0x0B5D
; which begins the process of resetting for the same player. 
; Otherwise, it completely resets the number of lives from input port 2
; This would have captured input from the arcade machine's dipswitch settings

._resetLivesPlayer1
     0x0b4d: 3A [FF 21]  |   LDA 0x21FF                     ; load player 1's count of remaining lives
     0x0b50: A7          |   ANA A                          ; if it's zero...
     0x0b51: C2 [5D 0B]  |   JNZ 0x0B5D
     0x0b54: CD [D1 08]  |   CAL 0x08D1                     ; resets number of player lives from Port 2
     0x0b57: 32 [FF 21]  |   STA 0x21FF                     ; store reset number back in 21FF
     0x0b5a: CD [7F 1A]  |   CAL 0x1A7F                     ; writes remaining player sprites/ count

; name: _resetBunkersPlayer1
; Restores RAM from ROM between 0x2000 and 0x20C0. This effectively resets the game structures
; only, without touching animation or splash-sequence data or player-specific game data (including scores) 

._resetBunkersPlayer1
     0x0b5d: CD [E4 01]  |   CAL 0x01E4                          ; reset ram 2000 - 20C0 ONLY
     0x0b60: CD [C0 01]  |   CAL 0x01C0                          ; reset "live" invaders array to 1s
     0x0b63: CD [EF 01]  |   CAL 0x01EF                          ; draw new bunkers to player 1's buffer
     0x0b66: CD [1A 02]  |   CAL 0x021A                          ; update the bunkers from player 1's buffer

; name: _startDemo
; initializes the demo by setting 0x20C1 to 1 (which allows more extensive ISR demo-mode processing)
; This is also where the horizontal line at the bottom of the screen is drawn

._startDemo
     0x0b69: 3E [01]     |   MVI A, 0x01
     0x0b6b: 32 [C1 20]  |   STA 0x20C1                          ; set splash sequence game processing to 1 (demo)
     0x0b6e: CD [CF 01]  |   CAL 0x01CF                          ; draw 1-pixel line cross bottom of screen

; name: _demoLoop
; this is the main loop that handles the splash screen demo. It begins by firing a shot and populating
; the next demo instruction code. It then calls a handler for side-to-side movement, triggering an explosion,
; and watching for the splash-screen-only "TAITO COP" hidden message
; It then writes out to port 6, which has no game impact.
; Finally, it checks player health and loops until the player is not healthy (it is shot at end of the demo)
; and then loops until ISR completes the player death animation, ending this portion of the splash sequence.

._demoLoop
     0x0b71: CD [18 16]  |   CAL 0x1618                          ; fire shot, next demo instruction in 0x201D
     0x0b74: CD [F1 0B]  |   CAL 0x0BF1                          ; handle side-to-side invader movement
                                                                 ; triggers invader explosion, also secret message
     0x0b77: D3 [06]     |   OUT 0x06                            ; output port 6 -- no game impact
     0x0b79: CD [59 0A]  |   CAL 0x0A59                          ; check player health (zero flag for healthy)
     0x0b7c: CA [71 0B]  |   JZ 0x0B71                           ; player is healthy, loop demo instructions
     0x0b7f: AF          |   XRA A
     0x0b80: 32 [25 20]  |   STA 0x2025                          ; set 0 in 2025 (player not shot)
     0x0b83: CD [59 0A]  |   CAL 0x0A59                          ; keep checking player health 
     0x0b86: C2 [83 0B]  |   JNZ 0x0B83                          ; ... until death sequence complete ...

; name: splashInsertCoin
; After the demo, the splash sequence asks players to insert a coin. If the splash toggle is clear, 
; There will be an extra "C" written into "INSERT CCOIN" (ahead of the animation sequence)

.splashInsertCoin
     0x0b89: AF          |   XRA A
     0x0b8a: 32 [C1 20]  |   STA 0x20C1                          ; clear 20C1 -- demo over
     0x0b8d: CD [B1 0A]  |   CAL 0x0AB1                          ; 40-tick wait loop
     0x0b90: CD [88 19]  |   CAL 0x1988                          ; jumps straight to 0x09d6: clear game area
     0x0b93: 0E [0C]     |   MVI C, 0x0C                         ; put 12 in C
     0x0b95: 21 [11 2C]  |   LXI H, 0x2C11                       ; point to screen coordinate
     0x0b98: 11 [90 1F]  |   LXI D, 0x1F90                       ; pointer to message: "INSERT  COIN"
     0x0b9b: CD [F3 08]  |   CAL 0x08F3                          ; .writeMessageNoDelay
     0x0b9e: 3A [EC 20]  |   LDA 0x20EC                          ; check splash toggle 
     0x0ba1: FE [00]     |   CPI 0x00                            ; is it clear?
     0x0ba3: C2 [AE 0B]  |   JNZ 0x0BAE                          ;    ... it's set, no extra "C"
     0x0ba6: 21 [11 33]  |   LXI H, 0x3311                       ; if clear, load screen coordinates
     0x0ba9: 3E [02]     |   MVI A, 0x02                         ; 
     0x0bab: CD [FF 08]  |   CAL 0x08FF                          ; write extra 'C' in 'INSERT CCOIN'
     0x0bae: 01 [9C 1F]  |   LXI B, 0x1F9C                       ; load 0x1F9C into BC 
     0x0bb1: CD [56 18]  |   CAL 0x1856                          ; coordinates into registers: '<1 OR 2 PLAYERS>' 
     0x0bb4: CD [4C 18]  |   CAL 0x184C                          ; writeTableMessage
     0x0bb7: DB [02]     |   IN 0x02                             ; read port 2 input
     0x0bb9: 07          |   RLC                                 ; check coin info switch
     0x0bba: DA [C3 0B]  |   JC 0x0BC3                           ; if it MSB is set, skip to _noCoinInfo

; name: _coinInfo
; if bit 7 on input port 2 is clear, the cost-per-player table will print.
; It uses the pointer-pointer data structures and .printTableLoop at 0x193A
; to write: "*1 PLAYER  1 COIN " and then "*2 PLAYERS 2 COINS" 

._coinInfo
     0x0bbd: 01 [A0 1F]  |   LXI B, 0x1FA0                       ; otherwise, load 1FA0 into BC
     0x0bc0: CD [3A 18]  |   CAL 0x183A                          ; printTableLoop (goes until FF)
                                                                 ; "*1 PLAYER  1 COIN "
                                                                 ; "*2 PLAYERS 2 COINS"
; name: _noCoinInfo
; This is where we resume processing if bit 7 of port 2 is nonzero. Here we see a 2-second pause.
; Then, if the splash toggle is nonzero, we jump over the "CCOIN" shoot-the-extra-C animation.

._noCoinInfo
     0x0bc3: CD [B6 0A]  |   CAL 0x0AB6                          ; 2-second pause
     0x0bc6: 3A [EC 20]  |   LDA 0x20EC                          ; load splash toggle
     0x0bc9: FE [00]     |   CPI 0x00                            ; if it's not clear...
     0x0bcb: C2 [DA 0B]  |   JNZ 0x0BDA                          ; ... jump over shoot-extra-C animation

; name: _splashAnimation_1FD5
; This loads the data for the alien's move from screen left to line up with the "C" in "CCOIN"
; In the three lines here, we see the alien move out into position. 
; It moves horizontally from 0x241A to 0x321A 

._splashAnimation_1FD5                                           ; TO GET HERE: TOGGLE SET
     0x0bce: 11 [D5 1F]  |   LXI D, 0x1FD5                       ;    load 1FD5 into DE
     0x0bd1: CD [E2 0A]  |   CAL 0x0AE2                          ;    reset splash data structure (12 bytes)
     0x0bd4: CD [80 0A]  |   CAL 0x0A80                          ;    set 0x20C1 to 2 and loop for ISR animation 
     0x0bd7: CD [9E 18]  |   CAL 0x189E                          ; animation sequence: shoot extra "C"

; name: _flipToggleRestartSplash
; toggles over to the other processing run. Splash loop control is as follows:
; ** 0x20EC starts at 0x01: "PLAY" (w/ normal Y) -> DEMO -> "COIN" (w/ normal C) -> toggle
; ** if 20EC == 0x00: "PLAY" (upside down Y)/alien fixes "Y" -> demo -> "CCOIN"/alien shoots C -> toggle

._flipToggleRestartSplash
     0x0bda: 21 [EC 20]  |   LXI H, 0x20EC                       ; toggle 0x20EC
     0x0bdd: 7E          |   MOV A, M
     0x0bde: 3C          |   INR A 
     0x0bdf: E6 [01]     |   ANI 0x01                            ; limit to bit 0
     0x0be1: 77          |   MOV M, A                            ; ... 0x20EC now toggled to 0x01
     0x0be2: CD [D6 09]  |   CAL 0x09D6                          ; clear the game area
     0x0be5: C3 [DF 18]  |   JMP 0x18DF                          ; jump to the top of splash loop
                                                                 ; this is the game init sequence
                                                                 ; comes right after storing high scores

; name: writeMessage_normalY
; this writes the word "PLAY" the the screen at position set in HL
; It then jumps to code that writes the remainder of the message "PLAY SPACE INVADERS"
; and then continues to write the splash-screen table of scores for various invaders
; this is the counterpart to a version that writes "PLAY" with an upside-down Y

.writeMessage_normalY                                            ; writes "play" with normal Y
     0x0be8: 11 [AB 1D]  |   LXI D, 0x1DAB                       ; C has been set to 4
     0x0beb: CD [93 0A]  |   CAL 0x0A93                          ; writeMessageWithDelay
     0x0bee: C3 [0B 0B]  |   JMP 0x0B0B                          ; next message: "SPACE  INVADERS"

; name: updateAliens
; wrapper function for demo-time movement of invader. Handles updating alien movement offsets,
; detecting shot hits, etc.
; Then jumps to handling for secret message

.updateAliens                                                    ; initiate explosion if necessary,
     0x0bf1: CD [0A 19]  |   CAL 0x190A                          ; and update offsets
     0x0bf4: C3 [9A 19]  |   JMP 0x199A                          ; check for inputs and write secret message

.secretMessage
     0x0bf7: 13                                                  ; message: 'T'
     0x0bf8: 00                                                  ;          'A'
     0x0bf9: 08                                                  ;          'I'
     0x0bfa: 13                                                  ;          'T'
     0x0bfb: 0E                                                  ;          'O'
     0x0bfc: 26                                                  ;          ' '
     0x0bfd: 02                                                  ;          'C'
     0x0bfe: 0E                                                  ;          'O'
     0x0bff: 0F                                                  ;          'P'




; **********************************************************************************
; *********************************************************************************
;
;    ----- 0x0C00 - 0x13FF: NOT ACCESSED ----
;         ** all memory locations in this region of ROM are 0 **
;
; *********************************************************************************
; ********************************************************************************



; ********************** WRITE / ERASE SPRITE UTILITIES 1 *************************
;--------------------------------------------------------------
;
; **** WRITE/ERASE SPRITE UTILITIES ****
;
;    0x1400 - draw shifted sprite (
;             use of OR makes backround transparent)
;    0x1424 - clear 2 bytes of sprite in Y direction over B columns
;    0x1439 - write sprite no shift
;    0x1452 - remove shifted sprite 
;             (use of AND/complement means background not affected)
;    0x1474 - send shift offset to output
;    0x147C - save 2 byte tall sprite that is B bytes long from
;             screen pointer at HL to memory buffer at DE
;    0x1491 - draws one of several shot sprites and checks for
;             collision as it does
;    0x14CB - clear 1-byte horizontal line
;    0x14CC - draw horizontal line or simple 1-byte sprite, repeated
;
;    additional write-sprite procedures continue at 0x15D3
;
;---------------------------------------------------------------

; name: drawShiftedSprite
; utility function that uses shift register to draw sprites in between byte demarcations in the
; Y direction. Encoded screen coordinates should be in HL, sprite art coordinates in DE, sprite size in B
; this makes the sprite background essentially transparent by using OR to leave other bytes in place

.drawShiftedSprite
     0x1400: 00          |   NOP
     0x1401: CD [74 14]  |   CAL 0x1474                     ; send y-coord to shift register (returns)
     0x1404: 00          |   NOP
     0x1405: C5          |   PUSH B                         ; save B
     0x1406: E5          |   PUSH H                         ; save H
     0x1407: 1A          |   LDAX D                         ; load A from address in DE
     0x1408: D3 [04]     |   OUT 0x04                       ; send to shift register
     0x140a: DB [03]     |   IN 0x03                        ; recieve shifted value
     0x140c: B6          |   ORA M                          ;
     0x140d: 77          |   MOV M, A                       ; add new bits to visual memory
     0x140e: 23          |   INX H                          ; move to second byte in visual memory
     0x140f: 13          |   INX D                          ; move to second byte of sprite
     0x1410: AF          |   XRA A                          ; clear accumulator
     0x1411: D3 [04]     |   OUT 0x04                       ; send to shift register                     ; 
     0x1413: DB [03]     |   IN 0x03                        ; receive shifted value
     0x1415: B6          |   ORA M                          ; add second byte's bits to visual memory
     0x1416: 77          |   MOV M, A
     0x1417: E1          |   POP H
     0x1418: 01 [20 00]  |   LXI B, 0x0020 
     0x141b: 09          |   DAD B                          ; add 20 to HL -- next row
     0x141c: C1          |   POP B                          ; restore
     0x141d: 05          |   DCR B                          ; ... and decrement
     0x141e: C2 [05 14]  |   JNZ 0x1405                     ; are we done? if not, loop
     0x1421: C9          |   RET                            ; ... and return

.__not_accessed__
     0x1422: 00          |   NOP
     0x1423: 00          |   NOP

; name: removeSprite
; this completely clears two bytes' worth of pixels (in Y direction) 
; over B columns (in X direction)

.removeSprite
     0x1424: CD [74 14]  |   CAL 0x1474                     ; send coordinates to shift register                                                         
     0x1427: C5          |   PUSH B
     0x1428: E5          |   PUSH H
     0x1429: AF          |   XRA A
     0x142a: 77          |   MOV M, A                       ; Fully clear two bytes over B columns
     0x142b: 23          |   INX H                          ; up one byte
     0x142c: 77          |   MOV M, A                       ; clear (HL)
     0x142d: 23          |   INX H                          ; advance
     0x142e: E1          |   POP H
     0x142f: 01 [20 00]  |   LXI B, 0x0020                  ; over one column
     0x1432: 09          |   DAD B 
     0x1433: C1          |   POP B           
     0x1434: 05          |   DCR B                          ; are we finished with length B? 
     0x1435: C2 [27 14]  |   JNZ 0x1427                     ; loop if not
     0x1438: C9          |   RET                            ; return

; name: writeSpriteNoShift
; This writes a single 8bit by 8bit sprite to graphical memory. It completely overwrites
; the 1-byte-by-B rectangle and is not sensitive to collision. 
; it then returns

.writeSpriteNoShift                                         ; writes 1-byte-high row of length B
     0x1439: C5          |   PUSH B
     0x143a: 1A          |   LDAX D                         ; load A from (DE)
     0x143b: 77          |   MOV M, A                       ; move into memory at HL
     0x143c: 13          |   INX D
     0x143d: 01 [20]     |   LXI B, 0x0020                  ; move over to next column
     0x1440: 09          |   DAD B
     0x1441: C1          |   POP B
     0x1442: 05          |   DCR B
     0x1443: C2 [39 14]  |   JNZ 0x1439                     ; and loop until done
     0x1446: C9          |   RET

.__not_accessed__
     0x1447: 00          |   NOP
     0x1448: 00          |   NOP
     0x1449: 00          |   NOP
     0x144a: 00          |   NOP
     0x144b: 00          |   NOP
     0x144c: 00          |   NOP
     0x144d: 00          |   NOP
     0x144e: 00          |   NOP
     0x144f: 00          |   NOP
     0x1450: 00          |   NOP
     0x1451: 00          |   NOP

; name: removeShiftedSprite
; shifts and clears selected bits byt taking the accumulator's complement (using sprite image)
; and then a logical AND to remove set bits that match the pixelart.

.removeShiftedSprite
     0x1452: CD [74 14]  |   CAL 0x1474                          ; send lower 3 bits of value in L
                                                                 ; to offset on shift register
._loopUntilErased                                                                 
     0x1455: C5          |   PUSH B
     0x1456: E5          |   PUSH H
     0x1457: 1A          |   LDAX D                              ; load accumulator from (DE)
     0x1458: D3 [04]     |   OUT 0x04                            ; out to shift register for conversion
     0x145a: DB [03]     |   IN 0x03                             ; read back in
     0x145c: 2F          |   CMA                                 ; erase by complementing the accumulator
     0x145d: A6          |   ANA M                               ; masking off the address in HL
     0x145e: 77          |   MOV M, A                            ; ... and replace in memory
     0x145f: 23          |   INX H
     0x1460: 13          |   INX D
     0x1461: AF          |   XRA A
     0x1462: D3 [04]     |   OUT 0x04                            ; do it again for the next byte...
     0x1464: DB [03]     |   IN 0x03
     0x1466: 2F          |   CMA                                 ; use complement w/ AND to remove bits
     0x1467: A6          |   ANA M
     0x1468: 77          |   MOV M, A
     0x1469: E1          |   POP H
     0x146a: 01 [20 00]  |   LXI B, 0x0020                       ; advance to the next column
     0x146d: 09          |   DAD B
     0x146e: C1          |   POP B
     0x146f: 05          |   DCR B                               ; ... until B is 0
     0x1470: C2 [55 14]  |   JNZ 0x1455                          ; loop
     0x1473: C9          |   RET

; Sets the shift register offset to draw a sprite from the least significant three
;    bits of the sprite's x-coordinate. Allows 16-bit-long sprites to be drawn when their
;    location in video memory does not perfectly align with a byte
;    Example (this would be turned counterclockwise on space invaders monitor)
;
;    For a shift register populated: 1111 1111 0000 0000
;
;              offset 0 returns: 1111 1111
;              offset 1 returns: 1111 1110
;              offset 2 returns: 1111 1100
;              offset 3 returns: 1111 1000
;              offset 4 returns: 1111 0000
;              offset 5 returns: 1110 0000
;              offset 6 returns: 1100 0000
;              offset 7 returns: 1000 0000
;              
;    This allows for bit-by-bit movement in the vertical (Y) direction

.sendShiftOffset
     0x1474: 7D          |   MOV A, L                       ; get Y coordinate
     0x1475: E6 [07]     |   ANI 0x07                       ; mask bottom 3 bits
     0x1477: D3 [02]     |   OUT 0x02                       ; set as shift register offset
     0x1479: C3 [47 1A]  |   JMP 0x1A47

; name: saveBunker
; Puts data from screen pointer at HL into memory buffer at DE
; This handles a 2-byte tall sprite that is B bytes long (including a bunker)
; it handles two bytes then repeats until counter in B is 0

.saveBunker
     0x147c: C5          |   PUSH B
     0x147d: E5          |   PUSH H
     0x147e: 7E          |   MOV A, M                       ; grab byte from location in HL (screen)
     0x147f: 12          |   STAX D                         ; store at location in DE (buffer)
     0x1480: 13          |   INX D
     0x1481: 23          |   INX H
     0x1482: 0D          |   DCR C                          ; do (C = 0x02) bytes
     0x1483: C2 [7E 14]  |   JNZ 0x147E
     0x1486: E1          |   POP H
     0x1487: 01 [20 00]  |   LXI B, 0x0020                  ; next column
     0x148a: 09          |   DAD B
     0x148b: C1          |   POP B
     0x148c: 05          |   DCR B
     0x148d: C2 [7C 14]  |   JNZ 0x147C                     ; until all (B = 0x16) columns are finished
     0x1490: C9          |   RET

; name: drawShot [PLAYER SHOT and PROCESS ALIEN SHOT SUBROUTINES / ISR]
; draws any one of several shot sprites and checks for collision as it does. A collision is defined as
; attempting to draw on a pixel that is already set. This shifts and decodes encoded coordinates.
; 0x2061 is the RAM variable collision indicator.

.drawShot
     0x1491: CD [74 14]  |   CAL 0x1474                     ; send x coord in L to shift register, convert & return
     0x1494: AF          |   XRA A                          ; clear A
     0x1495: 32 [61 20]  |   STA 0x2061                     ; and store it at 0x2061
     0x1498: C5          |   PUSH B                         ; save B
     0x1499: E5          |   PUSH H                         ; save H
     0x149a: 1A          |   LDAX D                         ; load A from the address in DE (init: 1C90)
     0x149b: D3 [04]     |   OUT 0x04                       ; send A out to shift register
     0x149d: DB [03]     |   IN 0x03                        ; and receive back a shifted value
     0x149f: F5          |   PUSH PSW                       ; push A to the stack
     0x14a0: A6          |   ANA M                          ; and check to see if corresponding bits at HL set
     0x14a1: CA [A9 14]  |   JZ 0x14A9                      ; if so, 
     0x14a4: 3E [01]     |   MVI A, 0x01                    ;
     0x14a6: 32 [61 20]  |   STA 0x2061                     ; ... store 1 at 0x2061
     0x14a9: F1          |   POP PSW                        ; either way, restore A (this was coonverted val at DE)
     0x14aa: B6          |   ORA M                          ;
     0x14ab: 77          |   MOV M, A                       ; ... draw bits using OR
     0x14ac: 23          |   INX H                          ; increment HL to next byte position
     0x14ad: 13          |   INX D                          ; increment DE
     0x14ae: AF          |   XRA A                          ; clear A
     0x14af: D3 [04]     |   OUT 0x04                       ; send cleared value out to shift register
     0x14b1: DB [03]     |   IN 0x03                        ; and receive back shifted value
     0x14b3: F5          |   PUSH PSW                       ; save A
     0x14b4: A6          |   ANA M                          ; and check if corresponding bits at HL set
     0x14b5: CA [BD 14]  |   JZ 0x14BD                      ; if so....
     0x14b8: 3E [01]     |   MVI A, 0x01
     0x14ba: 32 [61 20]  |   STA 0x2061                     ; ... store 1 at 2061
     0x14bd: F1          |   POP PSW                        ; restore A
     0x14be: B6          |   ORA M
     0x14bf: 77          |   MOV M, A                       ; ... draw bits using OR
     0x14c0: E1          |   POP H                          ; restore H
     0x14c1: 01 [20 00]  |   LXI B, 0x0020                  ; and move to the next row from original location
     0x14c4: 09          |   DAD B
     0x14c5: C1          |   POP B                          ; restore B
     0x14c6: 05          |   DCR B                          ; countdown
     0x14c7: C2 [98 14]  |   JNZ 0x1498                     ; ... repeat until B is 0
     0x14ca: C9          |   RET                            ; .. and return

; name: setupClearSprite
; clears A so that "writing" the sprite will actually clear video memory
; the number of bytes to be cleared should be in B
; The screen location should be in HL

.setupClearSprite
     0x14cb: AF          |   XRA A                          ; sets value of A to 0

; name: drawHorizontalLine
; This either clears or sets the bits in a single byte, repeating until
; a horizontal line is drawn (1 bit would be a very thin line). 
; If the accumulator is clear, it erases whatever has been drawn at the target
; The number of bytes to write should be in B
; the value to write should be in A 
; the screen coordinates should be in HL

.drawHorizontalLine                                         ; bumps to next row, 
                                                            ; writes row of length B w/ value A
     0x14cc: C5          |   PUSH B
     0x14cd: 77          |   MOV M, A
     0x14ce: 01 [20 00]  |   LXI B, 0x0020 
     0x14d1: 09          |   DAD B
     0x14d2: C1          |   POP B
     0x14d3: 05          |   DCR B
     0x14d4: C2 [CC 14]  |   JNZ 0x14CC
     0x14d7: C9          |   RET

; **************************** PLAYER SHOT GAME LOOP SUBROUTINE *******************************

; --------------------------------------------------------------------------
;
;    0x14D8 - player shot hit handling (game/demo)
;              0x14E1 - handle shot reaches top
;              0x14EA - handle nothing hit
;              0x14EF - handle UFO hit
;              0x14F5 - rule out shot that collides too low
;              0x1504 - handle possible invader hit (other possibilites exist)
;    0x1530 - process player shot miss
;    0x1538 - process shot explosion
;    0x1554 - utility: get distance H to A (compares shot coords to origin alien to determine
;                                           if shot is in "grid" of aliens)
;    0x1562 - get row of alien at relevant position in grid
;    0x156F - get column of alien at relevant position in grid
;    0x1579 - set UFO hit flag
;    0x1581 - identify index of invader that was/could be hit
;    0x1590 - utility: increment and wrap C (this is used as utility in 'get distance' logic.
;                      sometimes the origin alien has wrapped around to the top of the screen.
;                      This compensates)
;
; --------------------------------------------------------------------------

; name: playerShotHit
; Checks to see if the player's advancing shot has either (a) hit something or (b) reached the top

.playerShotHit
     0x14d8: 3A [25 20]  |   LDA 0x2025                     ; check player shot's status
     0x14db: FE [05]     |   CPI 0x05                       ;    ... 5 - shot hit an invader. explosion time
     0x14dd: C8          |   RZ                             ;    ....... return because ISR handles
     0x14de: FE [02]     |   CPI 0x02                       ;    ... 2 - there is a normal, advancing active shot
     0x14e0: C0          |   RNZ                            ;    ....... that's what this is about. otherwise return

; name: _shotHitTop
; Here we first check to see if the shot has reached the top of the active game zone.
; If it has, we initiate a miss.
; ** as a reminder, conversion of coordinates applies. So a comparison to 0xD8 spans the entirety of 
;    the top because this is the line in the top half where coordinates are 0x?B where ? is odd
;    you calculate these from the encoded coordinate in HL by: screen = (encoded / 8) | 0x2000

._shotHitTop                                                ; check if shot has reached top or hit UFO
     0x14e1: 3A [29 20]  |   LDA 0x2029                     ; LSB (row/height) encoded shot sprite coordinate
     0x14e4: FE [D8]     |   CPI 0xD8                       ; is it above D8? (converted, this is {1B, 3B, 5B...} line along the top)
     0x14e6: 47          |   MOV B, A                       ;    ... that's too high.
     0x14e7: D2 [30 15]  |   JNC 0x1530                     ;    ... Time to miss/explode (0x2025 <- 3, returns)
     
; name: _nothingHitCheck
; Otherwise, if nothing has been hit, let's return. Nothing more to do here.

._nothingHitCheck
     0x14ea: 3A [02 20]  |   LDA 0x2002                     ; otherwise, has something been hit?
     0x14ed: A7          |   ANA A                          ;    ... no 
     0x14ee: C8          |   RZ                             ;    ... ok return

; name: _shotHitUFO
; At this point, we know the shot has hit something. We check to see if the something was a UFO by checking 
; screen position again.
; Here we know 0xCE encoded indicates screen Y coordinate of 0x?8, where ? is odd (indicating top half of the screen)
; ... above this, we assume a collision means a UFO has been hit.

._shotHitUFO
     0x14ef: 78          |   MOV A, B                       ; is shot height above 0xCE?
     0x14f0: FE [CE]     |   CPI 0xCE                       ;    ... in the UFO zone
     0x14f2: D2 [79 15]  |   JNC 0x1579                     ; sets UFO hit, ends player shot sequence, returns

; name: _ruleOutTooLow
; Here we compare the shot's y-coordinate, plus some pad, with the lowest possible alien, using the
; origin alien's encoded y-coordinate in 0x2009 as a reference.
; However, because the origin alien's coordinate actually wraps around once it hits 0, we need to rule 
; that out before we check if the player's shot is lower.
; When converted, 0x90 turns out to be three bytes above where the origin alien started. 
; If the origin alien has wrapped, we proceed to jump and check more closely for a hit either way.
; But otherwise, if the shot plus pad is below the field of invaders, we rule out an invader hit and
; process a miss.

._ruleOutTooLow
     0x14f5: C6 [06]     |   ADI 0x06                       ; add 6-bit pad
     0x14f7: 47          |   MOV B, A                       ; move in B
     0x14f8: 3A [09 20]  |   LDA 0x2009                     ; load 0x2009 (origin alien y-coordinate)
     0x14fb: FE [90]     |   CPI 0x90                       ; compare: is the bottom origin alien coords
     0x14fd: D2 [04 15]  |   JNC 0x1504                     ; ... back at the top of the screen? if so -> hit possible
     0x1500: B8          |   CMP B                          ; ... if not, is the shot above or within 6 bits to lowest alien?
     0x1501: D2 [30 15]  |   JNC 0x1530                     ; ... if lowest alien is above shot w/ pad -> miss

; name: _invaderHitPossible
; In this function, we're checking closely for whether an alien has been hit, because the y-coordinates of the 
; player's shot are either within or close to the field of invaders. (We've ruled out the UFO zone, we've ruled
; out a miss at the top, and we've ruled out "too low, didn't reached the invaders" )
; Once we identify where the hypothetical invader we've hit would be, we check if there is in fact an alien there.
;
; If we find a hit, we set 0x2025 to 0x05 (alien hit), remove the alien, erase the sprite, 
; and start the explosion timer.
;
; ** the folks at computer archaology identify a bug here.
; when a player shoots and hits a bunker far to the right of the screen, it's considered inside the
; the field of invaders, but is in fact outside it to the right (only 11 columns are tracked considered).
; in that case, an invader in the next row up on the far left side of the screen will be erroneously 
; identified as being "hit" due to inadequate boundary checking
; see their writeup here: https://computerarcheology.com/Arcade/SpaceInvaders/Code.html#CodeBug1

._invaderHitPossible
     0x1504: 68          |   MOV L, B                       ; put padded shot height in L
     0x1505: CD [62 15]  |   CAL 0x1562                     ; B <- 0x10's between shot and origin alien
     0x1508: 3A [2A 20]  |   LDA 0x202A                     ; put x coordinate of player shot into H and A
     0x150b: 67          |   MOV H, A
     0x150c: CD [6F 15]  |   CAL 0x156F                     ; C <- 0x10's between player shot and origin alien                          
     0x150f: 22 [64 20]  |   SHLD 0x2064                    ; store HL at 2064 (2-byte screen coords for exploding alien)
     0x1512: 3E [05]     |   MVI A, 0x05                    ; put 5 into A
     0x1514: 32 [25 20]  |   STA 0x2025                     ; and set player shot status to alien hit
     0x1517: CD [81 15]  |   CAL 0x1581                     ; HL <- pointer for alien index
     0x151a: 7E          |   MOV A, M
     0x151b: A7          |   ANA A                          ; is alien present?
     0x151c: CA [30 15]  |   JZ 0x1530                      ;    ... no -> miss
     0x151f: 36 [00]     |   MVI M, 0x00                    ; set alien status to absent
     0x1521: CD [5F 0A]  |   CAL 0x0A5F                     ; points HL at 0x2062
     0x1524: CD [3B 1A]  |   CAL 0x1A3B                     ; load sprite info into registers
     0x1527: CD [D3 15]  |   CAL 0x15D3                     ; shift position & draw sprite
     0x152a: 3E [10]     |   MVI A, 0x10                    ; store 0x10 in 0x2003 (starts invader explosion timer)
     0x152c: 32 [03 20]  |   STA 0x2003
     0x152f: C9          |   RET                            ; and return

; name: _playerShotMiss
; handles a shot that missed the invaders but either hit something else or wound up at the top of the screen.
; This sets shot status to 03 (hit something that's not an invader), then turns off explosion audio and returns

._playerShotMiss                                             ; players shot has hit the top, or a bunker
     0x1530: 3E [03]     |   MVI A, 0x03
     0x1532: 32 [25 20]  |   STA 0x2025                     ; set player shot's status to 3
     0x1535: C3 [4A 15]  |   JMP 0x154A                     ; ._clearHitInidicator: 
                                                            ; restrict audio to invader explosion bit 
                                                            ; (this shouldn't trigger), then return

; name: processExplosion [VBLANK ISR]
; This procedure runs during VBLANK ISR game processing (before the game object loop) when we see that
; an invader is exploding. We decrement the invader's explosion timer. 
; If it's not 0 yet, we return. Otherwise:
;    * point HL at the invader that's exploding and remove the invader's sprite
;    * set the player's shot status in RAM at 0x2025 to 4, which means "explosion over"
;    * clear the "player shot hit something" indicator flag at 0x2002
;    * turn off exploding alien sound
;    * return

.processExplosion
     0x1538: 21 [03 20]  |   LXI H, 0x2003                  ; countdown alien explosion timer
     0x153b: 35          |   DCR M
     0x153c: C0          |   RNZ                            ; if it's not 0, return
     0x153d: 2A [64 20]  |   LHLD 0x2064
     0x1542: CD [24 14]  |   CAL 0x1424                     ; shift and clear spite at pointer in 0x2064

._endPlayerShot
     0x1545: 3E [04]     |   MVI A, 0x04                    ; and set shot status to 4 (explosion over)
     0x1547: 32 [25 20]  |   STA 0x2025

._clearHitIndicator
     0x154a: AF          |   XRA A
     0x154b: 32 [02 20]  |   STA 0x2002                     ; clear the "player shot hit something" indicator
     0x154e: 06 [F7]     |   MVI B, 0xF7                    ; put F7 in B
     0x1550: C3 [DC 19]  |   JMP 0x19DC                     ; use B to mask off Port 3 audio
                                                            ; (this turns off exploding alien sound)

.__not_accessed__
     0x1553: 00 [0E 00]  |   NOP

; name: getDistanceHtoA
;    ** if H is greater than A, A climbs until H is greater. C counts the 0x10's added.
;         example: player shot is above the origin alien y-coord. 
;                  Raising the alien by 0x10's gives us the row
;    ** if H is less than or equal to A initially, and A + 0x10 is still less than 0x7F, C=1
;         example: player shot is below origin alien, and also quite low on screen. We know
;                  it is within the grid of aliens, or close to it. Set C=1. 
;    ** if H is less than or equal to A initially, and A + 0x10 sets the sign flag (0x80 or greater),
;       A wraps around until sign flag is turned off (a value just above 0, between 00 and 0F)
;         example: player shot is significantly below the origin alien, but not terribly low on 
;                  screen. Because the origin alien wraps around, we also "wrap" our measurement
;
;    Note that all values of C will be too high by 1 and must be adjusted.

.getDistanceHtoA                                                 ; several cases:
                                                                 ; H is greater than A: 
                                                                           0. A climbs until H is greater
                                                                                -> C counts 0x10's added
                                                                 ; H is less than or equal to A initially:
                                                                           1. A + 0x10 is still less than 0x7F
                                                                              and this is still greater than H
                                                                                -> C = 1
                                                                           2. A wraps around to [0, 0F]
                                                                                -> C counts the 0x10's added
     0x1554: 0E [00   ]  |   MVI C, 0x00                         ; initialize C
     0x1556: BC          |   CMP H                               ; is H less or equal to A?
     0x1557: D4 [90 15]  |   CNC 0x1590                          ; yes. so how much lower is it?
                                                                 ;    If A + 0x10 < 0x7F, C is 0x01
                                                                 ;    otherwise, C is incremented for every
                                                                 ;    0x10 it takes to wrap A back to positive
     0x155a: BC          |   CMP H                               ; is H less than A + 0x10,
                                                                 ; or newly-positive A (<0x10)
     0x155b: D0          |   RNC                                 ;    yes. ... ok, we're finished.
     0x155c: C6 [10   ]  |   ADI 0x10                            ; ok H is now greater (or it was originally)
     0x155e: 0C          |   INR C                               ; add 1 to C and 0x10 to A
     0x155f: C3 [5A 15]  |   JMP 0x155A                          ; loop until H is less than A

; name: findAlienRow
; coming in with the encoded y coordinate (+6 bits) of a shot in L, we are looking for the row in the field of invaders
; where the shot is currently located. We know it should be inside the grid of invaders.

.findAlienRow
     0x1562: 3A [09 20]  |   LDA 0x2009                          ; load height of origin alien in A
     0x1565: 65          |   MOV H, L                            ; put padded height of player shot in H
     0x1566: CD [54 15]  |   CAL 0x1554                          ; get distance H <-> A (in C)
     0x1569: 41          |   MOV B, C                            ; put C into B and compensate for 
     0x156a: 05          |   DCR B                               ;    off-by-one
     0x156b: DE [10]     |   SBI 0x10                            ; 
     0x156d: 6F          |   MOV L, A                            ; put adjusted y-coordinate A back in L
     0x156e: C9          |   RET

; name: findAlienColumn
; here we put the x-coordinate of the origin alien in A, and come in with the x coordinate of 
; the player's shot in H. Because the origin alien is guaranteed to be less than the shot's coordinate,
; we don't worry about wraparound here. 

.findAlienColumn
     0x156f: 3A [0A 20]  |   LDA 0x200A                          ; load x coordinate of origin alien
     0x1572: CD [54 15]  |   CAL 0x1554                          ; get distance H <-> A (in C)
     0x1575: DE [10]     |   SBI 0x10                            ; compensate for off-by-one
     0x1577: 67          |   MOV H, A                            ; and put back into H
     0x1578: C9          |   RET

.setUFOHit
     0x1579: 3E [01 32]  |   MVI A, 0x01
     0x157b: 32 [85 20]  |   STA 0x2085                          ; set UFO hit indicator at 0x2085
     0x157e: C3 [45 15]  |   JMP 0x1545                          ; ends player explosion and clears hit indicator

; name: identifyInvaderHit
; we take the row and column information (row in B, column in C) and get the relevant invader's
; index number. We calculate by taking: invader = 11 * row + col (there are 11 aliens in a row)
; This returns a pointer to the alien's position in the player's invader status array in HL

.identifyInvaderHit                                              ; we have row number in B and column in C
                                                                 ; puts pointer for alien index in HL
     0x1581: 78          |   MOV A, B
     0x1582: 07          |   RLC                                 
     0x1583: 07          |   RLC
     0x1584: 07          |   RLC
     0x1585: 80          |   ADD B                               
     0x1586: 80          |   ADD B
     0x1587: 80          |   ADD B                               ; multiply row number by 11
     0x1588: 81          |   ADD C                               ; and add the column number
     0x1589: 3D          |   DCR A                               ; subtract 1 (comp. for col off-by-one)
     0x158a: 6F          |   MOV L, A                            ; and put in LSB
     0x158b: 3A [67 20]  |   LDA 0x2067
     0x158e: 67          |   MOV H, A                            ; put player-specific data area in MSB
     0x158f: C9          |   RET

; name: incrementAndWrapC
; adds 0x10. If the sign flag is now set, loops around until it turns off, keeping track of 0x10'S
; ** note that 0x80 converts to 0x10, or exactly midscreen.
;    If we get here, H is less than A, and the original A + 0x10 set the sign flag, so is above 0x80.
;    in at least one usage of this function, A is the origin alien y-coordinate. If it is above
;    0x80/converted 0x10/midscreen, it has gotten so low it wrapped around (the origin alien starts 
;    at 0x78/converted 0x0F)
;    This function is the origin alien in A "unwrapping" to compare with the player's shot

.incrementAndWrapC                                               ; increments C and adds 0x10 to A
     0x1590: 0C          |   INR C                               ; 
     0x1591: C6 [10]     |   ADI 0x10                            ; once or...
     0x1593: FA [90 15]  |   JM 0x1590                           ;    ... if sign flag is set, loop until positive
     0x1596: C9          |   RET                                 ; then return

; **************************************** MOVE INVADERS SUBROUTINE ************************************

; -------------------------------------------------------
;
; **** MOVE INVADERS ****
;
;    0x1597 - move aliens left: check right edge, turn aliens to move left if they've reached it
;    0x15A9 - utility: update offsets based on new direction
;    0x15B7 - move aliens right: check left edge, turn aliens to move right if they've reached it
;    0x15C5 - utility: used to check vertical line at edge of screen for presence of invaders
;
;    NOTE: 0x166B (below) is the set carry utility called when invaders encounter the edge
;                         It's called in the edge-check utility at 0x15C9
;
; -------------------------------------------------------

; name: moveAliensLeft
; Here we check a line on the right side of the screen to determine if the aliens have reached it and
; need to be turned around.
; this is a setup/initializer for _storeOffsets, which updates horizontal movement offset.
; stores the new x-offset in B and the new horizontal direction toggle value in A

.moveAliensLeft                                                  ; check line on right side of screen
     0x1597: 3A [0D 20]  |   LDA 0x200D                          ; load 0x200D into accumulator
     0x159a: A7          |   ANA A                               ; is it clear? Should be clear if currently moving right
     0x159b: C2 [B7 15]  |   JNZ 0x15B7                          ;    ... no. moveAliensRight
     0x159e: 21 [A4 3E]  |   LXI H, 0x3EA4                       ; otherwise, point at screen just above bunkers on right side
     0x15a1: CD [C5 15]  |   CAL 0x15C5                          ; check vertical line up the right side for sprites
     0x15a4: D0          |   RNC                                 ; ... nothing? return
     0x15a5: 06 [FE]     |   MVI B, 0xFE                         ; otherwise, 
     0x15a7: 3E [01]     |   MVI A, 0x01                         ; set A for toggle

; name: _storeOffsets
; reverses the direction toggle in memory and stores B as x-offset. Also updates y-offset
; from global y-offset variable in RAM

._storeOffsets 
     0x15a9: 32 [0D 20]  |   STA 0x200D                          ; toggle 0x200D
     0x15ac: 78          |   MOV A, B                            ; 
     0x15ad: 32 [08 20]  |   STA 0x2008                          ; change to either 0xFE, 0x02 or 0x03
     0x15b0: 3A [0E 20]  |   LDA 0x200E                          ; 
     0x15b3: 32 [07 20]  |   STA 0x2007                          ; stores global Y offset as active Y-offset in 2007
     0x15b6: C9          |   RET                                 ; and return

; name: moveAliensRight
; Here we check a line on the left side of the screen to determine if aliens have reache it and need
; to be turned around
; this is a setup/initializer for _storeOffsets, which updates horizontal movement offset
; stores the new offset in B and the new horizontal direction toggle value in A

.moveAliensRight
     0x15b7: 21 [24 25]  |   LXI H, 0x2524                       ; point HL at 0x2526
     0x15ba: CD [C5 15]  |   CAL 0x15C5                          ; check vertical line up the left for sprites
     0x15bd: D0          |   RNC                                 ; nothing? return
     0x15be: CD [F1 18]  |   CAL 0x18F1                          ; .invaderRightOffsetHelper
                                                                 ; 2 unless last alien, then 3
     0x15c1: AF          |   XRA A                               ; clear A for toggle
     0x15c2: C3 [A9 15]  |   JMP 0x15A9                          ; store offsets

.checkScreenMemory                                          ; checks 17 contiguous memory addresses (vertical line)
                                                            ; if something is there, sets carry and returns
     0x15c5: 06 [17 7E]  |   MVI B, 0x17                    ; let's take a look at 17 screen positions
     0x15c7: 7E          |   MOV A, M                       ; put byte from screen in A
     0x15c8: A7          |   ANA A                          ; is it zero?
     0x15c9: C2 [6B 16]  |   JNZ 0x166B                     ; ... found something! .setCarry_utility, return
     0x15cc: 23          |   INX H                          ; if zero, next memory position
     0x15cd: 05          |   DCR B                          ; let's decrement B
     0x15ce: C2 [C7 15]  |   JNZ 0x15C7                     ; and loop if it's not zero yet
     0x15d1: C9          |   RET

.__not_accessed__
     0x15d2: 00          |   NOP

; ********************** WRITE / ERASE SPRITE UTILITIES 2 *************************
;--------------------------------------------------------------
;
; **** WRITE/ERASE SPRITE UTILITIES ****
;
;    0x15D3 - shift coordinates and overwrite screen memory
;
;---------------------------------------------------------------

; name: drawSpriteOverwrite
; This procedure uses output/input to the 16-bit shift register in order to draw bytes that may not
; be aligned exactly to the bytes on screen.
; the call to 0x1474 sets the offset from the incoming y-coordinate (in L)
; incoming x and y coordinates are encoded. L (y coord) : yyyy yooo (o=offset bit)
;                                           H (x coord) : xxxx x---
; To convert: (HL) / 8 + 2000
; It should be noted that this is *very* similar to the draw function at 0x1400 EXCEPT that
; this overwrites memory instead of using "OR" to allow both sprites' bits to overlap, and preserves the
; original coordinates in HL

.drawSpriteOverwrite     
     0x15d3: CD [74 14]  |   CAL 0x1474                ; y-coord (offset) to shift
     0x15d6: E5          |   PUSH H
     0x15d7: C5          |   PUSH B
     0x15d8: E5          |   PUSH H
     0x15d9: 1A          |   LDAX D
     0x15da: D3 [04]     |   OUT 0x04                  ; data out to shift register
     0x15dc: DB [03]     |   IN 0x03                   ; ... read back in
     0x15de: 77          |   MOV M, A                  ; overwrite memory
     0x15df: 23          |   INX H                     ; advance to next byte
     0x15e0: 13          |   INX D
     0x15e1: AF          |   XRA A                     ; send 0 out to shift register
     0x15e2: D3 [04]     |   OUT 0x04
     0x15e4: DB [03]     |   IN 0x03                   ; read data back in
     0x15e6: 77          |   MOV M, A                  ; overwrite memory
     0x15e7: E1          |   POP H
     0x15e8: 01 [20 00]  |   LXI B, 0x0020             ; move over to next column
     0x15eb: 09          |   DAD B
     0x15ec: C1          |   POP B
     0x15ed: 05          |   DCR B
     0x15ee: C2 [D7 15]  |   JNZ 0x15D7                ; repeat until finished
     0x15f1: E1          |   POP H
     0x15f2: C9          |   RET

; *************************** GAME LOOP & DEMO PROCEDURES *****************************************

; -------------------------------------------------------------
;
; **** Game Loop and Demo Procedures ****
;
;    0x15F3 - count the number of invaders alive and store at 0x2082. 
;             set 0x206B to indicate only 1 left (used in game loop)
;    0x1611 - get pointer to current player's data (0x2100 or 0x2200)
;
; -------------------------------------------------------------

; name: updateInvaderCount [GAME LOOP]
; Loops through player's invader status array to count the number of invaders that are "alive"
; Puts the count in A and in the RAM variable at 0x2082
; If one or fewer invaders are left, we set flag at 0x206B.

.updateInvaderCount
     0x15f3: CD [11 16]  |   CAL 0x1611                              ; .getCurrentPlayerDataPtr
     0x15f6: 01 [00 37]  |   LXI B, 0x3700                           ; B = 0x37 (decimal 55), C = 0x00
     0x15f9: 7E          |   MOV A, M                                ; loop through player's data
     0x15fa: A7          |   ANA A                                   
     0x15fb: CA [FF 15]  |   JZ 0x15FF                               ; count only if nonzero
     0x15fe: 0C          |   INR C                                   ;     ... add to count in C
     0x15ff: 23          |   INX H                                   ; ... next one.
     0x1600: 05          |   DCR B                                   ; ... until B is 0 (55 repeats)
     0x1601: C2 [F9 15]  |   JNZ 0x15F9
     0x1604: 79          |   MOV A, C                                ; store count in A
     0x1605: 32 [82 20]  |   STA 0x2082                              ; and in 0x2082
     0x1608: FE [01]     |   CPI 0x01                                ; if more than 1 alien is left...
     0x160a: C0          |   RNZ                                     ; ... return; we're done.
     0x160b: 21 [6B 20]  |   LXI H, 0x206B                           ; otherwise set 0x206B to 1
     0x160e: 36 [01]     |   MVI M, 0x01
     0x1610: C9          |   RET

; name: getCurrentPlayerDataPtr
; places a pointer to the current player's data in HL.
; This will be either 0x2100 (player 1) or 0x2200 (player 2)

.getCurrentPlayerDataPtr
     0x1611: 2E [00]     |   MVI L, 0x00                    ; clear L
     0x1613: 3A [67 20]  |   LDA 0x2067                     ; look for current player (21 or 22)
     0x1616: 67          |   MOV H, A                       ; put it in H
     0x1617: C9          |   RET                            ; return

; ********************************** PLAYER SHOT GAME/DEMO SUBROUTINE *********************************
; --------------------------------------------------
;
; **** Player Shot Game/Demo Subroutine  ****
;
;    0x1618 - player fire handler entrypoint (runs at beginning of game loop)
;    0x1639 - checks for a first-time detection of player's fire command, starts shot
;    0x1648 - debounce: checks if fire button has been held
;    0x1652 - advance demo to next instruction
;
; -------------------------------------------------

; name: playerFireHandler [GAME/DEMO LOOPS]
; This is the first code to run in both the main game loop and the demo loop. It
;              * checks the player's health. If the player was shot, it returns
;              * Checks to sychronize with player's subroutine, although this goes first
;                0x2011 initializes to 0x80, and 0x2010 to 0x00. They are decremented 
;                during ISRs like a big-endian, 16-bit number, so 80 ticks (2 seconds).
;                This is the delay that prevents shooting/movement at beginning of round
;              * checks whether the player already has an active shot. If so, returns.
;              * checks game mode:
; *** in demo mode: simulates constant fire and then advances the demo instruction in 0x201D
; *** in game mode, handles player fire:
;              * checks player controls for the "fire" command.
;              * 0x202D set to either 0x01 (new "fire" detected) or 0x10 ("fire" held down)
;              * if this is the first time "fire" was pressed, starts new shot
;
.playerFireHandler 
     0x1618: 3A [15 20]  |   LDA 0x2015                               ; does 0x2015 == 0xFF (clear: shot hit player)?
     0x161b: FE [FF]     |   CPI 0xFF                                 ; ... if not
     0x161d: C0          |   RNZ                                      ; ... return
     0x161e: 21 [10 20]  |   LXI H, 0x2010                            ; load 0x2010
     0x1621: 7E          |   MOV A, M                                 ; put it in A
     0x1622: 23          |   INX H                                    ; load 0x2011
     0x1623: 46          |   MOV B, M                                 ; put it in B
     0x1624: B0          |   ORA B                                    ; is either one set?
     0x1625: C0          |   RNZ                                      ; return if so (blocks shot at beginning of round)
     0x1626: 3A [25 20]  |   LDA 0x2025                               ; if both are zero, continue
     0x1629: A7          |   ANA A                                    ; ... has the player fired a shot?
     0x162a: C0          |   RNZ                                      ; if shot is active, return
     0x162b: 3A [EF 20]  |   LDA 0x20EF                               ; check game mode
     0x162e: A7          |   ANA A                                    ; if it's clear,
     0x162f: CA [52 16]  |   JZ 0x1652                                ; this is the demo -> advanceDemo
     0x1632: 3A [2D 20]  |   LDA 0x202D                               ; was there a very recent shot
     0x1635: A7 [C2 48]  |   ANA A                                    ;    ... if yes, let's see if fire is still held
     0x1636: C2 [48 16]  |   JNZ 0x1648                               ;    ... -> checkFireButtonHeld

; name: _checkPlayerFire
; this code checks for a first-time detection of the player's fire command. If detected, starts
; a new shot by setting the flag at 0x2025 and sets the status variable at 0x202D to 0x01
;
._checkPlayerFire
     0x1639: CD [C0 17]  |   CAL 0x17C0                               ; A <- current player controls
     0x163c: E6 [10]     |   ANI 0x10                                 ; restrict to "fire" bit
     0x163e: C8          |   RZ                                       ; if clear, return
     0x163f: 3E [01]     |   MVI A, 0x01
     0x1641: 32 [25 20]  |   STA 0x2025                               ; otherwise, start new shot
     0x1644: 32 [2D 20]  |   STA 0x202D                               ; and set recent shot flag to 0x01
     0x1647: C9          |   RET                                      ; and return

; name: _checkFireButtonHeld
; Checks the current player's controls (in either port 1 or port 2) and checks bit 4 to see if the
; fire bit is currently set. If not, nothing to do here.
; if it's still pressed, this is now considered the fire button being "held" and the 
; status variable at 0x202D is set to 0x10
;
._checkButtonHeld
     0x1648: CD [C0 17]  |   CAL 0x17C0                               ; read current player controls
     0x164b: E6 [10]     |   ANI 0x10                                 ; is fire button still pressed? 
     0x164d: C0          |   RNZ                                      ; ... if so, return
     0x164e: 32 [2D 20]  |   STA 0x202D                               ; otherwise, put 0x10 in 0x202D
     0x1651: C9          |   RET                                      ; and return

; name: _advanceDemo
; Portion of the playerFireHandler that loops pointer from 1F74 - 1F74, dereferences and places
; instruction there in 201D (variable that holds next demo instruction)
; this also simulates constant player fire by setting 0x2025

._advanceDemo
     0x1652: 21 [25 20]  |   LXI H, 0x2025                            ; set new shot fired
     0x1655: 36 [01]     |   MVI M, 0x01
     0x1657: 2A [ED 20]  |   LHLD 0x20ED                              ; grab pointer at 20ED & 20EE
     0x165a: 23          |   INX H                                    ; increase HL pointer by 1
     0x165b: 7D          |   MOV A, L                                 ; if we've passed xx7E
     0x165c: FE [7E]     |   CPI 0x7E                                 ;    ... it's time to wrap around
     0x165e: DA [63 16]  |   JC 0x1663
     0x1661: 2E [74]     |   MVI L, 0x74                              ;    ... so restore 0x74 to L
     0x1663: 22 [ED 20]  |   SHLD 0x20ED                              ; store new pointer back at 20ED & 20EE
     0x1666: 7E          |   MOV A, M                                 ; dereference the pointer into A
     0x1667: 32 [1D 20]  |   STA 0x201D                               ; and put that value at 201D
     0x166a: C9          |   RET                                      ; ... and return

; name: setCarry_utility
; This is used above as a utility in the function that checks to see if the invaders have reached
; a line along the edge. It sets carry and returns if one of them has.

.setCarry_utility
     0x166b: 37          |   STC
     0x166c: C9          |   RET

; ******************************** GAME OVER SUBROUTINE ***********************************

; ------------------------------------------------------------------
;
; **** Game Over Subroutine ****
;
;    0x166D - calls 0x1A8B to set remaining lives count to 0
;    0x1671 - indicate death by setting player status to 0 (either 0x20E7/20E8)
;    0x1676 - check if high score exceeds previous high
;    0x168F - update high score with new value
;    0x169F - print player-specific "game over" message. Resumes game if
;             player is still alive
;    0x16C9 - game over handler: prints game over, turns off game mode, rejoins splash
;    0x16e6 - process player loss when invaders reach bottom. Exits midscreen ISR
;             by clearing the stack, turns off audio and enters the player loss
;             handler at 0x1671 
;
; ---------------------------------------------------------------------

; name: handlePlayerLoss
; if a player has no more lives left, game processing will jump here to process a game over.
; This happens as control exits the player's game object to reset the game. 
; here we set the digit displaying the number of lives remaining to '0', then fall into the
; playerLossReset function below.

.handlePlayerLoss
     0x166d: AF          |   XRA A
     0x166e: CD [8B 1A]  |   CAL 0x1A8B                               ; change remaining lives digit to '0'

; name: playerLossReset
; This routine handles exiting a losing player's game if one of the invaders has reached the bottom of the screen.
; Broadly, it writes the appropriate game over message(s), updates the score if necessary, and checks if the other
; player is still alive. If not, it moves into the single-player "game over" routine. If so, it loops back to the
; "player switch" portion of the main game loop.

.playerLossReset     
     0x1671: CD [10 19]  |   CAL 0x1910                               ; returns HL = 20E7 if p1, 20E8 if p2
     0x1674: 36 [00]     |   MVI M, 0x00                              ; set current player status to "dead"

; name: _compareHighScoreMSB
; Here we check if the player's MSB is greater than the high score and direct accordingly

._compareHighScoreMSB
     0x1676: CD [CA 09]  |   CAL 0x09CA                               ; point to current player's score
     0x1679: 23          |   INX H                                    ; move to MSB
     0x167a: 11 [F5 20]  |   LXI D, 0x20F5                            ; 
     0x167d: 1A          |   LDAX D                                   ; .... compare to high score MSB (A)
     0x167e: BE          |   CMP M                                    ; .... greater player score sets carry
     0x167f: 1B          |   DCX D
     0x1680: 2B          |   DCX H
     0x1681: 1A          |   LDAX D                                   ; grab high score LSB
     0x1682: CA [8B 16]  |   JZ 0x168B                                ; MSBs are the same. Let's look at LSBs
     0x1685: D2 [98 16]  |   JNC 0x1698                               ; high score greater -> no change
     0x1688: C3 [8F 16]  |   JMP 0x168F                               ; player score greater -> update high score

; name _compareHighScoreLSB
; if necessary we check if the player's LSB is greater than the high score LSB

._compareHighScoreLSB
     0x168b: BE          |   CMP M                                    ; compare to high score LSB (A)
     0x168c: D2 [98 16]  |   JNC 0x1698                               ; high score greater -> no change

; name: _updateHighScore
; if the player's score is greater than pre-existing high score, update the high score

._updateHighScore
     0x168f: 7E          |   MOV A, M                                 ; put player score LSB into A
     0x1690: 12          |   STAX D                                   ; ... and store as high score LSB
     0x1691: 13          |   INX D
     0x1692: 23          |   INX H
     0x1693: 7E          |   MOV A, M                                 ; put player score MSB into A
     0x1694: 12          |   STAX D                                   ; ... and store as high score MSB
     0x1695: CD [50 19]  |   CAL 0x1950                               ; write high score
     0x1698: 3A [CE 20]  |   LDA 0x20CE                               ; load number of players (0 = 1 player, 1 = 2 players)
     0x169b: A7          |   ANA A
     0x169c: CA [C9 16]  |   JZ 0x16C9                                ; single player game... jump to gameOverHandler

; name: _checkPlayerForGameOver
; We check which player is currently "on" in order to write the appropriate game over message
; Then write it to the screen in the form of "GAME OVER PLAYER<X>" with the correct X

._checkPlayerForGameOver
     0x169f: 21 [03 28]  |   LXI H, 0x2803 
     0x16a2: 11 [A6 1A]  |   LXI D, 0x1AA6                            ; point DE to "GAME OVER PLAYER < >" message
     0x16a5: 0E [14]     |   MVI C, 0x14                              ; set length of message
     0x16a7: CD [93 0A]  |   CAL 0x0A93                               ; write message with delay
     0x16aa: 25          |   DCR H
     0x16ab: 25          |   DCR H                                    ; point HL at position for number
     0x16ac: 06 [1B]     |   MVI B, 0x1B                              ; sprite code for "1"
     0x16ae: 3A [67 20]  |   LDA 0x2067                               ; who is the current player?
     0x16b1: 0F          |   RRC
     0x16b2: DA [B7 16]  |   JC 0x16B7                                ; player 1? jump to _addPlayerNumber

._player2GameOver
     0x16b5: 06 [1C]     |   MVI B, 0x1C                              ; if player 2, sprite code for "2"

._addPlayerNumber
     0x16b7: 78          |   MOV A, B
     0x16b8: CD [FF 08]  |   CAL 0x08FF                               ; add appropriate number, 1 or 2, to message
     0x16bb: CD [B1 0A]  |   CAL 0x0AB1                               ; one second pause
     0x16be: CD [E7 18]  |   CAL 0x18E7                               ; is other player alive?
     0x16c1: 7E          |   MOV A, M
     0x16c2: A7          |   ANA A
     0x16c3: CA [C9 16]  |   JZ 0x16C9                                ; if player is not alive, game over handler
     0x16c6: C3 [ED 02]  |   JMP 0x02ED                               ; otherwise, resume game for new current player

; name: gameOverHandler
; Exits the game loop entirely and rejoins splash. This is called when player 1 loses in a single-player game
; Or once both players have lost in a two-player game. It can also be called directly from the VBLANK interrupt
; routine when the _TILT command has been triggered.

.gameOverHandler                                                 ; can reach from VBLANK interrupt / Tilt
     0x16c9: 21 [18 2D]  |   LXI H, 0x2D18                       ;   HL :: screen coordinates 
     0x16cc: 11 [A6 1A]  |   LXI D, 0x1AA6                       ;   DE :: message coordinates
     0x16cf: 0E [0A]     |   MVI C, 0x0A                         ;   C  :: message length
     0x16d1: CD [93 0A]  |   CAL 0x0A93                          ; write 'GAME OVER ' message
     0x16d4: CD [B6 0A]  |   CAL 0x0AB6                          ; pause loop: 80 ticks
     0x16d7: CD [D6 09]  |   CAL 0x09D6                          ; clear the game area
     0x16da: AF          |   XRA A
     0x16db: 32 [EF 20]  |   STA 0x20EF                          ; switch to demo mode (0x20EF = 0)
     0x16de: D3 [05]     |   OUT 0x05                            ; clear port 5 audio (fleet movement, UFO)
     0x16e0: CD [D1 19]  |   CAL 0x19D1                          ; set ISR status (enable game processing for demo)
     0x16e3: C3 [89 0B]  |   JMP 0x0B89                          ; enter splash loop at splashInsertCoin

; name: resetAfterPlayerLoss [MIDSCREEN ISR -> EXIT TO SCORE COMPARE / GAME OVER / SWITCH PLAYER]
; you can reach this when the invaders reach the bottom of the screen. Here we exit from 
; the midscreen ISR by resetting the stack, then turn on the "extended audio" bit until the death is processed

.resetAfterPlayerLoss
     0x16e6: 31 [00 24]  |   LXI SP, 0x2400                      ; clear the stack
     0x16e9: FB          |   EI                                  ; enable interrupts (this is an exit from MIDSCREEN ISR)                                  
     0x16ea: AF          |   XRA A
     0x16eb: 32 [15 20]  |   STA 0x2015                          ; clear 0x2015 (player is unhealthy/dead)

._waitForPlayerReset
     0x16ee: CD [D8 14]  |   CAL 0x14D8                          ; check if player's shot has hit something... handle
     0x16f1: 06 [04]     |   MVI B, 0x04                         ; 
     0x16f3: CD [FA 18]  |   CAL 0x18FA                          ; sound bit to port 3: turn on "extended audio"
     0x16f6: CD [59 0A]  |   CAL 0x0A59                          ; check player health. zero flag only for healthy player.
     0x16f9: C2 [EE 16]  |   JNZ 0x16EE                          ; player death -> loop until interrupts finish handling death

._resetAfterPlayerLoss
     0x16fc: CD [D7 19]  |   CAL 0x19D7                          ; turn off ISR game processing
     0x16ff: 21 [01 27]  |   LXI H, 0x2701 
     0x1702: CD [FA 19]  |   CAL 0x19FA                          ; erase all player "lives" remaining on screen
     0x1705: AF          |   XRA A
     0x1706: CD [8B 1A]  |   CAL 0x1A8B                          ; write 0 lives remaining on lower-left digit
     0x1709: 06 [FB]     |   MVI B, 0xFB                         ; put 0xFB in B. This will be the mask for port 3 audio
     0x170b: C3 [6B 19]  |   JMP 0x196B                          ; ... so player death audio is turned off
                                                                 ; this then jumps to compare scores/game over/switch player routine

; ---------------------------------------------
;
; Invader Shot Intervals
;
;    0x170E - look up the interval between invader shots in a table
;             that references the current player's score
;
; ----------------------------------------------

; name: shotTempoLookup [MAIN GAME LOOP]
; uses table to look upt the initial time between invader shots (30, 10, B or 8)
; puts into 0x20CF (the new shot start timer)
; scores less than or equal to 200 -> 30
;                              1000 -> 10
;                              2000 -> 0B
;                              3000 -> 08
;                              3000+ -> 07

.shotTempoLookup                                            
     0x170e: CD [CA 09]  |   CAL 0x09CA                     ; point to current player's score
     0x1711: 23          |   INX H
     0x1712: 7E          |   MOV A, M                       ; put MSB in A
     0x1713: 11 [B8 1C]  |   LXI D, 0x1CB8                  ; point DE to 1CBB
     0x1716: 21 [A1 1A]  |   LXI H, 0x1AA1                  ; point HL to 1AA1 
     0x1719: 0E [04   ]  |   MVI C, 0x04                    ; put 4 in C
     0x171b: 47          |   MOV B, A                       ; put score MSB in B
     0x171c: 1A          |   LDAX D                         ; 
     0x171d: B8          |   CMP B                          ; is the score MSB (B) less than or equal to (DE)?
                                                            ; (DE): 2 -> 10 -> 20 -> 30
     0x171e: D2 [27 17]  |   JNC 0x1727                     ; yes. jump.
     0x1721: 23          |   INX H                          ; otherwise.. try the next one. HL keeps pace
     0x1722: 13          |   INX D                          ; increment DE
     0x1723: 0D          |   DCR C                          ; loop control.. only do 4 times, 
     0x1724: C2 [1C 17]  |   JNZ 0x171C
     0x1727: 7E          |   MOV A, M                       ; grab corresponding byte at HL: 30 -> 10 -> 0B -> 8
                                                            ; or 7 for greater than MSB of 30
     0x1728: 32 [CF 20]  |   STA 0x20CF                     ; and put it 0x20CF (new shot start timer)
     0x172b: C9          |   RET

; ---------------------------------------------
;
; **** PLAYER SHOT AUDIO ****
;
;    0x172C - turns off player shot audio
;    0x1739 - turns on player shot audio
;
; ----------------------------------------------


.turnOffShotAudio
     0x172c: 3A [25 20]  |   LDA 0x2025                     ; load current player shot status
     0x172f: FE [00]     |   CPI 0x00                       ; 
     0x1731: C2 [39 17]  |   JNZ 0x1739                     ; is there an active shot? (if yes, jump)
     0x1734: 06 [FD]     |   MVI B, 0xFD                    ; set B to 0xFD (set all bits but 1)
     0x1736: C3 [DC 19]  |   JMP 0x19DC                     ; turn off bit 1 (shot audio), send out on port 3

._playerShotAudioOn
     0x1739: 06 [02]     |   MVI B, 0x02
     0x173b: C3 [FA 18]  |   JMP 0x18FA                     ; sound out port 3; turn on bit 1 (shot)

.__not_accessed__
     0x173e: 00          |   NOP
     0x173f: 00          |   NOP

; ----------------------------------------------
;
; **** HANDLE INVADER AUDIO SEQUENCE ****
; We reach this procedure at the top of the 'gameProcess' loop during game mode in VBLANK ISR.
; (this is skipped by demo/splash). Broadly we:
;         1. decrement current playback timer. If 0, turn invader sound off
;         2. check if the player is dying. If the player is dying, turn invader sound off and return
;         3. decrement the audio sequence timer. This encompasses both playback and wait.
;            As long as we haven't reached 0 yet, return here.
;         4. start a new invader sound. When the timer hits 0, we send audio buffer to port 5
;         5. check the number of invaders active. If they're all dead, stop port 5 audio and return.
;         6. Otherwise, reset timers and signal to change invader sound in the audio buffer
;         7. return
;
;    0x1740 - turn off invader audio when timer to keep playing hits 0
;    0x1747 - checks if the player is dying and turns off invader sequence if so
;    0x174E - decrement interval timer when player is not dying. Timer includes
;             both playback time and wait-between time
;    0x1753 - start new invader sound
;    0x1759 - End soud sequence if no invaders are left
;    0x1760 - reset invader sound timers. Indicate time to advance sound
;    0x176D - mask port 5 audio to kill invader sound sequence
;    0x1775 - advance invader audio sequence to next sound 
;    0x17AA - count down the audio playback when extra life is added
;
; ------------------------------------------------

; name: playInvaderSound [VBLANK ISR]
; This is plart of the gameProcessing procedure that runs during VBLANK when game processing is permitted.
; There are four separate sounds played for the invaders in sequence. Here we decrement a timer for
; the current audio output (in RAM at 0x209B). If we reach zero, we turn off the current sound.
; This then falls into checking the player status (below).

.playInvaderSound
     0x1740: 21 [9B 20]  |   LXI H, 0x209B                  ; timer to keep playing current invader sound (0x209b)
     0x1743: 35          |   DCR M                          ; ... decrease it
     0x1744: CC [6D 17]  |   CZ 0x176D                      ; ... when we're done turn off invaders' audio

; name: _checkPlayerStatus [VBLANK ISR]
; This loads 0x2068, which is clear when the player is shot/dying. Here we turn off port 5 audio
; (the invaders sequence) when the player is dying. (The player's death part of the port 3 output)

._checkPlayerStatus
     0x1747: 3A [68 20]  |   LDA 0x2068                     ; load player status (dying if 0)
     0x174a: A7          |   ANA A
     0x174b: CA [6D 17]  |   JZ 0x176D                      ; if dying... turn off port 5 audio and return

; name: _waitBetweenSounds [VBLANK ISR]
; If the player is not dying, decrement the wait timer. This timer encompasses both the time the 
; invader sound plays and the downtime in between sounds. The value in this timer is loaded from
; a table in the ROM and depends on the number of invaders remaining on the screen.
; When this timer has not yet reached 0, we return and a new sound is not turned on.

._waitBetweenSounds
     0x174e: 21 [96 20]  |   LXI H, 0x2096                  ; point to timer for current invader sound
     0x1751: 35          |   DCR M                          ; decrease it
     0x1752: C0          |   RNZ                            ; return if not zero.. we're done

; name: _startNewInvaderSound [VBLANK ISR]
; If we have finished the full countdown for audio playback time + wait time (0x2096), this 
; procedure starts a new sound in the invader audio sequence.
; This loads the port 5 audio buffer and sends it out on port 5.

._startNewInvaderSound
     0x1753: 21 [98 20]  |   LXI H, 0x2098                  ; load the port 5 audio buffer
     0x1756: 7E          |   MOV A, M
     0x1757: D3 [05]     |   OUT 0x05                       ; send it out to port 5

; name: _noInvadersStopSound [VBLANK ISR]
; If we have reached here, we have just sent out the latest audio in the invader audio sequence.
; Here we stop and check to see if it's time to can the audio completely because the invaders
; have all been killed.
; If none remain on the screen, we turn off the invader audio (UFO can remain) and return

._noInvadersStopSound
     0x1759: 3A [82 20]  |   LDA 0x2082                     ; how many invaders are there?
     0x175c: A7          |   ANA A
     0x175d: CA [6D 17]  |   JZ 0x176D                      ; ... none! turn off port 5 audio and return

; name: _resetInvaderSound [VBLANK ISR]
; To reach here, we have completed the timing, and have just switched to a new invader audio, and loaded
; it into RAM. This resets the timers so that the new audio runs the appropriate amount of time.
; Here we also signal it's time to change sounds in the audio buffer, which preps the next sound in the
; invader audio sequence so it will be ready when the timers hit zero. (0x2095 is the signal)

._resetInvaderSound
     0x1760: 2B          |   DCX H                          ; point to 2097
     0x1761: 7E          |   MOV A, M
     0x1762: 2B          |   DCX H
     0x1763: 77          |   MOV M, A                       ; ... and copy into 0x2096
     0x1764: 2B          |   DCX H
     0x1765: 36 [01]     |   MVI M, 0x01                    ; and set 0x2095. It's time to switch sounds!
     0x1767: 3E [04]     |   MVI A, 0x04
     0x1769: 32 [9B 20]  |   STA 0x209B                     ; reset 0x209B to 4
     0x176c: C9          |   RET

; name: turnOffInvaderSound [VBLANK ISR]
; This is a utility function called to turn off whichever audio in the invader sequence is currently playing.

.turnOffInvaderSound
     0x176d: 3A [98 20]  |   LDA 0x2098                          ; load port 5 audio buffer

._maskPort5Audio
     0x1770: E6 [30]     |   ANI 0x30                            ; masks off port5 sound outside bits 4 & 5
     0x1772: D3 [05]     |   OUT 0x05                            ; ...only sound that may continue is UFO
     0x1774: C9          |   RET                                 ; 

; name: advanceInvaderAudio [MAIN GAME LOOP]
; When a player is healthy in the main game loop, we call this and change audio when the appropriate
; flag is set (0x2095) This also resets the countdown clock for invaders' audio

.advanceInvaderAudio
     0x1775: 3A [95 20]  |   LDA 0x2095                          ; check if time to advance invaders' audio
     0x1778: A7          |   ANA A                               ; no?
     0x1779: CA [AA 17]  |   JZ 0x17AA                           ; if zero, time down bit 4
     0x177c: 21 [11 1A]  |   LXI H, 0x1A11                       ; otherwise, point HL at 0x1A11 (sound delay table col 1)
     0x177f: 11 [21 1A]  |   LXI D, 0x1A21                       ; and point D at 0x1A21 (sound delay table col 2)
     0x1782: 3A [82 20]  |   LDA 0x2082                          ; load the remaining invaders' count into A
     0x1785: BE          |   CMP M                               ; is it greater than or equal to col1 value?
     0x1786: D2 [8E 17]  |   JNC 0x178E                          ; yes... jump
     0x1789: 23          |   INX H
     0x178a: 13          |   INX D
     0x178b: C3 [85 17]  |   JMP 0x1785                          ; otherwise, advance & keep looping until it is

; name: _soundDelayFound [MAIN GAME LOOP]
; pushes buffer for port 5 audio out, then sets next sound in sequence into the buffer.
; writes the new audio delay (set based on number of invaders) into 0x2097 and hten resets 
; the audio clock in 0x2095, which counts up.

._soundDelayFound
     0x178e: 1A          |   LDAX D                              ; DE now points to the delay from col 2
     0x178f: 32 [97 20]  |   STA 0x2097                          ; store it in 2097
     0x1792: 21 [98 20]  |   LXI H, 0x2098                       ; point HL at 0x2098 (port 5 audio buffer)
     0x1795: 7E          |   MOV A, M
     0x1796: E6 [30]     |   ANI 0x30                            ; we only care about the bottom 6 bits
     0x1798: 47          |   MOV B, A                            ; put it in B
     0x1799: 7E          |   MOV A, M                            ; and back in 0x2098
     0x179a: E6 [0F]     |   ANI 0x0F                            ; now mask off the upper nibble
     0x179c: 07          |   RLC                                 ; rotate left
     0x179d: FE [10]     |   CPI 0x10                            ; was sound 4 set?
     0x179f: C2 [A4 17]  |   JNZ 0x17A4                          ; no.. jump
     0x17a2: 3E [01]     |   MVI A, 0x01                         ; but if so, set it back to sound 0
     0x17a4: B0          |   ORA B                               ; all original bits (and new one) now in A
     0x17a5: 77          |   MOV M, A                            ; put in memory
     0x17a6: AF          |   XRA A
     0x17a7: 32 [95 20]  |   STA 0x2095                          ; clears the "time to update audio" indicator

; name: _extraLifeAudioCountdown [MAIN LOOP]
; this times down how long the extended play bit is left on (used in player death audio)
; when timer in 0x2099 hits 0, turn off bit 4 of port 3 (the extended play bit)
; note that this timer is only decremented when alien invader audio changes. So It's 0xFF times
; that interval

._extraLifeAudioCountdown
     0x17aa: 21 [99 20]  |   LXI H, 0x2099                       ; load extended audio timer 
     0x17ad: 35          |   DCR M                               ; is it 0?
     0x17ae: C0          |   RNZ                                 ; return if not.
     0x17af: 06 [EF]     |   MVI B, 0xEF                         ; if yes, turn off all port 3 sound
     0x17b1: C3 [DC 19]  |   JMP 0x19DC                          ; maskPort3Audio (and return)

.__not_accessed__                                                ; ? unclear why this is not touched
     0x17b4: 06 [EF 21]  |   MVI B, 0xEF                         ; it would have masked port 5 bit 4
     0x17b6: 21 [98 20]  |   LXI H, 0x2098                       ; which is the UFO hit audio
     0x17b9: 7E          |   MOV A, M
     0x17ba: A0          |   ANA B
     0x17bb: 77          |   MOV M, A
     0x17bc: D3 [05]     |   OUT 0x05
     0x17be: C9          |   RET
     0x17bf: 00          |   NOP

; ----------------------------------------------------------
;
; **** Check Player controls ****
;
;    0x17C0 - check player controls (checks player, jumps)
;    0x17C7 - check player 1 controls
;    0x17CA - check player 2 controls
;
; -----------------------------------------------------------

; name: checkPlayerControls
; Checks the controls in either port 1 or port 2 depending on the player, and returns
; with the results in the accumulator. Player controls share bits, except player 1's 
; come in through Port 1 and player 2's come in through Port 2
;
.checkPlayerControls
     0x17c0: 3A [67 20]  |   LDA 0x2067                     ; which is the current player?
     0x17c3: 0F          |   RRC                            ; .... player 1 sets carry
     0x17c4: D2 [CA 17]  |   JNC 0x17CA

; name: _player1Controls
; check player 1 controls in port 1 and leave result in accumulator
;
._player1Controls
     0x17c7: DB [01]     |   IN 0x01
     0x17c9: C9 [DB 02]  |   RET

; name: _player2Controls
; check player 2 controls in port 2 and leave results in accumulator
;
._player2Controls
     0x17ca: DB [02]     |   IN 0x02
     0x17cc: C9 [DB 02]  |   RET

; ---------------------------------------------------------------
;
; **** Process Tilt ****
;
;    0x17CD - poll for tilt command
;    0x17D2 - tilt command detected. check tilt flag & ignore if set
;    0x17D7 - process a new tilt command, reset stack (to exit ISR), clear play area
;    0x17EC - write "TILT" and pause
;    0x17FA - exit TILT subroutine to game over subroutine
;
; ---------------------------------------------------------------

; name: handleTilt [VBLANK ISR]
; this code polls for the _TILT command, which is essentially a fatal error as far as space invaders
; is concerned. It responds by ending the game and exiting ISR through the game-over routine

.handleTilt                                                      ; hits during VBLANK ISR
     0x17cd: DB [02]     |   IN 0x02                             ; read input port 2
     0x17cf: E6 [04]     |   ANI 0x04                            ; check bit 2 (command: _TILT)
     0x17d1: C8          |   RZ                                  ; command not triggered? return

; name: _tiltCommandDetected [VBLANK ISR]
; we get here if the _TILT command has actually been detected. Here we check to see if we 
; are still processing a previous _TILT by checking the RAM flag at 0x209A. 
; If so, we ignore and return.

._tiltCommandDetected [VBLANK ISR]
     0x17d2: 3A [9A 20]  |   LDA 0x209A                          ; check tilt flag. already triggered?
     0x17d5: A7          |   ANA A
     0x17d6: C0          |   RNZ                                 ; ... if yes, ignore this and return

; name: _processNewTilt [VBLANK ISR]
; we now know that the current _TILT command is new and not yet processed.
; We begin the process of exiting ISR through the tilt/game-over routine.
; Here we clear the stack, clear the game area, and set the RAM flag indicating a _TILT in progress

._processNewTilt
     0x17d7: 31 [00 24]  |   LXI SP, 0x2400                      ; reset stack
     0x17da: 06 [04]     |   MVI B, 0x04                         
     0x17dc: CD [D6 09]  |   CAL 0x09D6                          ; clear the game area (x4)
     0x17df: 05          |   DCR B
     0x17e0: C2 [DC 17]  |   JNZ 0x17DC                          ;    ... loop until B is 0
     0x17e3: 3E [01]     |   MVI A, 0x01
     0x17e5: 32 [9A 20]  |   STA 0x209A                          ; set tilt flag to 0x01
     0x17e8: CD [D7 19]  |   CAL 0x19D7                          ; lock ISR processing (no game tasks)
     0x17eb: FB          |   EI                                  ; enable interrupts

; name: _writeTiltAndPause [VBLANK ISR]
; This sets up parameters for the "TILT" message and calls the method for writing to the 
; screen without delays. Then enters a 1-second pause.

._writeTiltAndPause
     0x17ec: 11 [BC 1C]  |   LXI D, 0x1CBC                       ; start of the "TILT" message
     0x17ef: 21 [16 30]  |   LXI H, 0x3016                       ; screen coordinates: point cursor to 0x3016
     0x17f2: 0E [04]     |   MVI C, 0x04                         ; set message length
     0x17f4: CD [93 0A]  |   CAL 0x0A93                          ; write "TILT" message to screen
     0x17f7: CD [B1 0A]  |   CAL 0x0AB1                          ; 40-tick wait loop

; name: _exitTiltToGameOver [VBLANK ISR]
; Here is where we jump out of ISR to regular processing (note that stack was reset at 0x17D7
; AND interrupts were enabled at 0x17EB)

._exitTiltToGameOver
     0x17fa: AF          |   XRA A
     0x17fb: 32 [9A 20]  |   STA 0x209A                          ; clear tilt flag. processing done.                    
     0x17fe: 32 [93 20]  |   STA 0x2093                          ; clear waiting to start flag
     0x1801: C3 [C9 16]  |   JMP 0x16C9

; ------------------------------------------------------------------
;
;    **** handle UFO audio ****
;
;    0x1804 - handles normal UFO audio (sets/clears bit 0, port 3)
;
; -----------------------------------------------------------------

; name handleUFOAudio [MAIN GAME LOOP]
; This handles the normal UFO audio by setting or clearing bit 0 of port 3

.handleUFOAudio
     0x1804: 21 [84 20]  |   LXI H, 0x2084                       ; check if UFO is on screen
     0x1807: 7E          |   MOV A, M
     0x1808: A7          |   ANA A                               ; no? 
     0x1809: CA [07 07]  |   JZ 0x0707                           ; masks off UFO bit in port 3 audio & returns
     0x180c: 23          |   INX H                               ; otherwise point HL at 0x2085 (UFO hit)
     0x180d: 7E          |   MOV A, M
     0x180e: A7          |   ANA A                               ; has the UFO been hit?
     0x180f: C0          |   RNZ                                 ; yes. Return without repeating the sound
     0x1810: 06 [01]     |   MVI B, 0x01
     0x1812: C3 [FA 18]  |   JMP 0x18FA                          ; set the UFO audio bit and send out

; ------------------------------------------------------------
;
; **** Print Score Advance Table
;
;    0x1815 - top-level print procedure for score advance table,
;             loops through the sprites
;    0x1837 - print table loop - loops through table messages
;    0x1844 - write single table sprite (interprets table struct)
;    0x184C - write a single table message to screen (interprets table struct)
;    0x1856 - load registers from table struct, terminate loop when appropriate
;
; -------------------------------------------------------------

; name: printScoreAdvanceTable
; Writes the message "*SCORE ADVANCE TABLE*" and then prints the table itself.
; This uses a slightly different data structure and print mechanism. 
; For the table, the each table struct contains two 16-bit values:
;         * screenAddress (16-bits, will go in HL)
;         * contentPointer (16-bits, a pointer to the data in ROM)
; When the contentPointer is dereferenced, it must be interpreted for printing one of two ways:
;         * as a series of characters
;         * as a sprite
; This returns when all sprites are printed (carry set), then all messages (carry set again)
; loop control is in the load function at 0x1856, which sets carry when it hits 0xFF

.printScoreAdvanceTable
     0x1815: 21 [10 28]  |   LXI H, 0x2810 
     0x1818: 11 [A3 1C]  |   LXI D, 0x1CA3                       ; pointer to "*SCORE ADVANCE TABLE*"
     0x181b: 0E [15]     |   MVI C, 0x15                         ; 21 characters
     0x181d: CD [F3 08]  |   CAL 0x08F3                          ; .writeMessageNoDelay
     0x1820: 3E [0A]     |   MVI A, 0x0A
     0x1822: 32 [6C 20]  |   STA 0x206C                          ; store length: 10 decimal at 0x206C
     0x1825: 01 [BE 1D]  |   LXI B, 0x1DBE                       ; first point BC to 1DBE
     0x1828: CD [56 18]  |   CAL 0x1856                          ; loads 4 bytes pointed to by BC
     0x182b: DA [37 18]  |   JC 0x1837                           ; if FF: enter print table loop
     0x182e: CD [44 18]  |   CAL 0x1844                          ; otherwise write 16-byte sprites
     0x1831: C3 [28 18]  |   JMP 0x1828                          ; loop until we hit FF twice and return

.__not_accessed__                                                ; nothing jumps in here
     0x1834: CD [B1 0A]  |   CAL 0x0AB1                          ; this calls the one-second wait

; name: printTableLoop
; this is to print the character strings encoded by 4-byte pointer/pointer data
; structures. In the data here, the second pointer is to a string of charcter designations
; The carry flag is set by the load function if FF is the first byte, terminating the loop

.printTableLoop
     0x1837: 01 [CF 1D]  |   LXI B, 0x1DCF                       ; point BC to 1DCF
     0x183a: CD [56 18]  |   CAL 0x1856                          ; load registers from BC
     0x183d: D8          |   RC                                  ; return if first byte was FF
     0x183e: CD [4C 18]  |   CAL 0x184C                          ; writeTableMessage
     0x1841: C3 [3A 18]  |   JMP 0x183A                          ; loop until we're done, then return

; name: writeTableSprite
; This writes a sprite included in the "score-advance" table using pointer/pointer data
; structures referring to screen coordinates & data (see description at 0x1815). 
; When we get here, the screen coordinates should be in HL and the sprite data pointer in DE

.writeTableSprite
     0x1844: C5          |   PUSH B
     0x1845: 06 [10]     |   MVI B, 0x10                         ; length of sprite data
     0x1847: CD [39 14]  |   CAL 0x1439                          ; .writeSpriteNoShift
     0x184a: C1          |   POP B
     0x184b: C9          |   RET

; name: writeTableMessage
; This prints a string of characters of length (206C) to the screen at the address held in HL.
; The variable 0x206C is placed in C, and used to vary the string length for different tables.
;    * the default value is: 0x12
;    * for the 'score-advance' table, 206C is changed to 0x0A
; The address to the characters is held in DE

.writeTableMessage
     0x184c: C5          |   PUSH B
     0x184d: 3A [6C 20]  |   LDA 0x206C                          ; init 0x12 or 0x0A loaded at 0x1822
     0x1850: 4F          |   MOV C, A                            ; put it in C
     0x1851: CD [93 0A]  |   CAL 0x0A93                          ; writeMessageWithDelay
     0x1854: C1          |   POP B                               ; restore B
     0x1855: C9          |   RET

; name: loadRegistersFromBC
; dereferences BC and puts 4 bytes from the structure there into registers HL and DE. 
; little endianess is preserved, so the order is: L, H, E, D
; This is also used as a utility for loop control when using data from these structures.
; If the first byte of the structure is FF, it sets carry and returns without loading data

.loadRegistersFromBC
     0x1856: 0A          |   LDAX B                         ; load the first sprite value
     0x1857: FE [FF]     |   CPI 0xFF                       ; is it 0xFF? 
     0x1859: 37          |   STC                            ; if so,
     0x185a: C8          |   RZ                             ; ... we return with carry set
     0x185b: 6F          |   MOV L, A                       ; otherwise, L <- first byte
     0x185c: 03          |   INX B
     0x185d: 0A          |   LDAX B
     0x185e: 67          |   MOV H, A                       ; H <- second byte
     0x185f: 03          |   INX B
     0x1860: 0A          |   LDAX B
     0x1861: 5F          |   MOV E, A                       ; E <- third byte
     0x1862: 03          |   INX B
     0x1863: 0A          |   LDAX B                         ; D <- fourth byte
     0x1864: 57          |   MOV D, A
     0x1865: 03          |   INX B
     0x1866: A7          |   ANA A
     0x1867: C9          |   RET

; ---------------------------------------------------------------
;
; **** Splash Animation Helpers: ISR Animation ****
;
;    0x1868 - ISR splash processing (moves sprite)
;    0x1898 - flags animation complete
;
; ---------------------------------------------------------------

; name: processSplashAnimation [VBLANK]
; Sets up sprite in animation structure for ISR processor. These are simple animations that
; do not require complex game processing.
; The animation data structure is 12 bytes long, containing the following:
;         ** 20C2: sprite-switch counter
;         ** 20C3: encoded y-direction step
;         ** 20C4: encoded x-direction step
;         ** 20C5: current encoded y coord (updated here)
;         ** 20C6: current encoded x coord (updated here)
;         ** 20C7: next sprite pointer LSB
;         ** 20C8: next sprite pointer MSB
;         ** 20C9: sprite data length
;         ** 20CA: encoded x-axis (horizontal) target position
;         ** 20CB: target reached flag
;         ** 20CC: current sprite pointer LSB
;         ** 20CD: current sprite pointer MSB

.splashIndex2_ISR
     0x1868: 21 [C2 20]  |   LXI H, 0x20C2                       ; points HL to animation structure
     0x186b: 34          |   INR M                               ; move to next sprite
     0x186c: 23          |   INX H                               ; point HL at 20C3
     0x186d: 4E          |   MOV C, M                            ; setup, y offset in C
     0x186e: CD [D9 01]  |   CAL 0x01D9                          ; puts new position: 20c5 (y) / 20c6 (x)
     0x1871: 47          |   MOV B, A                            ; put 20c6 into B (x position)
     0x1872: 3A [CA 20]  |   LDA 0x20CA                          ; (init: 0x07)
     0x1875: B8          |   CMP B                               ; ... does new position == target (0x20CA)
     0x1876: CA [98 18]  |   JZ 0x1898                           ;    .. if so, set 0x20CB to 0x01
     0x1879: 3A [C2 20]  |   LDA 0x20C2                          ; load 0x20C2
     0x187c: E6 [04]     |   ANI 0x04                            ; only change sprite when bit 3 is set
     0x187e: 2A [CC 20]  |   LHLD 0x20CC                         ; either way, point HL at 0x20CC
     0x1881: C2 [88 18]  |   JNZ 0x1888                          
     0x1884: 11 [30 00]  |   LXI D, 0x0030                       ; ... not yet, load DE 
     0x1887: 19          |   DAD D                               ; ... and add to HL
     0x1888: 22 [C7 20]  |   SHLD 0x20C7                         ; and store at 0x20C7/20c8
     0x188b: 21 [C5 20]  |   LXI H, 0x20C5                       ; point HL at 0x20C5
     0x188e: CD [3B 1A]  |   CAL 0x1A3B                          ; load registers from there: E,D,L,H,B
     0x1891: EB          |   XCHG                                ; DE: adjusted alien coordinates
     0x1892: C3 [D3 15]  |   JMP 0x15D3                          ; shift position, write sprite, return

.__not_accessed__
     0x1895: 00          |   NOP
     0x1896: 00          |   NOP
     0x1897: 00          |   NOP

; name: animationTargetReached
; This is called when an animation handler has recognized that the final target is reached.
; It sets 0x20CB to 1. This is a data member of the animation structure. its role is to 
; flag when animation is complete.

.animationTargetReached
     0x1898: 3E [01]     |   MVI A, 0x01
     0x189a: 32 [CB 20]  |   STA 0x20CB                          ; set target reached
     0x189d: C9          |   RET

; ------------------------------------------------------------
;
; **** Splash Animation Helpers: Shoot Extra C ****
;
;    0x189E - splash loop animation handler for shooting extra C
;    0x18B8 - busy-wait for explosion to start
;    0x18C0 - busy-wait for explosion to end
;
; -------------------------------------------------------------

; name: animationSplashShootExtraC [SPLASH LOOP]
; This handles the shot animation by enabling enough game processing during ISR to use the final
; alien shot structure (the zigzag shot). This initializes the shot structure and waits for ISR
; to load it into the active shot buffer, then complete an explosion. 

.animationSplashShootExtraC
     0x189e: 21 [50 20]  |   LXI H, 0x2050                  ; beginning of 3rd alien shot data structure
     0x18a1: 11 [C0 1B]  |   LXI D, 0x1BC0                  ; point DE at 0x1BC0
     0x18a4: 06 [10]     |   MVI B, 0x10                    ; set B to 16
     0x18a6: CD [32 1A]  |   CAL 0x1A32                     ; reset the alien shot data structure from ROM
     0x18a9: 3E [02]     |   MVI A, 0x02
     0x18ab: 32 [80 20]  |   STA 0x2080                     ; set alien shot control to 0x02
     0x18ae: 3E [FF]     |   MVI A, 0xFF
     0x18b0: 32 [7E 20]  |   STA 0x207E                     ; Y offset for alien shots: -1 per cycle
     0x18b3: 3E [04]     |   MVI A, 0x04
     0x18b5: 32 [C1 20]  |   STA 0x20C1                     ; set ISR game processing to 0x04 (allows some shot processing)

._waitForExplosionStart
     0x18b8: 3A [55 20]  |   LDA 0x2055                     ; look at bit 0 (in active shot struct, this is 0x2073). 
     0x18bb: E6 [01]     |   ANI 0x01                       ;    ... is the shot exploding (bit 0 set)?
     0x18bd: CA [B8 18]  |   JZ 0x18B8                      ;    ... if not, check until it is set by ISR

._waitForExplosionEnd     
     0x18c0: 3A [55 20]  |   LDA 0x2055                     ; ... and now wait for 
     0x18c3: E6 [01]     |   ANI 0x01                       ; ... reset after
     0x18c5: C2 [C0 18]  |   JNZ 0x18C0                     ; ... explosion

._removeExtraC
     0x18c8: 21 [11 33]  |   LXI H, 0x3311                  ; point at extra C's coordinates
     0x18cb: 3E [26]     |   MVI A, 0x26                    ; code for " " (empty space)
     0x18cd: 00          |   NOP
     0x18ce: CD [FF 08]  |   CAL 0x08FF                     ; delete C by overwriting space
     0x18d1: C3 [B6 0A]  |   JMP 0x0AB6                     ; jump to 2-second wait loop (returns)

; ------------------------------------------------
;
; **** Game Init & RESET HELPERS ****
;
;    0x18D4 - initialize the Space Invaders game
;    0x18DF - set alien shot inverval and enter splash
;
;--------------------------------------------------

; initialize the space invaders game, beginning with the stack and the game variables.
; variables are housed in memory between 0x2000 and 0x20FF. Some, but not all of them,
; are initialized by values in the ROM from 0x1B00 to 0x1BFF

.gameInit
     0x18d4: 31 [00 24]  |   LXI SP, 0x2400                 ; initialize stack pointer: 0x2400
     0x18d7: 06 [00]     |   MVI B, 0x00                    ; set B to 0 so 256 bytes are copied
     0x18d9: CD [E6 01]  |   CAL 0x01E6                     ; Rom-to-Ram copy 1B00-1BFF -> 2000-20FF
     0x18dc: CD [56 19]  |   CAL 0x1956                     ; print high scores

; name: splash_playSpaceInvadersScreen
; begin the splash screen sequence by setting the alien shot interval to 0x08. 
; Then jump to 0x0AEA for further processing

.splash_playSpaceInvadersScreen
     0x18df: 3E [08]     |   MVI A, 0x08                    ; 
     0x18e1: 32 [CF 20]  |   STA 0x20CF                     ; set alien shot interval to 8
     0x18e4: C3 [EA 0A]  |   JMP 0x0AEA


; ----------------------------------------------------
;
; **** Helpers ****
;
;    0x18E7 - get the status (alive/not alive) of the other player
;    0x18F1 - increases the invaders' right-movement x-offset when
;              only 1 alien remains
;    0x18FA - sound out port 3 / port 3 audio buffer
;    0x1904 - point to player 2 data area and jump to reset p2 invaders array
;    0x190A - game loop control: check player shot. Init explosion or change offsets
;    0x1910 - get pointer to current player's status indicator
;
; ----------------------------------------------------

; name: getOtherPlayerStatusPointer
; points HL at the player 1 status variable if player 2, player 2 status variable if player 1
; If these are 1, the player in question is alive

.getOtherPlayerStatusPointer
     0x18e7: 3A [67 20]  |   LDA 0x2067
     0x18ea: 21 [E7 20]  |   LXI H, 0x20E7                  ; this will return 20E7 in HL for player 2
     0x18ed: 0F          |   RRC
     0x18ee: D0          |   RNC
     0x18ef: 23          |   INX H                          ; or 20E8 in HL for player 1
     0x18f0: C9          |   RET

; name: invaderRightOffsetHelper
; set right moving invader offset to 3 when there is only 1 left.

.invaderRightOffsetHelper
     0x18f1: 06 [02]     |   MVI B, 0x02                    ; right offset will be 2
     0x18f3: 3A [82 20]  |   LDA 0x2082                     ; ... unless there is only 1 invader left
     0x18f6: 3D          |   DCR A
     0x18f7: C0          |   RNZ
     0x18f8: 04          |   INR B                          ; in that case, A is now 3      
     0x18f9: C9          |   RET


; name: soundOutPort3
; Turns on additional audio bit(s) by "ORing" signal with the saved port 3 audio buffer
; in RAM at 0x2094. Then sends audio signal to output port 3
;         PORT 3 AUDIO BITS:
;              * 0: UFO 
;              * 1: player shot
;              * 2: player death
;              * 3: invader death
;              * 4: [instruction] extend audio
;              * 5: [instruction] enable
;
.soundOutPort3
     0x18fa: 3A [94 20]  |   LDA 0x2094                     ; port 3 sound buffer
     0x18fd: B0          |   ORA B                          ; set the bit in B
     0x18fe: 32 [94 20]  |   STA 0x2094                     ; and store
     0x1901: D3 [03]     |   OUT 0x03                       ; send out to port 3
     0x1903: C9          |   RET                            ; and return

; name: resetInvadersP2
; sets the array of invaders back to 1's for player 2. This is part of new game set / player 2 reset

.resetInvadersP2
     0x1904: 21 [00 22]  |   LXI H, 0x2200                  ; point HL at 0x2200 (player 2 data)
     0x1907: C3 [C3 01]  |   JMP 0x01C3                     ; reset invaders

; name: playerShotCheck [MAIN GAME & DEMO LOOPS]
; wrapper for function that initializes explosion when a player shot has hit an invader
; ** see 0x14D8 for more details
; then jumps to handling of invader movement. This changes per-step offsets when we are
;    (a) down to 1 alien 
;    (b) invaders have hit the edge and need to turn around
; ** see 0x1597 for more details
;
.playerShotCheck
     0x190a: CD [D8 14]  |   CAL 0x14D8                     ; initialize explosion if player shot hits
     0x190d: C3 [97 15]  |   JMP 0x1597                     ; change alien offsets if they've hit edges
                                                            ; or if we're down to one alien. Returns

; name: getPointerToPlayerStatus
; called during game over sequence (and award extra life) to get a pointer to the current player
; status indicator (20E7 = player 1, 20E8 = player 2)

.getPointerToPlayerStatus                                   ; returns with HL = 0x20E7 if p1, 0x20E8 if p2
     0x1910: 21 [E7 20]  |   LXI H, 0x20E7                  ; Point HL at 0x20E7
     0x1913: 3A [67 20]  |   LDA 0x2067                     ; get current player data page
     0x1916: 0F          |   RRC                            ; ... player 1 or 2?
     0x1917: D8          |   RC                             ; ... return if player 1
     0x1918: 23          |   INX H                          ; otherwise, point HL at 0x20E8
     0x1919: C9          |   RET


; ------------------------------------------------------
;
; **** Score & Credit Utilities ****
;
;    0x191A - write high score title
;    0x1925 - print player 1 score
;    0x192B - print player 2 score
;    0x1931 - load registers from score structure, jump to write BCD
;    0x193C - write "CREDIT"
;    0x1947 - display credit balance
;    0x1950 - write high score
;    0x1956 - print titles and all three scores
;
; ------------------------------------------------------

; name: writeHighScoreTitle
; at 0x1922, jumps to code that actually adds the message sprites to memory

.writeHighScoreTitle
     0x191a: 0E [1C]     |   MVI C, 0x1C                    ; load length of message
     0x191c: 21 [1E 24]  |   LXI H, 0x241E                  ; initial screen coordinates
     0x191f: 11 [E4 1A]  |   LXI D, 0x1AE4                  ; address of message in ROM
     0x1922: C3 [F3 08]  |   JMP 0x08F3

; name: printPlayer1Score
; points HL at 0x20F8, RAM address for P1 score variable.
; jumps to 0x1931 for the actual score-writing.

.printPlayer1Score
     0x1925: 21 [F8 20]  |   LXI H, 0x20F8                  ; RAM coords for player 1 score
     0x1928: C3 [31 19]  |   JMP 0x1931

; printPlayer2Score
; points HL at 0x20FC, RAM address for P2 score variable
; jumps to 0x1931 for the actual score writing

.printPlayer2Score
     0x192b: 21 [FC 20]  |   LXI H, 0x20FC                  ; RAM coords for player 2 score
     0x192e: C3 [31 19]  |   JMP 0x1931

; name: loadRegistersScoreStruct
; loads registers from a score structure. 
; ** DE receives the first 16 bits. This should be the score, in binary-coded decimal
; ** HL is modified to hold the second 16 bits. This should be the screen coordinates
; At 0x1939, jumps to routine that writes the score to video memory 

.loadRegistersScoreStruct
     0x1931: 5E          |   MOV E, M
     0x1932: 23          |   INX H
     0x1933: 56          |   MOV D, M
     0x1934: 23          |   INX H
     0x1935: 7E          |   MOV A, M
     0x1936: 23          |   INX H
     0x1937: 66          |   MOV H, M
     0x1938: 6F          |   MOV L, A
     0x1939: C3          |   JMP 0x09AD                     ; jump to writeUpdatedScore (the BCD digits)

; name: writeCreditMessage
; writes "CREDIT" to the bottom right corner of the screen by putting 
; screen coordinates in HL and coordinates of the message in DE

.writeCreditMessage
     0x193c: 0E [07]     |   MVI C, 0x07
     0x193e: 21 [01 35]  |   LXI H, 0x3501 
     0x1941: 11 [A9 1F]  |   LXI D, 0x1FA9                       ; 7 letter message at 1FA9 ('CREDIT')
     0x1944: C3 [F3 08]  |   JMP 0x08F3                          ; write message no delay

; name: displayCreditBalance
; converts a series of four binary-coded decimal digits into indices for the numeric
; digit sprites and prints them at the screen address in HL

.displayCreditBalance
     0x1947: 3A [EB 20]  |   LDA 0x20EB                          ; load the credit balance
     0x194a: 21 [01 3C]  |   LXI H, 0x3C01                       ; point HL at video memory location
     0x194d: C3 [B2 09]  |   JMP 0x09B2                          ; jump to displayBCDNums, returns

; name: writeHighScore
; points HL at 0x20F4, RAM address for high-score variable
; jumps to 0x1931 for the actual score writing

.writeHighScore
     0x1950: 21 [F4 20]  |   LXI H, 0x20F4 
     0x1953: C3 [31 19]  |   JMP 0x1931                          ; load registers from memory: E,D,H,L

; name: printHiScores
; writes " SCORE<1> HI-SCORE SCORE<2> " near the top of the screen
; as well as the 4-digit scores themselves.
; Also writes "CREDIT " and prints the current credit balance in the bottom right.

.printHiScores
     0x1956: CD [5C 1A]  |   CAL 0x1A5C                     ; clear video memory, set to 0s
     0x1959: CD [1A 19]  |   CAL 0x191A                     ; prints " score<1> hi-score score<2> "
     0x195c: CD [25 19]  |   CAL 0x1925                     ; prints player 1 score ("0000" for init) --> 0x20F8, 0x20F9
     0x195f: CD [2B 19]  |   CAL 0x192B                     ; prints player 2 score ("0000" for init) --> 0x20FC, 0x20FD
     0x1962: CD [50 19]  |   CAL 0x1950                     ; prints high score ("0000" for init) --> 0x20F4, 0x20F5
     0x1965: CD [3C 19]  |   CAL 0x193C                     ; prints "CREDIT "
     0x1968: C3 [47 19]  |   JMP 0x1947                     ; jump to displayCreditBalance

; --------------------------------------------------
;
; **** Handle Player Loss Utilities ****
;
;    0x196B - mask off port 3 audio
;    0x1971 - invaders have reached bottom. set flag and jump to exit ISR
;
; --------------------------------------------------

; name: _maskPort3Audio
; masks off port 3 audio to just bits set in B. This is called during the reset after player loss
; to turn off the "player death" sound

._maskPort3Audio
     0x196b: CD [DC 19]  |   CAL 0x19DC                     ; mask off port 3 audio
     0x196e: C3 [71 16]  |   JMP 0x1671                     ; handles update score, game over, or let opponent finish game

; name: handleInvaderWin
; invaders won the round by reaching the bottom of the screen

.handleInvaderWin [MIDSCREEN ISR]
     0x1971: 3E [01]     |   MVI A, 0x01                    ; here we set 0x206D to 1
     0x1973: 32 [6D 20]  |   STA 0x206D
     0x1976: C3 [E6 16]  |   JMP 0x16E6                     ; and jump to 0x16E6

; ------------------------------------------------------
;
; Pre-Start housekeeping utilities
;
;    0x1979 - displays credit balance and turns off game processing
;    0x1982 - set splash processing flag (0x20C1) to whichever value is in A
;    0x1988 - utility: jump to clear game area
;
; ---------------------------------------------------------

; name: preStartHousekeeping
; This is the first thing that happens as we exit ISR and enter wait-to-start. 
; The procedure turns off game processing in ISR and calls for credit-related

.preStartHousekeeping                                       ; turns off game processing & displays credit balance
     0x1979: CD [D7 19]  |   CAL 0x19D7                     ; turns off interrupt game processing
     0x197c: CD [47 19]  |   CAL 0x1947                     ; displays credit balance (in BCD digits)
     0x197f: C3 [3C 19]  |   JMP 0x193C                     ; prints "CREDIT" to screen

; name: setSplashProcessing
; Sets different processing capabilities for splash animation processing sequence by setting 
; the byte at 0x20C1 to the value that is in the accumulator. Settings are based on 1st bit set.
;    ** 0 (clear) - set at the top of the splash loop. No ISR processing.
;    ** 1 (bit 0) - set for the game demo. The most ISR processing afforded to a splash module.
;    ** 2 (bit 1) - ISR processing to animate a sprite
;    ** 4 (bit 2) - ISR processing to animate an invader's shot (used to shoot extra 'C')

.setSplashProcessing
     0x1982: 32 [C1 20]  |   STA 0x20C1                     ; put accumulator in 20C1
     0x1985: C9          |   RET

.__not_accessed__                                           ; not clear what this is. Maybe an artifact
     0x1986: 8B                                             ; as a pointer, this is to the
     0x1987: 19                                             ; unused 'TAITO CORPORATION' message

.jumpto_ClearGameArea
     0x1988: C3 [D6 09]  |   JMP 0x09D6

.__not_accessed__                                           ; this would print "TAITO CORPORATION" to screen
     0x198b: 21 [03 28]  |   LXI H, 0x2803                  ; set screen coordinates
     0x198e: 11 [BE 19]  |   LXI D, 0x19BE                  ; set message coordinates
     0x1991: 0E [13]     |   MVI C, 0x13
     0x1993: C3 [F3 08]  |   JMP 0x08F3                     ; .writeMessageNoDelay
     0x1996: 00          |   NOP
     0x1997: 00          |   NOP
     0x1998: 00          |   NOP
     0x1999: 00          |   NOP

; name: printSecretMessage
; prints the message "TAITO COP" during the demo if two sequences of keys are pressed, one after another.
; the first set of keys that should be pressed together is: bit 1, bit 5, bit 6, bit 7 (_START2PLAYER, _FIRE1, _LEFT1, _RIGHT1)
; _START1PLAYER should not be pressed during the first sequence
; the second set of keys that should be pressed together is: bit 2, bit 4, bit 5 (_START1PLAYER, _FIRE1, _LEFT1)
; _START2PLAYER and _RIGHT1 should not be pressed during the second sequence

.printSecretMessage
     0x199a: 3A [1E 20]  |   LDA 0x201E                     ; check 0x201E
     0x199d: A7          |   ANA A                          ; ... if we've detected the first key sequence
     0x199e: C2 [AC 19]  |   JNZ 0x19AC                     ; ... jump past detecting it

._checkFirstSequence
     0x19a1: DB [01]     |   IN 0x01                        ; check port 1 input
     0x19a3: E6 [76]     |   ANI 0x76                       ; mask to these bits:       . x x x . x x .
     0x19a5: D6 [72]     |   SUI 0x72                       ; subtract correct pattern  . x x x . . x .
     0x19a7: C0          |   RNZ                            ; if bits 4, 5, 6 and 1 are set, will be zero
     0x19a8: 3C          |   INR A                          ; set A to 0x01
     0x19a9: 32 [1E 20]  |   STA 0x201E                     ; and put in 0x201E (1st sequence detected)

._checkSecondSequence                                       
     0x19ac: DB [01]     |   IN 0x01                        ; check port 1 input
     0x19ae: E6 [76]     |   ANI 0x76                       ; mask to these bits:       . x x x . x x .
     0x19b0: FE [34]     |   CPI 0x34                       ; subtract correct pattern  . . x x . x . .
     0x19b2: C0          |   RNZ                            ; return if nonzero
     0x19b3: 21 [1B 2E]  |   LXI H, 0x2E1B                  ; 0x2E1B in HL (screen position)
     0x19b6: 11 [F7 0B]  |   LXI D, 0x0BF7                  ; pointer to code for sprites: "TAITO COP" 
     0x19b9: 0E [09]     |   MVI C, 0x09                    ; length of message
     0x19bb: C3 [F3 08]  |   JMP 0x08F3                     ; .writeMessageNoDelay

.taitoMessage
     0x19be: 28                                             ; message:     '*'
     0x19bf: 13                                             ;              'T'
     0x19c0: 00                                             ;              'A'
     0x19c1: 08                                             ;              'I'
     0x19c2: 13                                             ;              'T'
     0x19c3: 0E                                             ;              'O'
     0x19c4: 26                                             ;              ' '
     0x19c5: 02                                             ;              'C'
     0x19c6: 0E                                             ;              'O'
     0x19c7: 11                                             ;              'R'
     0x19c8: 0F                                             ;              'P'
     0x19c9: 0E                                             ;              'O'
     0x19ca: 11                                             ;              'R'
     0x19cb: 00                                             ;              'A'
     0x19cc: 13                                             ;              'T'
     0x19cd: 08                                             ;              'I'
     0x19ce: 0E                                             ;              'O'
     0x19cf: 0D                                             ;              'N'
     0x19d0: 28                                             ;              '*'

; ----------------------------------------------------
;
; **** Toggle ISR Game Processing ****
;
;    0x19D1 - enable ISR processing
;    0x19D3 - toggle ISR processing utility
;    0x19D7 - disable ISR processing
;
; ----------------------------------------------------

; name: enableInterruptProcessing
; unlocks ISR processing so that both game or splash may proceed as appropriate. 
; This happens when the game is done resetting for a new round, for example

.enableInterruptProcessing
     0x19d1: 3E [01 32]  |   MVI A, 0x01 

; name: toggleISR
; both disable/enable setters end here so data can be saved to the RAM variable
; at 0x20E9 (Procedure then returns)

.toggleISR                                                  ; clearing 20E9 causes ISR to exit 
                                                            ; without game processing
     0x19d3: 32 [E9 20]  |   STA 0x20E9                     ; setting it permits game processing
     0x19d6: C9 [AF C3]  |   RET

; name: disableInterruptProcessing
; Locks interrupt processing so that game objects are not touched by anything
; until the primary thread has completed its work. Used for resetting the game.

.disableInterruptProcessing
     0x19d7: AF [C3 D3]  |   XRA A
     0x19d8: C3 [D3 19]  |   JMP 0x19D3

     0x19db: 00 [3A 94]  |   NOP

; ----------------------------------------------------------
;
; **** Turn off port 3 audio ****
;
;    0x19DC - mask off port 3 audio / buffer (mask in B)
;
; ----------------------------------------------------------

; name: maskPort3Audio
; mask port 3 audio to bits set in B

.maskPort3Audio
     0x19dc: 3A [94 20]  |   LDA 0x2094                          ; load byte saved for sound (port 3)
     0x19df: A0 [32 94]  |   ANA B                               ; mask in B
     0x19e0: 32 [94 20]  |   STA 0x2094                          ; store back at 2094
     0x19e3: D3 [03 C9]  |   OUT 0x03                            ; and send out on port 3
     0x19e5: C9 [21 01]  |   RET


; ----------------------------------------------------------
;
; **** Handle Remaining Lives ****
;
;    0x19E6 - draws the remaining "ship" sprites indicating player's "lives"
;    0x19FA - erase a "used" life
;
; -----------------------------------------------------------

; name: drawRemainingLives
; writes "ship" sprites to screen in the lower-left portion of the screen, representing
; the number of lives a player has remaining

.drawRemainingLives
     0x19e6: 21 [01 27]  |   LXI H, 0x2701 
     0x19e9: CA [FA 19]  |   JZ 0x19FA                      ; zero lives remaining? skip forward
     0x19ec: 11 [60 1C]  |   LXI D, 0x1C60                  ; point D at player sprite
     0x19ef: 06 [10]     |   MVI B, 0x10                    ; put 16 in B
     0x19f1: 4F          |   MOV C, A                       ; put sprite count in C
     0x19f2: CD [39 14]  |   CAL 0x1439                     ; .writeSpriteNoShift (B is loop control)
     0x19f5: 79          |   MOV A, C
     0x19f6: 3D          |   DCR A                          ; decrement...
     0x19f7: C2 [EC 19]  |   JNZ 0x19EC                     ; do this until we reach zero lives
                                                            ; then fall into _eraseUsedLife

; name: _eraseUsedLife
; This clears a space immediately to the right of the ship-sprites that depict "lives"
; It effectively removes a previous "life" that could have been present.
; It begins to the right of the sprites representing "lives" (which begins at 0x2701) and continues
; in x direction, concluding a bit past midscreen at 0x3501 (should not overwrite "CREDIT")

._eraseUsedLife                                             ; clears 1 byte line up to column 0x35
     0x19fa: 06 [10]     |   MVI B, 0x10                    ; set B to 0x10 (16)
     0x19fc: CD [CB 14]  |   CAL 0x14CB                     ; draw clear line of length B
     0x19ff: 7C          |   MOV A, H                       ; put H in A
     0x1a00: FE [35]     |   CPI 0x35                       ; is it 0x35?
     0x1a02: C2 [FA 19]  |   JNZ 0x19FA                     ; no? repeat drawing 16-byte lines until it is
     0x1a05: C9          |   RET


; --------------------------------------------------------
;
; **** Task Filter ****
;
;    0x1A06 - check if we are on correct half of screen for current interrupt
;
; --------------------------------------------------------

; name: taskFilter [ISR]
; This runs to block processing on the incorrect half of the screen during either Midscreen or Vblank ISR

.taskFilter                                                 ; make sure the task runs during correct ISR
     0x1a06: 21 [72 20]  |   LXI H, 0x2072                  ; load screenDrawStatus into B
     0x1a09: 46 [1A E6]  |   MOV B, M
     0x1a0a: 1A [E6 80]  |   LDAX D                         ; put byte from DE into accumulator
     0x1a0b: E6 [80 A8]  |   ANI 0x80                       ; mask most significant bit
     0x1a0d: A8 [C0 37]  |   XRA B                          ; do screenDrawStatus and byte from DE share MSB?
     0x1a0e: C0 [37 C9]  |   RNZ                            ;    ... no. Return.
     0x1a0f: 37 [C9 32]  |   STC                            ; otherwise set carry
     0x1a10: C9 [32 2B]  |   RET                            ; and return

; -------------------------------------------------
;
; **** Sound Delay Table (Data) ****
;
; --------------------------------------------------

.soundDelayDataTable_col1
     0x1a11: 32                            
     0x1a12: 2B                      
     0x1a13: 24                        
     0x1a14: 1C                       
     0x1a15: 16                            
     0x1a16: 11                               
     0x1a17: 0D                        
     0x1a18: 0A                            
     0x1a19: 08                                   
     0x1a1a: 07                         
     0x1a1b: 06                               
     0x1a1c: 05                        
     0x1a1d: 04                       
     0x1a1e: 03                       
     0x1a1f: 02                         
     0x1a20: 01                            

.soundDelayDataTable_col2
     0x1a21: 34                        
     0x1a22: 2E                              
     0x1a23: 27                      
     0x1a24: 22                                
     0x1a25: 1C                         
     0x1a26: 18                                        
     0x1a27: 15                            
     0x1a28: 13                        
     0x1a29: 10                                    
     0x1a2a: 0E                              
     0x1a2b: 0D                      
     0x1a2c: 0C                        
     0x1a2d: 0B                       
     0x1a2e: 09                       
     0x1a2f: 07                      
     0x1a30: 05                         
     0x1a31: FF                      

; ------------------------------------------------
;
; **** Utility Functions ****
;
;    0x1A32: utility ROM to RAM copy (or RAM to RAM)
;    0x1A3B - load sprite info into registers
;    0x1A47 - convert coordinates no shift
;    0x1A5C - clear all video memory
;    0x1A69 - update bunkers from buffer
;    0x1A7f - write remaining player lives (sprites and digits -- calls 0x19E6)
;
; ------------------------------------------------


; name: romToRamCopy
; Copies values in memory at DE into HL, then advances both.
; The number of bytes it copies is held in B.

.romToRamCopy
     0x1a32: 1A          |   LDAX D                         ; starts copying (DE) into (HL)
     0x1a33: 77          |   MOV M, A
     0x1a34: 23          |   INX H
     0x1a35: 13          |   INX D
     0x1a36: 05          |   DCR B                          ; ... goes for (B) bytes
     0x1a37: C2 [32 1A]  |   JNZ 0x1A32
     0x1a3a: C9          |   RET                            ; and returns

; name: loadSpriteInfo
; We load 5 bytes from the location HL is pointing to.
; They are loaded as follows: 
;         ** DE - typically pixelart coordinates in ROM
;         ** HL - typically screen coordinates
;         ** B - typically the size of the sprite to write.

.loadSpriteInfo
     0x1a3b: 5E          |   MOV E, M                       ; puts sprite info into registers
     0x1a3c: 23          |   INX H                          ; usually as parameter to write/erase sprite
     0x1a3d: 56          |   MOV D, M
     0x1a3e: 23          |   INX H                          ; DE -> pixelart template in ROM
     0x1a3f: 7E          |   MOV A, M                       ; HL -> screen coordinates (could be encoded)
     0x1a40: 23          |   INX H                          ; B -> width of sprite (loop control for write)
     0x1a41: 4E          |   MOV C, M
     0x1a42: 23          |   INX H
     0x1a43: 46          |   MOV B, M
     0x1a44: 61          |   MOV H, C
     0x1a45: 6F          |   MOV L, A
     0x1a46: C9          |   RET

; name: convertHLScreenNoShift
; Divides H and L by 8 and sets bit 5 if it's not already set (essentially adding 0x2000)
; This converts encoded screen coordinates into the screen coordinates used for addressing visual memory

.convertHLScreenNoShift                                     ; convert encoded screen coordinate
                                                            ; by dividing H & L each by 8 and adding 2000
     0x1a47: C5          |   PUSH B
     0x1a48: 06 [03]     |   MVI B, 0x03                    ; loop three times
     0x1a4a: 7C          |   MOV A, H                       ;    H /= 2
     0x1a4b: 1F          |   RAR
     0x1a4c: 67          |   MOV H, A
     0x1a4d: 7D          |   MOV A, L                       ;    L /= 2
     0x1a4e: 1F          |   RAR
     0x1a4f: 6F          |   MOV L, A
     0x1a50: 05          |   DCR B
     0x1a51: C2 [4A 1A]  |   JNZ 0x1A4A                     ; done? if so
     0x1a54: 7C          |   MOV A, H                       ; boundary check on H:
     0x1a55: E6 [3F]     |   ANI 0x3F                       ;    nothing higher than 3FFF
     0x1a57: F6 [20]     |   ORI 0x20                       ; and add 0x2000 offset for RAM if needed
     0x1a59: 67          |   MOV H, A                       ; store converted H
     0x1a5a: C1          |   POP B
     0x1a5b: C9          |   RET

; name: clearVideoMemory
; Clears video memory portion of RAM from 0x2400 to 0x3FFF.

.clearVideoMemory
     0x1a5c: 21 [00 24]  |   LXI H, 0x2400                  ; starts HL at beginning of video memory
     0x1a5f: 36 [00]     |   MVI M, 0x00                    ; puts 0 into memory there
     0x1a61: 23          |   INX H                          ; increase H
     0x1a62: 7C          |   MOV A, H                       ; put in A
     0x1a63: FE [40]     |   CPI 0x40                       ; compare to 40... are we at 0x4000?
     0x1a65: C2 [5F 1A]  |   JNZ 0x1A5F                     ; no? loop
     0x1a68: C9          |   RET                            ; or, we're done! return

; name: updateBunkersFromBuffer
; This can be called after setting up registers with player specific info

.updateBunkersFromBuffer                                    ; (B: 0x16, C: 0x02)
     0x1a69: C5 [E5 1A]  |   PUSH B                         
     0x1a6a: E5 [1A B6]  |   PUSH H
     0x1a6b: 1A [B6 77]  |   LDAX D                         ; load accumulator from buffer
     0x1a6c: B6 [77 13]  |   ORA M
     0x1a6d: 77 [13 23]  |   MOV M, A
     0x1a6e: 13 [23 0D]  |   INX D
     0x1a6f: 23 [0D C2]  |   INX H
     0x1a70: 0D [C2 6B]  |   DCR C                          ; loop until C is 0 (do 2 bytes)
     0x1a71: C2 [6B 1A]  |   JNZ 0x1A6B
     0x1a74: E1 [01 20]  |   POP H
     0x1a75: 01 [20 00]  |   LXI B, 0x0020                  ; move to next row
     0x1a78: 09 [C1 05]  |   DAD B
     0x1a79: C1 [05 C2]  |   POP B                          ; restore 0x16 to B and 0x02 to C
     0x1a7a: 05 [C2 69]  |   DCR B
     0x1a7b: C2 [69 1A]  |   JNZ 0x1A69                     ; repeat until B is 0
     0x1a7e: C9 [CD 2E]  |   RET

; name: writeRemainingPlayerLives
; Updates the "lives remaining" portion of the screen in lower left, drawing the queued "player sprites"
; as well as a digit indicating how many remain (including the 'live' player)

.writeRemaningPlayerLives                                   ; writes both sprites and the count digit
     0x1a7f: CD [2E 09]  |   CAL 0x092E                     ; get current ships: put the number of ships in A
     0x1a82: A7          |   ANA A                          ; is it 0?
     0x1a83: C8          |   RZ                             ; return if so
     0x1a84: F5          |   PUSH PSW                       ; otherwise, save A
     0x1a85: 3D          |   DCR A                          ; decrement it
     0x1a86: 77          |   MOV M, A                       ; and put it back in memory in HL
     0x1a87: CD [E6 19]  |   CAL 0x19E6                     ; draws the remaining player lives & clear to right
     0x1a8a: F1          |   POP PSW                        ; restore A

._writeRemainingLivesNum
     0x1a8b: 21 [01 25]  |   LXI H, 0x2501                  ; point H at 2501 (coordinates on screen bottom left)
     0x1a8e: E6 [0F]     |   ANI 0x0F                       ; mask to lower nibble only
     0x1a90: C3 [C5 09]  |   JMP 0x09C5                     ; print BCD digit for ships remaining

.__not_accessed__
     0x1a93: 00                     
     0x1a94: 00                         

.animationStruct_1A95
     0x1a95: 00                     
     0x1a96: 00                      
     0x1a97: FF                       
     0x1a98: B8                       
     0x1a99: FE                         
     0x1a9a: 20                                     
     0x1a9b: 1C                     
     0x1a9c: 10                                      
     0x1a9d: 9E                        
     0x1a9e: 00                   
     0x1a9f: 20                                   
     0x1aa0: 1C                         

.shotSpeedTable_speed                                       ; result speed between invader shots corresponds to
                                                            ; data at 1Cb8 (this is set into 0x20CF)
     0x1aa1: 30                                    
     0x1aa2: 10                                    
     0x1aa3: 0B                                     
     0x1aa4: 08                                       
     0x1aa5: 07                                               

.messageData_gameOverPlayer
     0x1aa6: 06                                             ; message      'G'
     0x1aa7: 00                                             ;              'A'
     0x1aa8: 0C                                             ;              'M'
     0x1aa9: 04                                             ;              'E'
     0x1aaa: 26                                             ;              ' '
     0x1aab: 0E                                             ;              'O'
     0x1aac: 15                                             ;              'V'
     0x1aad: 04                                             ;              'E'
     0x1aae: 11                                             ;              'R'
     0x1aaf: 26                                             ;              ' '
     0x1ab0: 26                                             ;              ' '
     0x1ab1: 0F                                             ;              'P'
     0x1ab2: 0B                                             ;              'L'
     0x1ab3: 00                                             ;              'A'
     0x1ab4: 18                                             ;              'Y'
     0x1ab5: 04                                             ;              'E'
     0x1ab6: 11                                             ;              'R'
     0x1ab7: 24                                             ;              '<'
     0x1ab8: 26                                             ;              ' '
     0x1ab9: 25                                             ;              '>'

.messageData_1Or2PlayersButton
     0x1aba: 1B                                             ; message:     '1'
     0x1abb: 26                                             ;              ' '
     0x1abc: 0E                                             ;              'O'
     0x1abd: 11                                             ;              'R'
     0x1abe: 26                                             ;              ' '
     0x1abf: 1C                                             ;              '2'
     0x1ac0: 0F                                             ;              'P'
     0x1ac1: 0B                                             ;              'L'
     0x1ac2: 00                                             ;              'A'
     0x1ac3: 18                                             ;              'Y'
     0x1ac4: 04                                             ;              'E'
     0x1ac5: 11                                             ;              'R'
     0x1ac6: 12                                             ;              'S'
     0x1ac7: 26                                             ;              ' '
     0x1ac8: 01                                             ;              'B'
     0x1ac9: 14                                             ;              'U'
     0x1aca: 13                                             ;              'T'
     0x1acb: 13                                             ;              'T'
     0x1acc: 0E                                             ;              'O'
     0x1acd: 0D                                             ;              'N'
     0x1ace: 26                                             ;              ' '

.messageData_OnlyOnePlayerButton
     0x1acf: 0E                                             ; message:     'O'
     0x1ad0: 0D                                             ;              'N'
     0x1ad1: 0B                                             ;              'L'
     0x1ad2: 18                                             ;              'Y'
     0x1ad3: 26                                             ;              ' '
     0x1ad4: 1B                                             ;              '1'
     0x1ad5: 0F                                             ;              'P'
     0x1ad6: 0B                                             ;              'L'
     0x1ad7: 00                                             ;              'A'
     0x1ad8: 18                                             ;              'Y'
     0x1ad9: 04                                             ;              'E'
     0x1ada: 11                                             ;              'R'
     0x1adb: 26                                             ;              ' '
     0x1adc: 26                                             ;              ' '
     0x1add: 01                                             ;              'B'
     0x1ade: 14                                             ;              'U'
     0x1adf: 13                                             ;              'T'
     0x1ae0: 13                                             ;              'T'
     0x1ae1: 0E                                             ;              'O'
     0x1ae2: 0D                                             ;              'N'
     0x1ae3: 26                                             ;              ' '

.scoreLeaderboardTitle
     0x1ae4: 26                                             ;              ' '
     0x1ae5: 12                                             ;              'S'
     0x1ae6: 02                                             ;              'C'
     0x1ae7: 0E                                             ;              'O'
     0x1ae8: 11                                             ;              'R'
     0x1ae9: 04                                             ;              'E'
     0x1aea: 24                                             ;              '<'
     0x1aeb: 1B                                             ;              '1'
     0x1aec: 25                                             ;              '>'
     0x1aed: 26                                             ;              ' '
     0x1aee: 07                                             ;              'H'
     0x1aef: 08                                             ;              'I'
     0x1af0: 3F                                             ;              '-'
     0x1af1: 12                                             ;              'S'
     0x1af2: 02                                             ;              'C'
     0x1af3: 0E                                             ;              'O'
     0x1af4: 11                                             ;              'R'
     0x1af5: 04                                             ;              'E'
     0x1af6: 26                                             ;              ' '
     0x1af7: 12                                             ;              'S'
     0x1af8: 02                                             ;              'C'
     0x1af9: 0E                                             ;              'O'
     0x1afa: 11                                             ;              'R'
     0x1afb: 04                                             ;              'E'
     0x1afc: 24                                             ;              '<'
     0x1afd: 1C                                             ;              '2'
     0x1afe: 25                                             ;              '>'
     0x1aff: 26                                             ;              ' '

; ********************** INITIALIZED GAME VARIABLES *********************************************
; note that as part of game initialization, all data from 0x1B00 to 0x1BFF is copied into
; game RAM at 0x2000 to 0x20FF. This copy is what the "corresponding RAM" to the right refers to.

;                        ******** ROM *********                            ******* CORRESPONDING RAM ********

.initializeRAM_2000      ; invaders data, etc.                                  ; RAM: INVADERS DATA BUFFER
     0x1b00: 01                                                                 ; 2000 - draw_invaders_lock
     0x1b01: 00                                        
     0x1b02: 00                                                                 ; 2002 - player_shot_hit_something
     0x1b03: 10                                                                 ; 2003 - invader_explosion_timer
     0x1b04: 00                                                                 ; 2004 - current_invader_row
     0x1b05: 00                                                                 ; 2005 - invader_sprite_number
     0x1b06: 00                                                                 ; 2006 - current_invader_index
     0x1b07: 00                                                                 ; 2007 - current_invader_offset_Y
     0x1b08: 02                                                                 ; 2008 - current_invader_offset_X
     0x1b09: 78                                                                 ; 2009 - origin_invader_Y
     0x1b0a: 38                                                                 ; 200A - origin_invader_X
     0x1b0b: 78                                                                 ; 200B - current_invader_Y
     0x1b0c: 38                                                                 ; 200C - current_invader_X
     0x1b0d: 00                                                                 ; 200D - invader_direction_toggle
     0x1b0e: F8                                                                 ; 200E - group_offset_Y
     0x1b0f: 00                       

.initializeRAM_2010      ; player data                                          ; RAM: PLAYER DATA BUFFER
     0x1b10: 00                                                                 ; 2010 - player.countdown
     0x1b11: 80                             
     0x1b12: 00                                                                 ; 2012 - player.sync
     0x1b13: 8E                                                                 ; 2023 - player.jump_address
     0x1b14: 02                          
     0x1b15: FF                                                                 ; 2015 - player.is_alive
     0x1b16: 05                                                                 ; 2016 - player.explosion_countdown
     0x1b17: 0C                                                                 ; 2017 - player.explosion_stage
     0x1b18: 60                                                                 ; 2018 - player.sprite_ptr
     0x1b19: 1C                                   
     0x1b1a: 20                                                                 ; 201A - player.screen_coordinates
     0x1b1b: 30                                                                 ; 201B - [current x coord]
     0x1b1c: 10                                        
     0x1b1d: 01                                                                 ; 201D - demo_command
     0x1b1e: 00                                                                 ; 201E - first_secret_sequence
     0x1b1f: 00                           

.playerShotData          ; player shot data                                     ; RAM: PLAYER SHOT DATA BUFFER
     0x1b20: 00                                                                 ; 2020 - pshot.countdown
     0x1b21: 00                     
     0x1b22: 00                                                                 ; 2022 - pshot.sync
     0x1b23: BB                                                                 ; 2023 - pshot.jump_address
     0x1b24: 03                       
     0x1b25: 00                                                                 ; 2025 - pshot.shot_status
     0x1b26: 10                                                                 ; 2026 - pshot.explosion_countdown
     0x1b27: 90                                                                 ; 2027 - pshot.sprite_ptr
     0x1b28: 1C                              
     0x1b29: 28                                                                 ; 2028 - pshot.screen_coordinates
     0x1b2a: 30                                   
     0x1b2b: 01                                                                 ; 202B - pshot.sprite_width
     0x1b2c: 04                                                                 ; 202C - pshot.offset
     0x1b2d: 00                                                                 ; 202D - fire_command_status

.__not_accessed__
     0x1b2e: FF                           
     0x1b2f: FF                           

.initializeRAM_2030      ; "skinny" shot data structur                          ; RAM: SKINNY ALIEN SHOT BUFFER
     0x1b30: 00                                                                 ; 2030 - skinny.countdown
     0x1b31: 00                     
     0x1b32: 02                                                                 ; 2032 - skinny.sync
     0x1b33: 76                                                                 ; 2033 - skinny.jump_address
     0x1b34: 04                     
     0x1b35: 00                                                                 ; 2035 - skinny.shot_status
     0x1b36: 00                                                                 ; 2036 - skinny.running_time
     0x1b37: 00                                                                 ; 2037 - skinny.player_tracking_off
     0x1b38: 00                                                                 ; 2038 - skinny.enable_fire (16 bits)
     0x1b39: 00                      
     0x1b3a: 04                                                                 ; 203A - skinny.explosion_countdown
     0x1b3b: EE                                                                 ; 203B - skinny.sprite_ptr (16 bits)
     0x1b3c: 1C                                        
     0x1b3d: 00                                                                 ; 203D - skinny.shot_coordinates
     0x1b3e: 00                     
     0x1b3f: 03                                                                 ; 203F - skinny.shot_sprite_width

.initializeRAM_2040      ; uptack shot data structure                           ; RAM: UPTACK ALIEN SHOT BUFFER
     0x1b40: 00                                                                 ; 2040 - uptack.countdown
     0x1b41: 00                                                                 ; 
     0x1b42: 00                                                                 ; 2042 - uptack.sync
     0x1b43: B6                                                                 ; 2043 - uptack.jump_address
     0x1b44: 04                          
     0x1b45: 00                                                                 ; 2045 - uptack.shot_status
     0x1b46: 00                                                                 ; 2046 - uptack.running_time
     0x1b47: 01                                                                 ; 2047 - uptack.player_tracking_off
     0x1b48: 00                                                                 ; 2048 - uptack.spawn_column_table_ptr
     0x1b49: 1D                       
     0x1b4a: 04                                                                 ; 204A - uptack.explosion_countdown
     0x1b4b: E2                                                                 ; 204B - uptack.sprite_ptr (16 bits)
     0x1b4c: 1C                       
     0x1b4d: 00                                                                 ; 204D - uptack.shot_coordinates
     0x1b4e: 00                      
     0x1b4f: 03                                                                 ; 204F - uptack.shot_sprite_width

.initializeRAM_2050      ; zigzag shot data structure                           ; RAM: ZIGZAG ALIEN SHOT BUFFER
     0x1b50: 00                                                                 ; 2050 - zigzag.countdown
     0x1b51: 00                       
     0x1b52: 00                                                                 ; 2052 - zigzag.sync
     0x1b53: 82                                                                 ; 2053 - zigzag.jump_address
     0x1b54: 06                             
     0x1b55: 00                                                                 ; 2055 - zigzag.shot_status
     0x1b56: 00                                                                 ; 2056 - zigzag.running_time
     0x1b57: 01                                                                 ; 2057 - zigzag.player_tracking_off
     0x1b58: 06                                                                 ; 2058 - zigzag.spawn_column_table_ptr
     0x1b59: 1D                       
     0x1b5a: 04                                                                 ; 205A - zigzag.explosion_countdown
     0x1b5b: D0                                                                 ; 205B - zigzag.sprite_ptr (16 bits)
     0x1b5c: 1C                         
     0x1b5d: 00                                                                 ; 205D - zigzag.shot_coordinates
     0x1b5e: 00                          
     0x1b5f: 03                                                                 ; 205F - zigzag.shot_sprite_width

.initializeRAM_2060                                                             RAM: ALIEN EXPLOSION, VARIOUS
     0x1b60: FF                                                                 ; this FF stops game control ISR processing loop
     0x1b61: 00                                                                 ; 2061 - shot_collision_flag
     0x1b62: C0                                                                 ; 2062 - explosion_sprite_ptr
     0x1b63: 1C                        
     0x1b64: 00                                                                 ; 2064 - exploding_alien_coords
     0x1b65: 00                   
     0x1b66: 10                                                                 ; 2066 - player_data_LSB (not really used)
     0x1b67: 21                                                                 ; 2067 - player_data_page
     0x1b68: 01                                                                 ; 2068 - player_explosion
     0x1b69: 00                                                                 ; 2069 - alien_shot_active
     0x1b6a: 30                                                                 ; 206A - alien_shot_cooldown_timer
     0x1b6b: 00                                                                 ; 206B - one_alien_left
     0x1b6c: 12                                                                 ; 206C - table_message_size
     0x1b6d: 00                                                                 ; 206D - invaders_win_flag
     0x1b6e: 00                                                                 ; 206E - uptack_t_shot_blocker (when one alien left)
     0x1b6f: 00                                                                 ; 

.playPlayer1_message                         ; *** ROM ***                      ; RAM: ACTIVE ALIEN SHOT BUFFER
     0x1b70: 0F                              ; message: 'P'                     ; 2070 - running_time_1 (for other alien shot)
     0x1b71: 0B                              ;          'L'                     ; 2071 - running_time_2 (for 2nd other alien shot)
     0x1b72: 00                              ;          'A'
     0x1b73: 18                              ;          'Y'                     ; 2073 - ashot.shot_status
     0x1b74: 26                              ;          ' '                     ; 2074 - ashot.running_time
     0x1b75: 0F                              ;          'P'                     ; 2075 - ashot.player_tracking_off
     0x1b76: 0B                              ;          'L'                     ; 2076 - ashot.spawn_column_table_pointer
     0x1b77: 00                              ;          'A'
     0x1b78: 18                              ;          'Y'                     ; 2078 - ashot.explosion_countdown
     0x1b79: 04                              ;          'E'                     ; 2079 - ashot.active_shot_sprite_ptr (16 bits)
     0x1b7a: 11                              ;          'R'
     0x1b7b: 24                              ;          '<'                     ; 2078 - ashot.shot_coordinates (16 bits)
     0x1b7c: 1B                              ;          '1'
     0x1b7d: 25                              ;          '>'                     ; 207D - ashot.sprite_width

.initializeRAM_207E                                                             ; RAM: ALIEN SHOT BUFFER CONT
     0x1b7e: FC                                                                 ; 207E - ashot.shot_offsetY
     0x1b7f: 00                                                                 ; 207F - ashot.shot_sprite_limit

.initializeRAM_2080
     0x1b80: 01                                                                 ; 2080 - run_uptack_shot
     0x1b81: FF                                                                 ; 2081 - bunker_save_restore
     0x1b82: FF                                                                 ; 2082 - remaining_invader_count
     0x1b83: 00                                                                 ; 2083 - ufo_start
     0x1b84: 00                                                                 ; 2084 - ufo_on_screen
     0x1b85: 00                                                                 ; 2085 - ufo_hit
     0x1b86: 20                                   
     0x1b87: 64                                                                 ; 2087 - current_ufo_sprite_pointer (16 bits)
     0x1b88: 1D                        
     0x1b89: D0                                                                 ; 2089 - ufo_screen_coordinates (16 bits)
     0x1b8a: 29                      
     0x1b8b: 18                                                                 ; 208B - ufo_sprite_width
     0x1b8c: 02                      
     0x1b8d: 54                                                                 ; 208D - score_randomizer (16 bits)
     0x1b8e: 1D                   
     0x1b8f: 00                                                                 ; 208F - pseudorandom seed pointer, UFO direction
     0x1b90: 08                                   
     0x1b91: 00                                                                 ; 2091 - start UFO countdown
     0x1b92: 06                           
     0x1b93: 00                                                                 ; 2093 - waiting_to_start
     0x1b94: 00                                                                 ; 2094 - port3_audio_buffer
     0x1b95: 01                                                                 ; 2095 - invader_sound_change
     0x1b96: 40                                                                 ; 2096 - invader_sound_timer
     0x1b97: 00                                                                 ; 2097 - invader_audio_rest_interval
     0x1b98: 01                                                                 ; 2098 - port5_audio_buffer
     0x1b99: 00                                                                 ; 2099 - audio_hold_timer
     0x1b9a: 00                                                                 ; 209A - tilt_flag
     0x1b9b: 10                                                                 ; 209B - invader_audio_play_duration

.__not_accessed__                                                                                               
     0x1b9c: 9E                                        
     0x1b9d: 00 
     0x1b9e: 20                                                    
     0x1b9f: 1C

.alienWithUpsideDownY_1                      ; ROM
     0x1ba0: 00                              ; . . . . . . . .
     0x1ba1: 03                              ; . . . . . . x x
     0x1ba2: 04                              ; . . . . . x . .
     0x1ba3: 78                              ; . x x x x . . .
     0x1ba4: 14                              ; . . . x . x . .
     0x1ba5: 13                              ; . . . x . . x x
     0x1ba6: 08                              ; . . . . x . . .
     0x1ba7: 1A                              ; . . . x x . x .
     0x1ba8: 3D                              ; . . x x x x . x
     0x1ba9: 68                              ; . x x . x . . .
     0x1baa: FC                              ; x x x x x x . .
     0x1bab: FC                              ; x x x x x x . .
     0x1bac: 68                              ; . x x . x . . .
     0x1bad: 3D                              ; . . x x x x . x
     0x1bae: 1A                              ; . . . x x . x .
     0x1baf: 00                              ; . . . . . . . .

.animationStruct_1BB0
     0x1bb0: 00                     
     0x1bb1: 00                        
     0x1bb2: 01                            
     0x1bb3: B8                      
     0x1bb4: 98                      
     0x1bb5: A0                      
     0x1bb6: 1B                     
     0x1bb7: 10                                    
     0x1bb8: FF                      
     0x1bb9: 00                      
     0x1bba: A0                      
     0x1bbb: 1B                    

.__not_accessed__
     0x1bbc: 00                     
     0x1bbd: 00                   
     0x1bbe: 00                    
     0x1bbf: 00                   

.initializeRAM_20C0                                                             ; RAM: SPLASH ANIMATION BUFFER
     0x1bc0: 00                                                                 ; 20C0 - pause_timer
     0x1bc1: 10                                                                 ; 20C1 - splash_sequence_num

.liveAnimationData
     0x1bc2: 00                                                                 ; 20C2 - animation.sprite_switch_counter
     0x1bc3: 0E                                                                 ; 20C3 - animation.y_direction_step
     0x1bc4: 05                                                                 ; 20C4 - animation.x_direction_step
     0x1bc5: 00                                                                 ; 20C5 - animation.current_y
     0x1bc6: 00                                                                 ; 20C6 - animation.current_x
     0x1bc7: 00                                                                 ; 20c7 - animation.next_spriteLSB
     0x1bc8: 00                                                                 ; 20C8 - animation.next_spriteMSB
     0x1bc9: 00                                                                 ; 20C9 - animation.sprite data length
     0x1bca: 07                                                                 ; 20CA - animation.x_target
     0x1bcb: D0                                                                 ; 20CB - animation.target flag reached
     0x1bcc: 1C                                                                 ; 20CC - animation.current_spriteLSB
     0x1bcd: C8                                                                 ; 20CD - animation.current_spriteMSB

.initializeRAM_20CE
     0x1bce: 9B                                                                 ; 20CE - one_or_two_players
     0x1bcf: 03                                                                 ; 20CF - new_alien_shot_timer

.alienWithUpsideDownY_2                      ; ROM
     0x1bd0: 00                              ; . . . . . . . .
     0x1bd1: 00                              ; . . . . . . . .
     0x1bd2: 03                              ; . . . . . . x x 
     0x1bd3: 04                              ; . . . . . x . .
     0x1bd4: 78                              ; . x x x x . . .
     0x1bd5: 14                              ; . . . x . x . .
     0x1bd6: 0B                              ; . . . . x . x x
     0x1bd7: 19                              ; . . . x x . . x
     0x1bd8: 3A                              ; . . x x x . x .
     0x1bd9: 6D                              ; . x x . x x . x
     0x1bda: FA                              ; x x x x x . x .
     0x1bdb: FA                              ; x x x x x . x .
     0x1bdc: 6D                              ; . x x . x x . x
     0x1bdd: 3A                              ; . . x x x . x .
     0x1bde: 19                              ; . . . x x . . x
     0x1bdf: 00                              ; . . . . . . . .
     0x1be0: 00                              ; . . . . . . . .
     0x1be1: 00                              ; . . . . . . . .
     0x1be2: 00                              ; . . . . . . . .
     0x1be3: 00                              ; . . . . . . . .
     0x1be4: 00                              ; . . . . . . . .

.initializeRAM_20E5                                                             ; RAM: ISR PROCESSING DATA
     0x1be5: 00                                                                 ; 20E5 - enable_xtra_ship_p1
     0x1be6: 00                                                                 ; 20E6 - enable_xtra_ship_p2
     0x1be7: 00                                                                 ; 20E7 - player_one_alive
     0x1be8: 00                                                                 ; 20E8 - player_two_alive
     0x1be9: 01                                                                 ; 20E9 - enable_game_processing
     0x1bea: 00                                                                 ; 20EA - recent_coin_trigger
     0x1beb: 00                                                                 ; 20EB - credit_balance
     0x1bec: 01                                                                 ; 20EC - splash_toggle
     0x1bed: 74                                                                 ; 20ED - demo_instruction_pointer
     0x1bee: 1F                     
     0x1bef: 00                                                                 ; 20EF - game_mode_toggle

.__not_accessed__
     0x1bf0: 80                                                                 

.initializeRAM_20F1                                                             ; RAM: SCORES DATA STRUCTURE
     0x1bf1: 00                                                                 ; 20F1 - score_update_needed
     0x1bf2: 00                                                                 ; 20f2 - score_update_amount
     0x1bf3: 00                     
     0x1bf4: 00                                                                 ; 20F4 - high_score (16 bits, BCD)
     0x1bf5: 00                          
     0x1bf6: 1C                                                                 ; 20F6 - hi_score_coordinates (16 bits)
     0x1bf7: 2F                      
     0x1bf8: 00                                                                 ; 20F8 - player1_score (16 bits, BCD)
     0x1bf9: 00                        
     0x1bfa: 1C                                                                 ; 20FA - p1_score_coordinates (16 bits)
     0x1bfb: 27                       
     0x1bfc: 00                                                                 ; 20FC - player2_score (16 bits, BCD)
     0x1bfd: 00                         
     0x1bfe: 1C                                                                 ; 20F3 - p2_score_coordinates (16 bits)
     0x1bff: 39                          

; *****************************  GAME CONSTANTS *******************************

.invaderA_1
     0x1c00: 00                                        ; . . . . . . . . 
     0x1c01: 00                                        ; . . . . . . . .
     0x1c02: 39                                        ; . . x x x . . x
     0x1c03: 79                                        ; . x x x x . . x
     0x1c04: 7A                                        ; . x x x x . x .
     0x1c05: 6E                                        ; . x x . x x x .
     0x1c06: EC                                        ; x x x . x x . .
     0x1c07: FA                                        ; x x x x x . x .
     0x1c08: FA                                        ; x x x x x . x .
     0x1c09: EC                                        ; x x x . x x . .
     0x1c0a: 6E                                        ; . x x . x x x .
     0x1c0b: 7A                                        ; . x x x x . x .
     0x1c0c: 79                                        ; . x x x x . . x
     0x1c0d: 39                                        ; . . x x x . . x
     0x1c0e: 00                                        ; . . . . . . . .
     0x1c0f: 00                                        ; . . . . . . . .

.invaderB_1
     0x1c10: 00                                        ; . . . . . . . .
     0x1c11: 00                                        ; . . . . . . . .
     0x1c12: 00                                        ; . . . . . . . .
     0x1c13: 78                                        ; . x x x x . . .
     0x1c14: 1D                                        ; . . . x x x . x
     0x1c15: BE                                        ; x . x x x x x .
     0x1c16: 6C                                        ; . x x . x x . .
     0x1c17: 3C                                        ; . . x x x x . .
     0x1c18: 3C                                        ; . . x x x x . .
     0x1c19: 3C                                        ; . . x x x x . .
     0x1c1a: 6C                                        ; . x x . x x . .
     0x1c1b: BE                                        ; x . x x x x x .
     0x1c1c: 1D                                        ; . . . x x x . x
     0x1c1d: 78                                        ; . x x x x . . .
     0x1c1e: 00                                        ; . . . . . . . .
     0x1c1f: 00                                        ; . . . . . . . .

.invaderC_1
     0x1c20: 00                                        ; . . . . . . . .
     0x1c21: 00                                        ; . . . . . . . .
     0x1c22: 00                                        ; . . . . . . . .
     0x1c23: 00                                        ; . . . . . . . .
     0x1c24: 19                                        ; . . . x x . . x
     0x1c25: 3A                                        ; . . x x x . x .
     0x1c26: 6D                                        ; . x x . x x . x
     0x1c27: FA                                        ; x x x x x . x .
     0x1c28: FA                                        ; x x x x x . x .
     0x1c29: 6D                                        ; . x x . x x . x
     0x1c2a: 3A                                        ; . . x x x . x .
     0x1c2b: 19                                        ; . . . x x . . x
     0x1c2c: 00                                        ; . . . . . . . .
     0x1c2d: 00                                        ; . . . . . . . . 
     0x1c2e: 00                                        ; . . . . . . . .
     0x1c2f: 00                                        ; . . . . . . . .

.invaderA_2
     0x1c30: 00                                        ; . . . . . . . .
     0x1c31: 00                                        ; . . . . . . . .
     0x1c32: 38                                        ; . . x x x . . .
     0x1c33: 7A                                        ; . x x x x . x .
     0x1c34: 7F                                        ; . x x x x x x x
     0x1c35: 6D                                        ; . x x . x x . x
     0x1c36: EC                                        ; x x x . x x . .
     0x1c37: FA                                        ; x x x x x . x .
     0x1c38: FA                                        ; x x x x x . x .
     0x1c39: EC                                        ; x x x . x x . .
     0x1c3a: 6D                                        ; . x x . x x . x
     0x1c3b: 7F                                        ; . x x x x x x x
     0x1c3c: 7A                                        ; . x x x x . x .
     0x1c3d: 38                                        ; . . x x x . . .
     0x1c3e: 00                                        ; . . . . . . . .
     0x1c3f: 00                                        ; . . . . . . . .

.invaderB_2
     0x1c40: 00                                        ; . . . . . . . .
     0x1c41: 00                                        ; . . . . . . . .
     0x1c42: 00                                        ; . . . . . . . .
     0x1c43: 0E                                        ; . . . . x x x .
     0x1c44: 18                                        ; . . . x x . . .
     0x1c45: BE                                        ; x . x x x x x .
     0x1c46: 6D                                        ; . x x . x x . x
     0x1c47: 3D                                        ; . . x x x x . x
     0x1c48: 3C                                        ; . . x x x x . .
     0x1c49: 3D                                        ; . . x x x x . x
     0x1c4a: 6D                                        ; . x x . x x . x
     0x1c4b: BE                                        ; x . x x x x x .
     0x1c4c: 18                                        ; . . . x x . . .
     0x1c4d: 0E                                        ; . . . . x x x .
     0x1c4e: 00                                        ; . . . . . . . .
     0x1c4f: 00                                        ; . . . . . . . .

.invaderC_2     
     0x1c50: 00                                        ; . . . . . . . .
     0x1c51: 00                                        ; . . . . . . . .
     0x1c52: 00                                        ; . . . . . . . .
     0x1c53: 00                                        ; . . . . . . . .
     0x1c54: 1A                                        ; . . . x x . x .
     0x1c55: 3D                                        ; . . x x x x . x
     0x1c56: 68                                        ; . x x . x . . .
     0x1c57: FC                                        ; x x x x x x . .
     0x1c58: FC                                        ; x x x x x x . .
     0x1c59: 68                                        ; . x x . x . . .
     0x1c5a: 3D                                        ; . . x x x x . x
     0x1c5b: 1A                                        ; . . . x x . x .
     0x1c5c: 00                                        ; . . . . . . . .
     0x1c5d: 00                                        ; . . . . . . . .
     0x1c5e: 00                                        ; . . . . . . . .
     0x1c5f: 00                                        ; . . . . . . . .

.playerGunship
     0x1c60: 00                                        ; . . . . . . . .
     0x1c61: 00                                        ; . . . . . . . .
     0x1c62: 0F                                        ; . . . . x x x x 
     0x1c63: 1F                                        ; . . . x x x x x
     0x1c64: 1F                                        ; . . . x x x x x
     0x1c65: 1F                                        ; . . . x x x x x
     0x1c66: 1F                                        ; . . . x x x x x 
     0x1c67: 7F                                        ; . x x x x x x x 
     0x1c68: FF                                        ; x x x x x x x x 
     0x1c69: 7F                                        ; . x x x x x x x 
     0x1c6a: 1F                                        ; . . . x x x x x 
     0x1c6b: 1F                                        ; . . . x x x x x
     0x1c6c: 1F                                        ; . . . x x x x x
     0x1c6d: 1F                                        ; . . . x x x x x
     0x1c6e: 0F                                        ; . . . . x x x x
     0x1c6f: 00                                        ; . . . . . . . .

.playerExplodes_1     
     0x1c70: 00                                        ; . . . . . . . .
     0x1c71: 04                                        ; . . . . . x . .
     0x1c72: 01                                        ; . . . . . . . x
     0x1c73: 13                                        ; . . . x . . x x
     0x1c74: 03                                        ; . . . . . . x x
     0x1c75: 07                                        ; . . . . . x x x
     0x1c76: B3                                        ; x . x x . . x x
     0x1c77: 0F                                        ; . . . . x x x x
     0x1c78: 2F                                        ; . . x . x x x x
     0x1c79: 03                                        ; . . . . . . x x
     0x1c7a: 2F                                        ; . . x . x x x x
     0x1c7b: 49                                        ; . x . . x . . x
     0x1c7c: 04                                        ; . . . . . x . .
     0x1c7d: 03                                        ; . . . . . . x x
     0x1c7e: 00                                        ; . . . . . . . .
     0x1c7f: 01                                        ; . . . . . . . x

.playerExplodes_2
     0x1c80: 40                                        ; . x . . . . . .
     0x1c81: 08                                        ; . . . . x . . . 
     0x1c82: 05                                        ; . . . . . x . x
     0x1c83: A3                                        ; x . x . . . x x 
     0x1c84: 0A                                        ; . . . . x . x .
     0x1c85: 03                                        ; . . . . . . x x 
     0x1c86: 5B                                        ; . x . x x . x x
     0x1c87: 0F                                        ; . . . . x x x x
     0x1c88: 27                                        ; . . x . . x x x
     0x1c89: 27                                        ; . . x . . x x x
     0x1c8a: 0B                                        ; . . . . x . x x
     0x1c8b: 4B                                        ; . x . . x . x x
     0x1c8c: 40                                        ; . x . . . . . .
     0x1c8d: 84                                        ; x . . . . x . .
     0x1c8e: 11                                        ; . . . x . . . x
     0x1c8f: 48                                        ; . x . . x . . .

.playerShotSprite     
     0x1c90: 0F                                        ; . . . . x x x x

.playerShotExplosion
     0x1c91: 99                                        ; x . . x x . . x
     0x1c92: 3C                                        ; . . x x x x . .
     0x1c93: 7E                                        ; . x x x x x x .
     0x1c94: 3D                                        ; . . x x x x . x
     0x1c95: BC                                        ; x . x x x x . .
     0x1c96: 3E                                        ; . . x x x x x .
     0x1c97: 7C                                        ; . x x x x x . .
     0x1c98: 99                                        ; x . . x x . . x

.scoreMessage4                          ; this is the fourth message in the score advance table
     0x1c99: 27                                        ; message:     '='   
     0x1c9a: 1B                                        ;              '1'
     0x1c9b: 1A                                        ;              '0'
     0x1c9c: 26                                        ;              ' '
     0x1c9d: 0F                                        ;              'P'
     0x1c9e: 0E                                        ;              'O'             
     0x1c9f: 08                                        ;              'I'
     0x1ca0: 0D                                        ;              'N'
     0x1ca1: 13                                        ;              'T'
     0x1ca2: 12                                        ;              'S'

.scoreTableHeader
     0x1ca3: 28                                        ; message:     '*'
     0x1ca4: 12                                        ;              'S'
     0x1ca5: 02                                        ;              'C'
     0x1ca6: 0E                                        ;              'O'
     0x1ca7: 11                                        ;              'R'
     0x1ca8: 04                                        ;              'E'
     0x1ca9: 26                                        ;              ' '
     0x1caa: 00                                        ;              'A'
     0x1cab: 03                                        ;              'D'
     0x1cac: 15                                        ;              'V'
     0x1cad: 00                                        ;              'A'
     0x1cae: 0D                                        ;              'N'
     0x1caf: 02                                        ;              'C'
     0x1cb0: 04                                        ;              'E'
     0x1cb1: 26                                        ;              ' '
     0x1cb2: 13                                        ;              'T'
     0x1cb3: 00                                        ;              'A'
     0x1cb4: 01                                        ;              'B'
     0x1cb5: 0B                                        ;              'L'
     0x1cb6: 04                                        ;              'E'
     0x1cb7: 28                                        ;              '*'

.shotSpeedTable_col1                    ; lookup/compare to MSB of player score
                                        ; match to corresponding byte at 0x1AA1
     0x1cb8: 02                          
     0x1cb9: 10                                        
     0x1cba: 20                                       
     0x1cbb: 30                                        

.tiltMessage
     0x1cbc: 13                                        ; message:     'T'
     0x1cbd: 08                                        ;              'I'
     0x1cbe: 0B                                        ;              'L'
     0x1cbf: 13                                        ;              'T'

.invaderExplosion
     0x1cc0: 00                                        ; . . . . . . . .
     0x1cc1: 08                                        ; . . . . . . . .
     0x1cc2: 49                                        ; . x . . x . . x
     0x1cc3: 22                                        ; . . x . . . x .
     0x1cc4: 14                                        ; . . . x . x . .
     0x1cc5: 81                                        ; x . . . x . . .
     0x1cc6: 42                                        ; . x . . . . x .
     0x1cc7: 00                                        ; . . . . . . . .
     0x1cc8: 42                                        ; . x . . . . x .
     0x1cc9: 81                                        ; x . . . . . . x
     0x1cca: 14                                        ; . . . x . x . .
     0x1ccb: 22                                        ; . . x . . . x .
     0x1ccc: 49                                        ; . x . . x . . x 
     0x1ccd: 08                                        ; . . . . x . . .
     0x1cce: 00                                        ; . . . . . . . .
     0x1ccf: 00                                        ; . . . . . . . .

.zigZagShot_1
     0x1cd0: 44                                        ; . x . . . x . .
     0x1cd1: AA                                        ; x . x . x . x .
     0x1cd2: 10                                        ; . . . x . . . .

.zigZagShot_2
     0x1cd3: 88                                        ; x . . . x . . . 
     0x1cd4: 54                                        ; . x . x . x . .
     0x1cd5: 22                                        ; . . x . . . x .

.zigZagShot_3
     0x1cd6: 10                                        ; . . . x . . . .
     0x1cd7: AA                                        ; x . x . x . x .
     0x1cd8: 44                                        ; . x . . . x . .

.zigZagShot_4
     0x1cd9: 22                                        ; . . x . . . x .
     0x1cda: 54                                        ; . x . x . x . .
     0x1cdb: 88                                        ; x . . . x . . .

.alienShot_explosion
     0x1cdc: 4A                                        ; . x . . x . x .
     0x1cdd: 15                                        ; . . . x . x . x
     0x1cde: BE                                        ; x . x x x x x .
     0x1cdf: 3F                                        ; . . x x x x x x
     0x1ce0: 5E                                        ; . x . x x x x .
     0x1ce1: 25                                        ; . . x . . x . x

.uptackShot_1
     0x1ce2: 04                                        ; . . . . . x . .
     0x1ce3: FC                                        ; x x x x x x . .
     0x1ce4: 04                                        ; . . . . . x . .

.uptackShot_2
     0x1ce5: 10                                        ; . . . x . . . .
     0x1ce6: FC                                        ; x x x x x x . .
     0x1ce7: 10                                        ; . . . x . . . .

.uptackShot_3
     0x1ce8: 20                                        ; . . x . . . . .
     0x1ce9: FC                                        ; x x x x x x . .
     0x1cea: 20                                        ; . . x . . . . .

.uptackShot_4
     0x1ceb: 80                                        ; x . . . . . . .
     0x1cec: FC                                        ; x x x x x x . .
     0x1ced: 80                                        ; x . . . . . . .

.skinnyShot_1
     0x1cee: 00                                        ; . . . . . . . .
     0x1cef: FE                                        ; x x x x x x x .
     0x1cf0: 00                                        ; . . . . . . . .

.skinnyShot_2
     0x1cf1: 24                                        ; . . x . . x . .
     0x1cf2: FE                                        ; x x x x x x . .
     0x1cf3: 12                                        ; . . . x . . x .

.skinnyShot_3
     0x1cf4: 00                                        ; . . . . . . . . 
     0x1cf5: FE                                        ; x x x x x x x .
     0x1cf6: 00                                        ; . . . . . . . .

.skinnyShot_4
     0x1cf7: 48                                        ; . x . . x . . .
     0x1cf8: FE                                        ; x x x x x x x .
     0x1cf9: 90                                        ; x . . x . . . .

.message_playUpsideDown
     0x1cfa: 0F                                        ; message:     'P'
     0x1cfb: 0B                                        ;              'L'
     0x1cfc: 00                                        ;              'A'
     0x1cfd: 29                                        ;              '[upside-down Y]'

.__not_accessed__
     0x1cfe: 00                   
     0x1cff: 00                 

.alienShotSpawnColumnLookup        ; alien shot struct 2 (uptack-t): 1D00 - 1D0F
     0x1d00: 01                    ; alien shot struct 3 (zigzag): 1D06 - 1D14
     0x1d01: 07                              
     0x1d02: 01                               
     0x1d03: 01                              
     0x1d04: 01                                
     0x1d05: 04                       
._startAlienStruct3
     0x1d06: 0B                           
     0x1d07: 01                               
     0x1d08: 06                                
     0x1d09: 03                                 
     0x1d0a: 01                                      
     0x1d0b: 01                                    
     0x1d0c: 0B                               
     0x1d0d: 09                               
     0x1d0e: 02                                 
     0x1d0f: 08                                    
._stopAlienStruct2
     0x1d10: 02                       
     0x1d11: 0B                        
     0x1d12: 04                         
     0x1d13: 07                       
     0x1d14: 0A                             

.__not_accessed__
     0x1d15: 05                       
     0x1d16: 02                      
     0x1d17: 05                       
     0x1d18: 04                       
     0x1d19: 06                          
     0x1d1a: 07                   
     0x1d1b: 08                                   
     0x1d1c: 0A                     
     0x1d1d: 06                            
     0x1d1e: 0A                       
     0x1d1f: 03                        

.bunkerSprite                                          ; 22 bits x 2 bytes high
     0x1d20: FF                                   
     0x1d21: 0F                                        ; . . . . x x x x  x x x x x x x x
     0x1d22: FF                                   
     0x1d23: 1F                                        ; . . . x x x x x  x x x x x x x x
     0x1d24: FF                                   
     0x1d25: 3F                                        ; . . x x x x x x  x x x x x x x x
     0x1d26: FF                                   
     0x1d27: 7F                                        ; . x x x x x x x  x x x x x x x x
     0x1d28: FF                                   
     0x1d29: FF                                        ; x x x x x x x x  x x x x x x x x
     0x1d2a: FC                                   
     0x1d2b: FF                                        ; x x x x x x x x  x x x x x x . .
     0x1d2c: F8                                   
     0x1d2d: FF                                        ; x x x x x x x x  x x x x x . . .
     0x1d2e: F0                                   
     0x1d2f: FF                                        ; x x x x x x x x  x x x x . . . .
     0x1d30: F0                                   
     0x1d31: FF                                        ; x x x x x x x x  x x x x . . . .
     0x1d32: F0                                   
     0x1d33: FF                                        ; x x x x x x x x  x x x x . . . . 
     0x1d34: F0                                   
     0x1d35: FF                                        ; x x x x x x x x  x x x x . . . .
     0x1d36: F0                                   
     0x1d37: FF                                        ; x x x x x x x x  x x x x . . . .
     0x1d38: F0                                   
     0x1d39: FF                                        ; x x x x x x x x  x x x x . . . .
     0x1d3a: F0                                   
     0x1d3b: FF                                        ; x x x x x x x x  x x x x . . . .
     0x1d3c: F8                                   
     0x1d3d: FF                                        ; x x x x x x x x  x x x x x . . .
     0x1d3e: FC                                   
     0x1d3f: FF                                        ; x x x x x x x x  x x x x x x . .
     0x1d40: FF                                   
     0x1d41: FF                                        ; x x x x x x x x  x x x x x x x x
     0x1d42: FF                                   
     0x1d43: FF                                        ; x x x x x x x x  x x x x x x x x
     0x1d44: FF                                   
     0x1d45: 7F                                        ; . x x x x x x x  x x x x x x x x
     0x1d46: FF                                   
     0x1d47: 3F                                        ; . . x x x x x x  x x x x x x x x
     0x1d48: FF                                   
     0x1d49: 1F                                        ; . . . x x x x x  x x x x x x x x
     0x1d4a: FF                                   
     0x1d4b: 0F                                        ; . . . . x x x x  x x x x x x x x

.UFOMessageLocatorCol1        ; check: is this equal to score from randomizer table?
     0x1d4c: 05                   
     0x1d4d: 10                                   
     0x1d4e: 15                          
     0x1d4f: 30                                            

.UFOMessageLocatorCol2        ; then corresponding value here is the LSB of coords
     0x1d50: 94                      
     0x1d51: 97                      
     0x1d52: 9A                      
     0x1d53: 9D                       

.ufoScoreRandomizerTable
     0x1d54: 10                                     
     0x1d55: 05                    
     0x1d56: 05                       
     0x1d57: 10                                    
     0x1d58: 15                      
     0x1d59: 10                                     
     0x1d5a: 10                                    
     0x1d5b: 05                      
     0x1d5c: 30                                     
     0x1d5d: 10                                     
     0x1d5e: 10                                   
     0x1d5f: 10                                     
     0x1d60: 05                        
     0x1d61: 15                            
     0x1d62: 10                                         
     0x1d63: 05                        

.ufoSprite               ; 0x18 bit width
     0x1d64: 00                                        ; . . . . . . . .          
     0x1d65: 00                                        ; . . . . . . . .
     0x1d66: 00                                        ; . . . . . . . .
     0x1d67: 00                                        ; . . . . . . . .
     0x1d68: 04                                        ; . . . . . x . . 
     0x1d69: 0C                                        ; . . . . x x . . 
     0x1d6a: 1E                                        ; . . . x x x x .
     0x1d6b: 37                                        ; . . x x . x x x 
     0x1d6c: 3E                                        ; . . x x x x x .
     0x1d6d: 7C                                        ; . x x x x x . .
     0x1d6e: 74                                        ; . x x x . x . .
     0x1d6f: 7E                                        ; . x x x x x x .
     0x1d70: 7E                                        ; . x x x x x x .
     0x1d71: 74                                        ; . x x x . x . .
     0x1d72: 7C                                        ; . x x x x x . .
     0x1d73: 3E                                        ; . . x x x x x .
     0x1d74: 37                                        ; . . x x . x x x
     0x1d75: 1E                                        ; . . . x x x x .
     0x1d76: 0C                                        ; . . . . x x . .
     0x1d77: 04                                        ; . . . . . x . .
     0x1d78: 00                                        ; . . . . . . . .
     0x1d79: 00                                        ; . . . . . . . .
     0x1d7a: 00                                        ; . . . . . . . .
     0x1d7b: 00                                        ; . . . . . . . .

.ufoExplosion
     0x1d7c: 00                                        ; . . . . . . . .
     0x1d7d: 22                                        ; . . x . . . x .
     0x1d7e: 00                                        ; . . . . . . . .
     0x1d7f: A5                                        ; x . x . . x . x
     0x1d80: 40                                        ; . x . . . . . .
     0x1d81: 08                                        ; . . . . x . . .
     0x1d82: 98                                        ; x . . x x . . .
     0x1d83: 3D                                        ; . . x x x x . x
     0x1d84: B6                                        ; x . x x . x x .
     0x1d85: 3C                                        ; . . x x x x . .
     0x1d86: 36                                        ; . . x x . x x .
     0x1d87: 1D                                        ; . . . x x x . x
     0x1d88: 10                                        ; . . . x . . . .
     0x1d89: 48                                        ; . x . . x . . .
     0x1d8a: 62                                        ; . x x . . . x .
     0x1d8b: B6                                        ; x . x x . x x .
     0x1d8c: 1D                                        ; . . . x x x . x
     0x1d8d: 98                                        ; x . . x x . . .
     0x1d8e: 08                                        ; . . . . x . . .
     0x1d8f: 42                                        ; . x . . . . x .
     0x1d90: 90                                        ; x . . x . . . .
     0x1d91: 08                                        ; . . . . . . . .
     0x1d92: 00                                        ; . . . . . . . .
     0x1d93: 00                                        ; . . . . . . . .

.scoreMessage50
     0x1d94: 26                                        ; message: ' '
     0x1d95: 1F                                        ;          '5'
     0x1d96: 1A                                        ;          '0'

.scoreMessage100
     0x1d97: 1B                                        ; message: '1'
     0x1d98: 1A                                        ;          '0'
     0x1d99: 1A                                        ;          '0'

.scoreMessage150
     0x1d9a: 1B                                        ; message  '1'
     0x1d9b: 1F                                        ;          '5'
     0x1d9c: 1A                                        ;          '0'

.scoreMessage300
     0x1d9d: 1D                                        ; message  '3'
     0x1d9e: 1A                                        ;          '0'
     0x1d9f: 1A                                        ;          '0'

.alienScoresLookup
     0x1da0: 10               ; rows 0 and 1: 10
     0x1da1: 20               ; rows 2 and 3: 20
     0x1da2: 30               ; row 4: 30

.originAlienStartY_table      ; row corresponds to levels beat 1-8
     0x1da3: 60                            
     0x1da4: 50                         
     0x1da5: 48                       
     0x1da6: 48                        
     0x1da7: 48                        
     0x1da8: 40                       
     0x1da9: 40                       
     0x1daa: 40                      

.playNormalY
     0x1dab: 0F                                        ; message:    'P'
     0x1dac: 0B                                        ;             'L'
     0x1dad: 00                                        ;             'A'
     0x1dae: 18                                        ;             'Y'

.spaceInvaders     
     0x1daf: 12                                        ; message      'S'
     0x1db0: 0F                                        ;              'P'
     0x1db1: 00                                        ;              'A'
     0x1db2: 02                                        ;              'C'
     0x1db3: 04                                        ;              'E'
     0x1db4: 26                                        ;              ' '
     0x1db5: 26                                        ;              ' '
     0x1db6: 08                                        ;              'I'
     0x1db7: 0D                                        ;              'N'
     0x1db8: 15                                        ;              'V'
     0x1db9: 00                                        ;              'A'
     0x1dba: 03                                        ;              'D'
     0x1dbb: 04                                        ;              'E'
     0x1dbc: 11                                        ;              'R'
     0x1dbd: 12                                        ;              'S'

.scoreAdvanceTableSprites          ; note: sprites are 0x10 bits wide
     0x1dbe: 0E                                        ; first object: HL: 2C0E, DE: 1D68 (UFOSprite)
     0x1dbf: 2C                       
     0x1dc0: 68                         
     0x1dc1: 1D                       
     0x1dc2: 0C                                        ; second object: HL: 2C0C, DE: 1C20 (invaderC_1)
     0x1dc3: 2C                       
     0x1dc4: 20                                    
     0x1dc5: 1C                       
     0x1dc6: 0A                                        ; third object: HL: 2C0A, DE: 1C40 (invaderB_2)
     0x1dc7: 2C                       
     0x1dc8: 40                          
     0x1dc9: 1C                        
     0x1dca: 08                                        ; fourth object: HL: 2C08, DE: 1C00 (invaderA_1)
     0x1dcb: 2C                       
     0x1dcc: 00                  
     0x1dcd: 1C                    
     0x1dce: FF                                        ; loop control: 0xFF ends loop

.scoreAdvanceTableMessages         ; note: messages are 0x0A bits long
     0x1dcf: 0E                                        ; first message: HL: 2E0E, DE: 1DE0 (scoreMessage1)
     0x1dd0: 2E                            
     0x1dd1: E0                     
     0x1dd2: 1D                      
     0x1dd3: 0C                                        ; second message: HL: 2E0C, DE: 1DEA (scoreMessage2)
     0x1dd4: 2E                            
     0x1dd5: EA                          
     0x1dd6: 1D                       
     0x1dd7: 0A                                        ; third message: HL: 2E0A, DE: 1DF4 (scoreMessage3)
     0x1dd8: 2E                           
     0x1dd9: F4                         
     0x1dda: 1D                          
     0x1ddb: 08                                        ; fourth message: HL: 2008, DE: 1C99 (scoreMessage4)
     0x1ddc: 2E                            
     0x1ddd: 99                      
     0x1dde: 1C                         
     0x1ddf: FF                                        ; loop control: 0xFF ends loop

.scoreMessage1
     0x1de0: 27                                        ; message:     '='
     0x1de1: 38                                        ;              '?'
     0x1de2: 26                                        ;              ' '
     0x1de3: 0C                                        ;              'M'
     0x1de4: 18                                        ;              'Y'
     0x1de5: 12                                        ;              'S'
     0x1de6: 13                                        ;              'T'
     0x1de7: 04                                        ;              'E'
     0x1de8: 11                                        ;              'R'
     0x1de9: 18                                        ;              'Y'

.scoreMessage2
     0x1dea: 27                                        ; message:     '='
     0x1deb: 1D                                        ;              '3'
     0x1dec: 1A                                        ;              '0'
     0x1ded: 26                                        ;              ' '
     0x1dee: 0F                                        ;              'P'
     0x1def: 0E                                        ;              'O'
     0x1df0: 08                                        ;              'I'
     0x1df1: 0D                                        ;              'N'
     0x1df2: 13                                        ;              'T'
     0x1df3: 12                                        ;              'S'

.scoreMessage3
     0x1df4: 27                                        ; message:     '='
     0x1df5: 1C                                        ;              '2'
     0x1df6: 1A                                        ;              '0'
     0x1df7: 26                                        ;              ' '
     0x1df8: 0F                                        ;              'P'
     0x1df9: 0E                                        ;              'O'
     0x1dfa: 08                                        ;              'I'
     0x1dfb: 0D                                        ;              'N'
     0x1dfc: 13                                        ;              'T'
     0x1dfd: 12                                        ;              'S'

.__not_accessed__
     0x1dfe: 00 [00 00]  |   NOP
     0x1dff: 00 [00 1F]  |   NOP

; -----------------------------------------------------------------
;
; **** Alpha-numeric sprites ****
;
;    * coded in messages based on their byte offset from 0x1E00
;
; ------------------------------------------------------------------

.sprite00
     0x1e00: 00                                        ; . . . . . . . .
     0x1e01: 1F                                        ; . . . x x x x x
     0x1e02: 24                                        ; . . x . . x . .
     0x1e03: 44                                        ; . x . . . x . .
     0x1e04: 24                                        ; . . x . . x . .
     0x1e05: 1F                                        ; . . . x x x x x
     0x1e06: 00                                        ; . . . . . . . .
     0x1e07: 00                                        ; . . . . . . . .

.sprite01
     0x1e08: 00                                        ; . . . . . . . .
     0x1e09: 7F                                        ; . x x x x x x x 
     0x1e0a: 49                                        ; . x . . x . . x
     0x1e0b: 49                                        ; . x . . x . . x
     0x1e0c: 49                                        ; . x . . x . . x
     0x1e0d: 36                                        ; . . x x . x x .
     0x1e0e: 00                                        ; . . . . . . . .
     0x1e0f: 00                                        ; . . . . . . . .

.sprite02
     0x1e10: 00                                        ; . . . . . . . .
     0x1e11: 3E                                        ; . . x x x x x .
     0x1e12: 41                                        ; . x . . . . . x
     0x1e13: 41                                        ; . x . . . . . x
     0x1e14: 41                                        ; . x . . . . . x
     0x1e15: 22                                        ; . . x . . . x .
     0x1e16: 00                                        ; . . . . . . . .
     0x1e17: 00                                        ; . . . . . . . .

.sprite03     
     0x1e18: 00                                        ; . . . . . . . .
     0x1e19: 7F                                        ; . x x x x x x x
     0x1e1a: 41                                        ; . x . . . . . x
     0x1e1b: 41                                        ; . x . . . . . x
     0x1e1c: 41                                        ; . x . . . . . x
     0x1e1d: 3E                                        ; . . x x x x x .
     0x1e1e: 00                                        ; . . . . . . . .
     0x1e1f: 00                                        ; . . . . . . . .

.sprite04
     0x1e20: 00                                        ; . . . . . . . .
     0x1e21: 7F                                        ; . x x x x x x x
     0x1e22: 49                                        ; . x . . x . . x
     0x1e23: 49                                        ; . x . . x . . x
     0x1e24: 49                                        ; . x . . x . . x
     0x1e25: 41                                        ; . x . . . . . x
     0x1e26: 00                                        ; . . . . . . . .
     0x1e27: 00                                        ; . . . . . . . .

.sprite05
     0x1e28: 00                                        ; . . . . . . . .
     0x1e29: 7F                                        ; . x x x x x x x
     0x1e2a: 48                                        ; . x . . x . . .
     0x1e2b: 48                                        ; . x . . x . . .
     0x1e2c: 48                                        ; . x . . x . . .
     0x1e2d: 40                                        ; . x . . . . . .
     0x1e2e: 00                                        ; . . . . . . . . 
     0x1e2f: 00                                        ; . . . . . . . .

.sprite06
     0x1e30: 00                                        ; . . . . . . . .
     0x1e31: 3E                                        ; . . x x x x x .
     0x1e32: 41                                        ; . x . . . . . x
     0x1e33: 41                                        ; . x . . . . . x
     0x1e34: 45                                        ; . x . . . x . x
     0x1e35: 47                                        ; . x . . . x x x
     0x1e36: 00                                        ; . . . . . . . .
     0x1e37: 00                                        ; . . . . . . . .

.sprite07
     0x1e38: 00                                        ; . . . . . . . .
     0x1e39: 7F                                        ; . x x x x x x x
     0x1e3a: 08                                        ; . . . . x . . .
     0x1e3b: 08                                        ; . . . . x . . . 
     0x1e3c: 08                                        ; . . . . x . . .
     0x1e3d: 7F                                        ; . x x x x x x x
     0x1e3e: 00                                        ; . . . . . . . .
     0x1e3f: 00                                        ; . . . . . . . .

.sprite08
     0x1e40: 00                                        ; . . . . . . . .
     0x1e41: 00                                        ; . . . . . . . .
     0x1e42: 41                                        ; . x . . . . . x
     0x1e43: 7F                                        ; . x x x x x x x
     0x1e44: 41                                        ; . x . . . . . x
     0x1e45: 00                                        ; . . . . . . . .
     0x1e46: 00                                        ; . . . . . . . .
     0x1e47: 00                                        ; . . . . . . . .

.sprite09
     0x1e48: 00                                        ; . . . . . . . .
     0x1e49: 02                                        ; . . . . . . x .
     0x1e4a: 01                                        ; . . . . . . . x
     0x1e4b: 01                                        ; . . . . . . . x
     0x1e4c: 01                                        ; . . . . . . . x
     0x1e4d: 7E                                        ; . x x x x x x .
     0x1e4e: 00                                        ; . . . . . . . .
     0x1e4f: 00                                        ; . . . . . . . .

.sprite0A
     0x1e50: 00                                        ; . . . . . . . .
     0x1e51: 7F                                        ; . x x x x x x x
     0x1e52: 08                                        ; . . . . x . . .
     0x1e53: 14                                        ; . . . x . x . .
     0x1e54: 22                                        ; . . x . . . x .
     0x1e55: 41                                        ; . x . . . . . x
     0x1e56: 00                                        ; . . . . . . . .
     0x1e57: 00                                        ; . . . . . . . .

.sprite0B
     0x1e58: 00                                        ; . . . . . . . .
     0x1e59: 7F                                        ; . x x x x x x x
     0x1e5a: 01                                        ; . . . . . . . x
     0x1e5b: 01                                        ; . . . . . . . x
     0x1e5c: 01                                        ; . . . . . . . x
     0x1e5d: 01                                        ; . . . . . . . x
     0x1e5e: 00                                        ; . . . . . . . .
     0x1e5f: 00                                        ; . . . . . . . .

.sprite0C
     0x1e60: 00                                        ; . . . . . . . .
     0x1e61: 7F                                        ; . x x x x x x x
     0x1e62: 20                                        ; . . x . . . . .
     0x1e63: 18                                        ; . . . x x . . .
     0x1e64: 20                                        ; . . x . . . . .
     0x1e65: 7F                                        ; . x x x x x x x
     0x1e66: 00                                        ; . . . . . . . .
     0x1e67: 00                                        ; . . . . . . . .

.sprite0D
     0x1e68: 00                                        ; . . . . . . . .
     0x1e69: 7F                                        ; . x x x x x x x
     0x1e6a: 10                                        ; . . . x . . . .
     0x1e6b: 08                                        ; . . . . x . . .
     0x1e6c: 04                                        ; . . . . . x . .
     0x1e6d: 7F                                        ; . x x x x x x x
     0x1e6e: 00                                        ; . . . . . . . .
     0x1e6f: 00                                        ; . . . . . . . .

.sprite0E
     0x1e70: 00                                        ; . . . . . . . .
     0x1e71: 3E                                        ; . . x x x x x .
     0x1e72: 41                                        ; . x . . . . . x
     0x1e73: 41                                        ; . x . . . . . x
     0x1e74: 41                                        ; . x . . . . . x
     0x1e75: 3E                                        ; . . x x x x x .
     0x1e76: 00                                        ; . . . . . . . .
     0x1e77: 00                                        ; . . . . . . . .

.sprite0F
     0x1e78: 00                                        ; . . . . . . . .
     0x1e79: 7F                                        ; . x x x x x x x
     0x1e7a: 48                                        ; . x . . x . . .
     0x1e7b: 48                                        ; . x . . x . . .
     0x1e7c: 48                                        ; . x . . x . . .
     0x1e7d: 30                                        ; . . x x . . . .
     0x1e7e: 00                                        ; . . . . . . . .
     0x1e7f: 00                                        ; . . . . . . . .

.sprite10
     0x1e80: 00                                        ; . . . . . . . .
     0x1e81: 3E                                        ; . . x x x x x .
     0x1e82: 41                                        ; . x . . . . . x
     0x1e83: 45                                        ; . x . . . x . x
     0x1e84: 42                                        ; . x . . . . x .
     0x1e85: 3D                                        ; . . x x x x . x
     0x1e86: 00                                        ; . . . . . . . .
     0x1e87: 00                                        ; . . . . . . . .

.sprite11
     0x1e88: 00                                        ; . . . . . . . .
     0x1e89: 7F                                        ; . x x x x x x x
     0x1e8a: 48                                        ; . x . . x . . .
     0x1e8b: 4C                                        ; . x . . x x . .
     0x1e8c: 4A                                        ; . x . . x . x .
     0x1e8d: 31                                        ; . . x x . . . x
     0x1e8e: 00                                        ; . . . . . . . .
     0x1e8f: 00                                        ; . . . . . . . .

.sprite12
     0x1e90: 00                                        ; . . . . . . . .
     0x1e91: 32                                        ; . . x x . . x .
     0x1e92: 49                                        ; . x . . x . . x
     0x1e93: 49                                        ; . x . . x . . x
     0x1e94: 49                                        ; . x . . x . . x
     0x1e95: 26                                        ; . . x . . x x .
     0x1e96: 00                                        ; . . . . . . . .
     0x1e97: 00                                        ; . . . . . . . .

.sprite13
     0x1e98: 00                                        ; . . . . . . . .
     0x1e99: 40                                        ; . x . . . . . .
     0x1e9a: 40                                        ; . x . . . . . .
     0x1e9b: 7F                                        ; . x x x x x x x
     0x1e9c: 40                                        ; . x . . . . . .
     0x1e9d: 40                                        ; . x . . . . . .
     0x1e9e: 00                                        ; . . . . . . . .
     0x1e9f: 00                                        ; . . . . . . . .

.sprite14
     0x1ea0: 00                                        ; . . . . . . . .
     0x1ea1: 7E                                        ; . x x x x x x .
     0x1ea2: 01                                        ; . . . . . . . x
     0x1ea3: 01                                        ; . . . . . . . x
     0x1ea4: 01                                        ; . . . . . . . x
     0x1ea5: 7E                                        ; . x x x x x x .
     0x1ea6: 00                                        ; . . . . . . . .
     0x1ea7: 00                                        ; . . . . . . . .

.sprite15
     0x1ea8: 00                                        ; . . . . . . . . 
     0x1ea9: 7C                                        ; . x x x x x . . 
     0x1eaa: 02                                        ; . . . . . . x .
     0x1eab: 01                                        ; . . . . . . . x
     0x1eac: 02                                        ; . . . . . . x .
     0x1ead: 7C                                        ; . x x x x x . .
     0x1eae: 00                                        ; . . . . . . . .
     0x1eaf: 00                                        ; . . . . . . . .

.sprite16
     0x1eb0: 00                                        ; . . . . . . . .
     0x1eb1: 7F                                        ; . x x x x x x x
     0x1eb2: 02                                        ; . . . . . . x . 
     0x1eb3: 0C                                        ; . . . . x x . . 
     0x1eb4: 02                                        ; . . . . . . x .
     0x1eb5: 7F                                        ; . x x x x x x x
     0x1eb6: 00                                        ; . . . . . . . .
     0x1eb7: 00                                        ; . . . . . . . .

.sprite17
     0x1eb8: 00                                        ; . . . . . . . .
     0x1eb9: 63                                        ; . x x . . . x x
     0x1eba: 14                                        ; . . . x . x . . 
     0x1ebb: 08                                        ; . . . . x . . .
     0x1ebc: 14                                        ; . . . x . x . .
     0x1ebd: 63                                        ; . x x . . . x x 
     0x1ebe: 00                                        ; . . . . . . . .
     0x1ebf: 00                                        ; . . . . . . . .

.sprite18
     0x1ec0: 00                                        ; . . . . . . . .
     0x1ec1: 60                                        ; . x x . . . . .
     0x1ec2: 10                                        ; . . . x . . . .
     0x1ec3: 0F                                        ; . . . . x x x x
     0x1ec4: 10                                        ; . . . x . . . . 
     0x1ec5: 60                                        ; . x x . . . . .
     0x1ec6: 00                                        ; . . . . . . . .
     0x1ec7: 00                                        ; . . . . . . . .

sprite19
     0x1ec8: 00                                        ; . . . . . . . .
     0x1ec9: 43                                        ; . x . . . . x x
     0x1eca: 45                                        ; . x . . . x . .
     0x1ecb: 49                                        ; . x . . x . . x
     0x1ecc: 51                                        ; . x . x . . . x
     0x1ecd: 61                                        ; . x x . . . . x
     0x1ece: 00                                        ; . . . . . . . .
     0x1ecf: 00                                        ; . . . . . . . .

.sprite1A
     0x1ed0: 00                                        ; . . . . . . . .
     0x1ed1: 3E                                        ; . . x x x x x .
     0x1ed2: 45                                        ; . x . . . x . x
     0x1ed3: 49                                        ; . x . . x . . x
     0x1ed4: 51                                        ; . x . x . . . x
     0x1ed5: 3E                                        ; . . x x x x x .
     0x1ed6: 00                                        ; . . . . . . . .
     0x1ed7: 00                                        ; . . . . . . . .

.sprite1B
     0x1ed8: 00                                        ; . . . . . . . .
     0x1ed9: 00                                        ; . . . . . . . .
     0x1eda: 21                                        ; . . x . . . . x
     0x1edb: 7F                                        ; . x x x x x x x
     0x1edc: 01                                        ; . . . . . . . x
     0x1edd: 00                                        ; . . . . . . . .
     0x1ede: 00                                        ; . . . . . . . .
     0x1edf: 00                                        ; . . . . . . . .

.sprite1C
     0x1ee0: 00                                        ; . . . . . . . .
     0x1ee1: 23                                        ; . . x . . . x x 
     0x1ee2: 45                                        ; . x . . . x . x
     0x1ee3: 49                                        ; . x . . x . . x
     0x1ee4: 49                                        ; . x . . x . . x
     0x1ee5: 31                                        ; . . x x . . . x
     0x1ee6: 00                                        ; . . . . . . . .
     0x1ee7: 00                                        ; . . . . . . . .

.sprite1D
     0x1ee8: 00                                        ; . . . . . . . .
     0x1ee9: 42                                        ; . x . . . . x .
     0x1eea: 41                                        ; . x . . . . . x
     0x1eeb: 49                                        ; . x . . x . . x
     0x1eec: 59                                        ; . x . x x . . x
     0x1eed: 66                                        ; . x x . . x x .
     0x1eee: 00                                        ; . . . . . . . .
     0x1eef: 00                                        ; . . . . . . . .

.sprite1E
     0x1ef0: 00                                        ; . . . . . . . .
     0x1ef1: 0C                                        ; . . . . x x . .
     0x1ef2: 14                                        ; . . . x . x . .
     0x1ef3: 24                                        ; . . x . . x . .
     0x1ef4: 7F                                        ; . x x x x x x x
     0x1ef5: 04                                        ; . . . . . x . .
     0x1ef6: 00                                        ; . . . . . . . .
     0x1ef7: 00                                        ; . . . . . . . .

.sprite1F
     0x1ef8: 00                                        ; . . . . . . . .
     0x1ef9: 72                                        ; . x x x . . x .
     0x1efa: 51                                        ; . x . x . . . x
     0x1efb: 51                                        ; . x . x . . . x
     0x1efc: 51                                        ; . x . x . . . x
     0x1efd: 4E                                        ; . x . . x x x .
     0x1efe: 00                                        ; . . . . . . . .
     0x1eff: 00                                        ; . . . . . . . .

.sprite20
     0x1f00: 00                                        ; . . . . . . . .
     0x1f01: 1E                                        ; . . . x x x x .
     0x1f02: 29                                        ; . . x . x . . x
     0x1f03: 49                                        ; . x . . x . . x
     0x1f04: 49                                        ; . x . . x . . x
     0x1f05: 46                                        ; . x . . . x x .
     0x1f06: 00                                        ; . . . . . . . .
     0x1f07: 00                                        ; . . . . . . . .

.sprite21
     0x1f08: 00                                        ; . . . . . . . .
     0x1f09: 40                                        ; . x . . . . . .
     0x1f0a: 47                                        ; . x . . . x x x
     0x1f0b: 48                                        ; . x . . x . . .
     0x1f0c: 50                                        ; . x . x . . . .
     0x1f0d: 60                                        ; . x x . . . . .
     0x1f0e: 00                                        ; . . . . . . . .
     0x1f0f: 00                                        ; . . . . . . . .

.sprite22
     0x1f10: 00                                        ; . . . . . . . .
     0x1f11: 36                                        ; . . x x . x x .
     0x1f12: 49                                        ; . x . . x . . x
     0x1f13: 49                                        ; . x . . x . . x
     0x1f14: 49                                        ; . x . . x . . x
     0x1f15: 36                                        ; . . x x . x x .
     0x1f16: 00                                        ; . . . . . . . .
     0x1f17: 00                                        ; . . . . . . . .

.sprite23
     0x1f18: 00                                        ; . . . . . . . .
     0x1f19: 31                                        ; . . x x . . . x
     0x1f1a: 49                                        ; . x . . x . . x
     0x1f1b: 49                                        ; . x . . x . . x
     0x1f1c: 4A                                        ; . x . . x . x .
     0x1f1d: 3C                                        ; . . x x x x . .
     0x1f1e: 00                                        ; . . . . . . . .
     0x1f1f: 00                                        ; . . . . . . . .

.sprite24
     0x1f20: 00                                        ; . . . . . . . .
     0x1f21: 08                                        ; . . . . x . . .
     0x1f22: 14                                        ; . . . x . x . .
     0x1f23: 22                                        ; . . x . . . x .
     0x1f24: 41                                        ; . x . . . . . x
     0x1f25: 00                                        ; . . . . . . . .
     0x1f26: 00                                        ; . . . . . . . .
     0x1f27: 00                                        ; . . . . . . . .

.sprite25
     0x1f28: 00                                        ; . . . . . . . .
     0x1f29: 00                                        ; . . . . . . . .
     0x1f2a: 41                                        ; . x . . . . . x
     0x1f2b: 22                                        ; . . x . . . x .
     0x1f2c: 14                                        ; . . . x . x . .
     0x1f2d: 08                                        ; . . . . x . . .
     0x1f2e: 00                                        ; . . . . . . . .
     0x1f2f: 00                                        ; . . . . . . . .

sprite26                 ; alphanumeric ' '
     0x1f30: 00                                        ; . . . . . . . .
     0x1f31: 00                                        ; . . . . . . . .
     0x1f32: 00                                        ; . . . . . . . .
     0x1f33: 00                                        ; . . . . . . . .
     0x1f34: 00                                        ; . . . . . . . .
     0x1f35: 00                                        ; . . . . . . . .
     0x1f36: 00                                        ; . . . . . . . .
     0x1f37: 00                                        ; . . . . . . . .

sprite27                 ; alphanumeric '='
     0x1f38: 00                                        ; . . . . . . . .
     0x1f39: 14                                        ; . . . x . x . . 
     0x1f3a: 14                                        ; . . . x . x . .
     0x1f3b: 14                                        ; . . . x . x . .
     0x1f3c: 14                                        ; . . . x . x . .
     0x1f3d: 14                                        ; . . . x . x . .
     0x1f3e: 00                                        ; . . . . . . . .
     0x1f3f: 00                                        ; . . . . . . . .

sprite28                 ; alphanumeric '*'
     0x1f40: 00                                        ; . . . . . . . .
     0x1f41: 22                                        ; . . x . . . x .
     0x1f42: 14                                        ; . . . x . x . .
     0x1f43: 7F                                        ; . x x x x x x x
     0x1f44: 14                                        ; . . . x . x . .
     0x1f45: 22                                        ; . . x . . . x .
     0x1f46: 00                                        ; . . . . . . . .
     0x1f47: 00                                        ; . . . . . . . .

.sprite29                ; alphanumeric upside-down Y
     0x1f48: 00                                        ; . . . . . . . .
     0x1f49: 03                                        ; . . . . . . x x
     0x1f4a: 04                                        ; . . . . . x . .
     0x1f4b: 78                                        ; . x x x x . . .
     0x1f4c: 04                                        ; . . . . . x . .
     0x1f4d: 03                                        ; . . . . . . x x
     0x1f4e: 00                                        ; . . . . . . . .
     0x1f4f: 00                                        ; . . . . . . . .

.oneOrTwoPlayer
     0x1f50: 24                                        ;    message:  '<'
     0x1f51: 1B                                        ;              '1'
     0x1f52: 26                                        ;              ' '
     0x1f53: 0E                                        ;              'O'
     0x1f54: 11                                        ;              'R'
     0x1f55: 26                                        ;              ' '
     0x1f56: 1C                                        ;              '2'
     0x1f57: 26                                        ;              ' '
     0x1f58: 0F                                        ;              'P'
     0x1f59: 0B                                        ;              'L'
     0x1f5a: 00                                        ;              'A'
     0x1f5b: 18                                        ;              'Y'
     0x1f5c: 04                                        ;              'E'
     0x1f5d: 11                                        ;              'R'
     0x1f5e: 12                                        ;              'S'
     0x1f5f: 25                                        ;              '>'
     0x1f60: 26                                        ;              ' '
     0x1f61: 26                                        ;              ' '

.onePlayerOneCoin_message
     0x1f62: 28                                        ;              '*'
     0x1f63: 1B                                        ;              '1'
     0x1f64: 26                                        ;              ' '
     0x1f65: 0F                                        ;              'P'
     0x1f66: 0B                                        ;              'L'
     0x1f67: 00                                        ;              'A'
     0x1f68: 18                                        ;              'Y'
     0x1f69: 04                                        ;              'E'
     0x1f6a: 11                                        ;              'R'
     0x1f6b: 26                                        ;              ' '
     0x1f6c: 26                                        ;              ' '
     0x1f6d: 1B                                        ;              '1'
     0x1f6e: 26                                        ;              ' '
     0x1f6f: 02                                        ;              'C'
     0x1f70: 0E                                        ;              'O'
     0x1f71: 08                                        ;              'I'
     0x1f72: 0D                                        ;              'N'
     0x1f73: 26                                        ;              ' '

.demoCodes               ; looped through and stored at 0x201D
     0x1f74: 01                               
     0x1f75: 01                               
     0x1f76: 00                      
     0x1f77: 00                      
     0x1f78: 01                               
     0x1f79: 00                     
     0x1f7a: 02                        
     0x1f7b: 01                            
     0x1f7c: 00                   
     0x1f7d: 02                       
     0x1f7e: 01                              
     0x1f7f: 00                       

.alienWithY_1            ; pointed to by animation structure 1fC9
     0x1f80: 60                                        ; . x x . . . . .
     0x1f81: 10                                        ; . . . x . . . .
     0x1f82: 0F                                        ; . . . . x x x x
     0x1f83: 10                                        ; . . . x . . . .
     0x1f84: 60                                        ; . x x . . . . .
     0x1f85: 30                                        ; . . x x . . . .
     0x1f86: 18                                        ; . . . x x . . .
     0x1f87: 1A                                        ; . . . x x . x .
     0x1f88: 3D                                        ; . . x x x x . x
     0x1f89: 68                                        ; . x x . x . . .
     0x1f8a: FC                                        ; x x x x x x . .
     0x1f8b: FC                                        ; x x x x x x . .
     0x1f8c: 68                                        ; . x x . x . . .
     0x1f8d: 3D                                        ; . . x x x x . x
     0x1f8e: 1A                                        ; . . . x x . x .
     0x1f8f: 00                                        ; . . . . . . . .

.insertCoin_message
     0x1f90: 08                                        ; message:     'I'
     0x1f91: 0D                                        ;              'N'
     0x1f92: 12                                        ;              'S'
     0x1f93: 04                                        ;              'E'
     0x1f94: 11                                        ;              'R'
     0x1f95: 13                                        ;              'T'
     0x1f96: 26                                        ;              ' '
     0x1f97: 26                                        ;              ' '
     0x1f98: 02                                        ;              'C'
     0x1f99: 0E                                        ;              'O'
     0x1f9a: 08                                        ;              'I'
     0x1f9b: 0D                                        ;              'N'

.coinInfoTable           ; table-message data structures for printing coin-info
     0x1f9c: 0D                                        ; REGISTERS TO PRINT TABLE ROW:
     0x1f9d: 2A                                        ;    HL: 2A0D
     0x1f9e: 50                                        ;    DE: 1F50
     0x1f9f: 1F                                        ;    message: <1 OR 2 PLAYERS>
     0x1fa0: 0A                                        ; REGISTERS TO PRINT TABLE MESSAGE:
     0x1fa1: 2A                                        ;    HL: 2A0A
     0x1fa2: 62                                        ;    DE: 1F62
     0x1fa3: 1F                                        ;    message: '*1 PLAYER 1 COIN'
     0x1fa4: 07                                        ; REGISTERS TO PRINT TABLE MESSAGE:
     0x1fa5: 2A                                        ;    HL: 2A07
     0x1fa6: E1                                        ;    DE: 1FE1
     0x1fa7: 1F                                        ;    message: '*2 PLAYERS 2 COINS'
     0x1fa8: FF                                        ; loop control: 0xFF ends loop

.credit_message
     0x1fa9: 02                                        ; message:     'C'
     0x1faa: 11                                        ;              'R'
     0x1fab: 04                                        ;              'E'
     0x1fac: 03                                        ;              'D'
     0x1fad: 08                                        ;              'I'
     0x1fae: 13                                        ;              'T'
     0x1faf: 26                                        ;              ' '

.alienWithY_2
     0x1fb0: 00                                        ; . . . . . . . .
     0x1fb1: 60                                        ; . x x . . . . .
     0x1fb2: 10                                        ; . . . x . . . .
     0x1fb3: 0F                                        ; . . . . x x x x
     0x1fb4: 10                                        ; . . . x . . . .
     0x1fb5: 60                                        ; . x x . . . . .
     0x1fb6: 38                                        ; . . x x x . . .
     0x1fb7: 19                                        ; . . . x x . . x
     0x1fb8: 3A                                        ; . . x x x . x .
     0x1fb9: 6D                                        ; . x x . x x . x
     0x1fba: FA                                        ; x x x x x . x .
     0x1fbb: FA                                        ; x x x x x . x .
     0x1fbc: 6D                                        ; . x x . x x . x
     0x1fbd: 3A                                        ; . . x x x . x .
     0x1fbe: 19                                        ; . . . x x . . x
     0x1fbf: 00                                        ; . . . . . . . .

.sprite38                ; alphanumeric question mark
     0x1fc0: 00                                        ; . . . . . . . .
     0x1fc1: 20                                        ; . . x . . . . .
     0x1fc2: 40                                        ; . x . . . . . .
     0x1fc3: 4D                                        ; . x . . x x . x
     0x1fc4: 50                                        ; . x . x . . . .
     0x1fc5: 20                                        ; . . x . . . . .
     0x1fc6: 00                                        ; . . . . . . . .
     0x1fc7: 00                                        ; . . . . . . . .
     0x1fc8: 00                                        ; . . . . . . . .

.animationStruct_1FC9     
     0x1fc9: 00                                             
     0x1fca: 00                                             
     0x1fcb: FF                                            
     0x1fcc: B8                                             
     0x1fcd: FF                                             
     0x1fce: 80                                             
     0x1fcf: 1F                                             
     0x1fd0: 10                                             
     0x1fd1: 97                                             
     0x1fd2: 00                                             
     0x1fd3: 80                                             
     0x1fd4: 1F                       

.animationStruct_1FD5                                 
     0x1fd5: 00                                             
     0x1fd6: 00                                             
     0x1fd7: 01                                             
     0x1fd8: D0                                             
     0x1fd9: 22                            
     0x1fda: 20                                     
     0x1fdb: 1C                         
     0x1fdc: 10                                     
     0x1fdd: 94                         
     0x1fde: 00                    
     0x1fdf: 20                                    
     0x1fe0: 1C                       

.twoPlayers2Coins_message     
     0x1fe1: 28                                        ; message:     '*'
     0x1fe2: 1C                                        ;              '2'
     0x1fe3: 26                                        ;              ' '
     0x1fe4: 0F                                        ;              'P'
     0x1fe5: 0B                                        ;              'L'
     0x1fe6: 00                                        ;              'A'
     0x1fe7: 18                                        ;              'Y'
     0x1fe8: 04                                        ;              'E'
     0x1fe9: 11                                        ;              'R'
     0x1fea: 12                                        ;              'S'
     0x1feb: 26                                        ;              ' '
     0x1fec: 1C                                        ;              '2'
     0x1fed: 26                                        ;              ' '
     0x1fee: 02                                        ;              'C'
     0x1fef: 0E                                        ;              'O'
     0x1ff0: 08                                        ;              'I'
     0x1ff1: 0D                                        ;              'N'
     0x1ff2: 12                                        ;              'S'

.push_message
     0x1ff3: 0F                                        ;              'P'
     0x1ff4: 14                                        ;              'U'
     0x1ff5: 12                                        ;              'S'
     0x1ff6: 07                                        ;              'H'
     0x1ff7: 26                                        ;              ' '

.sprite3F                ; alphanumeric hyphen / minus
     0x1ff8: 00                                        ; . . . . . . . .
     0x1ff9: 08                                        ; . . . . x . . .
     0x1ffa: 08                                        ; . . . . x . . .
     0x1ffb: 08                                        ; . . . . x . . .
     0x1ffc: 08                                        ; . . . . x . . .
     0x1ffd: 08                                        ; . . . . x . . .
     0x1ffe: 00                                        ; . . . . . . . .
     0x1fff: 00                                        ; . . . . . . . .
