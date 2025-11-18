################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Columns.
#
# Student 1: Name, Student Number
# Student 2: Name, Student Number (if applicable)
#
# We assert that the code submitted here is entirely our own 
# creation, and will indicate otherwise when it is not.
#
######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       8
# - Unit height in pixels:      8
# - Display width in pixels:    256
# - Display height in pixels:   256
# - Base Address for Display:   0x10008000 ($gp)
##############################################################################

.data
##############################################################################
# Immutable Data
##############################################################################
# The address of the bitmap display. Don't forget to connect it!
ADDR_DSPL: .word 0x10008000
# The address of the keyboard. Don't forget to connect it!
ADDR_KBRD: .word 0xffff0000

# Colors
gray: .word 0x808080
red: .word 0xff0000        # $t1 = red
orange: .word 0xff7f00        # $t2 = orange
yellow: .word 0xffff00        # $t3 = yellow
green: .word 0x00ff00        # $t4 = green
blue: .word 0x0000ff        # $t5 = blue
purple: .word 0x8b00ff        # $t6 = purple

color_table:
    .word 0xff0000   # red
    .word 0xff7f00   # orange
    .word 0xffff00   # yellow
    .word 0x00ff00   # green
    .word 0x0000ff   # blue
    .word 0x8b00ff   # purple
color_count: .word 6

# offsets
row_offset: .word 128
col_offset: .word 4

start_row_const:     .word 4
start_col_const:     .word 4
outline_height:      .word 15
outline_width:       .word 8

##############################################################################
# Mutable Data
##############################################################################
current_piece_color0: .word 0
current_piece_color1: .word 0
current_piece_color2: .word 0

next_piece_color0: .word 0
next_piece_color1: .word 0
next_piece_color2: .word 0

# Current piece position
piece_row: .word 0
piece_col: .word 0

board_state: .space 312     # 13 rows × 6 columns × 4  = 312 bytes per cell

##############################################################################
# Code
##############################################################################
.text
.globl main

    # Run the game.
main:
    # Initialize the game
    # Draw the grid first

        lw $t0, ADDR_DSPL          # base address

    
    jal draw_canvas
    
    jal draw_next_three
    
    
    

exit:
    li $v0, 10              # terminate the program gracefully
    syscall





    # lw $t0, ADDR_DSPL       # $t0 = base address for display
    # sw $t1, 0($t0)          # paint the first unit (i.e., top-left) red
    # sw $t2, 4($t0)          # paint the second unit on the first row green
    # sw $t3, 128($t0)        # paint the first unit on the second row blue

# game_loop:
    # # 1a. Check if key has been pressed
    # # 1b. Check which key has been pressed
    # # 2a. Check for collisions
	# # 2b. Update locations (capsules)
	# # 3. Draw the screen
	# # 4. Sleep

    # # 5. Go back to Step 1
    # j game_loop

# ===================== draw next combo function ==========================
draw_next_three:
addi $sp, $sp, -20
sw $ra, 0($sp)
sw $t1, 4($sp)
sw $t2, 8($sp)
sw $a0, 12($sp)
sw $a1, 16($sp)

jal load_random_colors_to_next
# post : assume that the current color pieces are all filled data points
# t0 is display address 
# a0, a1 is going to be the location (x,y), but for now, we set them as their initial positions (7, 4)

#place holder
li $a0, 7
li $a1, 5

sll $a0, $a0, 2         # multiply the X coordinate by 4 (signed left shift) to get the horizontal offset
add $t2, $t0, $a0       # add this horizontal offset to $t0, store the result in $t2
sll $a1, $a1, 7         # multiply the Y coordinate by 128 to get the vertical offset
add $t2, $t2, $a1       # add this vertical offset to $t2

# now, t2 has both the horizontal and verticle values in it (recall that one get the x and y positions by applying modulus 128 and mod 4 nestedly
# Make a loop to draw a line.

lw $t1, current_piece_color0
sw $t1, 0( $t2 )        # paint the current pixel
addi $t2, $t2, 128        # move $t0 to the next pixel in the col.
lw $t1, current_piece_color1
sw $t1, 0( $t2 )        # paint the current pixel
addi $t2, $t2, 128        # move $t0 to the next pixel in the col.
lw $t1, current_piece_color2
sw $t1, 0( $t2 )        # paint the current pixel
addi $t2, $t2, 128        # move $t0 to the next pixel in the col.

