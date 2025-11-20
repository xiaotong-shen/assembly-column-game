################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Columns.
#
# Student 1: Lu Wang,1009921159
# Student 2: XiaoTong Shen 
#
# We assert that the code submitted here is entirely our own 
# creation, and will indicate otherwise when it is not.
#
######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       32
# - Unit height in pixels:      32
# - Display width in pixels:    1
# - Display height in pixels:   1
# - Base Address for Display:   0x10008000 ($gp)
##############################################################################

.data
##############################################################################
# Immutable Data
##############################################################################
# The address of the bitmap display. Don't forget to connect it!
displayaddress : .word 0x10008000
sideaddress:     .word 0x10008424
# The address of the keyboard. Don't forget to connect it!
ADDR_KBRD:.word 0xffff0000


## Assets
asset_endscreen:
    .include "assets/endscreen.s"
asset_clearscreen:
    .include "assets/clearscreen.s"
##############################################################################
grid:
.space 328
colour:
.word 0xD3D3D3  #store the grey 
.word 0xFFA500  #store the orange
.word 0xFFD700  #store the yellow
.word 0x32CD32  #store the green
.word 0x1E90FF  #store the blue
.word 0x8A2BE2  #store the purple
.word 0xFF4C4C  #store the red

black: .word 0x000000
white: .word 0xffffff

colour1: .word 0
colour2: .word 0
colour3: .word 0

cur_x : .word 0
cur_y : .word 0
gravity_timer: .word 0
##############################################################################

##############################################################################
# Code
##############################################################################
## draw the frame####################
.text

## Macros
.macro push(%reg)
	sub $sp, $sp, 4
	sw  %reg, 0($sp)	# push %reg
.end_macro

.macro pop(%reg)
	lw  %reg, 0($sp)	# pop %reg
	add $sp, $sp, 4
.end_macro

  # Macro to draw the %data asset, offsetted by a value of %offset
.macro load_asset(%data, %offset)
	push($t0)
    push($t1)
    push($a0)
    push($a1)
    la $t0 %data
    lw $t1 0($t0) #Read the size of the file
    addi $t0 $t0 4 #Skip to the first offset colour pair
    
    draw_asset_loop:
        lw $a0 0($t0) #Offset
        add $a0 $a0 %offset
        lw $a1 4($t0) #Colour
        
        draw($a0, $a1)
        addi $t0 $t0 8 #Go to the next offset colour pair
        subi $t1 $t1 1
        bgtz $t1, draw_asset_loop

    pop($a1)
    pop($a0)
    pop($t1)
    pop($t0)
.end_macro

.macro draw(%offset, %colour)
	push($t2)
    lw $t2, displayaddress
    add $t2 $t2 %offset
    sw %colour 0( $t2 )
    pop($t2)
.end_macro

.macro quit()
li $v0, 10                     
syscall
.end_macro

.macro sleep(%time)
li 		$v0, 32
li 		$a0, %time # time milliseconds
syscall
.end_macro

# store 1 if r is pressed, 0 if not, in v0
.macro is_r_pressed()
lw $t0, ADDR_KBRD               # $t0 = base address for keyboard
lw $t8, 0($t0)                  # Load first word from keyboard
beq $t8, 0, end_r_is_pressed     # If first word 1, key is pressed

# assume key is pressed
lw $a0, 4($t0)                  # Load second word from keyboard
beq $a0, 0x72, if_key_equals_r 

if_key_equals_r:
li $v0, 1
j end_r_is_pressed

else_key_not_equal_r:
li $v0, 0

end_r_is_pressed:
.end_macro

init:
load_asset(asset_clearscreen, $zero)

lw   $t0 , displayaddress
lw   $t1,colour
addi $a0,$zero,1
addi $a1,$zero,1
addi $a2,$zero, 8
jal draw_line_horizon

addi $a0,$zero,1
addi $a1,$zero,15
addi $a2,$zero, 8
jal draw_line_horizon

addi $a0,$zero,1
addi $a1,$zero,1
addi $a2,$zero,15
jal draw_line_vertical

addi $a0,$zero,8
addi $a1,$zero,1
addi $a2,$zero,15
jal draw_line_vertical


li $v0,32
li $a0,1000
syscall
###########################