end_next_three:
lw $ra, 0($sp)
lw $t1, 4($sp)
lw $t2, 8($sp)
lw $a0, 12($sp)
lw $a1, 16($sp)
addi $sp, $sp, 20

jr   $ra

load_random_colors_to_next:
# pre: these are loaded with the colors from last iteration
# next_piece_color0: .word 0
# next_piece_color1: .word 0
# next_piece_color2: .word 0

# first load them to the current colors datpieces 
# then, generate random colors and load them into next

# These are the immutable data currently stored, that we could enact with 
# gray: .word 0x808080
# red: .word 0xff0000        # $t1 = red
# orange: .word 0xff7f00        # $t2 = orange
# yellow: .word 0xffff00        # $t3 = yellow
# green: .word 0x00ff00        # $t4 = green
# blue: .word 0x0000ff        # $t5 = blue
# purple: .word 0x8b00ff        # $t6 = purple

# color_table:
    # .word 0xff0000   # red
    # .word 0xff7f00   # orange
    # .word 0xffff00   # yellow
    # .word 0x00ff00   # green
    # .word 0x0000ff   # blue
    # .word 0x8b00ff   # purple
# color_count: .word 6

# for now, omit the step of tansferring the current next colors to the current colors
# TODO delete unsed t0 t1
addi $sp, $sp, -20
sw $ra, 0($sp)
sw $t0, 4($sp)
sw $t1, 8($sp)
sw $a0, 12($sp)
sw $a1, 16($sp)

# genearte a number from 0 to 5
li $v0, 42
li $a0, 0
li $a1, 6
syscall
# now the random value is stored in a0

sll $a0, $a0, 2 # since words are in 4 bytes, and were indexing from colors

la $t0, color_table # load address
add $t1, $t0, $a0 # now t1 is add address of random color

lw $t2, 0($t1) # t2 consists of the actaul color value

sw $t2, current_piece_color0

# genearte a number from 0 to 5
li $v0, 42
li $a0, 0
li $a1, 6
syscall
# now the random value is stored in a0

sll $a0, $a0, 2 # since words are in 4 bytes, and were indexing from colors

la $t0, color_table # load address
add $t1, $t0, $a0 # now t1 is add address of random color

lw $t2, 0($t1) # t2 consists of the actaul color value

sw $t2, current_piece_color1

# genearte a number from 0 to 5
li $v0, 42
li $a0, 0
li $a1, 6
syscall
# now the random value is stored in a0

sll $a0, $a0, 2 # since words are in 4 bytes, and were indexing from colors

la $t0, color_table # load address
add $t1, $t0, $a0 # now t1 is add address of random color

lw $t2, 0($t1) # t2 consists of the actaul color value

sw $t2, current_piece_color2

end_load_random_colors_to_next:
lw $ra, 0($sp)
lw $t0, 4($sp)
lw $t1, 8($sp)
lw $a0, 12($sp)
lw $a1, 16($sp)
addi $sp, $sp, 20

jr   $ra

# load_next_colors_to_current:



# ===================== draw canvas (outer perimeter) function ==========================

draw_canvas:
addi $sp, $sp, -4
sw   $ra, 0($sp)        # save return address

lw $t1, gray               # gray outline color


addi $a0, $zero, 3     
addi $a1, $zero, 4 
addi $a2, $zero, 8 

jal draw_line_horizontal

addi $a0, $zero, 3     
addi $a1, $zero, 4 
addi $a2, $zero, 15 

jal draw_line_vertical

addi $a0, $zero, 3     
addi $a1, $zero, 18
addi $a2, $zero, 8 

jal draw_line_horizontal

addi $a0, $zero, 10    
addi $a1, $zero, 4
addi $a2, $zero, 15

jal draw_line_vertical

end_draw_canvas:
lw   $ra, 0($sp)        # restore return address
addi $sp, $sp, 4         # pop stack

jr $ra