jal new_piece
nothing_at_bottom:
lw $a0,cur_x    
lw $a1,cur_y
jal draw_piece

#sleep
li $v0,32
li $a0,16
syscall


lw $a0,cur_x    
lw $a1,cur_y
jal erase_piece

jal gravity
j keyboard_input

j End

#########################################
## Give the random colours and column
new_piece:
#random column(x coordinates)
li $v0, 42       
li $a0, 0        
li $a1, 6       
syscall            
addi $a0,$a0, 2    
la $t1,cur_x
sw $a0,0($t1)   
la $t1,cur_y
li $t2, 2
sw $t2, 0($t1)

## random colours
li $v0, 42
li $a0, 0
li $a1, 6
syscall
addi $a0,$a0,1
sll $t4, $a0, 2
la $t1, colour
add $t1, $t1, $t4
lw $t3, 0($t1)
la $t2, colour1
sw $t3, 0($t2)

li $v0, 42
li $a0, 0
li $a1, 6
syscall
addi $a0,$a0,1
sll $t4, $a0, 2
la $t1, colour
add $t1, $t1, $t4
lw $t3, 0($t1)
la $t2, colour2
sw $t3, 0($t2)

li $v0, 42
li $a0, 0
li $a1, 6
syscall
addi $a0,$a0,1
sll $t4, $a0, 2
la $t1, colour
add $t1, $t1, $t4
lw $t3, 0($t1)
la $t2, colour3
sw $t3, 0($t2)

jr $ra

# $a0 = the x coordinate of the first cell
# $a1 = the y coordinate of the first cell
get_address:
sll $t1,$a0,2
sll $t2,$a1,7
add $v0,$t1,$t0
add $v0,$v0,$t2
jr $ra


##
# $a0 = the x coordinate of the first cell
# $a1 = the y coordinate of the first cell
# $t1 = the first colour
# $t2 = the second colour
# $t3 = the third colour
# $t4 = the address of colour1(replaced with lw label)
# $t5 = start value caculated by get_address
# &t7 = &ra for draw_piece
draw_piece:
addi $t7,$ra,0
jal get_address
move $t5,$v0
lw $t1, colour1
lw $t2, colour1+4
lw $t3, colour1+8
sw $t1, 0($t5)
sw $t2, 128($t5)
sw $t3, 256($t5)
addi $ra,$t7,0
jr $ra

##
# $a0 = the x coordinate of the first cell
# $a1 = the y coordinate of the first cell
# $t5 = the starting location
# 
erase_piece:
addi $t7,$ra,0
jal get_address
li $t1,0
move $t5,$v0
sw $t1, 0($t5)
sw $t1, 128($t5)
sw $t1, 256($t5)
addi $ra,$t7,0
jr $ra


# $a0 = the x coordinate of the cell
# $a1 = the y coordinate of the cell
erase_cell:
addi $t7,$ra,0
jal get_address
li $t1,0
move $t5,$v0
sw $t1, 0($t5)
addi $ra,$t7,0
jr $ra

# This function was provided by the professor and was not written by us
##  The draw_line function
##  - Draws a horizontal line from a given X and Y coordinate 
# $a0 = the x coordinate of the line
# $a1 = the y coordinate of the line
# $a2 = the length of the line
# $t1 = the colour for this line
# $t0 = the top left corner of the bitmap display
# $t2 = the starting location for the line.
# $t3 = location for line drawing to stop.
draw_line_horizon:
sll $a0, $a0, 2         # multiply the X coordinate by 4 to get the horizontal offset
add $t2, $t0, $a0       # add this horizontal offset to $t0, store the result in $t2
sll $a1, $a1, 7         # multiply the Y coordinate by 128 to get the vertical offset
add $t2, $t2, $a1       # add this vertical offset to $t2

# Make a loop to draw a line.
sll $a2, $a2, 2         # calculate the difference between the starting value for $t2 and the end value.
add $t3, $t2, $a2       # set stopping location for $t2
line_loop_start:
beq $t2, $t3, line_loop_end  # check if $t0 has reached the final location of the line
sw $t1, 0( $t2 )        # paint the current pixel 
addi $t2, $t2, 4        # move $t0 to the next pixel in the row.
j line_loop_start            # jump to the start of the loop
line_loop_end:
jr $ra                  # return to the calling program.


# This function was adjusted based on the code professor provided.
##  The draw_line function
##  - Draws a horizontal line from a given X and Y coordinate 
# $a0 = the x coordinate of the line
# $a1 = the y coordinate of the line
# $a2 = the length of the line
# $t1 = the colour for this line (red)
# $t0 = the top left corner of the bitmap display
# $t2 = the starting location for the line.
# $t3 = location for line drawing to stop.
draw_line_vertical:
sll $a0, $a0, 2         # multiply the X coordinate by 4 to get the horizontal offset
add $t2, $t0, $a0       # add this horizontal offset to $t0, store the result in $t2
sll $a1, $a1, 7         # multiply the Y coordinate by 128 to get the vertical offset
add $t2, $t2, $a1       # add this vertical offset to $t2

# Make a loop to draw a line.
sll $a2, $a2, 7         # calculate the difference between the starting value for $t2 and the end value.
add $t3, $t2, $a2       # set stopping location for $t2
vertical_line_loop_start:
beq $t2, $t3, vertical_line_loop_end  # check if $t0 has reached the final location of the line
sw $t1, 0( $t2 )        # paint the current pixel 
addi $t2, $t2, 128        # move $t0 to the next pixel in the row.
j vertical_line_loop_start           # jump to the start of the loop
vertical_line_loop_end:
jr $ra                  # return to the calling program.



# We took the provided keyboard_input for reference
keyboard_input:
lw $t6, ADDR_KBRD
lw  $t7, 0($t6)
beq $t7, $zero, nothing_at_bottom
lw  $a0, 4($t6)       
beq $a0, 0x71, respond_to_Q     
beq $a0, 0x61, respond_to_A     
beq $a0, 0x64, respond_to_D    
beq $a0, 0x73, respond_to_S 
beq $a0, 0x77, respond_to_W
b   nothing_at_bottom

respond_to_Q:
j End

respond_to_W:
lw $t1,colour1
lw $t2,colour2
lw $t3,colour3
sw $t3,colour2
sw $t2,colour1
sw $t1,colour3
j nothing_at_bottom

respond_to_A:
lw $a0,cur_x
lw $a1,cur_y
jal get_address
move $t2,$v0
addi $t2,$t2,-4
lw $t3,0($t2)
bne $t3,0,nothing_at_bottom
lw $t3,128($t2)
bne $t3,0,nothing_at_bottom
lw $t3,256($t2)
bne $t3,0,nothing_at_bottom
la $t1,cur_x
lw $t2,0($t1)
addi $t2,$t2,-1
sw $t2,0($t1)
j nothing_at_bottom


respond_to_D:
lw $a0,cur_x
lw $a1,cur_y
jal get_address
move $t2,$v0
addi $t2,$t2,4
lw $t3,0($t2)
bne $t3,0,nothing_at_bottom
lw $t3,128($t2)
bne $t3,0,nothing_at_bottom
lw $t3,256($t2)
bne $t3,0,nothing_at_bottom
la $t1,cur_x
lw $t2,0($t1)
addi $t2,$t2,1
sw $t2,0($t1)
j nothing_at_bottom

respond_to_S:
lw $a0,cur_x
lw $a1,cur_y
jal get_address
move $t2,$v0
lw $t3,384($t2)
bne $t3,0,nothing_at_bottom
la $t1,cur_y
lw $t2,0($t1)
addi $t2,$t2,1
sw $t2,cur_y
j nothing_at_bottom

#The gravity of the game, can be adjusted by setting the different maximum value of gravity timer.
gravity:
lw $t1,cur_x
lw $t2,cur_y
sll $t1,$t1,2
sll $t2,$t2,7
add $t2,$t2,$t1
addi $t2,$t2,384
add $t2,$t2,$t0
lw $t3,0($t2)
bne $t3,0,redraw
lw  $t8, gravity_timer
addi $t8, $t8, 1
sw  $t8, gravity_timer
li $t9,32
bne $t8,$t9,back
la $t1,cur_y
lw $t2,0($t1)
addi $t2,$t2,1
sw $t2,0($t1)
sw $zero,gravity_timer
back:
jr $ra