##  The draw_line_horizontal function
##  - Draws a horizontal line from a given X and Y coordinate 
#
# $a0 = the x coordinate of the line
# $a1 = the y coordinate of the line
# $a2 = the length of the line
# $t1 = the colour for this line (red)
# $t0 = the top left corner of the bitmap display
# $t2 = the starting location for the line.
# $t3 = location for line drawing to stop.
draw_line_horizontal:
sll $a0, $a0, 2         # multiply the X coordinate by 4 (signed left shift) to get the horizontal offset
add $t2, $t0, $a0       # add this horizontal offset to $t0, store the result in $t2
sll $a1, $a1, 7         # multiply the Y coordinate by 128 to get the vertical offset
add $t2, $t2, $a1       # add this vertical offset to $t2

# now, t2 has both the horizontal and verticle values in it (recall that one get the x and y positions by applying modulus 128 and mod 4 nestedly
# Make a loop to draw a line.
sll $a2, $a2, 2         # calculate the difference between the starting value for $t2 and the end value.
# a2 = 4*a2 (a2 is length of line, since horizontal, add offset by 4)
add $t3, $t2, $a2       # set stopping location for $t2
# t3 = t2 (x, y pos), * a2
line_loop_start_row:
beq $t2, $t3, line_loop_end_row  # check if $t0 has reached the final location of the line
# while t2 < t3, otherwise go to line loop end
sw $t1, 0( $t2 )        # paint the current pixel red
addi $t2, $t2, 4        # move $t0 to the next pixel in the row.
j line_loop_start_row            # jump to the start of the loop
line_loop_end_row:
jr $ra                  # return to the calling program.

draw_line_vertical:
sll $a0, $a0, 2         # multiply the X coordinate by 4 (signed left shift) to get the horizontal offset
add $t2, $t0, $a0       # add this horizontal offset to $t0, store the result in $t2
sll $a1, $a1, 7         # multiply the Y coordinate by 128 to get the vertical offset
add $t2, $t2, $a1       # add this vertical offset to $t2

# now, t2 has both the horizontal and verticle values in it (recall that one get the x and y positions by applying modulus 128 and mod 4 nestedly
# Make a loop to draw a line.
sll $a2, $a2, 7         # calculate the difference between the starting value for $t2 and the end value.

add $t3, $t2, $a2       # set stopping location for $t2
# t3 = t2 (x, y pos), * a2
line_loop_start_col:
beq $t2, $t3, line_loop_end_col  # check if $t0 has reached the final location of the line
# while t2 < t3, otherwise go to line loop end
sw $t1, 0( $t2 )        # paint the current pixel
addi $t2, $t2, 128        # move $t0 to the next pixel in the col.
j line_loop_start_col            # jump to the start of the loop
line_loop_end_col:
jr $ra                  # return to the calling program.

# draw_initial_random_col:

    # # generate a random triplet (placeholder)
    # li $v0 , 42
    # li $a0 , 0
    # li $a1 , 16
    # syscall

    # lw $t0, ADDR_DSPL       # $t0 = base address for display
    
    # jal store_next_piece_colors # store random three colors in 
    
    # # draw first column of 3 random colors
    # lw $t1, current_piece_color0              # placeholder
    # lw $t2, current_piece_color1           # placeholder
    # lw $t3, current_piece_color2           # placeholder
    # sw $t1, 832($t0)         # 6*128 + 4*16 = 832
    # sw $t2, 960($t0)  
    # sw $t3, 1088($t0)
    
    # lw $t1, red              # placeholder
    # lw $t2, current_piece_color1           # placeholder
    # lw $t3, current_piece_color2           # placeholder
    # sw $t1, 832($t0)         # 6*128 + 4*16 = 832
    # sw $t2, 960($t0)  
    # sw $t3, 1088($t0)
    
# end_draw_grid:
    # jr $ra

# store_next_piece_colors:
# # generate 3 random colors
# li $t4, 0
# draw_random_piece_loop:
    # bge $t4, 3, end_store_next_piece_colors

    # li $v0, 42
    # li $a0, 0
    # li $a1, 6
    # syscall
    
    # sll $v0, $v0, 2
    # la $t1, color_table
    # add $t1, $t1, $v0
    # lw $t2, 0($t1)

    # # store in array style to avoid multiple beq
    # la $t3, current_piece_color0
    # sll $t5, $t4, 2    # $t5 = $t4 * 4 (left shift by 2)
    # add $t3, $t3, $t5  # $t3 = base address + offset   
    # sw $t2, 0($t3)

    # addi $t4, $t4, 1
    # j draw_random_piece_loop

# end_store_next_piece_colors:
    # jr $ra