redraw:
lw $a0,cur_x    
lw $a1,cur_y
jal draw_piece
lw $t1,cur_y
addi $t1,$t1,-3
bltz $t1,End #terminate if reaches the to
mark:
jal mark_line
jal mark_vertical
jal mark_right_diagonal
jal mark_left_diagonal
jal clear_marked_piece
jal fall
bne $t9,0,mark
jal new_piece
b nothing_at_bottom
End:
# jal DisplayGameOver
# loop/sleep for three second, if r is not pressed then terminate
load_asset(asset_endscreen, $zero)
jal play_game_over_sound

# use t0
addi $t0, $zero, 0
end_loop:
beq $t0, 5, end_end_loop
sleep(10)
is_r_pressed()
beq $v0, 1, init
addi $t0, $t0, 1
end_end_loop:
quit()


erase_board:
##  The draw_rect function (Provided by profs)
##  - Draws a rectangle at a given X and Y coordinate 
#
# $a0 = the x coordinate of the line
# $a1 = the y coordinate of the line
# $a2 = the width of the rectangle
# $a3 = the height of the rectangle
# $t1 = the colour for this line
addi $sp, $sp, -4 
sw $ra, 0($sp) # i guess this is indexing (?)

li $a0, 0
li $a1, 0
li $a2, 32
li $a3, 32
lw $t1, black

jal draw_rect

lw $ra, 0($sp)
addi $sp, $sp, 4

jr $ra


mark_line:
li $a0,6
li $a1,15
addi $t1,$zero,2 #x coordinates
addi $t2,$zero,2 #y coordinates
ml_outer_loop:
bgt $t2,14,ml_outer_loop_end
ml_inner_loop:
bgt $t1,6,ml_inner_loop_end
sll $t3,$t1,2
sll $t4,$t2,7
add $t5,$t3,$t4
add $t5,$t5,$t0
lw $t6,0($t5)
lw $t7,4($t5)
lw $t8,8($t5)
beq $t6,$zero,ml_if_end
bne $t6,$t7,ml_if_end
bne $t7,$t8,ml_if_end
addi $t6,$t1,-2 #t6 = i = x - 2
addi $t7,$t2,-2 #t7 = j = y - 2
li $t8,6
mul $t7,$t7,$t8 #t7 = j * 6
add $t7,$t7,$t6 #t7 = index
sll $t7,$t7,2   #t7 * 4(index to address)
la $t6,grid        # t6 = grid[0](address)
add $t6,$t6,$t7    # t6 = grid[index](address)
li $t9,1
sw $t9,0($t6) 
sw $t9,4($t6)    
sw $t9,8($t6)     

ml_if_end:
addi $t1,$t1,1
j ml_inner_loop
ml_inner_loop_end:
addi $t1,$zero,2
addi $t2,$t2,1
j ml_outer_loop
ml_outer_loop_end:
jr $ra



mark_vertical:
li $a0,6
li $a1,15
addi $t1,$zero,2 #x coordinates
addi $t2,$zero,2 #y coordinates
mv_outer_loop:
bgt $t2,12,mv_outer_loop_end
mv_inner_loop:
bgt $t1,7,mv_inner_loop_end
sll $t3,$t1,2
sll $t4,$t2,7
add $t5,$t3,$t4
add $t5,$t5,$t0
lw $t6,0($t5)
lw $t7,128($t5)
lw $t8,256($t5)
beq $t6,$zero,mv_if_end
bne $t6,$t7,mv_if_end
bne $t7,$t8,mv_if_end
addi $t6,$t1,-2   #t6 = i = x - 2
addi $t7,$t2,-2   #t7 = j = y - 2
li $t8,6
mul $t7,$t7,$t8   #t7 = j * 6
add $t7,$t7,$t6   #t7 = index
sll $t7,$t7,2     #t7 * 4(index to address)
la $t6,grid       #t6 = grid[0](address)
add $t6,$t6,$t7   #t6 = grid[index](address)
li $t9,1
sw $t9,0($t6) 
sw $t9,24($t6)    
sw $t9,48($t6)     

mv_if_end:
addi $t1,$t1,1
j mv_inner_loop
mv_inner_loop_end:
addi $t1,$zero,2
addi $t2,$t2,1
j mv_outer_loop
mv_outer_loop_end:
jr $ra


mark_right_diagonal:
li $a0,6
li $a1,15
addi $t1,$zero,2 #x coordinates
addi $t2,$zero,2 #y coordinates
mrd_outer_loop:
bgt $t2,12,mrd_outer_loop_end
mrd_inner_loop:
bgt $t1,5,mrd_inner_loop_end
sll $t3,$t1,2
sll $t4,$t2,7
add $t5,$t3,$t4
add $t5,$t5,$t0
lw $t6,0($t5)
lw $t7,132($t5)
lw $t8,264($t5)
beq $t6,$zero,mrd_if_end
bne $t6,$t7,mrd_if_end
bne $t7,$t8,mrd_if_end
addi $t6,$t1,-2 #t6 = i = x - 2
addi $t7,$t2,-2 #t7 = j = y - 2
li $t8,6
mul $t7,$t7,$t8 #t7 = j * 6
add $t7,$t7,$t6 #t7 = index
sll $t7,$t7,2   #t7 * 4(index to address)
la $t6,grid        # t6 = grid[0](address)
add $t6,$t6,$t7    # t6 = grid[index](address)
li $t9,1
sw $t9,0($t6) 
sw $t9,28($t6)    
sw $t9,56($t6)     

mrd_if_end:
addi $t1,$t1,1
j mrd_inner_loop
mrd_inner_loop_end:
addi $t1,$zero,2
addi $t2,$t2,1
j mrd_outer_loop
mrd_outer_loop_end:
jr $ra

mark_left_diagonal:
li $a0,6
li $a1,15
addi $t1,$zero,4 #x coordinates
addi $t2,$zero,2 #y coordinates
mld_outer_loop:
bgt $t2,12,mld_outer_loop_end
mld_inner_loop:
bgt $t1,7,mld_inner_loop_end
sll $t3,$t1,2
sll $t4,$t2,7
add $t5,$t3,$t4
add $t5,$t5,$t0
lw $t6,0($t5)
lw $t7,124($t5)
lw $t8,248($t5)
beq $t6,$zero,mld_if_end
bne $t6,$t7,mld_if_end
bne $t7,$t8,mld_if_end
addi $t6,$t1,-2 #t6 = i = x - 2
addi $t7,$t2,-2 #t7 = j = y - 2
li $t8,6
mul $t7,$t7,$t8  
add $t7,$t7,$t6 
sll $t7,$t7,2 
la $t6,grid       
add $t6,$t6,$t7 
li $t9,1
sw $t9,0($t6) 
sw $t9,20($t6)    
sw $t9,40($t6)     

mld_if_end:
addi $t1,$t1,1
j mld_inner_loop
mld_inner_loop_end:
addi $t1,$zero,4
addi $t2,$t2,1
j mld_outer_loop
mld_outer_loop_end:
jr $ra





clear_marked_piece:
addi $sp,$sp,-4
sw $ra,0($sp)
li $t4, 2         
clear_marked_piece_outer_loop:
bgt $t4,14,clear_marked_outer_loop_end
li $t3,2        

clear_marked_piece_inner_loop:
bgt $t3,7,clear_marked_piece_inner_loop_end
addi $t6,$t3,-2     # i = x - 2
addi $t7,$t4, -2     # j = y - 2
li $t8,6
mul $t7,$t7,$t8    # j * 6
add $t7,$t7,$t6    # index = j*6 + i
sll $t7,$t7,2      # index * 4
la $t6,grid
add $t6,$t6,$t7    # t6 = ad(grid[index])
lw $t8,0($t6)      # t8 = grid[index]
li $t9,1
bne $t8,$t9, clear_marked_piece_if_end
move $a0,$t3         
move $a1,$t4        
jal erase_cell
sw $zero, 0($t6)
clear_marked_piece_if_end:
addi $t3, $t3, 1      
j clear_marked_piece_inner_loop
clear_marked_piece_inner_loop_end:
addi $t4, $t4, 1      
j clear_marked_piece_outer_loop
clear_marked_outer_loop_end:
lw $ra,0($sp)
addi $sp,$sp,4
jr $ra

fall:
addi $t1,$zero,2 #x coordinate
addi $t2,$zero,13#y coordinate
addi $t6,$zero,0
addi $t9,$zero,0
fall_outer_loop:
blt $t2,2,fall_outer_loop_end
fall_inner_loop:
beq $t1,8,fall_inner_loop_end
sll $t4,$t2,7
sll $t5,$t1,2
add $t4,$t4,$t5
add $t4,$t4,$t0
lw $t7,0($t4)
beq $t7,$t6,next_x
lw $t5,128($t4)
bne $t5,$t6,next_x
lw $t5,256($t4)
bne $t5,$t6,fall_one
lw $t5,384($t4)
bne $t5,$t6,fall_two
j fall_three
fall_one:
sw $t7,128($t4)
sw $t6,0($t4)
addi $t9,$t9,1
j next_x
fall_two:
sw $t7,256($t4)
sw $t6,0($t4)
addi $t9,$t9,1
j next_x
fall_three:
sw $t7,384($t4)
sw $t6,0($t4)
addi $t9,$t9,1
next_x:
addi $t1,$t1,1
j fall_inner_loop
fall_inner_loop_end:
addi $t2,$t2,-1
addi $t1,$zero,2
j fall_outer_loop
fall_outer_loop_end:
jr $ra


##  The draw_rect function (Provided by profs)
##  - Draws a rectangle at a given X and Y coordinate 
#
# $a0 = the x coordinate of the line
# $a1 = the y coordinate of the line
# $a2 = the width of the rectangle
# $a3 = the height of the rectangle
draw_rect:
# no registers to initialize (use $a3 as the loop variable)
# restore a2 and a3
addi $sp, $sp, -12
sw $ra, 0($sp)
sw $t2, 4($sp)
sw $t3, 8($sp)
rect_loop_start:
beq $a3, $zero, rect_loop_end   # test if the stopping condition has been satisfied
addi $sp, $sp, -4               # move the stack pointer to an empty location
sw $ra, 0($sp)                  # push $ra onto the stack
addi $sp, $sp, -4               # move the stack pointer to an empty location
sw $a0, 0($sp)                  # push $a0 onto the stack
addi $sp, $sp, -4               # move the stack pointer to an empty location
sw $a1, 0($sp)                  # push $a1 onto the stack
addi $sp, $sp, -4               # move the stack pointer to an empty location
sw $a2, 0($sp)                  # push $a2 onto the stack

jal draw_line_horizon                # call the draw_line function.

lw $a2, 0($sp)                  # pop $a2 from the stack
addi $sp, $sp, 4                # move the stack pointer to the top stack element
lw $a1, 0($sp)                  # pop $a1 from the stack
addi $sp, $sp, 4                # move the stack pointer to the top stack element
lw $a0, 0($sp)                  # pop $a0 from the stack
addi $sp, $sp, 4                # move the stack pointer to the top stack element
lw $ra, 0($sp)                  # pop $ra from the stack
addi $sp, $sp, 4                # move the stack pointer to the top stack element
addi $a1, $a1, 1                # move the Y coordinate down one row in the bitmap
addi $a3, $a3, -1               # decrement loop variable $a3 by 1
j rect_loop_start               # jump to the top of the loop.

rect_loop_end:
lw $ra, 0($sp)
lw $t2, 4($sp)
lw $t3, 8($sp)
addi $sp, $sp, 12

jr $ra                          # return to the calling program.


# SOUND FUNCTIONS

play_game_over_sound:
li 	$v0, 31		# I		
li 	$a0, 60 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 31				
li 	$a0, 64 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 31				
li 	$a0, 67 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 33	
li 	$a0, 72 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall

li 	$v0, 31		# IV		
li 	$a0, 60 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 31				
li 	$a0, 65 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 31				
li 	$a0, 69 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 33	
li 	$a0, 72 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall

li 	$v0, 31		# V7		
li 	$a0, 62 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 31				
li 	$a0, 65 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 31				
li 	$a0, 67 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 33	
li 	$a0, 71 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall

li 	$v0, 31		# I		
li 	$a0, 60 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 31				
li 	$a0, 64 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 31				
li 	$a0, 67 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall
li 	$v0, 33	
li 	$a0, 72 			
li 	$a1, 500
li 	$a2, 0
li 	$a3, 127
syscall

jr 	$ra
